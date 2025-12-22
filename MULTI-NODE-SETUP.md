# Multi-Node Orion Ops Plane Setup

This guide explains how to set up the unified Orion ops plane across multiple nodes, enabling Homepage (running on HomeCore) to discover and monitor services from all nodes.

## Architecture Overview

The Orion ops plane consists of:

- **HomeCore** (Raspberry Pi 5): Homepage dashboard + Uptime Kuma monitoring
- **DataAICore** (Optiplex/Server): AI services + Observability stack (Grafana/Prometheus/Loki)
- **DNS Node**: DNS services (Pi-hole, AdGuard Home, etc.)
- **NetSec Node**: Security services (firewall, VPN, IDS, etc.)

All nodes communicate via LAN-only connections with firewall restrictions for security.

## Security Model

### Docker Socket Proxy

Each node runs a `docker-socket-proxy` service that:
- Exposes a restricted Docker API over HTTP (port 2376)
- Mounts `/var/run/docker.sock` read-only
- Allows only safe read operations (no container creation/deletion)
- Is firewall-restricted to accept connections ONLY from HomeCore IP

This is safer than mounting raw `docker.sock` into Homepage.

### Firewall Rules

Each node MUST firewall-restrict the docker-socket-proxy port to allow only HomeCore:

```bash
# On DataAICore, DNS, and NetSec nodes:
sudo ufw allow from <HOMECORE_IP> to any port 2376 comment 'Docker proxy for Homepage'
sudo ufw deny 2376
```

Verify the rule is active:
```bash
sudo ufw status numbered
```

### Verification

From HomeCore, test connectivity:
```bash
# Should work
curl http://<remote-node-ip>:2376/containers/json

# From any other LAN device, should be blocked
```

## HomeCore Setup

### 1. Install and Configure

Follow the main [INSTALL.md](INSTALL.md) guide, then:

```bash
# Edit .env and set all node IPs
sudo nano .env
```

Set these variables:
```bash
HOMECORE_NODE_IP=192.168.1.100       # This machine
DATAAICORE_NODE_IP=192.168.1.10      # DataAICore
DNS_NODE_IP=192.168.1.11             # DNS node
NETSEC_NODE_IP=192.168.1.12          # NetSec node
REMOTE_DOCKER_PROXY_PORT=2376
```

### 2. Start Portal Stack

```bash
./scripts/orionctl up ui
```

This starts:
- Homepage (port 3001)
- Uptime Kuma (port 3001)
- Local docker-socket-proxy (internal only)

### 3. Verify Multi-Node Discovery

Open Homepage: `http://<homecore-ip>:3001`

You should see services grouped by node:
- HomeCore
- DataAICore
- DNS
- NetSec

If a node doesn't show services, check:
1. Docker-socket-proxy is running on that node
2. Firewall allows HomeCore to connect
3. Services have proper Homepage labels

## DataAICore Setup

### 1. Add Agent Stack

Create `stacks/agent/compose.yaml`:

```yaml
# =============================================================================
# Orion Agent Stack (Docker Socket Proxy)
# =============================================================================
# Exposes restricted Docker API for Homepage discovery
# LAN-only, firewall-restricted to HomeCore IP
# =============================================================================

services:
  orion_dataai_dockerproxy:
    image: tecnativa/docker-socket-proxy:latest
    container_name: orion_dataai_dockerproxy
    restart: unless-stopped
    init: true
    stop_grace_period: 10s
    environment:
      - TZ=${TZ:-Europe/Amsterdam}
      - CONTAINERS=1
      - SERVICES=1
      - TASKS=1
      - NODES=0
      - SYSTEM=0
      - IMAGES=1
      - NETWORKS=1
      - VOLUMES=0
      - INFO=1
      - EVENTS=1
      - AUTH=0
      - SECRETS=0
      - CONFIGS=0
      - POST=0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "${HOST_IP:-0.0.0.0}:${REMOTE_DOCKER_PROXY_PORT:-2376}:2375"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:2375/version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    profiles:
      - agent
```

### 2. Add Observability Stack

Create `stacks/observability/compose.yaml`:

