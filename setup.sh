#!/bin/bash
# ==============================================================================
# SYSTEM INITIALIZATION & AUTOMATION DEPLOYMENT SCRIPT
# ==============================================================================
# Targets: Debian / Ubuntu Server environments.
# Execution: Run as root or a user with elevated sudo permissions.
# ==============================================================================

# Exit immediately if any underlying pipeline command fails
set -euo pipefail

# Define operational paths
QUADLET_DIR="/etc/containers/systemd"
ENV_DIR="/etc/containers"
WEB_DIR="/var/www/frontend"

echo "=== [1/6] Verifying System Prerequisites ==="
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This initialization script must be executed via sudo or as root." >&2
    exit 1
fi

echo "=== [2/6] Synchronizing Repositories & Installing Podman ==="
apt-get update
apt-get install -y podman

echo "=== [3/6] Generating System Target Directories ==="
mkdir -p "$QUADLET_DIR"
mkdir -p "$ENV_DIR"
mkdir -p "$WEB_DIR"

echo "=== [4/6] Provisioning Asset Distributions ==="
# 1. Copy the Podman Quadlet configuration definitions
if [ -d "deploy" ]; then
    echo "📋 Staging Quadlet service specifications..."
    cp deploy/*.container "$QUADLET_DIR/" 2>/dev/null || echo "ℹ️ No .container files found yet."
    cp deploy/*.network "$QUADLET_DIR/" 2>/dev/null || echo "ℹ️ No .network files found yet."
    cp deploy/*.volume "$QUADLET_DIR/" 2>/dev/null || echo "ℹ️ No .volume files found yet."
    cp deploy/nginx.conf "$ENV_DIR/nginx.conf" 2>/dev/null || echo "ℹ️ No nginx.conf file found yet."
    
    # 2. Safely initialize environment configuration without overwriting existing files
    if [ ! -f "$ENV_DIR/app.env" ]; then
        echo "🔑 Provisioning fresh environment template at $ENV_DIR/app.env"
        cp deploy/app.env.tmpl "$ENV_DIR/app.env"
        chmod 600 "$ENV_DIR/app.env" # Restrict read/write privileges strictly to root
    else
        echo "⚠️  Existing runtime environment file discovered at $ENV_DIR/app.env. Skipping configuration override."
    fi
else
    echo "❌ Error: Required directory 'deploy/' not found in working path." >&2
    exit 1
fi

# 3. Mount the universal user interface to the web root
if [ -d "frontend-web" ] && [ -f "frontend-web/index.html" ]; then
    echo "🌐 Copying static web user interface assets to $WEB_DIR..."
    cp -r frontend-web/* "$WEB_DIR/"
else
    echo "ℹ️ Note: Standard 'frontend-web/index.html' structure not located. Skipping web asset staging."
fi

echo "=== [5/6] Triggering Systemd Engine Re-Read ==="
# Forces systemd to process the new Quadlet files and generate transient units
systemctl daemon-reload

echo "=== [6/6] Initializing Background Services ==="
# Note: Podman Quadlets automatically generate systemd service targets matching filename.service
echo "syncing network and runtime configurations..."
systemctl enable --now app.network || echo "ℹ️ Network target pending runtime generation."

echo "=============================================================================="
echo "✅ Operational Setup Sequence Concluded Successfully."
echo "=============================================================================="
echo "💡 CRITICAL NEXT STEPS:"
echo " 1. Modify your production environment secrets block:"
echo "    sudo nano $ENV_DIR/app.env"
echo " "
echo " 2. Restart your core engine wrapper to safely apply updates:"
echo "    sudo systemctl restart app.service"
echo " "
echo " 3. Check current engine logs using standard tracking tools:"
echo "    sudo journalctl -u app.service -f"
echo "=============================================================================="