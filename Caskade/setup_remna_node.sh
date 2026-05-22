#!/usr/bin/env bash
ssh remna "mkdir -p /opt/remnawave-node"
scp ./remna_node.env remna:/opt/remnawave-node/.env
scp ./yc_node_docker_compose.yml remna:/opt/remnawave-node/docker-compose.yml

# copy geo data from yc
ssh yc "cat /opt/remnawave-node/geoip.dat" | ssh remna "cat > /opt/remnawave-node/geoip.dat"
ssh yc "cat /opt/remnawave-node/geosite.dat" | ssh remna "cat > /opt/remnawave-node/geosite.dat"

ssh remna "cd /opt/remnawave-node && docker compose up -d"
ssh remna "ufw allow 2222/tcp && ufw reload"
