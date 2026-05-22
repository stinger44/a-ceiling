#!/bin/bash
# Backup script for Nginx and SSL before Caddy migration

BACKUP_DIR="/root/nginx_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in $BACKUP_DIR..."

# Backup Nginx configs
cp -r /etc/nginx "$BACKUP_DIR/nginx"

# Backup Let's Encrypt certificates
cp -r /etc/letsencrypt "$BACKUP_DIR/letsencrypt"

# Save list of running docker containers for reference
docker ps > "$BACKUP_DIR/docker_ps.txt"

# Save current crontab (for certbot renew)
crontab -l > "$BACKUP_DIR/crontab.txt" 2>/dev/null

echo "Backup completed successfully."
echo "To restore Nginx: systemctl stop caddy && systemctl start nginx"
