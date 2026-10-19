#!/usr/bin/env bash
# Read-only; review output for hostnames/IPs before sharing it publicly.
set -u
uptime
free -h
df -h /srv/hytale
systemctl show hytale -p ActiveState -p ActiveEnterTimestamp -p NRestarts -p MemoryCurrent
ss -uln | grep ':5520' || true
tailscale status
tailscale debug metrics | grep -E 'wireguard_handshake_.*completed|peer_wireguard_state_established' || true
echo 'Recent Hytale warnings (may include player names and IPs):'
journalctl -u hytale -n 100 --no-pager | grep -Ei 'warn|error|exception' | cut -c1-500 || true
