#!/bin/bash
# Health check and recovery script for systemd integration

ENVIRONMENT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment if provided
if [ -n "$ENVIRONMENT" ] && [ -f "$SCRIPT_DIR/environments/$ENVIRONMENT.env" ]; then
    source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"
fi

# Quick health check
if rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "$(date): Cluster health check passed"
    exit 0
fi

echo "$(date): Cluster health check failed, checking if recovery is needed..."

# Wait a bit more for natural recovery
sleep 30

if rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "$(date): Cluster recovered naturally"
    exit 0
fi

# Check if force boot is enabled for this environment
if [ "$RABBITMQ_FORCE_BOOT_ON_STARTUP" = "true" ]; then
    echo "$(date): Force boot enabled, attempting automatic recovery..."
    "$SCRIPT_DIR/auto-force-boot.sh" -e "$ENVIRONMENT" -f
else
    echo "$(date): Force boot disabled, manual intervention may be required"
fi
