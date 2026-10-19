#!/usr/bin/env bash
# Consistent administrator snapshot: requires Hytale to be stopped.
set -euo pipefail
[[ "$EUID" == 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
state=$(systemctl show hytale -p ActiveState --value)
[[ "$state" == inactive || "$state" == failed ]] || { echo 'Stop Hytale before making an offline snapshot' >&2; exit 1; }
umask 077
stamp=$(date -u +%Y%m%dT%H%M%SZ)
destination=$(mktemp -d "/srv/hytale/backups/snapshot-$stamp-XXXXXX")
items=()
for item in universe mods config.json permissions.json bans.json whitelist.json; do
  [[ ! -e "/srv/hytale/game/Server/$item" ]] || items+=("$item")
done
(( ${#items[@]} )) || { echo 'No state to back up' >&2; exit 1; }
tar -C /srv/hytale/game/Server -czf "$destination/world-state.tar.gz" -- "${items[@]}"
cp -a /etc/hytale/server.env /etc/systemd/system/hytale.service "$destination/"
echo "$destination"
