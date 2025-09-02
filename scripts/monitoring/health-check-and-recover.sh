#!/bin/bash
# Health check and recovery script for systemd integration

set -e

ENVIRONMENT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment if provided
if [ -n "$ENVIRONMENT" ] && [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    echo "$(date): Loading environment configuration for $ENVIRONMENT"
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
else
    echo "$(date): Warning: Environment not specified or load script not found, using defaults"
    # Set some defaults
    RABBITMQ_FORCE_BOOT_ON_STARTUP="false"
    RABBITMQ_AUTO_RECOVERY_DELAY="30"
fi

# Function to log messages with timestamp
log_message() {
    echo "$(date): $1"
}

# Quick health check
log_message "Starting cluster health check..."
if rabbitmqctl cluster_status >/dev/null 2>&1; then
    log_message "Cluster health check passed"
    exit 0
fi

log_message "Cluster health check failed, checking if recovery is needed..."

# Wait a bit more for natural recovery
log_message "Waiting ${RABBITMQ_AUTO_RECOVERY_DELAY:-30} seconds for natural recovery..."
sleep "${RABBITMQ_AUTO_RECOVERY_DELAY:-30}"

if rabbitmqctl cluster_status >/dev/null 2>&1; then
    log_message "Cluster recovered naturally"
    exit 0
fi

# Check if force boot is enabled for this environment
if [ "$RABBITMQ_FORCE_BOOT_ON_STARTUP" = "true" ]; then
    log_message "Force boot enabled, attempting automatic recovery..."
    if [ -f "$SCRIPT_DIR/auto-force-boot.sh" ]; then
        "$SCRIPT_DIR/auto-force-boot.sh" -e "$ENVIRONMENT" -f
    else
        log_message "Error: auto-force-boot.sh script not found"
        exit 1
    fi
else
    log_message "Force boot disabled, manual intervention may be required"
    exit 1
fi
