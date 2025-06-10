#!/bin/bash

# Zabbix server auto-installation script for Ubuntu with PostgreSQL 17 and Nginx
# Author: Teerakan + Gemini
# Date: 2025-06-09 (Updated: 2025-06-10)
# Zabbix Version: 7.0 LTS
# Database: PostgreSQL 17
# Web Server: Nginx

# --- Define ANSI Color Codes ---
RED='\033[0;31m'    # Error / Failed
GREEN='\033[0;32m'  # Success / OK
YELLOW='\033[0;33m' # Warning / Info / In Progress
BLUE='\033[0;34m'   # Step Headers
NC='\033[0m'        # No Color (reset)

# Define log file path for detailed output
LOG_FILE="/tmp/zabbix_install_$(date +%Y%m%d%H%M%S).log"

# --- Zabbix Installation Steps (Installation Step Headings) ---
# Each element in this array corresponds to a step in the installation process.
# This list will be displayed as a checklist in the terminal.
STEPS=(
    "1. Update system and install prerequisites"
    "2. Configure system locale to en_US.UTF-8"
    "3. Install Zabbix Repository"
    "4. Install Zabbix Server, Frontend, and Agent2"
    "5. Install Zabbix Agent2 Plugins"
    "6. Install PostgreSQL 17"
    "7. Create Zabbix user and database in PostgreSQL"
    "8. Import initial Zabbix database schema and data"
    "9. Configure Zabbix Server"
    "10. Remove Nginx Default Site configuration"
    "11. Enable and Start Zabbix services"
)
NUM_STEPS=${#STEPS[@]} # Calculate total number of steps

# Global array to store current status of each step:
# 0 = pending (not started)
# 1 = in_progress (running)
# 2 = ok (successful)
# 3 = failed (failed)
declare -a STEP_STATUS

# Global variable to store the starting row of the checklist in the terminal.
# This will be determined dynamically to ensure correct cursor positioning.
CHECKLIST_START_ROW=0

# Function to initialize all step statuses to 'pending' (0)
function initialize_step_statuses() {
    for ((i=0; i<$NUM_STEPS; i++)); do
        STEP_STATUS[$i]=0 # Initialize all steps as pending
    done
}

# Function to draw or redraw the entire checklist in the terminal.
# It uses tput for cursor positioning to update the checklist in place.
function draw_checklist() {
    # Save current cursor position before modifying the display
    tput sc

    # Move cursor to the starting row of the checklist (0-indexed)
    tput cup $CHECKLIST_START_ROW 0

    for ((i=0; i<$NUM_STEPS; i++)); do
        local status_char=" " # Default pending character
        local color="${NC}"   # Default pending color

        # Determine the character and color based on the step's current status
        case ${STEP_STATUS[$i]} in
            0) status_char=" "; color="${NC}";;      # Pending
            1) status_char=">"; color="${YELLOW}";;  # In Progress (using '>' instead of gear icon)
            2) status_char="✓"; color="${GREEN}";;  # OK (Checkmark)
            3) status_char="x"; color="${RED}";;    # Failed (X mark)
        esac

        # Clear the current line to ensure no leftover characters from previous prints
        tput el
        # Print the updated status and step name
        echo -e "[${color}${status_char}${NC}] ${STEPS[$i]}"
    done

    # Restore cursor to its original position before draw_checklist was called
    tput rc
}

# Function to update a single item's status in the checklist and then redraw the entire checklist.
# Arguments:
#   $1: step_index (0-based index of the step in the STEPS array)
#   $2: new_status (0=pending, 1=in_progress, 2=ok, 3=failed)
function update_checklist_item() {
    local step_index="$1"
    local new_status="$2"

    STEP_STATUS[$step_index]=$new_status # Update the status in the global array
    draw_checklist                       # Redraw the entire checklist to reflect the change
}

