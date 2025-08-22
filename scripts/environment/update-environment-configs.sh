#!/bin/bash
# File: update-environment-configs.sh
# Update environment configurations with auto-recovery settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to update base environment with auto-recovery settings
update_base_environment() {
    local base_file="$SCRIPT_DIR/environments/base.env"
    
    echo "Updating base environment with auto-recovery settings..."
    
    # Add auto-recovery settings to base.env
    cat >> "$base_file" << 'EOF'

# === Auto-Recovery Configuration ===
RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY="30"
RABBITMQ_CLUSTER_FORMATION_RETRY_LIMIT="10"
RABBITMQ_AUTO_RECOVERY_ENABLED="true"
RABBITMQ_AUTO_RECOVERY_DELAY="30"

# === Boot Behavior ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="false"  # Set to true for aggressive recovery
RABBITMQ_STARTUP_TIMEOUT="300"          # 5 minutes timeout for startup

# === Cluster Formation Settings ===
RABBITMQ_CLUSTER_FORMATION_NODE_CLEANUP="true"
RABBITMQ_CLUSTER_FORMATION_LOG_CLEANUP="true"
RABBITMQ_RANDOMIZED_STARTUP_DELAY_MIN="5"
RABBITMQ_RANDOMIZED_STARTUP_DELAY_MAX="30"

# === Auto-Recovery Monitor Settings ===
RABBITMQ_MONITOR_CHECK_INTERVAL="60"
RABBITMQ_MONITOR_RECOVERY_TIMEOUT="300"
RABBITMQ_MONITOR_MAX_FAILURES="3"
RABBITMQ_MONITOR_RECOVERY_COOLDOWN="1800"
EOF
    
    echo "✅ Base environment updated with auto-recovery settings"
}

# Function to update production environment with specific settings
update_production_environment() {
    local prod_file="$SCRIPT_DIR/environments/prod.env"
    
    echo "Updating production environment with auto-recovery settings..."
    
    cat >> "$prod_file" << 'EOF'

# === Production Auto-Recovery Settings ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="false"  # Conservative for data safety
RABBITMQ_AUTO_RECOVERY_DELAY="60"       # Longer delay for production
RABBITMQ_STARTUP_TIMEOUT="600"          # 10 minutes for production startup

# === Production Monitor Settings ===
RABBITMQ_MONITOR_CHECK_INTERVAL="30"    # More frequent checks in production
RABBITMQ_MONITOR_RECOVERY_TIMEOUT="600" # Longer recovery timeout
RABBITMQ_MONITOR_MAX_FAILURES="5"       # More failures before recovery
RABBITMQ_MONITOR_RECOVERY_COOLDOWN="3600" # 1 hour between recovery attempts
EOF
    
    echo "✅ Production environment updated with auto-recovery settings"
}

# Function to update QA environment for aggressive recovery
update_qa_environment() {
    local qa_file="$SCRIPT_DIR/environments/qa.env"
    
    echo "Updating QA environment with auto-recovery settings..."
    
    cat >> "$qa_file" << 'EOF'

# === QA Auto-Recovery Settings ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="true"   # Aggressive recovery for QA
RABBITMQ_AUTO_RECOVERY_DELAY="15"       # Quick recovery for testing
RABBITMQ_STARTUP_TIMEOUT="180"          # 3 minutes for QA startup

# === QA Monitor Settings ===
RABBITMQ_MONITOR_CHECK_INTERVAL="30"    # Frequent checks for testing
RABBITMQ_MONITOR_RECOVERY_TIMEOUT="180" # Quick recovery for QA
RABBITMQ_MONITOR_MAX_FAILURES="2"       # Quick recovery trigger
RABBITMQ_MONITOR_RECOVERY_COOLDOWN="300" # 5 minutes between attempts
EOF
    
    echo "✅ QA environment updated with auto-recovery settings"
}

# Function to update staging environment
update_staging_environment() {
    local staging_file="$SCRIPT_DIR/environments/staging.env"
    
    echo "Updating staging environment with auto-recovery settings..."
    
    cat >> "$staging_file" << 'EOF'

# === Staging Auto-Recovery Settings ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="false"  # Conservative like production
RABBITMQ_AUTO_RECOVERY_DELAY="30"       # Moderate delay
RABBITMQ_STARTUP_TIMEOUT="300"          # 5 minutes for staging startup

# === Staging Monitor Settings ===
RABBITMQ_MONITOR_CHECK_INTERVAL="45"    # Moderate frequency
RABBITMQ_MONITOR_RECOVERY_TIMEOUT="300" # Standard recovery timeout
RABBITMQ_MONITOR_MAX_FAILURES="3"       # Standard threshold
RABBITMQ_MONITOR_RECOVERY_COOLDOWN="900" # 15 minutes between attempts
EOF
    
    echo "✅ Staging environment updated with auto-recovery settings"
}

