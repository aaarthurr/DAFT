#!/bin/bash

# Exit on error
set -e 

# --- Constants ---
APP_NAME="daft"
ROOT_DIR=$(pwd)
SRC_DIR="$ROOT_DIR/src"
INSTALL_DIR="$HOME/.local/share/$APP_NAME"
CONFIG_DIR="$HOME/.config/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
ENV_FILE="$CONFIG_DIR/.env"
LOG_DIR="$HOME/.daft_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Text Formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DAFT AI Assistant Installer (Safe Mode) ===${NC}"

# ==============================
# PART 0: PRE-FLIGHT & COMPATIBILITY CHECKS
# ==============================
echo -e "\n${GREEN}[0/3] Compatibility Checks...${NC}"

# 1. Check for Bash Execution (Internal)
if [ -z "$BASH_VERSION" ]; then
    echo -e "${RED}[ERROR] This DAFT only runs in Bash for the moment, maybe in the future more compatibility will be added.${NC}"
    echo "Please run: ./install.sh"
    exit 1
fi

# 2. Check for User's Shell (External)
# We assume the user wants to use DAFT in their current preferred shell.
USER_SHELL=$(basename "$SHELL")
if [[ "$USER_SHELL" != "bash" ]]; then
    echo -e "${YELLOW}[WARNING] Your default shell appears to be '$USER_SHELL', not 'bash'.${NC}"
    echo "DAFT relies on .bashrc hooks which usually do not work in Zsh, Fish, or PowerShell."
    echo "If you proceed, DAFT will be installed, but you might need to manually configure your $USER_SHELLrc."
    read -p "Do you really want to continue? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Installation aborted."
        exit 1
    fi
fi

# 3. Check for .bashrc existence
BASHRC="$HOME/.bashrc"
if [ ! -f "$BASHRC" ]; then
    echo -e "${RED}[ERROR] No .bashrc file found at $BASHRC.${NC}"
    echo "DAFT requires a standard Bash environment configuration file."
    exit 1
fi

# 4. Check Source Files
if [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}[ERROR] 'src' directory not found at $SRC_DIR${NC}"
    exit 1
fi

# 5. Check Dependencies (Python)
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR] python3 could not be found.${NC}"
    exit 1
fi

echo "Checks passed. System compatible."

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
echo "Copying source files from src/..."
cp "$SRC_DIR/commands.py" "$INSTALL_DIR/"
cp "$SRC_DIR/utils.py" "$INSTALL_DIR/"
cp "$SRC_DIR/requirements.txt" "$INSTALL_DIR/"
cp "$SRC_DIR/daft" "$INSTALL_DIR/main.py" 

# Setup Venv
echo "Setting up Python Environment..."
if [ ! -d "$INSTALL_DIR/venv" ]; then
    if ! python3 -m venv "$INSTALL_DIR/venv"; then
         echo -e "${RED}[ERROR] Failed to create venv. Is python3-venv installed?${NC}"
         exit 1
    fi
fi

# Install Deps
echo "Installing dependencies..."
if ! "$INSTALL_DIR/venv/bin/pip" install --upgrade pip > /dev/null; then
    echo -e "${RED}[ERROR] Failed to upgrade pip.${NC}"
    exit 1
fi
if ! "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" > /dev/null; then
    echo -e "${RED}[ERROR] Failed to install requirements.${NC}"
    exit 1
fi
"$INSTALL_DIR/venv/bin/pip" install python-dotenv > /dev/null

# Setup .env
if [ -f "$ENV_FILE" ]; then
    echo "Config exists at $ENV_FILE"
else
    echo -e "${YELLOW}Configuration needed!${NC}"
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
# PART 2: BASHRC LOGGER (SAFE)
# ==============================

echo -e "\n${GREEN}[2/3] Configuring Shell Logger...${NC}"

if grep -q "DAFT_LOG_DIR" "$BASHRC"; then
    echo "Bashrc already configured. Skipping."
else
    # 1. Safety Backup
    cp "$BASHRC" "$HOME/bashrc_pre_daft_$TIMESTAMP.bak"
    echo "Backup created at: $HOME/bashrc_pre_daft_$TIMESTAMP.bak"

    echo "Appending DAFT Logger to .bashrc..."
    
    # 2. Append safely
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
    PS1="\[\033[91m\][DAFT]\[\033[0m\]\$PS1"
fi

# Interactive Shell Hint
if [[ \$- == *i* ]]; then
    # Only show hint if we are NOT currently logging
    if [ -z "\${DAFT_HISTORY_FILE:-}" ]; then
        printf "\n\033[0;34mYou can activate DAFT memory using daft_start\033[0m\n\n"
    fi
fi
# --- DAFT LOGGER END OF CONFIGURATION ---
EOF
    echo "Configuration appended."
fi

# ==============================
# PART 3: CRON CLEANUP (SAFE)
# ==============================

echo -e "\n${GREEN}[3/3] Setting up Garbage Collector...${NC}"

CRON_CMD="/usr/bin/find $LOG_DIR -type f -mmin +720 -name 'log_*.txt' -delete"
CRON_JOB="0 */12 * * * $CRON_CMD"

# 1. Check if job exists
if (crontab -l 2>/dev/null || true) | grep -F "$CRON_CMD" > /dev/null; then
    echo "Cron job already exists."
else
    echo "Adding cron job safely..."
    
    # 2. Safety Backup
    if crontab -l >/dev/null 2>&1; then
        crontab -l > "$HOME/crontab_pre_daft_$TIMESTAMP.bak"
        echo "Backup created at: $HOME/crontab_pre_daft_$TIMESTAMP.bak"
    fi

    # 3. Use Temp File (Atomic Write)
    TEMP_CRON=$(mktemp)
    
    # Dump current cron to temp (if it exists)
    crontab -l 2>/dev/null > "$TEMP_CRON" || true
    
    # Append our new job
    echo "$CRON_JOB" >> "$TEMP_CRON"
    
    # 4. Verification
    if [ -s "$TEMP_CRON" ]; then
        crontab "$TEMP_CRON"
        echo "Cron job installed successfully."
    else
        echo -e "${RED}[ERROR] Temp crontab file is empty. Aborting cron installation.${NC}"
    fi
    
    rm "$TEMP_CRON"
fi

echo -e "\n${BLUE}=== Installation Complete ===${NC}"
echo "1. Restart your terminal."
echo "2. You should see the welcome message!"