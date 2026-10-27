#!/bin/sh
# =============================================================================
# *arr disk guard
# =============================================================================
# Every minute, measures free space on the library drive (/data). Below
# ARR_MIN_FREE_GB it stops every torrent in qBittorrent, so downloads can never
# fill the drive that also holds the photo library. Torrents stay stopped
# until you start them again in qBittorrent.
# =============================================================================

set -u
trap 'exit 0' TERM INT

URL="${QBT_URL:-http://qbittorrent:5080}"
MIN_GB="${ARR_MIN_FREE_GB:-100}"
INTERVAL="${ARR_DISKGUARD_INTERVAL:-60}"
JAR="/tmp/qbt-cookies"

free_gb() {
    df -Pk /data | awk 'NR == 2 { print int($4 / 1048576) }'
}

# qBittorrent 5.x answers 204 (ok) or 401; 4.x answers 200 with "Ok." or "Fails."
login() {
    status="$(curl -sS -o /tmp/qbt-login -w '%{http_code}' -c "$JAR" -H "Referer: ${URL}" \
        --data-urlencode "username=${QBT_USERNAME:-admin}" \
        --data-urlencode "password=${QBT_PASSWORD:-}" \
        "${URL}/api/v2/auth/login" 2>/dev/null)"
    [ "$status" = "204" ] || { [ "$status" = "200" ] && [ "$(cat /tmp/qbt-login)" = "Ok." ]; }
}

# qBittorrent 5 renamed pause to stop; fall back for 4.x
stop_all() {
    login || return 1
    curl -fsS -b "$JAR" -o /dev/null -d "hashes=all" "${URL}/api/v2/torrents/stop" \
        || curl -fsS -b "$JAR" -o /dev/null -d "hashes=all" "${URL}/api/v2/torrents/pause"
}

echo "diskguard: stopping all torrents whenever /data has under ${MIN_GB}GB free (checked every ${INTERVAL}s)"

below=false
while :; do
    free="$(free_gb)"
    if [ "$free" -lt "$MIN_GB" ]; then
        # Repeat every cycle: new torrents may have been added since the last stop
        if stop_all; then
            [ "$below" = false ] && echo "diskguard: ${free}GB free, below ${MIN_GB}GB - stopped all torrents"
            below=true
        else
            echo "diskguard: ERROR ${free}GB free, below ${MIN_GB}GB, but could not log in to qBittorrent (not running, or QBT_PASSWORD in .env is wrong)"
        fi
    elif [ "$below" = true ]; then
        echo "diskguard: ${free}GB free again - torrents stay stopped until you start them"
        below=false
    fi
    # Backgrounded so a stop signal interrupts the wait instead of queuing behind it
    sleep "$INTERVAL" &
    wait $!
done
