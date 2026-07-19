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
deploy_dir="deploy"             # folder for deploy files
frontend_dir="frontend-web"     # folder for light front end web files
backend_dir="backend"           # folder for backend service files

QUADLET_DIR="/etc/containers/systemd"   # folder to deploy podman files and systemd units
ENV_DIR="/etc/containers"               # folder to deploy .env and configuration files
WEB_DIR="/var/www/frontend"             # folder to deploy frontend
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

discovered_pods=()
discovered_networks=()
discovered_volumes=()
discovered_containers=()
discovered_envs=()

echo "=== [1/6] Verifying System Prerequisites ==="
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This initialization script must be executed via sudo or as root." >&2
    exit 1
fi

echo "=== [2/6] Synchronizing Repositories & Installing Core Infrastructure ==="
apt-get update
apt-get install -y podman nginx

echo "=== [3/6] Generating System Target Directories ==="
mkdir -p "$QUADLET_DIR"
mkdir -p "$ENV_DIR"
mkdir -p "$WEB_DIR"
mkdir -p "$NGINX_SITES_AVAILABLE"
mkdir -p "$NGINX_SITES_ENABLED"

echo "=== [4/6] Provisioning Asset Distributions ==="
# 1. Copy the Podman Quadlet configuration definitions
if [ -d "$deploy_dir" ]; then
    echo "📋 Staging Quadlet service specifications..."

    ( # find and migrate containers
        end=".container"
        srv="-container.service"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_containers+=("$service")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    )
    ( # find and migrate networks
        end=".network"
        srv="-network.service"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_networks+=("$service")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    )
    ( # find and migrate volumes
        end=".volume"
        srv="-volume.service"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_volumes+=("$service")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    )
    ( # find and migrate pods
        end=".pod"
        srv="-pod.service"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_pods+=("$service")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    )

    # 2. Establish Public Nginx Tracked Infrastructure Configuration
    if [ -f "$deploy_dir/nginx/travel-log.conf" ]; then
        echo "🔗 Linking tracked public Nginx server configuration directly to repository..."
        
        # 1. Resolve the absolute path to your live Git repository file
        ABS_CONF_PATH=$(realpath "$deploy_dir/nginx/travel-log.conf")
        TARGET_LINK="$NGINX_SITES_ENABLED/travel-log.conf"
        
        # 2. Clean up any existing file or broken link at that destination first
        if [ -L "$TARGET_LINK" ] || [ -f "$TARGET_LINK" ]; then
            rm -f "$TARGET_LINK"
        fi
        
        # 3. Link Nginx directly to your live repo file
        ln -s "$ABS_CONF_PATH" "$TARGET_LINK"
        echo "✅ Public Nginx site linked directly to: $ABS_CONF_PATH"
    else
        echo "ℹ️ No custom deployment nginx template located at $deploy_dir/nginx/travel-log.conf"
    fi
    
    # 3. Safely initialize environment configuration without overwriting existing files
    ( # find and migrate .env files
        end=".env.tmpl"
        srv=".env"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                real="${base/"$end"/"$srv"}"
                
                if [ ! -f "$ENV_DIR/$real" ]; then
                    cp "$file" "$ENV_DIR/$real"
                    chmod 600 "$ENV_DIR/$real" # Restrict read/write privileges strictly to root
                    echo "✅ Initialized fresh runtime environment file at $ENV_DIR/$real"
                else
                    echo "⚠️ Existing runtime environment file discovered at $ENV_DIR/$real. Skipping configuration override."
                fi
            fi
        done
    )
else
    echo "❌ Error: Required directory '$deploy_dir/' not found in working path." >&2
    exit 1
fi

# 4. Mount the universal user interface to the web root
if [ -d "$frontend_dir" ]; then
    echo "🌐 Copying static web user interface assets to $WEB_DIR..."
    cp -r "$frontend_dir"/* "$WEB_DIR/"
else
    echo "ℹ️ Note: Standard '$frontend_dir/' structure not located. Skipping web asset staging."
fi

echo "=== [5/6] Triggering Systemd Engine Re-Read ==="
# Forces systemd to process the new quadlet, pods, volumes, and network files and generate transient units
systemctl daemon-reload

echo "=== [6/6] Initializing Background Services ==="
echo "syncing network and runtime configurations..."

# Systemwide systemctl execution path (root mode)
for net_file in "$deploy_dir"/*.network; do
    if [ -f "$net_file" ]; then
        net_base=$(basename "$net_file")
        net_service=${net_base/.network/-network.service}
        echo "🌐 Starting network: $net_service"
        systemctl restart "$net_service"
    fi
done

for pod_file in "$deploy_dir"/*.pod; do
    if [ -f "$pod_file" ]; then
        pod_base=$(basename "$pod_file")
        pod_service="${pod_base/.pod/-pod.service}"
        echo "📦 Starting tracking pod: $pod_service"
        systemctl restart "$pod_service"
    fi
done

# Reload Nginx to capture any updated configuration mappings smoothly
echo "⚙️ Refreshing system Nginx server mappings..."
systemctl restart nginx

echo "=============================================================================="
echo "✅ Operational Setup Sequence Concluded Successfully."
echo "=============================================================================="
echo "💡 CRITICAL NEXT STEPS:"
echo " 1. Modify your production environment secrets block:"
echo "    sudo nano $ENV_DIR/app.env"
echo " "
echo " 2. Restart your core engine pod wrapper to safely apply updates:"
echo "    sudo systemctl restart travel-log-pod.service"
echo " "
echo " 3. Check current engine logs using standard tracking tools:"
echo "    sudo journalctl -u travel-log-pod.service -f"
echo "=============================================================================="