# Function to execute a command and update the checklist's status accordingly.
# Arguments:
#   $1: step_index (0-based index of the step in the STEPS array)
#   $2: command (The actual shell command to execute)
#   $3: allow_failure (Optional, 'true' if the script should continue even if this step fails)
function execute_step() {
    local step_index="$1"
    local command="$2"
    local allow_failure=${3:-false}
    local step_name="${STEPS[$step_index]}" # Get the descriptive name of the step

    # Log the step header and the command being executed to the detailed log file
    echo "--- $step_name ---" >> "$LOG_FILE"
    echo "[$step_name] Command: $command" >> "$LOG_FILE"

    # Update the checklist item to 'in_progress' status
    update_checklist_item "$step_index" 1

    # Execute the command. Redirect all stdout and stderr to the log file.
    # This prevents the command's verbose output from cluttering the terminal
    # and interfering with the checklist UI.
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        # If command succeeds, update checklist item to 'OK' status
        update_checklist_item "$step_index" 2
        return 0 # Indicate success
    else
        # If command fails, update checklist item to 'FAILED' status
        update_checklist_item "$step_index" 3
        if [ "$allow_failure" = false ]; then
            # If failure is not allowed, print error message to console and exit
            # First, move cursor below the checklist to print the error message
            tput cup $((CHECKLIST_START_ROW + NUM_STEPS + 1)) 0 # +1 for a blank line after checklist
            tput el # Clear the line
            echo -e "${RED}Error: Step '$step_name' failed. Please check the log file (${YELLOW}$LOG_FILE${RED}) for details.${NC}"
            tput el # Clear the line
            echo -e "${BLUE}--------------------------------------------------------${NC}"
            tput el # Clear the line
            echo -e "${YELLOW}Full installation log for review:${NC}"
            cat "$LOG_FILE" # Display the log file content for immediate review
            exit 1 # Exit the script with an error code
        fi
        return 1 # Indicate failure
    fi
}

# --- Main Script Execution Starts Here ---

echo -e "${BLUE}--------------------------------------------------------${NC}"
echo ""
echo -e "${GREEN}Starting Zabbix Server 7.0 installation with PostgreSQL 17 and Nginx on Ubuntu...${NC}"
echo -e "Detailed installation progress and logs are being written to: ${YELLOW}$LOG_FILE${NC}"
echo ""
echo -e "${BLUE}--------------------------------------------------------${NC}"

# --- Initial Confirmation ---
echo -e "${YELLOW}Warning: This script will perform system updates and install Zabbix server, PostgreSQL 17, and Nginx.${NC}"
read -p "Do you want to proceed with the installation? (y/N): " -n 1 -r
echo # Move to a new line after user input
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${RED}Installation cancelled by user.${NC}"
    exit 1
fi
echo "" # Blank line before the checklist starts drawing

# Calculate the starting row for the checklist dynamically.
# Count lines printed before this point:
# 1 (border) + 1 (blank) + 1 (start msg) + 1 (log path) + 1 (blank) + 1 (border) + 1 (blank) + 1 (warning) + 1 (read prompt) + 1 (blank after read) = 10 lines (0-indexed rows 0-9).
# So, the checklist will start at row 10 (0-indexed).
CHECKLIST_START_ROW=10

# Initialize all step statuses to pending
initialize_step_statuses
# Draw the initial checklist with empty boxes for all steps
draw_checklist

# --- Execute Installation Steps ---
# Call execute_step for each phase of the installation, passing the step index, command, and allow_failure if needed.
execute_step 0 "sudo apt update -y && sudo apt upgrade -y && sudo apt install -y gnupg gnupg1 gnupg2"
execute_step 1 "sudo sed -i 's/^# \\(en_US\\.UTF-8 UTF-8\\)$/\\1/' /etc/locale.gen && sudo locale-gen && sudo update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8"
# Export locale variables to ensure they are applied for subsequent commands in the current shell session
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

