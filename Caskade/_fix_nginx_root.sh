#!/bin/bash
sudo mv /var/www/alphaceiling23.ru/images/vpnlogo.jpg /var/www/alphaceiling/images/vpnlogo.jpg
sudo sed -i "s|root /var/www/alphaceiling23.ru;|root /var/www/alphaceiling;|g" /etc/nginx/sites-available/reality-masquerade
sudo systemctl reload nginx
