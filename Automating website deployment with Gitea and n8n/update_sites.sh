#!/usr/bin/env bash
# update_sites.sh
# Description: Sets up sparse checkout to only pull the _site directory in the example repository.
# On subsequent runs, it fetches changes.
# Usage: Run this script as root or with sudo privileges
# Prerequisites:
#   - Git installed
#   - Target directory exists and is owned by 'www-data' user

set -euo pipefail
IFS=$'\n\t'

# Configuration Variables
REPO_URL="http://gitea/youruser/example.git"
TARGET_DIR="/var/www/html/yourdomain"
BRANCH="main"  # Change if your default branch is different
DEPLOY_USER="www-data"  # Assuming you're using 'www-data'; change if using a different user
LOG_FILE="/var/log/update_sites.log"

# Function to log messages with timestamp
log() {
    local MESSAGE="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $MESSAGE" | tee -a "$LOG_FILE"
}

# Function to retry commands
retry() {
    local -r MAX_ATTEMPTS=5
    local -r DELAY=10
    local -i attempt_num=1

    while (( attempt_num <= MAX_ATTEMPTS )); do
        if "$@"; then
            return 0
        fi
        log "Warning: Attempt $attempt_num failed! Trying again in $DELAY seconds..."
        sleep $DELAY
        attempt_num=$(( attempt_num + 1 ))
    done

    log "Error: All $MAX_ATTEMPTS attempts failed!"
    return 1
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    log "Error: Please run as root or using sudo."
    exit 1
fi

# Check for required commands
command_exists() {
    command -v "$1" &>/dev/null
}

if ! command_exists git; then
    log "Git is not installed. Installing Git..."
    # Detect OS and install Git accordingly
    if command_exists apt; then
        apt update && apt install -y git
    elif command_exists yum; then
        yum install -y git
    else
        log "Unsupported OS or package manager not found. Please install Git manually."
        exit 1
    fi
fi

# Check if the target directory exists and is a git repository
if [ -d "$TARGET_DIR/.git" ]; then
    log "Existing git repository found in $TARGET_DIR. Pulling latest changes."
    cd "$TARGET_DIR"
    retry sudo -u "$DEPLOY_USER" git fetch origin "$BRANCH"
    sudo -u "$DEPLOY_USER" git reset --hard "origin/$BRANCH"
    log "Update completed successfully!"
else
    # Create the target directory if it doesn't exist
    if [ ! -d "$TARGET_DIR" ]; then
        log "Creating target directory: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        chown "$DEPLOY_USER":"$DEPLOY_USER" "$TARGET_DIR"
    fi

    # Navigate to the target directory
    cd "$TARGET_DIR"

    # Initialize Git repository
    log "Initializing empty Git repository in $TARGET_DIR"
    sudo -u "$DEPLOY_USER" git init

    # Add the remote repository
    log "Adding remote repository: $REPO_URL"
    sudo -u "$DEPLOY_USER" git remote add origin "$REPO_URL"

    # Configure sparse checkout to pull only the '_site' directory
    log "Configuring sparse checkout to pull only the '_site' directory in non-cone mode"

    # Disable cone mode and enable sparse checkout
    sudo -u "$DEPLOY_USER" git config core.sparseCheckout true
    sudo -u "$DEPLOY_USER" git config core.sparseCheckoutCone false

    # Initialize sparse-checkout in non-cone mode
    sudo -u "$DEPLOY_USER" git sparse-checkout init --no-cone

    # Set the sparse-checkout patterns to include only '_site' directory
    echo "_site/*" | sudo -u "$DEPLOY_USER" tee "$TARGET_DIR/.git/info/sparse-checkout" >/dev/null

    # Fetch the specified branch
    log "Fetching the $BRANCH branch"
    retry sudo -u "$DEPLOY_USER" git fetch origin "$BRANCH"

    # Reset the branch to match the remote
    log "Checking out the $BRANCH branch"
    sudo -u "$DEPLOY_USER" git checkout -f "$BRANCH"

    log "Sparse checkout setup completed successfully!"
fi
