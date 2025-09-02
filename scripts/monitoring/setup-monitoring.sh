#!/bin/bash
# RabbitMQ Monitoring Setup Script
# This script installs and configures Prometheus and Alert Manager for RabbitMQ monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-qa}"

# Load environment
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
fi

echo "Setting up RabbitMQ monitoring for $ENVIRONMENT environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Install Prometheus
install_prometheus() {
    print_status "Installing Prometheus..."
    
    cd /opt
    if [ -d "prometheus" ]; then
        print_warning "Prometheus directory already exists, updating..."
        rm -rf prometheus
    fi
    
    # Download Prometheus
    PROMETHEUS_VERSION="2.45.0"
    PROMETHEUS_ARCHIVE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    
    if [ ! -f "$PROMETHEUS_ARCHIVE" ]; then
        print_status "Downloading Prometheus ${PROMETHEUS_VERSION}..."
        wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_ARCHIVE}"
    fi
    
    tar -xzf "$PROMETHEUS_ARCHIVE"
    ln -sf "prometheus-${PROMETHEUS_VERSION}" prometheus
    
    # Create prometheus user if it doesn't exist
    if ! id "prometheus" &>/dev/null; then
        useradd --no-create-home --shell /bin/false prometheus
    fi
    
    # Create directories
    mkdir -p /opt/prometheus/data
    mkdir -p /etc/prometheus
    mkdir -p /var/log/prometheus
    
    # Set ownership
    chown -R prometheus:prometheus /opt/prometheus
    chown prometheus:prometheus /etc/prometheus
    chown prometheus:prometheus /var/log/prometheus
    
    # Create systemd service
    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/prometheus/data \
    --web.listen-address=:9090 \
    --web.enable-lifecycle \
    --storage.tsdb.retention.time=30d \
    --log.level=info
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_status "Prometheus installed successfully"
}

# Install Alert Manager
install_alertmanager() {
    print_status "Installing Alert Manager..."
    
    cd /opt
    if [ -d "alertmanager" ]; then
        print_warning "Alert Manager directory already exists, updating..."
        rm -rf alertmanager
    fi
    
    # Download Alert Manager
    ALERTMANAGER_VERSION="0.25.0"
    ALERTMANAGER_ARCHIVE="alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    
    if [ ! -f "$ALERTMANAGER_ARCHIVE" ]; then
        print_status "Downloading Alert Manager ${ALERTMANAGER_VERSION}..."
        wget "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/${ALERTMANAGER_ARCHIVE}"
    fi
    
    tar -xzf "$ALERTMANAGER_ARCHIVE"
    ln -sf "alertmanager-${ALERTMANAGER_VERSION}" alertmanager
    
    # Create directories
    mkdir -p /opt/alertmanager/data
    mkdir -p /etc/alertmanager
    mkdir -p /var/log/alertmanager
    
    # Set ownership
    chown -R prometheus:prometheus /opt/alertmanager
    chown prometheus:prometheus /etc/alertmanager
    chown prometheus:prometheus /var/log/alertmanager
    
    # Create systemd service
    cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Alert Manager
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/alertmanager/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/opt/alertmanager/data \
    --web.listen-address=:9093 \
    --log.level=info
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    print_status "Alert Manager installed successfully"
}

# Configure monitoring
configure_monitoring() {
    print_status "Configuring monitoring..."
    
    # Create Prometheus config
    cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "rabbitmq-cluster"

rule_files:
  - "rabbitmq_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s
    honor_labels: true

  - job_name: 'rabbitmq-management'
    static_configs:
      - targets: ['localhost:15672']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s
    honor_labels: true

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s
EOF

    # Create alerting rules
    cat > /etc/prometheus/rabbitmq_rules.yml << 'EOF'
groups:
  - name: rabbitmq
    rules:
      - alert: RabbitMQDown
        expr: up{job="rabbitmq"} == 0
        for: 1m
        labels:
          severity: critical
          service: rabbitmq
        annotations:
          summary: "RabbitMQ instance is down"
          description: "RabbitMQ instance {{ $labels.instance }} has been down for more than 1 minute"

      - alert: HighMemoryUsage
        expr: rabbitmq_process_resident_memory_bytes / rabbitmq_erlang_vm_memory_bytes_total * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: rabbitmq
        annotations:
          summary: "High memory usage"
          description: "RabbitMQ memory usage is above 80% on {{ $labels.instance }}"

      - alert: HighDiskUsage
        expr: rabbitmq_disk_free_bytes / rabbitmq_disk_free_bytes_total * 100 < 20
        for: 5m
        labels:
          severity: warning
          service: rabbitmq
        annotations:
          summary: "Low disk space"
          description: "RabbitMQ disk space is below 20% on {{ $labels.instance }}"

      - alert: HighQueueDepth
        expr: rabbitmq_queue_messages > 10000
        for: 5m
        labels:
          severity: warning
          service: rabbitmq
        annotations:
          summary: "High queue depth"
          description: "Queue {{ $labels.queue }} has more than 10,000 messages on {{ $labels.instance }}"

      - alert: HighConnectionCount
        expr: rabbitmq_connections_total > 1000
        for: 5m
        labels:
          severity: warning
          service: rabbitmq
        annotations:
          summary: "High connection count"
          description: "More than 1000 connections to RabbitMQ on {{ $labels.instance }}"

      - alert: ClusterPartition
        expr: rabbitmq_cluster_members < 3
        for: 2m
        labels:
          severity: critical
          service: rabbitmq
        annotations:
          summary: "Cluster partition detected"
          description: "RabbitMQ cluster has fewer than 3 members on {{ $labels.instance }}"

      - alert: HighMessageRate
        expr: rate(rabbitmq_queue_messages_published_total[5m]) > 1000
        for: 5m
        labels:
          severity: warning
          service: rabbitmq
        annotations:
          summary: "High message publishing rate"
          description: "Message publishing rate is above 1000 msg/sec on {{ $labels.instance }}"
EOF

    # Create Alert Manager config
    cat > /etc/alertmanager/alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@company.com'
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'team-rabbitmq'
  routes:
    - match:
        severity: critical
      receiver: 'team-rabbitmq-critical'
      repeat_interval: 30m

receivers:
  - name: 'team-rabbitmq'
    email_configs:
      - to: 'rabbitmq-alerts@company.com'
        send_resolved: true
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#rabbitmq-alerts'
        send_resolved: true
        title: '{{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'

  - name: 'team-rabbitmq-critical'
    email_configs:
      - to: 'rabbitmq-critical@company.com'
        send_resolved: true
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#rabbitmq-critical'
        send_resolved: true
        title: '🚨 CRITICAL: {{ template "slack.title" . }}'
        text: '{{ template "slack.text" . }}'

templates:
  - '/etc/alertmanager/templates/*.tmpl'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF

    # Set ownership
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    chown prometheus:prometheus /etc/prometheus/rabbitmq_rules.yml
    chown prometheus:prometheus /etc/alertmanager/alertmanager.yml

    print_status "Monitoring configuration completed"
}

# Configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Check if firewall-cmd is available
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=9090/tcp  # Prometheus
        firewall-cmd --permanent --add-port=9093/tcp  # Alert Manager
        firewall-cmd --reload
        print_status "Firewall configured successfully"
    else
        print_warning "firewall-cmd not available, please configure firewall manually:"
        print_warning "  - Port 9090 (Prometheus)"
        print_warning "  - Port 9093 (Alert Manager)"
    fi
}

# Start services
start_services() {
    print_status "Starting monitoring services..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable and start Prometheus
    systemctl enable prometheus
    systemctl start prometheus
    
    # Enable and start Alert Manager
    systemctl enable alertmanager
    systemctl start alertmanager
    
    # Wait for services to start
    sleep 5
    
    # Check service status
    if systemctl is-active --quiet prometheus; then
        print_status "Prometheus started successfully"
    else
        print_error "Failed to start Prometheus"
        systemctl status prometheus
    fi
    
    if systemctl is-active --quiet alertmanager; then
        print_status "Alert Manager started successfully"
    else
        print_error "Failed to start Alert Manager"
        systemctl status alertmanager
    fi
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    # Test Prometheus
    if curl -s http://localhost:9090/api/v1/targets > /dev/null; then
        print_status "Prometheus is responding"
    else
        print_error "Prometheus is not responding"
    fi
    
    # Test Alert Manager
    if curl -s http://localhost:9093/api/v1/alerts > /dev/null; then
        print_status "Alert Manager is responding"
    else
        print_error "Alert Manager is not responding"
    fi
    
    # Test RabbitMQ metrics (if RabbitMQ is running)
    if command -v rabbitmqctl &> /dev/null; then
        if curl -s http://localhost:15692/metrics > /dev/null; then
            print_status "RabbitMQ metrics endpoint is accessible"
        else
            print_warning "RabbitMQ metrics endpoint is not accessible (RabbitMQ may not be running)"
        fi
    fi
}

# Create log rotation
setup_log_rotation() {
    print_status "Setting up log rotation..."
    
    cat > /etc/logrotate.d/prometheus << 'EOF'
/var/log/prometheus/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 prometheus prometheus
    postrotate
        systemctl reload prometheus
    endscript
}
EOF

    cat > /etc/logrotate.d/alertmanager << 'EOF'
/var/log/alertmanager/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 prometheus prometheus
    postrotate
        systemctl reload alertmanager
    endscript
}
EOF

    print_status "Log rotation configured"
}

# Main execution
main() {
    print_status "Starting RabbitMQ monitoring setup..."
    
    # Check if running as root
    check_root
    
    # Install components
    install_prometheus
    install_alertmanager
    
    # Configure
    configure_monitoring
    configure_firewall
    setup_log_rotation
    
    # Start services
    start_services
    
    # Verify
    verify_installation
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    print_status "Monitoring setup completed successfully!"
    echo ""
    echo "Services:"
    echo "  - Prometheus: http://${SERVER_IP}:9090"
    echo "  - Alert Manager: http://${SERVER_IP}:9093"
    echo ""
    echo "Next steps:"
    echo "1. Add Prometheus data source in Grafana: http://${SERVER_IP}:9090"
    echo "2. Import RabbitMQ dashboard (ID: 10991)"
    echo "3. Update alerting configuration in /etc/alertmanager/alertmanager.yml"
    echo "4. Configure your email/Slack webhook URLs"
    echo "5. Test the monitoring pipeline"
    echo ""
    echo "Configuration files:"
    echo "  - Prometheus: /etc/prometheus/prometheus.yml"
    echo "  - Alert Manager: /etc/alertmanager/alertmanager.yml"
    echo "  - Alert Rules: /etc/prometheus/rabbitmq_rules.yml"
    echo ""
    echo "Logs:"
    echo "  - Prometheus: journalctl -u prometheus -f"
    echo "  - Alert Manager: journalctl -u alertmanager -f"
}

# Run main function
main "$@"
