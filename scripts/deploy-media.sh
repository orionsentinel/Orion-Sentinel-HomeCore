#!/bin/bash
# =============================================================================
# Orion-Sentinel-HomeCore Media Deploy (Immich, Jellyfin, Navidrome, Audiobookshelf)
# =============================================================================
# Idempotent deploy of the media profiles, built for a
# Raspberry Pi 5 that already runs other services. Safe to re-run: it only adds
# missing .env keys, never overwrites data, and only starts the media
# containers (Home Assistant and other stacks are left untouched).
#
# Usage:
#   ./scripts/deploy-media.sh [--check] [--no-immich] [--no-jellyfin] [--no-navidrome]
#                             [--no-audiobookshelf] [--no-ml] [--tailscale]
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE="${REPO_ROOT}/env/.env.example"

# Keys this script owns in .env (copied from env/.env.example when missing)
MEDIA_KEYS_RE='^(IMMICH_[A-Z_]+|JELLYFIN_[A-Z_]+|NAVIDROME_[A-Z_]+|AUDIOBOOKSHELF_[A-Z_]+|MEDIA_ROOT)='

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ERRORS=0
fail() {
    log_error "$1"
    ERRORS=$((ERRORS + 1))
}

show_help() {
    echo -e "${CYAN}Deploy Immich (photos), Jellyfin (video), Navidrome (music) and${NC}"
    echo -e "${CYAN}Audiobookshelf (audiobooks, podcasts) on this host${NC}"
    echo ""
    echo "Usage: deploy-media.sh [options]"
    echo ""
    echo "Options:"
    echo "  --check         Run preflight checks only, change nothing"
    echo "  --no-immich     Skip Immich"
    echo "  --no-jellyfin   Skip Jellyfin"
    echo "  --no-navidrome  Skip Navidrome"
    echo "  --no-audiobookshelf"
    echo "                  Skip Audiobookshelf"
    echo "  --no-ml         Run Immich without machine learning (faces, smart search)"
    echo "  --tailscale     Expose each service over HTTPS on this host's tailnet name"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Paths, ports and versions come from .env (see the Media section of"
    echo "env/.env.example and MEDIA.md)."
}

# Run a command as root only when the current user is not already root
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Letters and digits only - Immich rejects anything else in DB_PASSWORD
generate_db_password() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 24
    else
        head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

# Safe value replacement using awk to avoid regex issues. Rewrites the file in
# place (not mv) so a 600 .env keeps its permissions.
replace_value() {
    local key="$1"
    local new_value="$2"
    local file="$3"

    awk -v key="$key" -v new="$new_value" '
        index($0, key "=") == 1 { print key "=" new; next }
        { print }
    ' "$file" > "${file}.tmp" && cat "${file}.tmp" > "$file" && rm -f "${file}.tmp"
}

load_env() {
    set -a
    # shellcheck source=/dev/null
    source "$1"
    set +a
}

# Nearest existing ancestor of a path (the directory may not exist yet)
existing_ancestor() {
    local path="$1"
    while [ ! -e "$path" ]; do
        path="$(dirname "$path")"
    done
    echo "$path"
}

# Check where a data path will land: filesystem type, free space, OS disk
# Roles: db (local Unix filesystem only), immich (Unix filesystem), media (anything)
check_storage() {
    local label="$1"
    local path="$2"
    local role="$3"
    local base fstype free_gb

    base="$(existing_ancestor "$path")"
    fstype="$(stat -f -c %T "$base")"
    free_gb="$(df -BG --output=avail "$base" | tail -n 1 | tr -dc '0-9')"
    log_info "${label}: ${path} (${fstype}, ${free_gb}GB free)"

    case "$fstype" in
        msdos|vfat|exfat|fuseblk|ntfs*)
            if [ "$role" != "media" ]; then
                fail "${label} is on ${fstype}, which has no Unix ownership/permissions - use ext4"
            fi
            ;;
        nfs*|cifs|smb*|fuse*)
            if [ "$role" = "db" ]; then
                fail "${label} is on a network filesystem (${fstype}) - the database must be on local disk"
            fi
            ;;
    esac

    if [ "$role" = "db" ] && [ "$free_gb" -lt 10 ]; then
        fail "${label} needs at least 10GB free"
    fi

    # Bulk data on the OS disk: a missing mount is an error, otherwise a warning
    if [ "$role" != "db" ] && [ "$(stat -c %d "$base")" = "$(stat -c %d /)" ]; then
        case "$path" in
            /mnt/*|/media/*)
                fail "${label} resolves to the OS disk - is the external drive mounted? (${base})"
                ;;
            *)
                log_warn "${label} is on the OS disk; photos and movies will fill it. Point it at an external drive."
                ;;
        esac
    fi
}

port_in_use() {
    ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
}

container_exists() {
    docker ps -a --format '{{.Names}}' | grep -qx "$1"
}

check_port() {
    local label="$1"
    local port="$2"
    local container="$3"

    if ! command -v ss &> /dev/null; then
        return
    fi
    if port_in_use "$port" && ! container_exists "$container"; then
        fail "Port ${port} (${label}) is already in use by another process - change it in .env"
    fi
}

# Create a directory (with sudo if needed), owned by $2 when given.
# Existing directories are left exactly as they are.
ensure_dir() {
    local dir="$1"
    local owner="${2:-}"

    if [ -d "$dir" ]; then
        return
    fi
    mkdir -p "$dir" 2>/dev/null || as_root mkdir -p "$dir"
    if [ -n "$owner" ]; then
        as_root chown "$owner" "$dir"
    fi
    log_success "Created ${dir}"
}

# Hand a service's own directory tree to the user its container runs as
ensure_owner() {
    local dir="$1"
    local owner="$2"

    if [ "$(stat -c '%u:%g' "$dir")" != "$owner" ]; then
        as_root chown -R "$owner" "$dir"
        log_info "Set owner ${owner} on ${dir}"
    fi
}

# URL a local client uses for a service bound to HOST_IP-style addresses
local_url() {
    local ip="$1"
    local port="$2"

    case "$ip" in
        0.0.0.0) echo "http://$(hostname -I | awk '{print $1}'):${port}" ;;
        127.0.0.1) echo "http://127.0.0.1:${port} (this host only)" ;;
        *) echo "http://${ip}:${port}" ;;
    esac
}

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

CHECK_ONLY=false
WITH_IMMICH=true
WITH_JELLYFIN=true
WITH_NAVIDROME=true
WITH_AUDIOBOOKSHELF=true
WITH_ML=true
WITH_TAILSCALE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true ;;
        --no-immich) WITH_IMMICH=false ;;
        --no-jellyfin) WITH_JELLYFIN=false ;;
        --no-navidrome) WITH_NAVIDROME=false ;;
        --no-audiobookshelf) WITH_AUDIOBOOKSHELF=false ;;
        --no-ml) WITH_ML=false ;;
        --tailscale) WITH_TAILSCALE=true ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
    shift
done

if [ "$WITH_IMMICH" = false ] && [ "$WITH_JELLYFIN" = false ] \
    && [ "$WITH_NAVIDROME" = false ] && [ "$WITH_AUDIOBOOKSHELF" = false ]; then
    log_error "Nothing to deploy: every service was skipped"
    exit 1
fi

# Jellyfin, Navidrome and Audiobookshelf all read from MEDIA_ROOT
WITH_LIBRARY=false
if [ "$WITH_JELLYFIN" = true ] || [ "$WITH_NAVIDROME" = true ] || [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    WITH_LIBRARY=true
fi

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  HomeCore Media Deploy                     ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------

if [ ! -f "$ENV_FILE" ]; then
    if [ "$CHECK_ONLY" = true ]; then
        log_warn ".env not found - checking against env/.env.example defaults"
        load_env "$ENV_EXAMPLE"
    else
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        log_warn "Created .env from env/.env.example - review DATA_ROOT and HOST_IP"
    fi
fi

if [ -f "$ENV_FILE" ]; then
    # Fill in media keys an older .env does not have yet; never touch existing values
    missing=()
    while IFS= read -r line; do
        key="${line%%=*}"
        if ! grep -q "^${key}=" "$ENV_FILE"; then
            missing+=("$line")
        fi
    done < <(grep -E "$MEDIA_KEYS_RE" "$ENV_EXAMPLE")

    if [ ${#missing[@]} -gt 0 ]; then
        if [ "$CHECK_ONLY" = true ]; then
            log_info "Would add ${#missing[@]} media settings to .env (using example defaults for this check)"
            load_env <(printf '%s\n' "${missing[@]}")
        else
            {
                echo ""
                echo "# Media settings added by deploy-media.sh on $(date +%F) - see env/.env.example"
                printf '%s\n' "${missing[@]}"
            } >> "$ENV_FILE"
            log_success "Added ${#missing[@]} media settings to .env"
        fi
    fi
    load_env "$ENV_FILE"
fi

DATA_ROOT="${DATA_ROOT:-/srv/orion/homecore}"
HOST_IP="${HOST_IP:-127.0.0.1}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
IMMICH_PORT="${IMMICH_PORT:-2283}"
JELLYFIN_PORT="${JELLYFIN_PORT:-8096}"
JELLYFIN_HOST_IP="${JELLYFIN_HOST_IP:-$HOST_IP}"
NAVIDROME_PORT="${NAVIDROME_PORT:-4533}"
AUDIOBOOKSHELF_PORT="${AUDIOBOOKSHELF_PORT:-13378}"
IMMICH_DB_DIR="${DATA_ROOT}/immich/postgres"

# Generate the database password once; refuse if a database already exists without one
if [ "$WITH_IMMICH" = true ]; then
    if [ -z "${IMMICH_DB_PASSWORD:-}" ] || [ "$IMMICH_DB_PASSWORD" = "changeme" ]; then
        if [ -n "$(ls -A "$IMMICH_DB_DIR" 2>/dev/null)" ]; then
            fail "IMMICH_DB_PASSWORD is unset but ${IMMICH_DB_DIR} already holds a database - restore the original password in .env"
        elif [ "$CHECK_ONLY" = true ]; then
            log_info "Would generate IMMICH_DB_PASSWORD"
        else
            replace_value "IMMICH_DB_PASSWORD" "$(generate_db_password)" "$ENV_FILE"
            load_env "$ENV_FILE"
            log_success "Generated IMMICH_DB_PASSWORD"
        fi
    elif [[ ! "$IMMICH_DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
        fail "IMMICH_DB_PASSWORD may only contain letters and digits"
    fi
fi

# -----------------------------------------------------------------------------
# Preflight Checks
# -----------------------------------------------------------------------------

log_info "Running preflight checks..."

DOCKER_OK=false
if ! command -v docker &> /dev/null; then
    fail "Docker is not installed (https://docs.docker.com/engine/install/debian/)"
elif ! docker info &> /dev/null; then
    fail "Cannot reach the Docker daemon - add your user to the docker group or run with sudo"
elif ! docker compose version &> /dev/null; then
    fail "Docker Compose v2 plugin is missing (apt install docker-compose-plugin)"
else
    DOCKER_OK=true
    log_success "Docker $(docker version --format '{{.Server.Version}}'), $(docker compose version --short 2>/dev/null || echo 'compose v2')"
    # The ML and Jellyfin memory caps are what keep a spike from OOM-killing the host
    if [ "$(docker info --format '{{.MemoryLimit}}' 2>/dev/null)" != "true" ]; then
        log_warn "Docker cannot enforce memory limits here, so IMMICH_ML_MEM_LIMIT/JELLYFIN_MEM_LIMIT are ignored."
        log_warn "On a Pi: append 'cgroup_enable=memory' to /boot/firmware/cmdline.txt and reboot (MEDIA.md)"
    fi
    if [ "$(docker info --format '{{.CgroupVersion}}' 2>/dev/null)" = "1" ]; then
        log_warn "Docker uses cgroup v1: Immich's server may run out of JS heap on first start (MEDIA.md)"
    fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64|x86_64)
        log_success "Architecture: ${ARCH}"
        ;;
    *)
        fail "Unsupported architecture ${ARCH} - Immich and Jellyfin need 64-bit (on a Pi, the 64-bit OS)"
        ;;
esac

mem_total_mb="$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
mem_avail_mb="$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)"
log_info "Memory: ${mem_avail_mb}MB available of ${mem_total_mb}MB"
if [ "$WITH_IMMICH" = true ] && [ "$WITH_ML" = true ]; then
    if [ "$mem_total_mb" -lt 4000 ]; then
        fail "Immich machine learning needs more than 4GB RAM - re-run with --no-ml"
    elif [ "$mem_avail_mb" -lt 4500 ]; then
        # Measured: ML peaks ~3GB with all models loaded, server + Postgres ~1.2GB
        log_warn "Under 4.5GB available and Immich peaks near 4GB during imports: run big imports overnight,"
        log_warn "set job concurrency to 1, or turn off OCR (MEDIA.md)"
    fi
fi

PAGE_SIZE="$(getconf PAGESIZE)"
if [ "$WITH_JELLYFIN" = true ] && [ "$PAGE_SIZE" != "4096" ]; then
    log_warn "Kernel page size is ${PAGE_SIZE}; Jellyfin is expected to restart-loop on it (exit 133). Checked after start."
fi

if [ "$WITH_IMMICH" = true ]; then
    check_storage "Immich database" "$IMMICH_DB_DIR" db
    check_storage "Immich library" "${IMMICH_UPLOAD_LOCATION:-/srv/orion/media/immich}" immich
fi
if [ "$WITH_JELLYFIN" = true ]; then
    check_storage "Jellyfin config" "${DATA_ROOT}/jellyfin" db
fi
if [ "$WITH_NAVIDROME" = true ]; then
    check_storage "Navidrome database" "${DATA_ROOT}/navidrome" db
fi
if [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    check_storage "Audiobookshelf database" "${DATA_ROOT}/audiobookshelf" db
fi
if [ "$WITH_LIBRARY" = true ]; then
    check_storage "Media library" "${MEDIA_ROOT:-/srv/orion/media/library}" media
fi

if [ "$DOCKER_OK" = true ]; then
    [ "$WITH_IMMICH" = true ] && check_port "Immich" "$IMMICH_PORT" immich_server
    [ "$WITH_JELLYFIN" = true ] && check_port "Jellyfin" "$JELLYFIN_PORT" jellyfin
    [ "$WITH_NAVIDROME" = true ] && check_port "Navidrome" "$NAVIDROME_PORT" navidrome
    [ "$WITH_AUDIOBOOKSHELF" = true ] && check_port "Audiobookshelf" "$AUDIOBOOKSHELF_PORT" audiobookshelf
fi

if [ "$WITH_TAILSCALE" = true ]; then
    if ! command -v tailscale &> /dev/null; then
        fail "--tailscale given but tailscale is not installed (https://tailscale.com/download/linux)"
    elif ! tailscale status &> /dev/null; then
        fail "--tailscale given but this host is not logged in (sudo tailscale up)"
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    log_error "${ERRORS} preflight check(s) failed - nothing was started"
    exit 1
fi
log_success "Preflight checks passed"

if [ "$CHECK_ONLY" = true ]; then
    exit 0
fi

# -----------------------------------------------------------------------------
# Directories
# -----------------------------------------------------------------------------

log_info "Preparing directories..."

ensure_dir "$DATA_ROOT" "$(id -u):$(id -g)"

if [ "$WITH_IMMICH" = true ]; then
    ensure_dir "$IMMICH_DB_DIR"
    ensure_dir "${DATA_ROOT}/immich/model-cache"
    ensure_dir "$IMMICH_UPLOAD_LOCATION"
fi

# Service state directories must exist with the right owner before first
# start, or Docker creates them as root and the container (PUID:PGID) cannot write
OWNED_DIRS=()
LIBRARY_DIRS=()
if [ "$WITH_JELLYFIN" = true ]; then
    OWNED_DIRS+=(jellyfin/config jellyfin/cache)
    LIBRARY_DIRS+=(Movies TV Music)
fi
if [ "$WITH_NAVIDROME" = true ]; then
    OWNED_DIRS+=(navidrome/data)
    LIBRARY_DIRS+=(Music)
fi
if [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    OWNED_DIRS+=(audiobookshelf/config audiobookshelf/metadata)
    LIBRARY_DIRS+=(Audiobooks Podcasts)
fi
for dir in "${OWNED_DIRS[@]}"; do
    ensure_dir "${DATA_ROOT}/${dir}"
    ensure_owner "${DATA_ROOT}/${dir}" "${PUID}:${PGID}"
done

# Missing library folders are created empty and owned by PUID:PGID so you can
# add files; existing folders and everything in them are never touched
if [ "$WITH_LIBRARY" = true ]; then
    ensure_dir "$MEDIA_ROOT" "${PUID}:${PGID}"
    for sub in "${LIBRARY_DIRS[@]}"; do
        ensure_dir "${MEDIA_ROOT}/${sub}" "${PUID}:${PGID}"
    done
fi

# -----------------------------------------------------------------------------
# Start Services
# -----------------------------------------------------------------------------

PROFILE_ARGS=()
SERVICES=()
CONTAINERS=()
if [ "$WITH_IMMICH" = true ]; then
    PROFILE_ARGS+=(--profile immich)
    SERVICES+=(immich-server immich-redis immich-database)
    CONTAINERS+=(immich_server immich_redis immich_postgres)
    if [ "$WITH_ML" = true ]; then
        SERVICES+=(immich-machine-learning)
        CONTAINERS+=(immich_machine_learning)
    fi
fi
if [ "$WITH_JELLYFIN" = true ]; then
    PROFILE_ARGS+=(--profile jellyfin)
    SERVICES+=(jellyfin)
    CONTAINERS+=(jellyfin)
fi
if [ "$WITH_NAVIDROME" = true ]; then
    PROFILE_ARGS+=(--profile navidrome)
    SERVICES+=(navidrome)
    CONTAINERS+=(navidrome)
fi
if [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    PROFILE_ARGS+=(--profile audiobookshelf)
    SERVICES+=(audiobookshelf)
    CONTAINERS+=(audiobookshelf)
fi

cd "$REPO_ROOT"

log_info "Pulling images (the first run downloads a few GB)..."
docker compose "${PROFILE_ARGS[@]}" pull "${SERVICES[@]}"

# Naming the services keeps compose from starting anything outside the media stacks
log_info "Starting: ${SERVICES[*]}"
docker compose "${PROFILE_ARGS[@]}" up -d "${SERVICES[@]}"

# -----------------------------------------------------------------------------
# Wait for Health
# -----------------------------------------------------------------------------

# First start runs database migrations; allow a slow SD/NVMe-backed Pi 10 minutes
log_info "Waiting for containers to become healthy..."

declare -A RESULT=()
deadline=$((SECONDS + 600))
while :; do
    pending=0
    for name in "${CONTAINERS[@]}"; do
        [ -n "${RESULT[$name]:-}" ] && continue
        IFS='/' read -r status health restarts < <(docker inspect -f \
            '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}/{{.RestartCount}}' \
            "$name" 2>/dev/null || echo "missing/none/0")
        if [ "$restarts" -ge 3 ] || [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            RESULT[$name]="failed"
        elif [ "$status" = "running" ] && { [ "$health" = "healthy" ] || [ "$health" = "none" ]; }; then
            RESULT[$name]="ok"
        else
            pending=$((pending + 1))
        fi
    done
    [ "$pending" -eq 0 ] && break
    if [ "$SECONDS" -ge "$deadline" ]; then
        for name in "${CONTAINERS[@]}"; do
            [ -z "${RESULT[$name]:-}" ] && RESULT[$name]="timeout"
        done
        break
    fi
    sleep 5
done

FAILED=0
for name in "${CONTAINERS[@]}"; do
    if [ "${RESULT[$name]}" = "ok" ]; then
        log_success "${name} is up"
        continue
    fi
    FAILED=$((FAILED + 1))
    log_error "${name}: ${RESULT[$name]} - last log lines:"
    docker logs --tail 20 "$name" 2>&1 | sed 's/^/    /' || true
    if [ "$name" = "jellyfin" ] && [ "$PAGE_SIZE" != "4096" ]; then
        echo ""
        log_warn "Jellyfin is known to fail on the Pi 5's ${PAGE_SIZE}-byte-page kernel. Switch to the 4K kernel:"
        echo "    echo 'kernel=kernel8.img' | sudo tee -a /boot/firmware/config.txt && sudo reboot"
        echo "    # after reboot: getconf PAGESIZE  -> 4096, then re-run this script (see MEDIA.md)"
    fi
done

# -----------------------------------------------------------------------------
# Tailscale (optional)
# -----------------------------------------------------------------------------

TS_HOST=""
if [ "$WITH_TAILSCALE" = true ]; then
    TS=(tailscale)
    [ "$(id -u)" -ne 0 ] && TS=(sudo tailscale)
    TS_HOST="$(tailscale status --json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    serve_status="$("${TS[@]}" serve status 2>/dev/null || true)"

    ts_serve() {
        local label="$1"
        local https_port="$2"
        local port="$3"
        local ip="$4"

        [ "$ip" = "0.0.0.0" ] && ip=127.0.0.1
        if grep -q ":${https_port}\b" <<< "$serve_status"; then
            log_info "Tailscale :${https_port} is already configured - left as-is (tailscale serve status)"
            return
        fi
        "${TS[@]}" serve --bg --https="$https_port" "http://${ip}:${port}" > /dev/null
        log_success "${label} published on the tailnet at :${https_port}"
    }

    [ "$WITH_IMMICH" = true ] && ts_serve "Immich" "${IMMICH_TAILSCALE_PORT:-14443}" "$IMMICH_PORT" "$HOST_IP"
    [ "$WITH_JELLYFIN" = true ] && ts_serve "Jellyfin" "${JELLYFIN_TAILSCALE_PORT:-16443}" "$JELLYFIN_PORT" "$JELLYFIN_HOST_IP"
    [ "$WITH_NAVIDROME" = true ] && ts_serve "Navidrome" "${NAVIDROME_TAILSCALE_PORT:-18443}" "$NAVIDROME_PORT" "$HOST_IP"
    [ "$WITH_AUDIOBOOKSHELF" = true ] && ts_serve "Audiobookshelf" "${AUDIOBOOKSHELF_TAILSCALE_PORT:-20443}" "$AUDIOBOOKSHELF_PORT" "$HOST_IP"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Media Services Running!                  ${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  ${FAILED} container(s) need attention (above) ${NC}"
    echo -e "${YELLOW}============================================${NC}"
fi
echo ""
if [ "$WITH_IMMICH" = true ]; then
    echo "Immich:    $(local_url "$HOST_IP" "$IMMICH_PORT")"
    [ -n "$TS_HOST" ] && echo "           https://${TS_HOST}:${IMMICH_TAILSCALE_PORT:-14443}"
fi
if [ "$WITH_JELLYFIN" = true ]; then
    echo "Jellyfin:  $(local_url "$JELLYFIN_HOST_IP" "$JELLYFIN_PORT")"
    [ -n "$TS_HOST" ] && echo "           https://${TS_HOST}:${JELLYFIN_TAILSCALE_PORT:-16443}"
fi
if [ "$WITH_NAVIDROME" = true ]; then
    echo "Navidrome: $(local_url "$HOST_IP" "$NAVIDROME_PORT")"
    [ -n "$TS_HOST" ] && echo "           https://${TS_HOST}:${NAVIDROME_TAILSCALE_PORT:-18443}"
fi
if [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    echo "Audiobookshelf: $(local_url "$HOST_IP" "$AUDIOBOOKSHELF_PORT")"
    [ -n "$TS_HOST" ] && echo "           https://${TS_HOST}:${AUDIOBOOKSHELF_TAILSCALE_PORT:-20443}"
fi
echo ""
echo -e "${YELLOW}Next Steps (details in MEDIA.md):${NC}"
echo ""
if [ "$WITH_IMMICH" = true ]; then
    echo "- Immich: open the URL and create the admin account (first user)."
    echo "  Administration > Settings > Job Settings: set concurrency to 1."
    [ "$WITH_ML" = false ] && echo "  Administration > Settings > Machine Learning: turn it off (no ML container)."
    echo "  Phone: install the Immich app, use the tailnet URL, enable backup."
    echo "- Back up the Immich library off this device - it becomes the only copy."
fi
if [ "$WITH_JELLYFIN" = true ]; then
    echo "- Jellyfin: run the setup wizard, add /media/Movies and /media/TV."
    echo "  Dashboard > Playback > Transcoding: keep hardware acceleration at None."
fi
if [ "$WITH_NAVIDROME" = true ]; then
    echo "- Navidrome: open the URL and create the admin account (first visit)."
    echo "  Phone: any Subsonic app (Symfonium, Amperfy), server = the tailnet URL."
fi
if [ "$WITH_AUDIOBOOKSHELF" = true ]; then
    echo "- Audiobookshelf: create the root user, then add libraries /audiobooks"
    echo "  (Books) and /podcasts (Podcasts). Phone: the Audiobookshelf app."
fi
echo ""

[ "$FAILED" -eq 0 ] || exit 1
