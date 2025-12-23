#!/bin/bash

# Exit on error
set -e 

# --- Constants ---
APP_NAME="daft"
ROUTE_DIR=$(pwd)
SOURCE_DIR="$ROUTE_DIR/src"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
CONFIG_DIR="$HOME/.config/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
ENV_FILE="$CONFIG_DIR/.env"
LOG_DIR="$HOME/.daft_logs"

# Text Formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DAFT AI Assistant Installer ===${NC}"
# ==============================
# PART 1: FILES & PYTHON ENV
# ==============================

echo -e "\n${GREEN}[1/3] Installing Application...${NC}"

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$LOG_DIR"

# Copy Files
echo "Copying source files..."
cp "$SOURCE_DIR/commands.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/utils.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/requirements.txt" "$INSTALL_DIR/"
cp "$SOURCE_DIR/daft" "$INSTALL_DIR/main.py" 

# Setup Venv
echo "Setting up Python Environment..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    python3 -m venv "$INSTALL_DIR/venv"
fi

# Install Deps
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip > /dev/null
"$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" > /dev/null
"$INSTALL_DIR/venv/bin/pip" install python-dotenv > /dev/null

# Setup .env
if [ -f "$ENV_FILE" ]; then
    echo "Config exists at $ENV_FILE"
else
    echo -e "${RED}Configuration needed!${NC}"
    echo -n "Enter your Google GenAI API Key: "
    read -s API_KEY
    echo ""
    echo "GOOGLE_API_KEY=$API_KEY" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
fi

# Create Launcher
LAUNCHER="$BIN_DIR/$APP_NAME"
cat <<EOF > "$LAUNCHER"
#!/bin/bash
exec "$INSTALL_DIR/venv/bin/python3" "$INSTALL_DIR/main.py" "\$@"
EOF
chmod +x "$LAUNCHER"

# ==============================
# PART 2: BASHRC LOGGER
# ==============================

echo -e "\n${GREEN}[2/3] Configuring Shell Logger...${NC}"
BASHRC="$HOME/.bashrc"

# Check if we already installed the hook to avoid duplicates
if grep -q "DAFT_LOG_DIR" "$BASHRC"; then
    echo "Bashrc already configured. Skipping."
else
    echo "Backing up .bashrc to .bashrc.bak..."
    cp "$BASHRC" "$BASHRC.bak"

    echo "Appending DAFT Logger to .bashrc..."
    cat <<EOF >> "$BASHRC"

# --- DAFT LOGGER START OF CONFIGURATION ---
# Added by DAFT Installer on $(date)

alias DAFT='daft'

DAFT_LOG_DIR="\$HOME/.daft_logs"
mkdir -p "\$DAFT_LOG_DIR"
function daft_start() {
    local log_dir="\$HOME/.daft_logs"
    mkdir -p "\$log_dir"
    local terminal_id=\$\$
    export DAFT_HISTORY_FILE="\$log_dir/log_\$terminal_id.txt"
    export DAFT_LOGGING_ACTIVE=1

    echo "DAFT: Logging activated. Type 'exit' to stop."
    
    # Start the logged shell
    script -q -f "\$DAFT_HISTORY_FILE" -c "bash --rcfile \$HOME/.bashrc"

    unset DAFT_HISTORY_FILE
    unset DAFT_LOGGING_ACTIVE
    echo "DAFT: Logging stopped."
}

if [ ! -z "\$DAFT_LOGGING_ACTIVE" ]; then
    PS1="\[\033[91m\]DAFT:\[\033[0m\]\$PS1"
fi

# Interactive Shell Hint
if [[ \$- == *i* ]]; then
    if [ -z "\${DAFT_HISTORY_FILE:-}" ]; then
        # Optional: Uncomment if you want the hint every time
        # printf "\nYou can activate the DAFT logs with daft_start\n\n"
        :
    fi
fi
# --- DAFT LOGGER END OF CONFIGURATION ---
EOF
fi

# ==============================
# PART 3: CRON CLEANUP
# ==============================

echo -e "\n${GREEN}[3/3] Setting up Garbage Collector...${NC}"

# Logic: List current cron, look for our command. If not found, append it.
CRON_CMD="/usr/bin/find $LOG_DIR -type f -mmin +720 -name 'log_*.txt' -delete"
CRON_JOB="0 */12 * * * $CRON_CMD"

# We use 'crontab -l' to read, then append if missing
(crontab -l 2>/dev/null || true) | grep -F "$CRON_CMD" > /dev/null && echo "Cron job already exists." || (
    echo "Adding cron job..."
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
)

echo -e "\n${BLUE}=== Installation Complete ===${NC}"
echo "1. Restart your terminal."
echo "2. Type 'daft_start' to begin recording."
echo "3. Type '$APP_NAME --help' to use the AI."