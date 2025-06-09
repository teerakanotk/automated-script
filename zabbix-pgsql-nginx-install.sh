#!/bin/bash

# Zabbix server auto-installation script for Ubuntu with PostgreSQL 17 and Nginx
# Author: Teerakan + Gemini
# Date: 2025-06-09
# Zabbix Version: 7.0 LTS
# Database: PostgreSQL 17
# Web Server: Nginx

# Define log file path for detailed output
LOG_FILE="/tmp/zabbix_install_$(date +%Y%m%d%H%M%S).log"

echo "--------------------------------------------------------"
echo ""
echo "Starting Zabbix Server 7.0 installation with PostgreSQL 17 and Nginx on Ubuntu..."
echo "Detailed installation progress and logs are being written to: $LOG_FILE"
echo ""
echo "--------------------------------------------------------"

# Function to execute a command and log its output, showing simple progress
execute_step() {
    local step_name="$1"
    local command="$2"
    local allow_failure=${3:-false} # Set to 'true' if the step can fail without exiting

    echo "--- $step_name ---"
    echo "  Executing..."
    echo "[$step_name] Command: $command" >> "$LOG_FILE"

    # Execute the command, redirecting all output to the log file
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        echo "  [OK]"
        return 0
    else
        echo "  [FAILED]"
        if [ "$allow_failure" = false ]; then
            echo "Error: $step_name failed. Please check the log file ($LOG_FILE) for details."
            echo "--------------------------------------------------------"
            echo "Full installation log for review:"
            cat "$LOG_FILE"
            exit 1
        fi
        return 1
    fi
}

# --- 1. Update system and install prerequist ---
execute_step "Updating system and installing prerequisites" \
    "sudo apt update -y && sudo apt upgrade -y && sudo apt install -y gnupg gnupg1 gnupg2"

# --- 1.1. Configure Locales to en_US.UTF-8 ---
echo "--- Configuring system locale to en_US.UTF-8 ---"
echo "  Executing..."
# Execute locale configuration commands in a subshell, logging all output
(
    sudo sed -i 's/^# \(en_US\.UTF-8 UTF-8\)$/\1/' /etc/locale.gen
    sudo locale-gen
    sudo update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8
) >> "$LOG_FILE" 2>&1
# Check the exit status of the subshell
if [ $? -ne 0 ]; then
    echo "  [FAILED]"
    echo "Error: Locale configuration failed. Please check the log file ($LOG_FILE) for details."
    echo "--------------------------------------------------------"
    echo "Full installation log for review:"
    cat "$LOG_FILE"
    exit 1
fi
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8
echo "  [OK]"

# --- 2. Install Zabbix repository ---
execute_step "Installing Zabbix repository" \
    "wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb -O zabbix-release_latest_7.0+ubuntu22.04_all.deb && sudo dpkg -i zabbix-release_latest_7.0+ubuntu22.04_all.deb && sudo apt update -y && sudo rm zabbix-release_latest_7.0+ubuntu22.04_all.deb"

# --- 3. Install Zabbix server, frontened, agent2, plugins
execute_step "Installing Zabbix server, frontend, and agent2" \
    "sudo apt install -y zabbix-server-pgsql zabbix-frontend-php php8.1-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2"
execute_step "Installing Zabbix agent2 plugins" \
    "sudo apt install -y zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql"

# --- 4. Install postgresql-17 ---
execute_step "Installing PostgreSQL 17" \
    "sudo apt install -y postgresql-common && echo | sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh && sudo apt install -y postgresql-17"

# --- 5. Create initial PostgreSQL database ---
echo "--- Setting up PostgreSQL database for Zabbix ---"
ZABBIX_DB="zabbix"
ZABBIX_USER="zabbix"

echo "  Generating a strong random password for the Zabbix database user..."
# Generate a strong random password for the Zabbix database user
# Uses /dev/urandom for randomness, tr to filter for alphanumeric and underscore,
# and head -c 16 to get a 16-character string.
ZABBIX_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
echo "  [INFO] Generated Zabbix database password: $ZABBIX_PASSWORD" # Print password to console immediately
echo "ZABBIX_PASSWORD: $ZABBIX_PASSWORD" >> "$LOG_FILE" # Also log the password for later reference

echo "  Creating PostgreSQL user and database for Zabbix..."
# Create PostgreSQL user and database for Zabbix in a subshell, logging output
(
    sudo -u postgres psql -c "CREATE USER $ZABBIX_USER WITH ENCRYPTED PASSWORD '$ZABBIX_PASSWORD';"
    sudo -u postgres createdb -O "$ZABBIX_USER" -E Unicode -T template0 "$ZABBIX_DB"
) >> "$LOG_FILE" 2>&1
# Check the exit status of the subshell
if [ $? -ne 0 ]; then
    echo "  [FAILED]"
    echo "Error: Failed to create Zabbix database or user in PostgreSQL. Please check PostgreSQL installation."
    echo "--------------------------------------------------------"
    echo "Full installation log for review:"
    cat "$LOG_FILE"
    exit 1
fi
echo "  [OK] PostgreSQL database and user for Zabbix created successfully."

execute_step "Importing initial Zabbix database schema and data" \
    "zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u $ZABBIX_USER psql $ZABBIX_DB"

# --- 6. Configure Zabbix Server ---
echo "--- Configuring Zabbix Server ---"
echo "  Executing..."
# Edit Zabbix server configuration file to specify DB details in a subshell, logging output
(
    sudo sed -i "s/^# DBHost=.*/DBHost=localhost/" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s/^# DBName=.*/DBName=$ZABBIX_DB/" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s/^# DBUser=.*/DBUser=$ZABBIX_USER/" /etc/zabbix/zabbix_server.conf
    sudo sed -i "s/^# DBPassword=.*/DBPassword=$ZABBIX_PASSWORD/" /etc/zabbix/zabbix_server.conf
) >> "$LOG_FILE" 2>&1
# Check the exit status of the subshell
if [ $? -ne 0 ]; then
    echo "  [FAILED]"
    echo "Error: Zabbix server configuration failed. Please check the log file ($LOG_FILE) for details."
    echo "--------------------------------------------------------"
    echo "Full installation log for review:"
    cat "$LOG_FILE"
    exit 1
fi
echo "  [OK]"

# --- 7. Remove the default Nginx site configuration ---
execute_step "Removing default Nginx site configuration" \
    "sudo rm /etc/nginx/sites-enabled/default && sudo rm /etc/nginx/sites-available/default"

# --- 8. Enable and Start Zabbix Services ---
execute_step "Enabling and starting Zabbix services" \
    "sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.1-fpm && sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.1-fpm"

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
echo ""
