# Cascade VPN Infrastructure (Remnawave Panel & Subscriptions)

This repository contains the complete dockerized setup for the Cascade VPN bridge (Split-tunneling VPN) using **Remnawave** and **Xray Core**.

## Topology
```
Client (from RF) ---> Russian Entry Node (443, Reality) ---> Swedish Exit Node (2223, Tunnel) ---> Internet
```

## Quick Start (SWE Server - Main Panel)

1. **Prerequisites**: Ensure Docker and Caddy are installed on the host.
2. **Setup Env**: Copy `.env.example` to `.env` and fill in the required keys, domains, and database passwords:
   ```bash
   cp .env.example .env
   ```
3. **Deploy Container Stack**:
   ```bash
   docker compose up -d
   ```
4. **Configure Reverse Proxy**: Configure Caddy using the provided `Caddyfile` to handle SSL and reverse proxy traffic to:
   - Panel (`https://panelhide.su:8443`)
   - Subscriptions (`https://sub.panelhide.su`)
5. **Initialize Database**:
   Add the exit node and the entry node configuration in the Remnawave Panel admin dashboard.

---

## Setting up the Entry Node (RU Server)

1. On the Russian Entry server, copy `setup_ru_entry_node.sh` and run it:
   ```bash
   bash setup_ru_entry_node.sh <NODE_API_KEY>
   ```
2. This script installs Docker, configures the `remnawave-node` in host networking mode, sets up the decoy web page, and pulls the geo-databases.
3. Configure Let's Encrypt for the decoy domain `alphaceiling23.ru` using Certbot:
   ```bash
   certbot --nginx -d alphaceiling23.ru
   ```

---

## Adding the Cascade Tunnel in the Panel

1. **Russian Node**:
   - Create a profile containing `VLESS_REALITY_RU_ENTRY` inbound listening on port `443` on `0.0.0.0`.
   - Set up an outbound named `swe-exit` pointing to the Swedish Exit Node on port `2223` (using the static UUID `1cc78261-2a77-49af-b178-c6e3d2c36c58`).
   - Add routing rules so that `.ru` domains and geoip:ru route `DIRECT` from the Russian node, and everything else routes to `swe-exit`.

2. **Swedish Node**:
   - Create a profile containing `CASCADE_FROM_RU` inbound listening on port `2223` on `0.0.0.0` (with VLESS, security `none`).
   - Route all requests `DIRECT` (without any warp rules, unless WARP is running locally on port 40000).

3. **Tunnel Authentication**:
   To authorize the tunnel connection between nodes, run the SQL script in `scratch/create_tunnel_user.sql` inside the panel database.
