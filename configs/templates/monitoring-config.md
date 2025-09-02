# RabbitMQ Monitoring Configuration with Remote Grafana

## Overview
This guide covers setting up comprehensive monitoring for RabbitMQ clusters using Prometheus and remote Grafana.

## Architecture
```
RabbitMQ Cluster → Prometheus Exporter → Prometheus → Remote Grafana
     ↓                    ↓              ↓           ↓
  Metrics           HTTP Endpoint    Data Store   Dashboards
```

## Components
1. **RabbitMQ Prometheus Plugin** - Exports metrics from RabbitMQ
2. **Prometheus** - Collects and stores metrics
3. **Remote Grafana** - Visualizes metrics and creates dashboards
4. **Alert Manager** - Sends alerts based on thresholds

## Configuration Steps

### Step 1: Enable RabbitMQ Prometheus Plugin
The plugin is already enabled in `enabled_plugins`. Verify it's running:
```bash
rabbitmq-plugins list | grep prometheus
```

### Step 2: Configure Prometheus Plugin
Add to `rabbitmq.conf`:
```conf
# Prometheus metrics endpoint
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
prometheus.tcp.path = /metrics
```

### Step 3: Install and Configure Prometheus
```bash
# Download Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar -xzf prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus-2.45.0

# Create configuration
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rabbitmq_rules.yml"

scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s

  - job_name: 'rabbitmq-management'
    static_configs:
      - targets: ['localhost:15672']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s
EOF

# Create alerting rules
cat > rabbitmq_rules.yml << 'EOF'
groups:
  - name: rabbitmq
    rules:
      - alert: RabbitMQDown
        expr: up{job="rabbitmq"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ instance is down"
          description: "RabbitMQ instance has been down for more than 1 minute"

      - alert: HighMemoryUsage
        expr: rabbitmq_process_resident_memory_bytes / rabbitmq_erlang_vm_memory_bytes_total * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "RabbitMQ memory usage is above 80%"

      - alert: HighDiskUsage
        expr: rabbitmq_disk_free_bytes / rabbitmq_disk_free_bytes_total * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space"
          description: "RabbitMQ disk space is below 20%"

      - alert: HighQueueDepth
        expr: rabbitmq_queue_messages > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High queue depth"
          description: "Queue has more than 10,000 messages"

      - alert: HighConnectionCount
        expr: rabbitmq_connections_total > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High connection count"
          description: "More than 1000 connections to RabbitMQ"
EOF

# Start Prometheus
./prometheus --config.file=prometheus.yml --storage.tsdb.path=./data --web.listen-address=:9090
```

### Step 4: Configure Remote Grafana Connection

#### 4.1: Add Prometheus Data Source in Grafana
1. Open your remote Grafana instance
2. Go to **Configuration** → **Data Sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Configure:
   - **Name**: `RabbitMQ-Prometheus`
   - **URL**: `http://YOUR_PROMETHEUS_SERVER_IP:9090`
   - **Access**: `Server (default)`
   - **HTTP Method**: `GET`
6. Click **Save & Test**

#### 4.2: Import RabbitMQ Dashboard
1. In Grafana, go to **Dashboards** → **Import**
2. Use dashboard ID: `10991` (Official RabbitMQ Dashboard)
3. Or import the custom dashboard below

### Step 5: Create Custom RabbitMQ Dashboard

Create a file `rabbitmq-dashboard.json` and import it to Grafana:

```json
{
  "dashboard": {
    "id": null,
    "title": "RabbitMQ Cluster Monitoring",
    "tags": ["rabbitmq", "monitoring"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Cluster Status",
        "type": "stat",
        "targets": [
          {
            "expr": "rabbitmq_cluster_members",
            "legendFormat": "{{instance}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 1}
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "title": "Memory Usage",
        "type": "gauge",
        "targets": [
          {
            "expr": "rabbitmq_process_resident_memory_bytes / rabbitmq_erlang_vm_memory_bytes_total * 100",
            "legendFormat": "Memory %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "min": 0,
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 85}
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "title": "Disk Usage",
        "type": "gauge",
        "targets": [
          {
            "expr": "(1 - rabbitmq_disk_free_bytes / rabbitmq_disk_free_bytes_total) * 100",
            "legendFormat": "Disk %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "min": 0,
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 85}
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "title": "Queue Messages",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_queue_messages",
            "legendFormat": "{{queue}}"
          }
        ]
      },
      {
        "id": 5,
        "title": "Connections",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_connections_total",
            "legendFormat": "Total Connections"
          }
        ]
      }
    ]
  }
}
```

### Step 6: Set Up Alerting

#### 6.1: Configure Alert Manager
```bash
# Download Alert Manager
wget https://github.com/prometheus/alertmanager/releases/download/v0.25.0/alertmanager-0.25.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.25.0.linux-amd64.tar.gz
cd alertmanager-0.25.0

# Create configuration
cat > alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@company.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'team-rabbitmq'

receivers:
  - name: 'team-rabbitmq'
    email_configs:
      - to: 'rabbitmq-alerts@company.com'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#rabbitmq-alerts'
EOF

# Start Alert Manager
./alertmanager --config.file=alertmanager.yml --storage.path=./data
```

#### 6.2: Update Prometheus Configuration
Add to `prometheus.yml`:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - "rabbitmq_rules.yml"
```

### Step 7: Monitoring Scripts

#### 7.1: Create Monitoring Script
```bash
#!/bin/bash
# File: scripts/monitoring/setup-monitoring.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-qa}"

# Load environment
source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"

echo "Setting up RabbitMQ monitoring for $ENVIRONMENT environment..."

