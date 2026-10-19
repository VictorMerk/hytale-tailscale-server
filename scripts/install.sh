#!/usr/bin/env bash
# Installs service plumbing only; does not download game files or touch firewalls.
set -euo pipefail
[[ "$EUID" == 0 ]] || { echo 'Run with sudo' >&2; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v systemctl >/dev/null
[[ -x /usr/bin/java ]] || { echo 'Install Java 25 first' >&2; exit 1; }
version=$(/usr/bin/java -version 2>&1 | head -1)
[[ "$version" =~ \"25[\.\"] ]] || { echo 'This toolkit requires Java 25' >&2; exit 1; }
command -v python3 >/dev/null
[[ -d /sys/class/net/tailscale0 ]] || { echo 'Install and connect Tailscale first' >&2; exit 1; }
if [[ -e /etc/systemd/system/hytale.service || -e /etc/hytale/server.env || -e /srv/hytale/game/Server/HytaleServer.jar ]]; then
  echo 'Existing Hytale installation detected. Refusing to overwrite it; install manually.' >&2
  exit 1
fi
getent passwd hytale >/dev/null || useradd --system --home-dir /srv/hytale --shell /usr/sbin/nologin hytale
install -d -o hytale -g hytale /srv/hytale/game/Server /srv/hytale/backups
install -d -m 0755 /usr/local/lib/hytale /etc/hytale
install -m 0755 "$repo/scripts/launch.sh" /usr/local/lib/hytale/launch.sh
install -m 0755 "$repo/scripts/backup.sh" /usr/local/lib/hytale/backup.sh
install -m 0640 -o root -g hytale "$repo/config/server.env.example" /etc/hytale/server.env
install -m 0644 "$repo/systemd/hytale.service" /etc/systemd/system/hytale.service
systemctl daemon-reload
echo 'Installed, but NOT started or enabled. Edit /etc/hytale/server.env and supply game files; see README.'
