#!/bin/bash
# ==============================================================================
# SYSTEM INITIALIZATION, AUTOMATION DEPLOYMENT, & TEARDOWN SCRIPT
# ==============================================================================
# Targets: Debian / Ubuntu Server environments.
# Execution: 
#   Setup:    sudo ./deploy.sh
#   Teardown: sudo ./deploy.sh --teardown
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
discovered_builds=()
discovered_envs=()
discovered_networks=()
discovered_volumes=()
discovered_containers=()

# ==============================================================================
# STAGE 1: Check Prerequisites & Flags
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be executed via sudo or as root." >&2
    exit 1
fi

# Check if the user requested a teardown
TEARDOWN_MODE=false
if [ "${1:-}" = "--teardown" ] || [ "${1:-}" = "-u" ]; then
    TEARDOWN_MODE=true
fi

# ==============================================================================
# BRANCH: TEARDOWN LOGIC
# ==============================================================================
if [ "$TEARDOWN_MODE" = true ]; then
    echo "=== [1/4] Stopping Active Quadlet Services ==="
    if [ -d "$deploy_dir" ]; then
        # 1. Bring down active containers first
        for file in "$deploy_dir"/*.container; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service="${base/.container/.service}"
                echo "🛑 Stopping application container: $service"
                systemctl stop "$service" || true
            fi
        done

        # 2. Bring down active pods
        for file in "$deploy_dir"/*.pod; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service="${base/.pod/-pod.service}"
                echo "🛑 Stopping tracking pod: $service"
                systemctl stop "$service" || true
            fi
        done

        # 3. Drop active networks
        for file in "$deploy_dir"/*.network; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                service="${base/.network/-network.service}"
                echo "🌐 Stopping network service: $service"
                systemctl stop "$service" || true
            fi
        done
    fi

    echo "=== [2/4] Purging Staged Assets & Mappings ==="
    if [ -d "$deploy_dir" ]; then
        echo "🧹 Removing target configurations from systemd..."
        for ext in .container .build .network .volume .pod; do
            for file in "$deploy_dir"/*"$ext"; do
                if [ -f "$file" ]; then
                    base=$(basename "$file")
                    rm -f "$QUADLET_DIR/$base"
                fi
            done
        done
    fi

    TARGET_LINK="$NGINX_SITES_ENABLED/travel-log.conf"
    if [ -L "$TARGET_LINK" ] || [ -f "$TARGET_LINK" ]; then
        echo "🔗 Removing Nginx configuration link..."
        rm -f "$TARGET_LINK"
    fi

    if [ -d "$WEB_DIR" ]; then
        echo "🗑️ Wiping frontend build assets out of $WEB_DIR..."
        rm -rf "${WEB_DIR:?}"/*
    fi

    echo "=== [3/4] Triggering Systemd Engine Re-Read ==="
    systemctl daemon-reload
    systemctl reset-failed

    echo "=== [4/4] Purging Stopped Container Infrastructure ==="
    echo "🐋 Pruning residual container assets..."
    podman pod prune -f
    podman volume prune -f
    podman network prune -f
    
    systemctl restart nginx

    echo "=============================================================================="
    echo "✅ Teardown Complete. Environment safely un-setup."
    echo "=============================================================================="
    exit 0
fi

# ==============================================================================
# BRANCH: SETUP LOGIC
# ==============================================================================
echo "=== [1/6] Verifying System Prerequisites ==="

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
if [ -d "$deploy_dir" ]; then
    echo "📋 Staging Quadlet service specifications..."

    { # find and migrate containers
        end=".container"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                discovered_containers+=("$base")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    }
    { # find and migrate build files
        end=".build"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                discovered_builds+=("$base")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    }
    { # find and migrate networks
        end=".network"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                discovered_networks+=("$base")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    }
    { # find and migrate volumes
        end=".volume"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                discovered_volumes+=("$base")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    }
    { # find and migrate pods
        end=".pod"
        for file in "$deploy_dir"/*"$end"; do
            if [ -f "$file" ]; then
                base=$(basename "$file")
                discovered_pods+=("$base")
                cp "$file" "$QUADLET_DIR/"
            fi
        done
    }

    # Establish Public Nginx Link
    if [ -f "$deploy_dir/nginx/travel-log.conf" ]; then
        echo "🔗 Linking tracked public Nginx server configuration directly to repository..."
        ABS_CONF_PATH=$(realpath "$deploy_dir/nginx/travel-log.conf")
        TARGET_LINK="$NGINX_SITES_ENABLED/travel-log.conf"
        
        # Remove default Debian site if present to prevent port 80 collisions
        rm -f "$NGINX_SITES_ENABLED/default"

        if [ -L "$TARGET_LINK" ] || [ -f "$TARGET_LINK" ]; then
            rm -f "$TARGET_LINK"
        fi
        
        ln -s "$ABS_CONF_PATH" "$TARGET_LINK"
        echo "✅ Public Nginx site linked directly to: $ABS_CONF_PATH"
    fi
    
    # Safely initialize environment configuration
    for file in "$deploy_dir"/*.env.tmpl; do
        if [ -f "$file" ]; then
            base=$(basename "$file")
            discovered_envs+=("$base")
            real="${base/.env.tmpl/.env}"
            
            if [ ! -f "$ENV_DIR/$real" ]; then
                cp "$file" "$ENV_DIR/$real"
                chmod 600 "$ENV_DIR/$real"
                echo "✅ Initialized fresh runtime environment file at $ENV_DIR/$real"
            else
                echo "⚠️ Existing runtime environment file discovered at $ENV_DIR/$real. Skipping configuration override."
            fi
        fi
    done
else
    echo "❌ Error: Required directory '$deploy_dir/' not found in working path." >&2
    exit 1
fi

# Mount user interface to web root
if [ -d "$frontend_dir" ]; then
    echo "🌐 Copying static web user interface assets to $WEB_DIR..."
    cp -r "$frontend_dir"/* "$WEB_DIR/"
fi

echo "=== [5/6] Triggering Systemd Engine Re-Read ==="
systemctl daemon-reload

echo "=== [6/6] Initializing Background Services ==="
echo "syncing network and runtime configurations..."

# 1. Start networks
for net_file in "$deploy_dir"/*.network; do
    if [ -f "$net_file" ]; then
        net_base=$(basename "$net_file")
        net_service="${net_base/.network/-network.service}"
        echo "🌐 Starting network: $net_service"
        systemctl restart "$net_service"
    fi
done

# 2. Start pods
for pod_file in "$deploy_dir"/*.pod; do
    if [ -f "$pod_file" ]; then
        pod_base=$(basename "$pod_file")
        pod_service="${pod_base/.pod/-pod.service}"
        echo "📦 Starting tracking pod: $pod_service"
        systemctl restart "$pod_service"
    fi
done

# 3. Explicitly start Quadlet containers
for container_file in "$deploy_dir"/*.container; do
    if [ -f "$container_file" ]; then
        container_base=$(basename "$container_file")
        container_service="${container_base/.container/.service}"
        echo "🚀 Starting application container: $container_service"
        systemctl restart "$container_service"
    fi
done

echo "⚙️ Refreshing system Nginx server mappings..."
systemctl restart nginx

echo "=============================================================================="
echo "✅ Operational Setup Sequence Concluded Successfully."
echo "=============================================================================="