```yaml
# =============================================================================
# Observability Stack (Grafana + Prometheus + Loki)
# =============================================================================
# Centralized metrics and logging for all Orion nodes
# LAN-only access
# =============================================================================

services:
  prometheus:
    image: prom/prometheus:${PROM_IMAGE_TAG:-latest}
    container_name: prometheus
    restart: unless-stopped
    init: true
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    volumes:
      - ${DATA_ROOT}/prometheus/config:/etc/prometheus
      - ${DATA_ROOT}/prometheus/data:/prometheus
    ports:
      - "${HOST_IP:-127.0.0.1}:${PROM_PORT:-9090}:9090"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    profiles:
      - observability
    labels:
      - homepage.group=Observability
      - homepage.name=Prometheus
      - homepage.icon=prometheus
      - homepage.href=http://${HOST_IP:-127.0.0.1}:${PROM_PORT:-9090}
      - homepage.description=Metrics collection
      - homepage.weight=2
      - homepage.instance=dataaicore

  loki:
    image: grafana/loki:${LOKI_IMAGE_TAG:-latest}
    container_name: loki
    restart: unless-stopped
    init: true
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ${DATA_ROOT}/loki/config:/etc/loki
      - ${DATA_ROOT}/loki/data:/loki
    ports:
      - "${HOST_IP:-127.0.0.1}:${LOKI_PORT:-3100}:3100"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    profiles:
      - observability
    labels:
      - homepage.group=Observability
      - homepage.name=Loki
      - homepage.icon=loki
      - homepage.href=http://${HOST_IP:-127.0.0.1}:${LOKI_PORT:-3100}
      - homepage.description=Log aggregation
      - homepage.weight=3
      - homepage.instance=dataaicore

  grafana:
    image: grafana/grafana:${GRAFANA_IMAGE_TAG:-latest}
    container_name: grafana
    restart: unless-stopped
    init: true
    environment:
      - TZ=${TZ:-Europe/Amsterdam}
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_INSTALL_PLUGINS=
    volumes:
      - ${DATA_ROOT}/grafana/data:/var/lib/grafana
      - ${DATA_ROOT}/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "${HOST_IP:-127.0.0.1}:${GRAFANA_PORT:-3000}:3000"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    profiles:
      - observability
    labels:
      - homepage.group=Observability
      - homepage.name=Grafana
      - homepage.icon=grafana
      - homepage.href=http://${HOST_IP:-127.0.0.1}:${GRAFANA_PORT:-3000}
      - homepage.description=Metrics dashboards
      - homepage.weight=1
      - homepage.instance=dataaicore
```

### 3. Create Prometheus Config

Create `${DATA_ROOT}/prometheus/config/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter_homecore'
    static_configs:
      - targets: ['${HOMECORE_NODE_IP}:9100']
        labels:
          node: 'homecore'

  - job_name: 'node_exporter_dataaicore'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          node: 'dataaicore'

  - job_name: 'node_exporter_dns'
    static_configs:
      - targets: ['${DNS_NODE_IP}:9100']
        labels:
          node: 'dns'

  - job_name: 'node_exporter_netsec'
    static_configs:
      - targets: ['${NETSEC_NODE_IP}:9100']
        labels:
          node: 'netsec'
```

### 4. Start Services

```bash
./scripts/orionctl up agent observability
```

### 5. Configure Firewall

```bash
# Allow HomeCore to access docker proxy
sudo ufw allow from <HOMECORE_IP> to any port 2376 comment 'Docker proxy for Homepage'

# Deny all other access to docker proxy
sudo ufw deny 2376

# Reload firewall
sudo ufw reload
```

## DNS and NetSec Node Setup

### 1. Create Orion Agent Stack

On DNS and NetSec nodes, create `stacks/orion-agent/compose.yaml`:

```yaml
# =============================================================================
# Orion Agent Stack
# =============================================================================
# Docker Socket Proxy + Node Exporter + Promtail
# Enables Homepage discovery and observability
# =============================================================================

services:
  dockerproxy:
    image: tecnativa/docker-socket-proxy:latest
    container_name: orion_agent_dockerproxy
    restart: unless-stopped
    init: true
    stop_grace_period: 10s
    environment:
      - TZ=${TZ:-Europe/Amsterdam}
      - CONTAINERS=1
      - SERVICES=1
      - TASKS=1
      - NODES=0
      - SYSTEM=0
      - IMAGES=1
      - NETWORKS=1
      - VOLUMES=0
      - INFO=1
      - EVENTS=1
      - AUTH=0
      - SECRETS=0
      - CONFIGS=0
      - POST=0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "${HOST_IP:-0.0.0.0}:${REMOTE_DOCKER_PROXY_PORT:-2376}:2375"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:2375/version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  node_exporter:
    image: prom/node-exporter:${NODE_EXPORTER_TAG:-latest}
    container_name: orion_agent_node_exporter
    restart: unless-stopped
    command:
      - '--path.rootfs=/host'
    volumes:
      - '/:/host:ro,rslave'
    ports:
      - "${HOST_IP:-0.0.0.0}:${NODE_EXPORTER_PORT:-9100}:9100"
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:9100/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  promtail:
    image: grafana/promtail:${PROMTAIL_TAG:-latest}
    container_name: orion_agent_promtail
    restart: unless-stopped
    init: true
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ${DATA_ROOT:-/srv/orion}/promtail:/etc/promtail
    environment:
      - TZ=${TZ:-Europe/Amsterdam}
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://localhost:9080/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### 2. Create Promtail Config

Create `${DATA_ROOT}/promtail/config.yml`:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://${DATAAICORE_NODE_IP}:${LOKI_PORT:-3100}/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          node: ${NODE_NAME}
          __path__: /var/log/*.log

  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'
```

