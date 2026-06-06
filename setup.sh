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

QUADLET_DIR="/etc/containers/systemd"   #folder to deploy podman files and systemd units
ENV_DIR="/etc/containers"               #folder to deploy .env and configuration files
WEB_DIR="/var/www/frontend"             #folder to deploy frontend

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

echo "=== [2/6] Synchronizing Repositories & Installing Podman ==="
apt-get update
apt-get install -y podman

echo "=== [3/6] Generating System Target Directories ==="
mkdir -p "$QUADLET_DIR"
mkdir -p "$ENV_DIR"
mkdir -p "$WEB_DIR"

echo "=== [4/6] Provisioning Asset Distributions ==="
# 1. Copy the Podman Quadlet configuration definitions
if [ -d "$deploy_dir" ]; then
    echo "📋 Staging Quadlet service specifications..."

    ( #find and migrate containers
        end=".container"
        srv="-container.service"
        for file in $deploy_dir/*$end; do
            if [-f "$file"]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_containers+=($service)
                cp "$file" "$QUADLET_DIR/" 1> /dev/null || echo "copying $file to $QUADLET_DIR"
            else
                echo "$file is not a file?"
            fi
        done
    )
    ( #find and migrate networks
        end=".network"
        srv="-network.service"
        for file in $deploy_dir/*$end; do
            if [-f "$file"]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_networks+=($service)
                cp "$file" "$QUADLET_DIR/" 1> /dev/null || echo "copying $file to $QUADLET_DIR"
            else
                echo "$file is not a file?"
            fi
        done
    )
    ( #find and migrate volumes
        end=".volume"
        srv="-volume.service"
        for file in $deploy_dir/*$end; do
            if [-f "$file"]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_volumes+=($service)
                cp "$file" "$QUADLET_DIR/" 1> /dev/null || echo "copying $file to $QUADLET_DIR"
            else
                echo "$file is not a file?"
            fi
        done
    )
    ( #find and migrate pods
        end=".pod"
        srv="-pod.service"
        for file in $deploy_dir/*$end; do
            if [-f "$file"]; then
                base=$(basename "$file")
                service=${base/"$end"/"$srv"}
                discovered_pods+=($service)
                cp "$file" "$QUADLET_DIR/" 1> /dev/null || echo "copying $file to $QUADLET_DIR"
            else
                echo "$file is not a file?"
            fi
        done
    )

    # find and migrate the nginx file if it exists
    cp $deploy_dir/nginx.conf "$ENV_DIR/nginx.conf" 2>/dev/null || echo "ℹ️ No nginx.conf file found yet."
    
    # 2. Safely initialize environment configuration without overwriting existing files
    
    
    ( #find and migrate .env files
        end=".env.tmpl"
        srv=".env"
        for file in $deploy_dir/*$end; do
            if [-f "$file"]; then
                base=$(basename "$file")
                real="${base/"$end"/"$srv"}"
                discovered_pods+=($real)
                
                if [ ! -f "$ENV_DIR/$target_name" ]; then
                    cp $file "$ENV_DIR/$real" 1> /dev/null || echo "copying $file to $ENV_DIR as $real"
                    chmod 600 "$ENV_DIR/$target_name" # Restrict read/write privileges strictly to root
                else
                    echo "⚠️  Existing runtime environment file discovered at $ENV_DIR/$real. Skipping configuration override."
                    echo "\t to force copy run the commands:"
                    echo "cp \"$file $ENV_DIR/$real\" #copying the file"
                    echo "chmod 600 \"$ENV_DIR/$target_name\" # Restrict read/write privileges strictly to root"
                fi
            else
                echo "$file is not a file?"
            fi
        done
    )

    
else
    echo "❌ Error: Required directory '$deploy_dir/' not found in working path." >&2
    exit 1
fi

# 3. Mount the universal user interface to the web root
if [ -d "$frontend_dir" ] && [-f "$frontend_dir/*.html"]; then
    echo "🌐 Copying static web user interface assets to $WEB_DIR..."
    cp -r "$frontend_dir/*" "$WEB_DIR/"
else
    echo "ℹ️ Note: Standard 'frontend-web/*.html' structure not located. Skipping web asset staging."
fi

echo "=== [5/6] Triggering Systemd Engine Re-Read ==="
# Forces systemd to process the new quadlet, pods, volumes, and network files and generate transient units
systemctl daemon-reload

echo "=== [6/6] Initializing Background Services ==="
# Note: Podman Quadlets, volumes, pods, and networks automatically
# generate systemd service targets matching filename.service
echo "syncing network and runtime configurations..."

for net_file in $deploy_dir/*.network; do
    if [-f "$net_file"]; then
        net_base$(basename "$net_file")
        net_service=${net_base/.network/-network.service}
        echo "🌐 Starting network: $net_service"
        systemctl --user enable --now "$net_service"
    fi
done

for pod_file in "$deploy_dir/*.pod"; do
    if [ -f "$pod_file" ]; then
        pod_base=$(basename "$pod_file")
        pod_service="${pod_base/.pod/-pod.service}"

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