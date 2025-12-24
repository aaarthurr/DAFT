#!/bin/bash

# --- Constants ---
APP_NAME="daft"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
CONFIG_DIR="$HOME/.config/$APP_NAME"
BIN_FILE="$HOME/.local/bin/$APP_NAME"
LOG_DIR="$HOME/.daft_logs"
BASHRC="$HOME/.bashrc"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Text Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}=== DAFT Uninstaller (Paranoid Mode) ===${NC}"
echo -e "${YELLOW}Warning: This will remove the application and logs.${NC}"
echo -e "${YELLOW}Safety Checks: Line counting, Backup verification, Singularity checks enabled.${NC}"
read -p "Are you sure you want to proceed? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# ==============================
# PART 1: REMOVE FILES
# ==============================
echo -e "\n${GREEN}[1/3] Removing Application Files...${NC}"
# We wrap this in a block to ensure failures don't stop the script (though rm rarely fails)

rm_safe() {
    if [ -e "$1" ]; then
        rm -rf "$1"
        echo "Removed: $1"
    else
        echo "Skipping (Not found): $1"
    fi
}

rm_safe "$BIN_FILE"
rm_safe "$INSTALL_DIR"
rm_safe "$CONFIG_DIR"
rm_safe "$LOG_DIR"

# ==============================
# PART 2: CLEAN BASHRC (PARANOID)
# ==============================
echo -e "\n${GREEN}[2/3] Cleaning .bashrc...${NC}"

START_MARKER="# --- DAFT LOGGER START OF CONFIGURATION ---"
END_MARKER="# --- DAFT LOGGER END OF CONFIGURATION ---"

# 1. Backup
cp "$BASHRC" "$HOME/bashrc_backup_$TIMESTAMP.bak"
echo "Backup created at: $HOME/bashrc_backup_$TIMESTAMP.bak"

# 2. Analyze File content
if grep -Fq "$START_MARKER" "$BASHRC" && grep -Fq "$END_MARKER" "$BASHRC"; then
    
    # Get line numbers of markers
    # grep -n returns "123:MatchingText", cut -d: -f1 gets "123"
    START_LINE=$(grep -nF "$START_MARKER" "$BASHRC" | head -n 1 | cut -d: -f1)
    END_LINE=$(grep -nF "$END_MARKER" "$BASHRC" | head -n 1 | cut -d: -f1)

    # Sanity Check 1: Order
    if [ "$START_LINE" -ge "$END_LINE" ]; then
        echo -e "${RED}[ERROR] Start marker found after End marker. Aborting bashrc cleanup.${NC}"
    else
        # Calculate expected line reduction
        # (End - Start + 1) is the total lines to delete
        EXPECTED_DIFF=$(( END_LINE - START_LINE + 1 ))
        
        # Create temp file without the block
        TEMP_BASHRC=$(mktemp)
        sed "/$START_MARKER/,/$END_MARKER/d" "$BASHRC" > "$TEMP_BASHRC"
        
        # Count lines
        ORIG_COUNT=$(wc -l < "$BASHRC")
        NEW_COUNT=$(wc -l < "$TEMP_BASHRC")
        ACTUAL_DIFF=$(( ORIG_COUNT - NEW_COUNT ))

        # Sanity Check 2: Math Verification
        echo "Debug: Removing block lines $START_LINE to $END_LINE ($EXPECTED_DIFF lines)."
        
        if [ "$ACTUAL_DIFF" -eq "$EXPECTED_DIFF" ]; then
            # Verify the content is not empty (paranoid check)
            if [ "$NEW_COUNT" -gt 0 ]; then
                mv "$TEMP_BASHRC" "$BASHRC"
                echo -e "${BLUE}[SUCCESS] .bashrc cleaned successfully. Removed exactly $ACTUAL_DIFF lines.${NC}"
            else
                 echo -e "${RED}[ERROR] Resulting file is empty. Aborting restoration.${NC}"
                 rm "$TEMP_BASHRC"
            fi
        else
            echo -e "${RED}[ERROR] Line count mismatch! Expected to remove $EXPECTED_DIFF lines, but sed removed $ACTUAL_DIFF.${NC}"
            echo "Restoring from safety backup just in case..."
            cp "$HOME/bashrc_backup_$TIMESTAMP.bak" "$BASHRC"
            rm "$TEMP_BASHRC"
        fi
    fi

elif grep -Fq "$START_MARKER" "$BASHRC"; then
    echo -e "${YELLOW}[SKIP] Found start marker but NOT end marker. Manual edit required.${NC}"
else
    echo "No DAFT configuration found in .bashrc."
fi

# ==============================
# PART 3: CLEAN CRONTAB (PARANOID)
# ==============================
echo -e "\n${GREEN}[3/3] Removing Cron Job...${NC}"

CRON_CMD_PART=".daft_logs"

# Check if user has a crontab
if crontab -l > /dev/null 2>&1; then
    
    # 1. Backup
    crontab -l > "$HOME/crontab_backup_$TIMESTAMP.bak"
    echo "Backup created at: $HOME/crontab_backup_$TIMESTAMP.bak"

    # 2. Count matches
    MATCH_COUNT=$(crontab -l | grep -c "$CRON_CMD_PART")

    if [ "$MATCH_COUNT" -eq 0 ]; then
        echo "No DAFT cron job found."
    elif [ "$MATCH_COUNT" -gt 1 ]; then
        echo -e "${RED}[ERROR] Multiple ($MATCH_COUNT) DAFT lines found in crontab.${NC}"
        echo "Refusing to delete automatically to prevent mistakes. Please edit manually using 'crontab -e'."
    else
        # Exactly 1 match found. Proceed with safe deletion.
        TEMP_CRON=$(mktemp)
        
        # Filter to temp
        crontab -l | grep -v "$CRON_CMD_PART" > "$TEMP_CRON"
        
        # Verify line counts
        ORIG_ROWS=$(crontab -l | wc -l)
        NEW_ROWS=$(wc -l < "$TEMP_CRON")
        DIFF=$(( ORIG_ROWS - NEW_ROWS ))

        if [ "$DIFF" -eq 1 ]; then
            crontab "$TEMP_CRON"
            echo -e "${BLUE}[SUCCESS] Removed the single DAFT cron job.${NC}"
        else
            echo -e "${RED}[ERROR] Cron line verification failed (Diff=$DIFF). Restoring backup.${NC}"
            crontab "$HOME/crontab_backup_$TIMESTAMP.bak"
        fi
        
        rm "$TEMP_CRON"
    fi
else
    echo "No active crontab found."
fi

echo -e "\n${GREEN}=== Uninstall Complete ===${NC}"
echo "Please restart your terminal."