### 3. Start Agent Stack

```bash
docker compose -f stacks/orion-agent/compose.yaml up -d
```

### 4. Configure Firewall

```bash
# Allow HomeCore to access docker proxy
sudo ufw allow from <HOMECORE_IP> to any port 2376 comment 'Docker proxy for Homepage'

# Allow DataAICore to scrape metrics
sudo ufw allow from <DATAAICORE_IP> to any port 9100 comment 'Node exporter for Prometheus'

# Deny all other access
sudo ufw deny 2376
sudo ufw deny 9100

# Reload firewall
sudo ufw reload
```

## Homepage Label Conventions

All services across all nodes should use these Docker labels for auto-discovery:

```yaml
labels:
  - homepage.group=<NodeName>           # HomeCore, DataAICore, DNS, NetSec
  - homepage.name=<ServiceName>         # Display name
  - homepage.icon=<icon>                # Icon name (from Homepage icons)
  - homepage.href=http://<url>          # Service URL
  - homepage.description=<description>  # Short description
  - homepage.weight=<number>            # Order within group (lower = first)
  - homepage.instance=<instance>        # homecore, dataaicore, dns, netsec
```

Example for a service on DataAICore:

```yaml
labels:
  - homepage.group=DataAICore
  - homepage.name=Nextcloud
  - homepage.icon=nextcloud
  - homepage.href=http://192.168.1.10:8080
  - homepage.description=Cloud storage
  - homepage.weight=1
  - homepage.instance=dataaicore
```

## Uptime Kuma Configuration

1. Open Uptime Kuma: `http://<homecore-ip>:3001`
2. Create account (first time only)
3. Add monitors for each service across all nodes
4. Create a Status Page:
   - Settings → Status Pages → New Status Page
   - Add all monitors to the page
   - Group by node (HomeCore, DataAICore, DNS, NetSec)
   - Copy the status page slug (URL path)
5. Update HomeCore `.env`:
```bash
KUMA_STATUS_SLUG=orion-services
```
6. Edit Homepage services config:
```bash
sudo nano ${DATA_ROOT}/homepage/services.yaml
```
7. Uncomment the Status section
8. Restart Homepage:
```bash
./scripts/orionctl restart portal
```

## Troubleshooting

### Homepage Not Discovering Remote Services

1. Check docker-socket-proxy is running:
```bash
# On remote node
docker ps | grep dockerproxy
```

2. Test connectivity from HomeCore:
```bash
curl http://<remote-ip>:2376/containers/json
```

3. Check firewall rules:
```bash
# On remote node
sudo ufw status numbered
```

4. Check Homepage docker.yaml:
```bash
# On HomeCore
cat ${DATA_ROOT}/homepage/docker.yaml
```

### Node Exporter Not Scraped

1. Test from DataAICore:
```bash
curl http://<node-ip>:9100/metrics
```

2. Check Prometheus targets:
- Open `http://<dataaicore-ip>:9090/targets`
- All targets should show "UP"

### Logs Not Appearing in Loki

1. Check Promtail on node:
```bash
docker logs orion_agent_promtail
```

2. Check Loki endpoint from node:
```bash
curl http://<dataaicore-ip>:3100/ready
```

3. Verify Promtail config has correct Loki URL

## Next Steps

- Add more services to your nodes and they'll auto-appear in Homepage
- Create Grafana dashboards for your metrics
- Set up alerting in Grafana/Prometheus
- Configure Uptime Kuma notifications (email, Slack, etc.)
