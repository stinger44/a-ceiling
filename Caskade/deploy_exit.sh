#!/usr/bin/env bash
# ==============================================================================
# REMNAWAVE MAIN SERVER DEPLOYMENT SCRIPT (Panel + DB + Caddy)
# ==============================================================================
# This script automates the full deployment of the core Remnawave control panel,
# PostgreSQL database, Redis/Valkey, and Caddy (with SSL).
# Run on your main VPS (e.g., Ubuntu/Debian) as root in the project root:
# ./deploy_main.sh
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
echo -e "${PURPLE}         REMNAWAVE MAIN SERVER AUTO-DEPLOYMENT SYSTEM                 ${NC}"
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

# Install dependencies & Docker if not available
install_dependencies() {
    echo -e "${CYAN}[1/5] Installing system dependencies and Docker...${NC}"
    
    # Update package lists
    apt-get update -y
    apt-get install -y curl git openssl pwgen jq -y

    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
    fi

    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Installing Docker Compose plugin...${NC}"
        apt-get install -y docker-compose-plugin
    fi
    echo -e "${GREEN}✓ Dependencies and Docker installed.${NC}"
}

# Prompt for configuration
setup_config() {
    echo -e "${CYAN}[2/5] Configuring domain...${NC}"
    
    read -p "Enter your Main Panel Domain (e.g., panelhide.su): " PANEL_DOMAIN
    if [ -z "$PANEL_DOMAIN" ]; then
        echo -e "${RED}Domain cannot be empty.${NC}"
        exit 1
    fi

    echo -e "${BLUE}Configured panel domain: ${PANEL_DOMAIN}${NC}"
}

# Create directory structure and configs
generate_files() {
    echo -e "${CYAN}[3/5] Generating configuration files and secrets...${NC}"
    
    mkdir -p /opt/remnawave
    cd /opt/remnawave

    # Generate secure keys
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    JWT_AUTH_SECRET=$(openssl rand -hex 64)
    JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)
    METRICS_PASS=$(openssl rand -hex 32)
    WEBHOOK_SECRET_HEADER=$(openssl rand -hex 32)

    # 1. Write .env for Remnawave Panel
    cat <<EOF > /opt/remnawave/.env
# App settings
APP_PORT=3000
METRICS_PORT=3001
API_INSTANCES=1

# Metrics Auth
METRICS_USER=metrics_admin
METRICS_PASS=${METRICS_PASS}
WEBHOOK_SECRET_HEADER=${WEBHOOK_SECRET_HEADER}

# Database
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@remnawave-db:5432/postgres?sslmode=disable

# Redis
REDIS_HOST=remnawave-redis
REDIS_PORT=6379

# JWT
JWT_AUTH_SECRET=${JWT_AUTH_SECRET}
JWT_API_TOKENS_SECRET=${JWT_API_TOKENS_SECRET}

# Domain
PANEL_DOMAIN=${PANEL_DOMAIN}
FRONT_END_DOMAIN=*
EOF

    # 2. Write Caddyfile
    cat <<EOF > /opt/remnawave/Caddyfile
${PANEL_DOMAIN} {
    reverse_proxy remnawave:3000
}
EOF

    # 3. Write docker-compose.yml
    cat <<EOF > /opt/remnawave/docker-compose.yml
services:
  remnawave-db:
    image: postgres:17-alpine
    container_name: remnawave-db
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=postgres
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    networks:
      - remnawave-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  remnawave-redis:
    image: valkey/valkey:8.1-alpine
    container_name: remnawave-redis
    restart: always
    volumes:
      - remnawave-redis-data:/data
    networks:
      - remnawave-network
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  remnawave:
    image: remnawave/backend:2
    container_name: remnawave
    restart: always
    env_file: .env
    ports:
      - 127.0.0.1:3000:3000
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy
    networks:
      - remnawave-network

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: always
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
    networks:
      - remnawave-network
    depends_on:
      - remnawave

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge

volumes:
  remnawave-db-data:
  remnawave-redis-data:
  caddy-data:
  caddy-config:
EOF

    echo -e "${GREEN}✓ Configuration files generated in /opt/remnawave.${NC}"
}

# Start services
start_services() {
    echo -e "${CYAN}[4/5] Pulling and launching containers...${NC}"
    cd /opt/remnawave
    docker compose pull
    docker compose up -d
    echo -e "${GREEN}✓ Containers launched successfully.${NC}"
}

# Generate API token
generate_token() {
    echo -e "${CYAN}[5/5] Creating admin API token...${NC}"
    
    # Wait for database migrations to finish
    echo -e "${YELLOW}Waiting for Remnawave to boot and run database migrations (20 seconds)...${NC}"
    sleep 20

    # Execute inside container to generate token
    TOKEN_NAME="NodeDeploymentToken_$(date +%s)"
    TOKEN_CMD="docker exec -t remnawave node dist/apps/backend/main.js create-token \"$TOKEN_NAME\""
    
    if API_TOKEN_RAW=$($TOKEN_CMD 2>/dev/null); then
        API_TOKEN=$(echo "$API_TOKEN_RAW" | grep -E -o '[0-9a-fA-F-]{32,}')
    else
        API_TOKEN=$(openssl rand -hex 16 | tr -d '\n')
        echo -e "${YELLOW}CLI token generation failed. Inserting token directly into DB...${NC}"
        SQL="INSERT INTO \"api_tokens\" (id, name, token, created_at) VALUES ('$(cat /proc/sys/kernel/random/uuid)', '${TOKEN_NAME}', '${API_TOKEN}', NOW());"
        docker exec -t remnawave-db psql -U postgres -d postgres -c "$SQL" >/dev/null
    fi

    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${GREEN}✓ REMNAWAVE PANEL DEPLOYED SUCCESSFULLY!                              ${NC}"
    echo -e "${GREEN}======================================================================${NC}"
    echo -e "${YELLOW}Main Panel URL: https://${PANEL_DOMAIN}${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "${PURPLE}NODE SECRET KEY (Use this in your node setup script):${NC}"
    echo -e "${CYAN}${API_TOKEN}${NC}"
    echo -e "${BLUE}----------------------------------------------------------------------${NC}"
    echo -e "You can manage the stack in: ${YELLOW}/opt/remnawave${NC}"
}

main() {
    install_dependencies
    setup_config
    generate_files
    start_services
    generate_token
}

main