# Install Prometheus
install_prometheus() {
    echo "Installing Prometheus..."
    cd /opt
    wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
    tar -xzf prometheus-2.45.0.linux-amd64.tar.gz
    ln -sf prometheus-2.45.0 prometheus
    
    # Create systemd service
    cat > /etc/systemd/system/prometheus.service << EOF
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

    # Create prometheus user
    useradd --no-create-home --shell /bin/false prometheus
    mkdir -p /opt/prometheus/data
    chown prometheus:prometheus /opt/prometheus/data
    
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
}

# Install Alert Manager
install_alertmanager() {
    echo "Installing Alert Manager..."
    cd /opt
    wget https://github.com/prometheus/alertmanager/releases/download/v0.25.0/alertmanager-0.25.0.linux-amd64.tar.gz
    tar -xzf alertmanager-0.25.0.linux-amd64.tar.gz
    ln -sf alertmanager-0.25.0 alertmanager
    
    # Create systemd service
    cat > /etc/systemd/system/alertmanager.service << EOF
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
    
    systemctl daemon-reload
    systemctl enable alertmanager
    systemctl start alertmanager
}

# Configure monitoring
configure_monitoring() {
    echo "Configuring monitoring..."
    
    # Create Prometheus config
    cat > /opt/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

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

  - job_name: 'rabbitmq-management'
    static_configs:
      - targets: ['localhost:15672']
    metrics_path: /metrics
    scrape_interval: 30s
    scrape_timeout: 10s
EOF

    # Create alerting rules
    cat > /opt/prometheus/rabbitmq_rules.yml << EOF
groups:
  - name: rabbitmq
    rules:
      - alert: RabbitMQDown
        expr: up{job="rabbitmq"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ instance is down"
          description: "RabbitMQ instance has been down for more than 1 minute"

      - alert: HighMemoryUsage
        expr: rabbitmq_process_resident_memory_bytes / rabbitmq_erlang_vm_memory_bytes_total * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "RabbitMQ memory usage is above 80%"

      - alert: HighDiskUsage
        expr: rabbitmq_disk_free_bytes / rabbitmq_disk_free_bytes_total * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space"
          description: "RabbitMQ disk space is below 20%"

      - alert: HighQueueDepth
        expr: rabbitmq_queue_messages > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High queue depth"
          description: "Queue has more than 10,000 messages"

      - alert: HighConnectionCount
        expr: rabbitmq_connections_total > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High connection count"
          description: "More than 1000 connections to RabbitMQ"
EOF

    chown prometheus:prometheus /opt/prometheus/prometheus.yml
    chown prometheus:prometheus /opt/prometheus/rabbitmq_rules.yml
}

# Configure firewall
configure_firewall() {
    echo "Configuring firewall..."
    firewall-cmd --permanent --add-port=9090/tcp  # Prometheus
    firewall-cmd --permanent --add-port=9093/tcp  # Alert Manager
    firewall-cmd --reload
}

# Main execution
main() {
    install_prometheus
    install_alertmanager
    configure_monitoring
    configure_firewall
    
    echo "Monitoring setup completed!"
    echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
    echo "Alert Manager: http://$(hostname -I | awk '{print $1}'):9093"
    echo ""
    echo "Next steps:"
    echo "1. Add Prometheus data source in Grafana: http://$(hostname -I | awk '{print $1}'):9090"
    echo "2. Import RabbitMQ dashboard"
    echo "3. Configure alerting channels"
}

main "$@"
```

### Step 8: Verification and Testing

#### 8.1: Test Metrics Endpoint
```bash
# Test RabbitMQ metrics
curl http://localhost:15692/metrics

# Test Prometheus
curl http://localhost:9090/api/v1/targets

# Test Alert Manager
curl http://localhost:9093/api/v1/alerts
```

#### 8.2: Verify Grafana Connection
1. Check data source status in Grafana
2. Verify metrics are being collected
3. Test dashboard queries
4. Validate alerting rules

### Step 9: Advanced Monitoring Features

#### 9.1: Custom Metrics
```bash
# Add custom metrics to RabbitMQ
rabbitmqctl eval 'prometheus_metrics:gauge("custom_queue_depth", 100, [{queue, "my_queue"}]).'
```

#### 9.2: Log Aggregation
```bash
# Configure log forwarding to central logging system
# Example with rsyslog
echo "local0.* @@log-server.company.com:514" >> /etc/rsyslog.conf
systemctl restart rsyslog
```

### Step 10: Maintenance and Troubleshooting

#### 10.1: Regular Maintenance
```bash
# Check Prometheus storage
du -sh /opt/prometheus/data

# Rotate logs
logrotate /etc/logrotate.d/prometheus

# Update Prometheus
# Download new version and restart service
```

#### 10.2: Troubleshooting
```bash
# Check service status
systemctl status prometheus
systemctl status alertmanager

# Check logs
journalctl -u prometheus -f
journalctl -u alertmanager -f

# Test metrics collection
curl -s http://localhost:15692/metrics | grep rabbitmq
```

## Summary

This setup provides:
- ✅ Real-time RabbitMQ metrics collection
- ✅ Remote Grafana integration
- ✅ Automated alerting
- ✅ Historical data retention
- ✅ Scalable monitoring architecture
- ✅ Production-ready configuration

## Next Steps

1. **Deploy the monitoring stack** using the provided scripts
2. **Configure Grafana data sources** for your remote instance
3. **Import dashboards** and customize as needed
4. **Set up alerting channels** (email, Slack, etc.)
5. **Test the complete monitoring pipeline**
6. **Document monitoring procedures** for your team
