#!/usr/bin/env bash
set -euo pipefail
: "${JAVA:?Set JAVA in /etc/hytale/server.env}"
: "${TAILSCALE_IP:?Set TAILSCALE_IP in /etc/hytale/server.env}"
: "${PORT:=5520}" "${HEAP_MIN:=2G}" "${HEAP_MAX:=5G}" "${AUTH_MODE:=authenticated}"
[[ "$TAILSCALE_IP" =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a Tailscale IPv4 address' >&2; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]] && ((10#$PORT > 0 && 10#$PORT <= 65535)) || exit 1
case "$AUTH_MODE" in authenticated|offline|insecure) ;; *) echo 'Unsupported auth mode' >&2; exit 1;; esac
# Refuse wildcard/public binds and wait for the exact private address to exist.
for attempt in {1..60}; do
  if ip -4 -o addr show dev tailscale0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$TAILSCALE_IP"; then
    exec "$JAVA" "-Xms$HEAP_MIN" "-Xmx$HEAP_MAX" -jar HytaleServer.jar \
      --assets ../Assets.zip --auth-mode "$AUTH_MODE" --bind "$TAILSCALE_IP:$PORT" \
      --backup --backup-dir backups --backup-frequency 30
  fi
  sleep 2
done
echo 'Tailscale address unavailable; refusing to start on another address' >&2
exit 1
