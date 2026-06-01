#!/usr/bin/env bash
# ==============================================================================
# REMNAWAVE NODE SERVER DEPLOYMENT SCRIPT (Docker + Node + Nginx Masking)
# ==============================================================================
# This script sets up a VLESS Reality node with a local Nginx masking site
# running strictly on localhost (127.0.0.1:8443) for secure fallback redirection.
# Run on your Node VPS (e.g., Ubuntu/Debian) as root in the project root:
# ./deploy_node.sh
# ==============================================================================

set -euo pipefail

# --- Color Definitions for Premium UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${PURPLE}         REMNAWAVE NODE SERVER AUTO-DEPLOYMENT SYSTEM                 ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root.${NC}" >&2
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Unsupported OS.${NC}" >&2
    exit 1
fi

setup_swap() {
    echo -e "${CYAN}[1/6] Setting up Swap space...${NC}"
    if [ $(free | awk '/^Swap:/ {print $2}') -eq 0 ]; then
        echo -e "${YELLOW}No swap space detected. Creating 2GB swap file...${NC}"
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}✓ 2GB Swap file successfully created and enabled.${NC}"
    else
        echo -e "${GREEN}✓ Swap space already exists. Skipping.${NC}"
    fi
}

install_docker_nginx() {
    echo -e "${CYAN}[2/6] Installing Docker, Nginx, and Certbot...${NC}"
    
    apt-get update -y
    apt-get install -y curl git openssl nginx certbot python3-certbot-nginx -y

    systemctl enable --now nginx

    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi

    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Installing Docker Compose plugin...${NC}"
        apt-get install -y docker-compose-plugin
    fi

    echo -e "${GREEN}✓ Docker, Nginx, and Certbot installed.${NC}"
}

setup_node_config() {
    echo -e "${CYAN}[3/6] Configuring node and domain parameters...${NC}"
    
    read -p "Enter the Node Secret Key (from Main Server): " SECRET_KEY
    if [ -z "$SECRET_KEY" ]; then
        echo -e "${RED}Secret Key cannot be empty.${NC}"
        exit 1
    fi

    read -p "Enter your Node Domain (e.g., alphaceiling23.ru): " NODE_DOMAIN
    if [ -z "$NODE_DOMAIN" ]; then
        echo -e "${RED}Node domain cannot be empty.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Configured Node Domain: ${NODE_DOMAIN}${NC}"
}

configure_nginx_masking() {
    echo -e "${CYAN}[4/6] Setting up Nginx masking site on 127.0.0.1:8443...${NC}"

    mkdir -p /etc/nginx/ssl
    
    # Generate self-signed certificate first as fallback
    if [ ! -f "/etc/nginx/ssl/selfsigned.crt" ]; then
        echo -e "${YELLOW}Generating self-signed SSL certificate for fallback...${NC}"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/selfsigned.key \
            -out /etc/nginx/ssl/selfsigned.crt \
            -subj "/CN=${NODE_DOMAIN}/O=RemnaNodeMasking/C=RU"
    fi

    # Write Nginx configuration block (strictly listening on localhost loopback)
    cat <<EOF > /etc/nginx/sites-available/remna-masking
server {
    listen 127.0.0.1:8443 ssl http2;
    server_name ${NODE_DOMAIN};

    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/alphaceiling;
    index index.html fabricwalls.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

# HTTP standard configuration to answer Let's Encrypt challenges
server {
    listen 80;
    server_name ${NODE_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

    # Create directories and test index files
    mkdir -p /var/www/alphaceiling
    mkdir -p /var/www/html
    cat <<EOF > /var/www/alphaceiling/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to Web Server</title>
    <style>body { font-family: sans-serif; text-align: center; padding: 50px; background-color: #f7f9fc; }</style>
</head>
<body>
    <h1>System Status: Operating Normally</h1>
    <p>Secure TLS Gateway.</p>
</body>
</html>
EOF

    # Enable config and restart nginx
    ln -sf /etc/nginx/sites-available/remna-masking /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default || true
    nginx -t
    systemctl restart nginx

    echo -e "${GREEN}✓ Nginx configured on loopback port 8443 (self-signed).${NC}"

    # Offer real Let's Encrypt SSL
    echo -e "${YELLOW}------------------------------------------------------------${NC}"
    echo -e "${YELLOW}Would you like to generate a real Let's Encrypt SSL certificate?${NC}"
    echo -e "${YELLOW}(Make sure your domain ${NODE_DOMAIN} is already pointing to this VPS IP!)${NC}"
    read -p "Generate Let's Encrypt SSL? (y/N): " GET_SSL
    
    if [[ "$GET_SSL" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Running Certbot...${NC}"
        if certbot certonly --nginx -d "${NODE_DOMAIN}" --non-interactive --agree-tos --email "admin@${NODE_DOMAIN}"; then
            # Update Nginx config to point to Let's Encrypt keys
            sed -i "s|/etc/nginx/ssl/selfsigned.crt|/etc/letsencrypt/live/${NODE_DOMAIN}/fullchain.pem|g" /etc/nginx/sites-available/remna-masking
            sed -i "s|/etc/nginx/ssl/selfsigned.key|/etc/letsencrypt/live/${NODE_DOMAIN}/privkey.pem|g" /etc/nginx/sites-available/remna-masking
            systemctl restart nginx
            echo -e "${GREEN}✓ Let's Encrypt SSL configured successfully!${NC}"
        else
            echo -e "${RED}Certbot failed. Falling back to self-signed certificate.${NC}"
        fi
    fi
}

start_remnanode() {
    echo -e "${CYAN}[5/6] Building and starting remnanode container...${NC}"
    
    mkdir -p /opt/remnanode
    cd /opt/remnanode

    # Write docker-compose.yml
    cat <<EOF > /opt/remnanode/docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=${SECRET_KEY}
EOF

    docker compose down || true
    docker compose pull
    docker compose up -d

    echo -e "${GREEN}✓ RemnaNode container successfully started.${NC}"
}

verify_deployment() {
    echo -e "${CYAN}[6/6] Verifying deployment state...${NC}"
    sleep 5

    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${PURPLE}Checking Node Docker Container State:${NC}"
    docker ps -f name=remnanode
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${PURPLE}Last 15 lines of Xray logs:${NC}"
    if docker exec remnanode [ -f /var/log/supervisor/xray.out.log ]; then
        docker exec remnanode tail -n 15 /var/log/supervisor/xray.out.log || true
    else
        docker logs remnanode --tail 15 || true
    fi
    echo -e "${BLUE}------------------------------------------------------------${NC}"

    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}✓ REMNAWAVE NODE SETUP COMPLETE!                                      ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "Nginx Masking Server: Localhost loopback port 8443 (via ${NODE_DOMAIN} redirection)"
    echo -e "Remnanode API status: Port ${YELLOW}2222${NC}"
    echo -e "Reality Listener Port: Port ${YELLOW}443${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
}

main() {
    setup_swap
    install_docker_nginx
    setup_node_config
    configure_nginx_masking
    start_remnanode
    verify_deployment
}

main
