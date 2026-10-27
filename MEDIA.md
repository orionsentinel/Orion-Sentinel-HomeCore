# Media: Immich + Jellyfin on a Raspberry Pi 5

Two optional profiles that replace photo and streaming subscriptions with services on your own hardware:

| Service | Replaces | Profile | Port | Tailscale (`--tailscale`) |
|---------|----------|---------|------|---------------------------|
| Immich | Google Photos / iCloud Photos | `immich` | 2283 | `https://<host>.<tailnet>.ts.net:14443` |
| Jellyfin | Plex, and streaming services for content you own | `jellyfin` | 8096 | `https://<host>.<tailnet>.ts.net:16443` |

Jellyfin only streams files you have. It does not replace a streaming catalogue.

## Read first: Pi 5 constraints

1. **Immich is not a backup.** Once phones upload to it and you free up phone or iCloud space, the Pi's drive holds the **only copy** of your photos. Set up the off-device copy in [Backups](#backups) before you delete anything from a phone.
2. **RAM.** Immich asks for 6GB. An 8GB Pi that already runs other services has less than that free. Measured in testing: Immich server ~700MB, Postgres ~470MB, Jellyfin ~200MB idle. Machine learning drops to ~250MB idle, because models unload after 5 minutes, and peaks at ~3GB while the face, smart-search and OCR models are all loaded. The stack caps ML at `IMMICH_ML_MEM_LIMIT` (4G) and Jellyfin at `JELLYFIN_MEM_LIMIT` (2G), so a runaway restarts one container instead of OOM-killing Home Assistant. Run the first big import overnight. On a large library it takes days, not hours.
3. **No hardware video encoder.** The Pi 5 dropped the H.264 encoder. Jellyfin transcodes on the CPU, which handles about one 1080p stream. Keep files in H.264/HEVC and let clients direct-play them.
4. **16K-page kernel.** Raspberry Pi OS boots the Pi 5 with 16K memory pages. Jellyfin restart-loops on it (`Restarting (133)`) and never recovers on its own. The deploy script detects that and prints the fix (see [4K kernel](#4k-page-kernel-jellyfin)).

## Deploy

The bulk data (photos, movies) goes on a large external drive. The Immich database and service config stay under `DATA_ROOT` on the SSD/NVMe, because Postgres must not sit on a network share or a slow USB HDD.

```bash
# 1. Get the repo (or `git pull` an existing checkout)
git clone https://github.com/orionsentinel/Orion-Sentinel-HomeCore.git
cd Orion-Sentinel-HomeCore
[ -f .env ] || cp env/.env.example .env

# 2. Point the media settings at the external drive (Media section of .env)
nano .env

# 3. Dry run: checks architecture, RAM, page size, filesystems, free space and ports. Changes nothing.
./scripts/deploy-media.sh --check

# 4. Deploy and publish on the tailnet
./scripts/deploy-media.sh --tailscale
```

The script is idempotent. Re-run it after changing `.env` or bumping a version. It:

- adds any media keys missing from an older `.env`;
- generates `IMMICH_DB_PASSWORD`, letters and digits only as Immich requires. It refuses to do this if a database already exists;
- creates the Jellyfin directories as `PUID:PGID` before first start. Otherwise Docker creates them as root and Jellyfin cannot write to them;
- starts **only** the media containers, and never touches Home Assistant or other stacks;
- waits for health checks and catches restart loops;
- with `--tailscale`, runs `tailscale serve` on ports 14443 and 16443 and leaves any existing mapping on those ports alone.

Options: `--no-immich`, `--no-jellyfin`, `--no-ml` (Immich without faces or smart search, for hosts short on RAM).

For logs, use `./scripts/orionctl logs immich-server` (or `jellyfin`). On a host where HomeCore also manages Home Assistant, `./scripts/orionctl up media` works too. If Home Assistant runs some other way, use the deploy script: `orionctl up` also starts HomeCore's own Home Assistant.

### Values for `acuity-pi`

`acuity-pi` is the Pi 5 that runs Métis Acuity. It already serves other services from the `/mnt/nextcloud-data` drive and over `tailscale serve` on ports 443, 8443, 10443 and 12443.

```bash
IMMICH_UPLOAD_LOCATION=/mnt/nextcloud-data/immich
MEDIA_ROOT=/mnt/nextcloud-data/media
# Lets TVs on the home LAN reach Jellyfin; leave 127.0.0.1 for tailnet-only access
JELLYFIN_HOST_IP=192.168.2.107
```

Before you deploy, check `df -h /mnt/nextcloud-data` and plan for the library plus 10–20% for thumbnails and transcoded video. If the drive is not mounted, `--check` fails rather than writing photos onto the 256GB OS disk.

### 4K-page kernel (Jellyfin)

Do this only if the deploy script reports that Jellyfin is restart-looping.

```bash
getconf PAGESIZE                                   # 16384 = default Pi 5 kernel
echo 'kernel=kernel8.img' | sudo tee -a /boot/firmware/config.txt
sudo reboot
getconf PAGESIZE                                   # 4096
./scripts/deploy-media.sh --tailscale
```

To revert, remove the line and reboot. The 4K kernel is slightly slower on some memory-heavy work, which you won't notice here. If the Pi uses other kernel modules, for example the Hailo AI HAT, check them after the reboot (`lsmod | grep hailo`).

## First-run setup

### Immich

1. Open the Immich URL. The first account you create becomes the admin.
2. **Administration → Settings → Job Settings:** set concurrency to 1 for Thumbnail Generation, Smart Search, Face Detection and Video Conversion. Raise them later once the backlog is cleared.
3. **Administration → Settings → Video Transcoding:** iPhone and modern Android videos are HEVC. If HEVC is not in *Accepted video codecs*, Immich re-encodes every video on the CPU. Add HEVC unless you need playback in browsers without HEVC support.
4. **Administration → Settings → Server → External Domain:** set the tailnet URL so shared links work.
5. **Phones:** install Tailscale and the Immich app. Use `https://<host>.<tailnet>.ts.net:14443` as the server URL (if the app rejects it, add `/api` to the end), then enable backup, including background backup.
6. **Second adult:** create a separate user and turn on partner sharing. One account per person keeps face clusters and libraries clean.
7. **Existing libraries** (Google Takeout, Apple Photos exports): import them from a computer with the official CLI (`npx @immich/cli upload`) or the community tool `immich-go`, not through the phone app.

Machine learning runs locally on the CPU. The Pi's VideoCore GPU and Hailo NPU are not Immich ML backends.

### Jellyfin

1. Open the Jellyfin URL and run the wizard. Add the libraries `/media/Movies`, `/media/TV` and `/media/Music`. The library is mounted read-only.
2. **Dashboard → Playback → Transcoding:** leave Hardware acceleration at *None*.
3. Create one user per person. Kids get a profile with a maximum parental rating.
4. **Clients:** use the official Jellyfin apps, Swiftfin, or Infuse on Apple TV/iOS. Infuse direct-plays almost everything, which suits a Pi. Over Tailscale, set the client's maximum streaming bitrate to its highest value so it does not request a transcode.
5. **Adding files** from another machine. No new services are needed:

   ```bash
   rsync -avh --progress "Some Film (2024).mkv" acuity-pi:/mnt/nextcloud-data/media/Movies/
   ```

### File naming (Jellyfin)

Jellyfin matches files by name, so naming decides whether you get posters and metadata:

```
Movies/The Matrix (1999)/The Matrix (1999).mkv     # year in parentheses is required
TV/Severance/Season 01/Severance - S01E01.mkv      # zero-padded SxxExx is required
```

Strip release-group, resolution and codec tags from names. Give subtitles the same base name as the video (`The Matrix (1999).en.srt`). After adding files: **Dashboard → Libraries → Scan All Libraries**; fix mismatches with **Identify**.

### Dashboard (Homepage)

Add this to the Homepage `services.yaml`:

```yaml
- Media:
    - Immich:
        href: https://<host>.<tailnet>.ts.net:14443
        icon: immich.png
        description: Photos
    - Jellyfin:
        href: https://<host>.<tailnet>.ts.net:16443
        icon: jellyfin.png
        description: Movies & TV
```

## Backups

| Data | Covered by | Notes |
|------|-----------|-------|
| Immich database | Immich itself (nightly dump into `$IMMICH_UPLOAD_LOCATION/backups`) and `./scripts/orionctl backup` | Small |
| Jellyfin config | `./scripts/orionctl backup` | Metadata images excluded (re-downloadable) |
| **Photos and videos** | **Nothing yet: you must add this** | The only copy once phones are cleaned up |
| Movies/TV | Optional | Usually replaceable |

Back up `$IMMICH_UPLOAD_LOCATION` to a different physical device, and ideally a second location as well. The `thumbs/` and `encoded-video/` subfolders can be regenerated and may be excluded. With restic:

```bash
export RESTIC_REPOSITORY=/mnt/backup-disk/immich-restic   # or an off-site repo (B2, SFTP, Storage Box)
restic init
restic backup "$IMMICH_UPLOAD_LOCATION" \
    --exclude "$IMMICH_UPLOAD_LOCATION/thumbs" \
    --exclude "$IMMICH_UPLOAD_LOCATION/encoded-video"
restic check
```

Schedule it with a systemd timer. Test a restore once before you rely on it.

## Upgrades

- **Immich:** read the release notes first, because breaking changes ship in minor versions. Set `IMMICH_VERSION` in `.env` and re-run `./scripts/deploy-media.sh`. If the release's `docker-compose.yml` changes the database or Valkey image digest, update `stacks/immich/compose.yaml` to match.
- **Jellyfin:** back up first (`./scripts/orionctl backup`), because database migrations cannot be rolled back. Then set `JELLYFIN_VERSION` and re-run the script.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-------|
| `jellyfin` restart-loops right after start (`Restarting (133)`) | 16K-page kernel | [4K kernel](#4k-page-kernel-jellyfin) |
| `immich_machine_learning` keeps restarting; `docker inspect -f '{{.State.OOMKilled}}' immich_machine_learning` → `true` | Hit `IMMICH_ML_MEM_LIMIT` | Keep it at 4G or more (peak is ~3GB). If the host can't spare that, turn off OCR in **Administration → Settings → Machine Learning** |
| Host sluggish during first import | Thumbnails + ML + transcoding at once | Concurrency 1; pause queues in **Administration → Jobs** |
| Jellyfin cannot write `/config` | Directory created as root | Re-run the deploy script (it fixes the owner) |
| Jellyfin library shows nothing | Files not readable by `PUID` | `sudo chmod -R a+rX "$MEDIA_ROOT"` |
| Remote playback buffers | CPU transcode | Raise the client bitrate limit; re-encode the file to H.264/HEVC |
| `--check` says the drive resolves to the OS disk | External drive not mounted | Mount it (check `/etc/fstab`), then re-run |
| Deploy warns that Docker cannot enforce memory limits | Memory cgroup disabled at boot | Append `cgroup_enable=memory` to the single line in `/boot/firmware/cmdline.txt`, then reboot |
| `immich_server` logs `ERR_WORKER_OUT_OF_MEMORY` at "Starting geodata import" | Host on cgroup v1, where Node sizes its heap at ~256MB | Create `compose.override.yaml` in the repo root with `services: {immich-server: {environment: [NODE_OPTIONS=--max-old-space-size=2048]}}` and re-run |
