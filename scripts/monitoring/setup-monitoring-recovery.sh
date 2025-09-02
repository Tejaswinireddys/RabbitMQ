#!/bin/bash
# RabbitMQ Monitoring and Recovery Setup Script
# This script sets up the complete monitoring and auto-recovery system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-qa}"
INSTALL_MONITORING="${2:-true}"
INSTALL_RECOVERY="${3:-true}"

# Load environment
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_recovery() {
    echo -e "${PURPLE}[RECOVERY]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Install required packages
install_packages() {
    print_info "Installing required packages..."
    
    # Update package list
    if command -v yum &> /dev/null; then
        yum update -y || true
        yum install -y curl wget jq net-tools || true
    elif command -v apt-get &> /dev/null; then
        apt-get update || true
        apt-get install -y curl wget jq net-tools || true
    else
        print_warning "Package manager not detected, skipping package installation"
    fi
    
    print_status "Package installation completed"
}

# Setup monitoring system
setup_monitoring() {
    if [[ "$INSTALL_MONITORING" != "true" ]]; then
        print_info "Skipping monitoring setup as requested"
        return 0
    fi
    
    print_info "Setting up monitoring system..."
    
    # Check if Prometheus is already installed
    if [[ -d "/opt/prometheus" ]]; then
        print_info "Prometheus already installed, updating configuration..."
    else
        print_info "Installing Prometheus..."
        
        # Download Prometheus
        cd /opt
        wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
        tar -xzf prometheus-2.45.0.linux-amd64.tar.gz
        ln -sf prometheus-2.45.0 prometheus
        
        # Create prometheus user
        useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
        mkdir -p /opt/prometheus/data
        chown prometheus:prometheus /opt/prometheus/data
    fi
    
    # Create enhanced Prometheus configuration
    print_info "Creating enhanced Prometheus configuration..."
    
    cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "rabbitmq-cluster"
    environment: "production"

rule_files:
  - "tier1_alerts.yml"
  - "tier2_alerts.yml"
  - "tier3_alerts.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

scrape_configs:
  # RabbitMQ Core Metrics
  - job_name: 'rabbitmq-core'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 15s
    scrape_timeout: 10s
    honor_labels: true
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'rabbitmq_(queue_messages|connections_total|channels_total|exchanges_total)'
        action: keep

  # RabbitMQ Performance Metrics
  - job_name: 'rabbitmq-performance'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 15s
    honor_labels: true
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'rabbitmq_(queue_messages_published_total|queue_messages_delivered_total|queue_messages_redelivered_total|queue_messages_ack_total)'
        action: keep

  # RabbitMQ System Metrics
  - job_name: 'rabbitmq-system'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 60s
    scrape_timeout: 20s
    honor_labels: true
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'rabbitmq_(process_resident_memory_bytes|erlang_vm_memory_bytes_total|disk_free_bytes|disk_free_bytes_total)'
        action: keep

  # RabbitMQ Cluster Metrics
  - job_name: 'rabbitmq-cluster'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 45s
    scrape_timeout: 15s
    honor_labels: true
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'rabbitmq_(cluster_members|cluster_links|cluster_partitions)'
        action: keep

  # Prometheus Self-Monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
EOF
    
    # Copy alert rules
    print_info "Setting up multi-tier alerting rules..."
    
    cp "$SCRIPT_DIR/../configs/templates/tier1_alerts.yml" /opt/prometheus/
    cp "$SCRIPT_DIR/../configs/templates/tier2_alerts.yml" /opt/prometheus/
    cp "$SCRIPT_DIR/../configs/templates/tier3_alerts.yml" /opt/prometheus/
    
    chown prometheus:prometheus /opt/prometheus/*.yml
    
    # Create Prometheus systemd service
    print_info "Creating Prometheus systemd service..."
    
    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/opt/prometheus/data --web.listen-address=:9090
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    # Install Alert Manager
    print_info "Installing Alert Manager..."
    
    cd /opt
    wget https://github.com/prometheus/alertmanager/releases/download/v0.25.0/alertmanager-0.25.0.linux-amd64.tar.gz
    tar -xzf alertmanager-0.25.0.linux-amd64.tar.gz
    ln -sf alertmanager-0.25.0 alertmanager
    
    # Create Alert Manager configuration
    cat > /opt/alertmanager/alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@company.com'

route:
  group_by: ['alertname', 'tier']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default-receiver'
  
  routes:
    # Tier 1: Executive alerts
    - match:
        tier: "tier1"
      receiver: 'executive-team'
      repeat_interval: 1h
      
    # Tier 2: Operations alerts
    - match:
        tier: "tier2"
      receiver: 'operations-team'
      repeat_interval: 30m
      
    # Tier 3: Technical alerts
    - match:
        tier: "tier3"
      receiver: 'development-team'
      repeat_interval: 15m

receivers:
  - name: 'default-receiver'
    email_configs:
      - to: 'rabbitmq-alerts@company.com'
    
  - name: 'executive-team'
    email_configs:
      - to: 'executive@company.com'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#executive-alerts'
        
  - name: 'operations-team'
    email_configs:
      - to: 'operations@company.com'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#operations-alerts'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
        
  - name: 'development-team'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#development-alerts'
    webhook_configs:
      - url: 'YOUR_JIRA_WEBHOOK_URL'
        send_resolved: true
EOF
    
    # Create Alert Manager systemd service
    cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Alert Manager
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/alertmanager/alertmanager --config.file=/opt/alertmanager/alertmanager.yml --storage.path=/opt/alertmanager/data
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    mkdir -p /opt/alertmanager/data
    chown prometheus:prometheus /opt/alertmanager/data
    
    print_status "Monitoring system setup completed"
}

# Setup recovery system
setup_recovery() {
    if [[ "$INSTALL_RECOVERY" != "true" ]]; then
        print_info "Skipping recovery setup as requested"
        return 0
    fi
    
    print_info "Setting up recovery system..."
    
    # Copy monitoring and recovery scripts
    print_info "Installing monitoring and recovery scripts..."
    
    mkdir -p /usr/local/bin
    cp "$SCRIPT_DIR/cluster-monitor.sh" /usr/local/bin/rabbitmq-monitor.sh
    cp "$SCRIPT_DIR/cluster-auto-recovery.sh" /usr/local/bin/rabbitmq-recovery.sh
    
    chmod +x /usr/local/bin/rabbitmq-monitor.sh
    chmod +x /usr/local/bin/rabbitmq-recovery.sh
    
    # Create systemd service files
    print_info "Creating systemd services..."
    
    cp "$SCRIPT_DIR/../configs/templates/rabbitmq-monitor.service" /etc/systemd/system/
    cp "$SCRIPT_DIR/../configs/templates/rabbitmq-monitor.timer" /etc/systemd/system/
    
    # Create log directories
    mkdir -p /var/log/rabbitmq
    mkdir -p /backup/rabbitmq
    
    # Create monitoring wrapper script
    cat > /usr/local/bin/rabbitmq-monitor.sh << 'EOF'
#!/bin/bash
# RabbitMQ Monitoring Wrapper Script

ENVIRONMENT="${RABBITMQ_ENVIRONMENT:-production}"
LOG_FILE="/var/log/rabbitmq/cluster-monitor.log"

# Log monitoring start
echo "$(date): Starting RabbitMQ cluster monitoring" >> "$LOG_FILE"

# Run cluster monitoring
if /usr/local/bin/rabbitmq-monitor.sh "$ENVIRONMENT"; then
    echo "$(date): Cluster monitoring completed successfully" >> "$LOG_FILE"
    exit 0
else
    echo "$(date): Cluster monitoring detected issues, attempting recovery" >> "$LOG_FILE"
    
    # Run auto-recovery
    if /usr/local/bin/rabbitmq-recovery.sh "$ENVIRONMENT" "auto"; then
        echo "$(date): Auto-recovery completed successfully" >> "$LOG_FILE"
        exit 0
    else
        echo "$(date): Auto-recovery failed, manual intervention required" >> "$LOG_FILE"
        exit 1
    fi
fi
EOF
    
    chmod +x /usr/local/bin/rabbitmq-monitor.sh
    
    print_status "Recovery system setup completed"
}

# Configure firewall
configure_firewall() {
    print_info "Configuring firewall..."
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=9090/tcp  # Prometheus
        firewall-cmd --permanent --add-port=9093/tcp  # Alert Manager
        firewall-cmd --permanent --add-port=15692/tcp # RabbitMQ Prometheus
        firewall-cmd --reload
        print_status "Firewall configured"
    else
        print_warning "FirewallD not available, skipping firewall configuration"
    fi
}

# Setup log rotation
setup_log_rotation() {
    print_info "Setting up log rotation..."
    
    cat > /etc/logrotate.d/rabbitmq-monitor << 'EOF'
/var/log/rabbitmq/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 rabbitmq rabbitmq
    postrotate
        systemctl reload rabbitmq-server > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_status "Log rotation configured"
}

# Start services
start_services() {
    print_info "Starting monitoring and recovery services..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # Start Prometheus
    systemctl enable prometheus
    systemctl start prometheus
    
    # Start Alert Manager
    systemctl enable alertmanager
    systemctl start alertmanager
    
    # Start monitoring timer
    systemctl enable rabbitmq-monitor.timer
    systemctl start rabbitmq-monitor.timer
    
    print_status "Services started successfully"
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    # Check Prometheus
    if curl -s http://localhost:9090/api/v1/query?query=up > /dev/null 2>&1; then
        print_status "Prometheus is running and accessible"
    else
        print_error "Prometheus is not accessible"
        return 1
    fi
    
    # Check Alert Manager
    if curl -s http://localhost:9093/api/v1/alerts > /dev/null 2>&1; then
        print_status "Alert Manager is running and accessible"
    else
        print_error "Alert Manager is not accessible"
        return 1
    fi
    
    # Check monitoring script
    if /usr/local/bin/rabbitmq-monitor.sh --help > /dev/null 2>&1; then
        print_status "Monitoring script is working"
    else
        print_error "Monitoring script is not working"
        return 1
    fi
    
    # Check recovery script
    if /usr/local/bin/rabbitmq-recovery.sh --help > /dev/null 2>&1; then
        print_status "Recovery script is working"
    else
        print_error "Recovery script is not working"
        return 1
    fi
    
    # Check timer service
    if systemctl is-active --quiet rabbitmq-monitor.timer; then
        print_status "Monitoring timer service is active"
    else
        print_error "Monitoring timer service is not active"
        return 1
    fi
    
    print_status "Installation verification completed successfully"
    return 0
}

# Display next steps
display_next_steps() {
    echo ""
    echo "=== RabbitMQ Monitoring and Recovery Setup Complete ==="
    echo ""
    echo "Next Steps:"
    echo "1. Configure Grafana data source: http://$(hostname -I | awk '{print $1}'):9090"
    echo "2. Import multi-tier dashboards from configs/dashboards/"
    echo "3. Update Alert Manager configuration with your notification channels"
    echo "4. Test the monitoring system: /usr/local/bin/rabbitmq-monitor.sh"
    echo "5. Test the recovery system: /usr/local/bin/rabbitmq-recovery.sh"
    echo ""
    echo "Services Status:"
    echo "- Prometheus: $(systemctl is-active prometheus)"
    echo "- Alert Manager: $(systemctl is-active alertmanager)"
    echo "- Monitoring Timer: $(systemctl is-active rabbitmq-monitor.timer)"
    echo ""
    echo "Logs:"
    echo "- Prometheus: journalctl -u prometheus -f"
    echo "- Alert Manager: journalctl -u alertmanager -f"
    echo "- Monitoring: tail -f /var/log/rabbitmq/cluster-monitor.log"
    echo ""
    echo "Manual Monitoring:"
    echo "- Cluster Health: /usr/local/bin/rabbitmq-monitor.sh $ENVIRONMENT"
    echo "- Auto Recovery: /usr/local/bin/rabbitmq-recovery.sh $ENVIRONMENT auto"
    echo ""
}

# Main execution
main() {
    print_info "Starting RabbitMQ monitoring and recovery setup..."
    
    # Check root privileges
    check_root
    
    # Install packages
    install_packages
    
    # Setup monitoring
    setup_monitoring
    
    # Setup recovery
    setup_recovery
    
    # Configure firewall
    configure_firewall
    
    # Setup log rotation
    setup_log_rotation
    
    # Start services
    start_services
    
    # Verify installation
    if verify_installation; then
        print_status "Setup completed successfully!"
        display_next_steps
    else
        print_error "Setup completed with errors. Please check the logs."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [environment] [install_monitoring] [install_recovery]"
        echo "  environment: qa, staging, prod (default: qa)"
        echo "  install_monitoring: true, false (default: true)"
        echo "  install_recovery: true, false (default: true)"
        echo ""
        echo "Examples:"
        echo "  $0 qa                    # Setup everything for QA"
        echo "  $0 prod true false       # Setup monitoring only for production"
        echo "  $0 staging false true    # Setup recovery only for staging"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
