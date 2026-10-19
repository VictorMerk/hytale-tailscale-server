# Hytale over Tailscale

A small, inspectable toolkit for running a **private Hytale dedicated server on Ubuntu/systemd**, including Oracle Cloud ARM64 VPSs. Friends connect through Tailscale; the game port stays off the public internet.

Built from a working two-player deployment on Ubuntu 24.04, Java 25, ARM64 and Hytale 0.7.2. Includes service plumbing, private-address validation, backup/import helpers, restricted friend sharing, and an evidence-based troubleshooting guide.

**No Hytale binaries, assets, accounts, private keys, player data or worlds are distributed here.** Obtain your own compatible server files through the official launcher/downloader. This is an independent project, not affiliated with Hypixel Studios, Oracle or Tailscale.

## What you need

- Ubuntu with systemd, `bash`, `iproute2`, `tar`, Python 3, and Java 25. The installation helper expects `/usr/bin/java`; change `JAVA` in the environment file if needed.
- Tailscale installed and connected on the server and each player PC.
- Compatible Hytale client/server versions, a game license, and server authentication for the official game.
- Capacity for Java **plus the OS and your existing applications**. A 2–5 GiB heap was used on a VPS with 12 GiB total RAM; it is an example, not a universal requirement.

Read the [official server manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual) for current Java, authentication and version requirements. Install Java and Tailscale from their official sources before continuing. This toolkit does not install packages, alter cloud rules, reset firewalls, or reconfigure Docker.

## Install on a new server

Review scripts before running them. `install.sh` refuses existing Hytale installations and does **not** start the game.

```bash
git clone https://github.com/VictorMerk/hytale-tailscale-server.git
cd hytale-tailscale-server
sudo bash scripts/install.sh
sudoedit /etc/hytale/server.env
```

Set `TAILSCALE_IP` to the server's own `tailscale ip -4` output. `100.101.102.103` in the examples is a placeholder, not a public demo server. Adjust heap sizes for your available memory. Keep `AUTH_MODE=authenticated` for official servers.

Copy your own `HytaleServer.jar` and `Assets.zip` to this layout:

```text
/srv/hytale/
  game/
    Assets.zip
    Server/
      HytaleServer.jar
      universe/             # Generated or imported later
  backups/
```

```bash
sudo chown hytale:hytale /srv/hytale/game/Assets.zip /srv/hytale/game/Server/HytaleServer.jar
java --version
sudo -u hytale sh -c 'cd /srv/hytale/game/Server && java -jar HytaleServer.jar --version'
```

Complete authentication **before** enabling the unattended service. Follow the official device-authentication workflow. For versions supporting it, run an interactive foreground server as the `hytale` user in the same working directory, binding only to your Tailscale IP, then enter `/auth login device` at its console. Select the supported persistent credential store if your version requires that step. Stop the foreground server cleanly before starting systemd. Never post device codes, auth files or tokens in issues.

```bash
sudo systemctl enable --now hytale
sudo journalctl -u hytale -f
```

Wait for `Hytale Server Booted! [Multiplayer]`. The launcher waits up to two minutes for the exact address on `tailscale0` and refuses to fall back to a wildcard bind. Inspect `ss -ulnp` and confirm the game listens on **your Tailscale IP:5520**, not `0.0.0.0:5520`.

### Existing servers

Do not run the installer over a working deployment. Back up your service, environment, world and mod state, then compare the supplied files manually. Preserve existing firewall rules, cloud security lists, Docker/Coolify configuration and service dependencies. The helper deliberately does not modify any of them.

### Authentication compatibility

Official servers default to `authenticated`. `offline` is **not** a universal multiplayer solution: the tested build rejected a multiplayer join with `offlineModeSingleplayerOnly`. Some custom builds expose `insecure`; it is accepted by the launcher only for compatibility with an administrator-supplied build and is not an official authentication recommendation. Check your own JAR's `--help`. This repository supplies no authentication patches or bypasses. Never expose an unauthenticated server publicly.

## Let a friend join only the game

1. Each friend installs Tailscale and signs in with their own account.
2. Review the network's **Access controls** before sharing the server.
3. On the Machines page, choose your server → Share. Share that **machine**, rather than inviting someone into your whole tailnet.
4. Send the single-use invitation/link privately. The friend accepts using their own account and connects Tailscale.
5. Both clients use Direct Connect: `YOUR_TAILSCALE_IP:5520`.

For an otherwise default network, the following grants preserve member access and permit external sharing recipients only UDP 5520 on the server:

```json
"grants": [
  {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},
  {"src": ["autogroup:shared"], "dst": ["100.101.102.103"], "ip": ["udp:5520"]}
]
```

Replace the placeholder IP. **Merge into your current policy; do not overwrite unrelated SSH, Funnel, tags, grants or other settings.** Remove/replace the default `*` → `*` allow-all rule: permissions are additive, so a narrow grant cannot cancel a broader grant. Tagged devices or more complex networks may need different internal rules; preserve their necessary access explicitly. `autogroup:shared` covers all external share recipients, not one email address. Sharing the machine controls who receives that access. Save only after Tailscale validates the policy, then verify denied ports as well as the game connection.