# Function to update the config generator to include auto-recovery settings
update_config_generator() {
    echo "Updating generate-configs.sh to include auto-recovery settings..."
    
    # Create a patch for the generate-configs.sh to include auto-recovery in rabbitmq.conf
    cat > "/tmp/auto-recovery-config-patch.txt" << 'EOF'

# === Auto-Recovery Settings ===
cluster_formation.node_cleanup.only_log_warning = $RABBITMQ_CLUSTER_FORMATION_LOG_CLEANUP
cluster_formation.node_cleanup.interval = $RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY

# === Retry Logic ===
cluster_formation.discovery_retry_limit = $RABBITMQ_CLUSTER_FORMATION_RETRY_LIMIT
cluster_formation.discovery_retry_interval = ${RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY}000

# === Startup Behavior ===
cluster_formation.randomized_startup_delay_range.min = $RABBITMQ_RANDOMIZED_STARTUP_DELAY_MIN
cluster_formation.randomized_startup_delay_range.max = $RABBITMQ_RANDOMIZED_STARTUP_DELAY_MAX

# === Environment-specific Partition Handling ===
# For production: use pause_minority for data safety
# For QA/staging: can use autoheal for automatic recovery
EOF
    
    echo "✅ Auto-recovery configuration template created"
    echo "📝 Note: The generate-configs.sh will need to be updated to include these settings"
}

# Function to create systemd service template with auto-recovery
create_systemd_template() {
    echo "Creating systemd service template with auto-recovery..."
    
    cat > "$SCRIPT_DIR/systemd-service-template.service" << 'EOF'
[Unit]
Description=RabbitMQ broker with Auto-Recovery (%i)
After=network.target epmd@0.0.0.0.socket network-online.target
Wants=network.target epmd@0.0.0.0.socket network-online.target

[Service]
Type=notify
User=rabbitmq
Group=rabbitmq
NotifyAccess=all
TimeoutStartSec=${RABBITMQ_STARTUP_TIMEOUT}
TimeoutStopSec=120

# Environment variables for auto-recovery
Environment=RABBITMQ_ENVIRONMENT=%i
Environment=RABBITMQ_NODENAME=rabbit@%H
Environment=RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
Environment=RABBITMQ_AUTO_RECOVERY_ENABLED=${RABBITMQ_AUTO_RECOVERY_ENABLED}

# Service execution with startup delay for cluster formation
ExecStartPre=/bin/sleep ${RABBITMQ_RANDOMIZED_STARTUP_DELAY_MIN}
ExecStart=/usr/lib/rabbitmq/bin/rabbitmq-server
ExecStop=/usr/lib/rabbitmq/bin/rabbitmqctl shutdown

# Auto-recovery configuration
Restart=always
RestartSec=${RABBITMQ_AUTO_RECOVERY_DELAY}
StartLimitBurst=10
StartLimitIntervalSec=600

# Post-start health check and recovery
ExecStartPost=/bin/bash -c 'sleep 60 && /opt/rabbitmq-deployment/health-check-and-recover.sh %i'

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    
    echo "✅ Systemd service template created: systemd-service-template.service"
}

# Function to create health check and recovery script for systemd
create_health_check_script() {
    echo "Creating health check and recovery script for systemd..."
    
    cat > "$SCRIPT_DIR/health-check-and-recover.sh" << 'EOF'
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
EOF
    
    chmod +x "$SCRIPT_DIR/health-check-and-recover.sh"
    echo "✅ Health check and recovery script created: health-check-and-recover.sh"
}

# Main execution
main() {
    echo "=== Updating Environment Configurations for Auto-Recovery ==="
    echo ""
    
    # Update environment files
    update_base_environment
    echo ""
    
    update_production_environment
    echo ""
    
    update_qa_environment
    echo ""
    
    update_staging_environment
    echo ""
    
    # Update supporting files
    update_config_generator
    echo ""
    
    create_systemd_template
    echo ""
    
    create_health_check_script
    echo ""
    
    echo "=== Auto-Recovery Configuration Update Complete ==="
    echo ""
    echo "📋 What was updated:"
    echo "  ✅ environments/base.env - Added auto-recovery settings"
    echo "  ✅ environments/prod.env - Production-specific auto-recovery"
    echo "  ✅ environments/qa.env - Aggressive auto-recovery for QA"
    echo "  ✅ environments/staging.env - Balanced auto-recovery for staging"
    echo "  ✅ systemd-service-template.service - Auto-recovery systemd template"
    echo "  ✅ health-check-and-recover.sh - Health check script for systemd"
    echo ""
    echo "🔧 Next steps:"
    echo "  1. Update generate-configs.sh to use new auto-recovery settings"
    echo "  2. Regenerate configurations: ./generate-configs.sh <environment>"
    echo "  3. Deploy updated systemd service: sudo cp systemd-service-template.service /etc/systemd/system/rabbitmq-server@.service"
    echo "  4. Start auto-recovery monitor: ./cluster-auto-recovery-monitor.sh -e <environment> -d"
    echo ""
    echo "💡 Environment-specific behaviors:"
    echo "  🔴 Production: Conservative recovery, manual intervention preferred"
    echo "  🟡 Staging: Balanced approach, moderate auto-recovery"
    echo "  🟢 QA: Aggressive auto-recovery, force boot enabled"
    echo ""
    echo "🚀 For immediate auto-recovery setup:"
    echo "  ./auto-force-boot.sh -e <environment>              # Manual force boot"
    echo "  ./cluster-auto-recovery-monitor.sh -e <environment> # Start monitoring"
}

main "$@"