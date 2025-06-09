#!/bin/bash

# Zabbix server auto-installation script for Ubuntu with PostgreSQL 17 and Nginx
# Author: Teerakan + Gemini
# Date: 2025-06-09
# Zabbix Version: 7.0
# Database: PostgreSQL 17
# Web Server: Nginx

echo "Starting Zabbix Server 7.0 installation with PostgreSQL 17 and Nginx on Ubuntu..."

# --- 1. Update system and install prerequist ---
echo "Updating system and install prerequist"
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y gnupg gnupg1 gnupg2

# --- 2. Install Zabbix repository ---
echo "Install Zabbix repository"
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_latest_7.0+ubuntu22.04_all.deb
sudo apt update

# --- 3. Install Zabbix server, frontened, agent2, plugins
echo "Install Zabbix server, frontend, agent2, plugins"
sudo apt install -y zabbix-server-pgsql zabbix-frontend-php php8.1-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 \ zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql

# --- 4. Install postgresql-17 ---
echo "Install postgresql-17"
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
sudo apt install -y postgresql-17

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
# This command creates the user and sets the password NON-INTERACTIVELY.
sudo -u postgres psql -c "CREATE USER $ZABBIX_USER WITH ENCRYPTED PASSWORD '$ZABBIX_PASSWORD';"
sudo -u postgres createdb -O "$ZABBIX_USER" -E Unicode -T template0 "$ZABBIX_DB"

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

# --- 7. Remove the default Nginx site configuration ---
echo "Remove the default nginx site configuration"
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
    echo "Removed default Nginx site configuration."
fi

# --- 8. Enable and Start Zabbix Services ---
echo "Enabling and starting Zabbix services..."
sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.1-fpm
sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.1-fpm

echo "Waiting a few seconds for services to start..."
sleep 10

echo ""
echo "--------------------------------------------------------"
echo "Zabbix 7.0 installation completed!"
echo "You can now access Zabbix frontend via your web browser:"
echo "http://$(hostname -I | awk '{print $1}')/"
echo ""
echo "Zabbix database user (zabbix) password: $ZABBIX_PASSWORD"
echo "Default Zabbix frontend login credentials:"
echo "  Username: Admin"
echo "  Password: zabbix"
echo ""
echo "Please change the default passwords after first login."
echo "--------------------------------------------------------"