See [machine sharing](https://tailscale.com/docs/features/sharing) and [grants syntax](https://tailscale.com/docs/reference/syntax/grants). This restriction does not change any websites you already expose publicly.

## Backups and world import

The service enables Hytale's built-in 30-minute backups under `game/Server/backups/`. Check the actual files and retention behavior on your game version. Backups on the same VPS are not disaster recovery: copy important snapshots off-host privately.

For a consistent administrator snapshot, stop the game first:

```bash
sudo systemctl stop hytale
sudo /usr/local/lib/hytale/backup.sh
sudo systemctl start hytale
```

The helper includes world/player state, mods, permissions and server settings. It does not delete old backups or export authentication credentials. Keep service environment snapshots private even if you later add sensitive values to them.

To import a **trusted** ZIP with `universe/worlds/default/config.json` and region files at its root:

```bash
sudo python3 scripts/import-world.py /path/to/world.zip --replace
sudo journalctl -u hytale -f
```

The importer validates archive paths, rejects symlinks/duplicates, limits extraction to 20 GiB, extracts before downtime, stops only Hytale, retains the previous `universe/` under `/srv/hytale/backups/before-import-*`, swaps in the new universe and starts the service. It imports player saves along with worlds. ZIP paths must begin with `universe/`; wrapper folders and other world layouts require manual preparation. Have free disk space for extraction plus the old world.

Server auth, passwords, bans, permissions and service configuration are not imported. **World-specific settings inside the universe, including PvP and inventories, are imported.** Review them first. World-specific mod data outside `universe/` needs a separate, reviewed migration; executable mods are never installed by this helper. Avoid importing a ZIP captured while another server was writing the world.

The script restarts the service but cannot prove game compatibility. Verify boot logs, world identity, inventories and player joins. For rollback, stop Hytale, move the imported universe to a new holding directory, move the retained old `universe/` back to `game/Server/universe`, check ownership (`hytale:hytale`), and start Hytale. Never overwrite or delete either world during rollback.

## Performance

- Start with `"MaxViewRadius": 12` in `game/Server/config.json`, while the server is stopped. The official manual recommends 12 chunks; larger loaded areas increase memory demand. Preserve the rest of the file.
- Measure during play, not just while idle: `vmstat 1 10`, `free -h`, and the game logs. Short join/chunk-generation spikes are not proof of sustained overload.
- Run `tailscale ping SERVER_IP` on **each** client. A direct path normally avoids relay overhead. If one player uses DERP, investigate that player's connectivity using Tailscale's [performance guide](https://tailscale.com/docs/reference/troubleshooting/poor-performance-tailnet).
- Do not increase the Java heap until the machine runs out of memory or starves existing applications. Reserve RAM for the OS, Docker and other services.
- Missing particles or player-animation stutter are symptoms, not diagnoses. Check whether the issue is local rendering, server task delays, packet loss or a client/version issue before changing networking or world data.

No speculative JVM flags or automatic firewall changes are applied here.

## Troubleshooting: discovery ping is not the whole data path

In the source deployment, discovery pings succeeded while actual ICMP, TCP, UDP and game QUIC traffic failed. Peer node keys disagreed and WireGuard sessions never completed. Later, live peer maps converged and real traffic worked. **The exact action that repaired synchronization was not established**; this is not a claim of a universal cache-clear fix.

Check in order:

1. `tailscale status` on both sides. Verify accounts, device approval/expiry, routes and intended access policy.
2. `tailscale ping SERVER_IP` for discovery/path, then real traffic. TCP 22 works as a test only for an administrator already allowed SSH; game-only friends should not gain SSH just for diagnosis.
3. `tailscale debug metrics` and handshake/established counters. These are daemon-wide, not necessarily specific to the one peer.
4. A narrowly scoped `tcpdump -ni tailscale0 udp port 5520` during a join attempt, plus `journalctl -u hytale -f`.
5. If peer keys are inconsistent, compare the current `tailscale debug netmap` privately. Show only short public-key prefixes in reports. Never publish full debug dumps, state files, auth files or private keys.
6. Reconnect/control-refresh diagnostics should preserve identity. Back up first and maintain independent public SSH access. Do not blindly delete Tailscale state, log devices out, reset firewalls, or kill apparently duplicate Windows daemon processes: a service parent and subprocess may be normal.

Advanced cache/relay debug commands are version-dependent and intentionally not automated. Follow official support guidance. Do not assume a VPN application interferes merely because its processes are running.

## Validation and limitations

The originating Ubuntu ARM64 deployment was verified with two players joining the same world over Tailscale. These generalized scripts are **not yet verified by a clean-machine end-to-end deployment**, and no performance benchmark is claimed. Test them on a disposable server before adopting them for an existing installation. The importer has automated archive-safety tests; shell scripts are syntax-checked. CI repeats those checks.

```bash
python3 -m unittest discover -s tests -v
for file in scripts/*.sh; do bash -n "$file"; done
```

Report issues with versions, sanitized errors, direct/relay status and reproduction steps. Do not upload game binaries, worlds, full logs, IP/account lists or credentials. Improvements and reproducible reports are welcome.

## License

MIT for this repository's original scripts and documentation. Hytale and third-party software retain their own licenses.
