#!/bin/bash

# Zabbix server auto-installation script for Ubuntu with PostgreSQL 17 and Nginx
# Author: Gemini
# Date: 2025-06-09
# Zabbix Version: 7.0
# Database: PostgreSQL 17
# Web Server: Nginx

echo "Starting Zabbix Server 7.0 installation with PostgreSQL 17 and Nginx on Ubuntu..."

# --- 1. Update system and install prerequisites ---
echo "Updating system and installing necessary packages..."
sudo apt update -y
sudo apt upgrade -y
# Install common tools, Nginx, and PHP 8.1 with required modules
sudo apt install -y curl wget gnupg2 software-properties-common nginx \
    php8.1 php8.1-fpm php8.1-pgsql php8.1-gd php8.1-xml php8.1-ldap php8.1-bcmath \
    php8.1-mbstring php8.1-json php8.1-cli systemd

# --- 1.1. Install PostgreSQL 17 ---
echo "Adding PostgreSQL 17 repository and installing PostgreSQL 17..."
# Import the PostgreSQL PGP key
wget -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /usr/share/keyrings/postgresql.gpg >/dev/null
# Add the PostgreSQL repository for Ubuntu 22.04
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
sudo apt update -y
# Install PostgreSQL 17
sudo apt install -y postgresql-17

# --- 2. Install Zabbix Repository ---
echo "Installing Zabbix repository for version 7.0 on Ubuntu 22.04..."
# Download and install the Zabbix 7.0 release package for Ubuntu 22.04
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu22.04_all.deb
sudo apt update -y
rm zabbix-release_7.0-1+ubuntu22.04_all.deb # Clean up the downloaded .deb file

# --- 3. Install Zabbix Server, Frontend, Agent 2, and SQL scripts ---
echo "Installing Zabbix Server (PostgreSQL), Frontend (Nginx), Agent 2, and SQL scripts..."
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php php8.1-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2

# --- 4. Install Zabbix Agent 2 Plugins ---
echo "Installing Zabbix Agent 2 plugins..."
sudo apt install -y zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql

# --- 5. Create initial PostgreSQL database ---
echo "Setting up PostgreSQL database for Zabbix..."

ZABBIX_DB="zabbix"
ZABBIX_USER="zabbix"
# Generate a strong random password for the Zabbix database user
# Uses /dev/urandom for randomness, tr to filter for alphanumeric and underscore,
# and head -c 16 to get a 16-character string.
ZABBIX_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
echo "Generated Zabbix database password: $ZABBIX_PASSWORD" # <--- IMPORTANT: This password will be displayed.

# Create PostgreSQL user and database for Zabbix
# Using psql -c to avoid interactive prompts
sudo -u postgres psql -c "CREATE USER $ZABBIX_USER WITH ENCRYPTED PASSWORD '$ZABBIX_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE $ZABBIX_DB OWNER $ZABBIX_USER;"

if [ $? -ne 0 ]; then
    echo "Error: Failed to create Zabbix database or user in PostgreSQL. Please check PostgreSQL installation."
    exit 1
fi
echo "PostgreSQL database and user for Zabbix created successfully."

# Import initial schema and data
echo "Importing initial Zabbix database schema and data..."
# The user provides 'zabbix-sql-scripts/postgresql/server.sql.gz'
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u $ZABBIX_USER psql $ZABBIX_DB

if [ $? -ne 0 ]; then
    echo "Error: Failed to import Zabbix database schema. Please check Zabbix user password or database connection."
    exit 1
fi
echo "Zabbix database schema imported successfully."

# --- 6. Configure Zabbix Server ---
echo "Configuring Zabbix Server..."
# Edit Zabbix server configuration file to specify DB details
sudo sed -i "s/^# DBHost=.*/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBName=.*/DBName=$ZABBIX_DB/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBUser=.*/DBUser=$ZABBIX_USER/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBPassword=.*/DBPassword=$ZABBIX_PASSWORD/" /etc/zabbix/zabbix_server.conf

# --- 7. Configure PHP for Zabbix Frontend (Nginx with PHP-FPM) ---
echo "Configuring PHP for Zabbix Frontend..."
# Zabbix requires specific PHP settings. zabbix-nginx-conf typically handles Nginx config.
# Ensure timezone is set in php-fpm's php.ini
PHP_INI_PATH="/etc/php/8.1/fpm/php.ini" # Path for PHP 8.1 FPM
TIMEZONE="Asia/Bangkok" # <--- IMPORTANT: Change this to your desired timezone

if grep -q "^;date.timezone =" "$PHP_INI_PATH"; then
    sudo sed -i "s/^;date.timezone =.*/date.timezone = \"$TIMEZONE\"/" "$PHP_INI_PATH"
else
    # If the line doesn't exist or is not commented, append it.
    echo "date.timezone = \"$TIMEZONE\"" | sudo tee -a "$PHP_INI_PATH"
fi

# --- 8. Configure Nginx to serve Zabbix at root (/) and remove default page ---
echo "Configuring Nginx to serve Zabbix at / and removing default Nginx page..."

ZABBIX_NGINX_CONF="/etc/nginx/conf.d/zabbix.conf" # Common location for Zabbix Nginx config

# Check if the Zabbix Nginx config exists
if [ -f "$ZABBIX_NGINX_CONF" ]; then
    # Change location /zabbix to location /
    sudo sed -i 's|location /zabbix {|location / {|g' "$ZABBIX_NGINX_CONF"
    # Ensure alias points to /usr/share/zabbix directly in the root location
    # This might be tricky as the file might already have alias, ensuring it's for root
    # We expect 'alias /usr/share/zabbix;' inside the location block, we ensure it's not commenting out
    sudo sed -i 's|# alias /usr/share/zabbix;|alias /usr/share/zabbix;|g' "$ZABBIX_NGINX_CONF"
    sudo sed -i 's|alias /usr/share/zabbix/html;|alias /usr/share/zabbix;|g' "$ZABBIX_NGINX_CONF" # Handle variations
else
    echo "Warning: Zabbix Nginx configuration file '$ZABBIX_NGINX_CONF' not found. Manual configuration may be required."
fi

# Remove the default Nginx site configuration
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
    echo "Removed default Nginx site configuration."
fi

# --- 9. Enable and Start Zabbix Services ---
echo "Enabling and starting Zabbix services..."
sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.1-fpm
sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.1-fpm

echo "Waiting a few seconds for services to start..."
sleep 10

# --- 10. Check service status ---
echo "Checking Zabbix Server, Agent 2, Nginx, and PHP-FPM status..."
sudo systemctl status zabbix-server --no-pager | grep "Active:"
sudo systemctl status zabbix-agent2 --no-pager | grep "Active:"
sudo systemctl status nginx --no-pager | grep "Active:"
sudo systemctl status php8.1-fpm --no-pager | grep "Active:"

echo ""
echo "--------------------------------------------------------"
echo "Zabbix 7.0 installation completed!"
echo "You can now access Zabbix frontend via your web browser:"
echo "http://$(hostname -I | awk '{print $1}')/"
echo ""
echo "Zabbix database user (zabbix) password: $ZABBIX_PASSWORD"
echo "Default Zabbix frontend login credentials:"
echo "  Username: Admin"
echo "  Password: zabbix"
echo ""
echo "Please change the default passwords after first login."
echo "--------------------------------------------------------"
