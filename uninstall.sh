#!/bin/bash

# --- Constants ---
APP_NAME="daft"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
CONFIG_DIR="$HOME/.config/$APP_NAME"
BIN_FILE="$HOME/.local/bin/$APP_NAME"
LOG_DIR="$HOME/.daft_logs"
BASHRC="$HOME/.bashrc"

# Text Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== DAFT Uninstaller ===${NC}"
echo -e "${YELLOW}Warning: This will remove the application, your API key config, and all logs.${NC}"
read -p "Are you sure you want to proceed? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# ==============================
# PART 1: REMOVE FILES
# ==============================
echo -e "\n${GREEN}[1/3] Removing Files and Directories...${NC}"

if [ -f "$BIN_FILE" ]; then
    echo "Removing launcher: $BIN_FILE"
    rm "$BIN_FILE"
fi

if [ -d "$INSTALL_DIR" ]; then
    echo "Removing application files: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

if [ -d "$CONFIG_DIR" ]; then
    echo "Removing configuration: $CONFIG_DIR"
    rm -rf "$CONFIG_DIR"
fi

if [ -d "$LOG_DIR" ]; then
    echo "Removing logs: $LOG_DIR"
    rm -rf "$LOG_DIR"
fi

# ==============================
# PART 2: CLEAN BASHRC
# ==============================
echo -e "\n${GREEN}[2/3] Cleaning .bashrc...${NC}"

# We use sed to delete the block of text starting with the header and ending with the footer
# The markers must match EXACTLY what is in install.sh
START_MARKER="# --- DAFT LOGGER START OF CONFIGURATION ---"
END_MARKER="# --- DAFT LOGGER END OF CONFIGURATION ---"

if grep -Fq "$START_MARKER" "$BASHRC"; then
    # Create a backup just in case
    cp "$BASHRC" "$BASHRC.bak_uninstall"
    echo "Backup created at $BASHRC.bak_uninstall"
    
    # Delete the range
    sed -i "/$START_MARKER/,/$END_MARKER/d" "$BASHRC"
    echo "DAFT configuration removed from .bashrc."
else
    echo "No DAFT configuration found in .bashrc."
fi

# ==============================
# PART 3: CLEAN CRONTAB
# ==============================
echo -e "\n${GREEN}[3/3] Removing Cron Job...${NC}"

# Define the command we are looking for (partially) to identify the line
CRON_CMD_PART=".daft_logs"

# Check if it exists
if crontab -l 2>/dev/null | grep -q "$CRON_CMD_PART"; then
    # List cron, grep -v (invert match) to exclude the line, then write back
    crontab -l 2>/dev/null | grep -v "$CRON_CMD_PART" | crontab -
    echo "Cron job removed."
else
    echo "No DAFT cron job found."
fi

echo -e "\n${GREEN}=== Uninstall Complete ===${NC}"
echo "Please restart your terminal for all changes to take effect."