execute_step 2 "wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb -O zabbix-release_latest_7.0+ubuntu22.04_all.deb && sudo dpkg -i zabbix-release_latest_7.0+ubuntu22.04_all.deb && sudo apt update -y && sudo rm zabbix-release_latest_7.0+ubuntu22.04_all.deb"

execute_step 3 "sudo apt install -y zabbix-server-pgsql zabbix-frontend-php php8.1-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2"
execute_step 4 "sudo apt install -y zabbix-agent2-plugin-mongodb zabbix-agent2-plugin-mssql zabbix-agent2-plugin-postgresql"

execute_step 5 "sudo apt install -y postgresql-common && echo | sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh && sudo apt install -y postgresql-17"

# --- Create initial PostgreSQL database for Zabbix ---
ZABBIX_DB="zabbix"
ZABBIX_USER="zabbix"
# Generate a strong, random password for the Zabbix database user
# Uses /dev/urandom for randomness, 'tr' to filter for alphanumeric characters and underscore,
# and 'head -c 16' to get a 16-character string.
ZABBIX_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9_ | head -c 16)
echo "ZABBIX_PASSWORD: $ZABBIX_PASSWORD" >> "$LOG_FILE" # Also log the password for later reference

execute_step 6 "sudo -u postgres psql -c \"CREATE USER $ZABBIX_USER WITH ENCRYPTED PASSWORD '$ZABBIX_PASSWORD';\" && sudo -u postgres createdb -O \"$ZABBIX_USER\" -E Unicode -T template0 \"$ZABBIX_DB\""

execute_step 7 "zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u $ZABBIX_USER psql $ZABBIX_DB"

# --- Configure Zabbix Server ---
execute_step 8 "sudo sed -i \"s/^# DBHost=.*/DBHost=localhost/\" /etc/zabbix/zabbix_server.conf && sudo sed -i \"s/^# DBName=.*/DBName=$ZABBIX_DB/\" /etc/zabbix/zabbix_server.conf && sudo sed -i \"s/^# DBUser=.*/DBUser=$ZABBIX_USER/\" /etc/zabbix/zabbix_server.conf && sudo sed -i \"s/^# DBPassword=.*/DBPassword=$ZABBIX_PASSWORD/\" /etc/zabbix/zabbix_server.conf"

execute_step 9 "sudo rm -f /etc/nginx/sites-enabled/default && sudo rm -f /etc/nginx/sites-available/default"

execute_step 10 "sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.1-fpm && sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.1-fpm"

# --- Installation Completion Summary ---
# Move cursor to the line after the last checklist item before printing summary
tput cup $((CHECKLIST_START_ROW + NUM_STEPS)) 0
tput el # Clear the line to ensure it's empty

echo -e "${GREEN}--------------------------------------------------------${NC}"
tput el # Clear before printing
echo -e "${GREEN}Zabbix 7.0 installation completed!${NC}"
tput el # Clear before printing
echo -e "You can now access the Zabbix frontend via your web browser:${NC}"
tput el # Clear before printing
echo -e "  ${YELLOW}http://$(hostname -I | awk '{print $1}')/${NC}"
tput el # Clear before printing
echo ""
tput el # Clear before printing
echo -e "${YELLOW}Zabbix database user (zabbix) password: ${RED}$ZABBIX_PASSWORD${NC}"
tput el # Clear before printing
echo -e "${YELLOW}Default Zabbix frontend login credentials:${NC}"
tput el # Clear before printing
echo -e "  ${YELLOW}Username: Admin${NC}"
tput el # Clear before printing
echo -e "  ${YELLOW}Password: zabbix${NC}"
tput el # Clear before printing
echo ""
tput el # Clear before printing
echo -e "${RED}Please change the default passwords after the first login.${NC}"
tput el # Clear before printing
echo -e "${GREEN}--------------------------------------------------------${NC}"
tput el # Clear before printing
echo ""
