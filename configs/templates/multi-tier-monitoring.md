# RabbitMQ Multi-Tier Monitoring System

## 🏗️ Architecture Overview

```
RabbitMQ Cluster → Prometheus → Grafana Dashboards
     ↓              ↓              ↓
  Metrics      Data Store    Tier 1: High-Level (Executive)
  Collection                Tier 2: Detailed (Engineer)  
                            Tier 3: Very Detailed (Developer)
```

## 📊 Monitoring Tiers

### **Tier 1: High-Level Overview (Executive Dashboard)**
**Purpose**: Business stakeholders, executives, high-level status
**Update Frequency**: 1-5 minutes
**Focus**: Business impact, availability, capacity

### **Tier 2: Detailed Operations (Engineer Dashboard)**
**Purpose**: Operations team, system administrators
**Update Frequency**: 30 seconds - 2 minutes
**Focus**: Performance, resource usage, operational health

### **Tier 3: Very Detailed Deep-Dive (Developer/Support Dashboard)**
**Purpose**: Developers, support engineers, troubleshooting
**Update Frequency**: 15-30 seconds
**Focus**: Deep metrics, debugging, optimization

## 🔧 Configuration

### Enhanced Prometheus Configuration
```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "rabbitmq-cluster"
    environment: "production"

rule_files:
  - "tier1_alerts.yml"    # High-level business alerts
  - "tier2_alerts.yml"    # Operational alerts
  - "tier3_alerts.yml"    # Technical alerts

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
```

## 🚨 Multi-Tier Alerting Rules

### Tier 1: High-Level Business Alerts
```yaml
# /etc/prometheus/tier1_alerts.yml
groups:
  - name: tier1_business_alerts
    rules:
      - alert: RabbitMQServiceDown
        expr: up{job="rabbitmq-core"} == 0
        for: 2m
        labels:
          tier: "tier1"
          severity: "critical"
          business_impact: "high"
        annotations:
          summary: "RabbitMQ service is down - Business Impact"
          description: "RabbitMQ messaging service is unavailable. This affects all dependent applications and business processes."
          business_impact: "All message processing stopped. Customer-facing services may be affected."

      - alert: ClusterUnavailable
        expr: rabbitmq_cluster_members < 3
        for: 3m
        labels:
          tier: "tier1"
          severity: "critical"
          business_impact: "high"
        annotations:
          summary: "RabbitMQ cluster is degraded - Business Impact"
          description: "RabbitMQ cluster has fewer than 3 nodes. High availability is compromised."
          business_impact: "Risk of service interruption. Message processing may be delayed."

      - alert: HighQueueBacklog
        expr: sum(rabbitmq_queue_messages) > 100000
        for: 5m
        labels:
          tier: "tier1"
          severity: "warning"
          business_impact: "medium"
        annotations:
          summary: "High message backlog - Business Impact"
          description: "Total messages in queues exceed 100,000. This may indicate processing delays."
          business_impact: "Customer requests may be delayed. Consider scaling up consumers."
```

### Tier 2: Detailed Operational Alerts
```yaml
# /etc/prometheus/tier2_alerts.yml
groups:
  - name: tier2_operational_alerts
    rules:
      - alert: HighMemoryUsage
        expr: rabbitmq_process_resident_memory_bytes / rabbitmq_erlang_vm_memory_bytes_total * 100 > 75
        for: 5m
        labels:
          tier: "tier2"
          severity: "warning"
          operational_impact: "medium"
        annotations:
          summary: "High memory usage detected"
          description: "RabbitMQ memory usage is above 75% on {{ $labels.instance }}"
          operational_impact: "Performance may degrade. Consider restarting or scaling."

      - alert: LowDiskSpace
        expr: rabbitmq_disk_free_bytes / rabbitmq_disk_free_bytes_total * 100 < 25
        for: 5m
        labels:
          tier: "tier2"
          severity: "warning"
          operational_impact: "medium"
        annotations:
          summary: "Low disk space warning"
          description: "RabbitMQ disk space is below 25% on {{ $labels.instance }}"
          operational_impact: "Risk of service failure. Clean up logs or expand storage."

      - alert: HighConnectionCount
        expr: rabbitmq_connections_total > 800
        for: 5m
        labels:
          tier: "tier2"
          severity: "warning"
          operational_impact: "medium"
        annotations:
          summary: "High connection count"
          description: "More than 800 connections to RabbitMQ on {{ $labels.instance }}"
          operational_impact: "Resource exhaustion possible. Check for connection leaks."

      - alert: QueueDepthThreshold
        expr: rabbitmq_queue_messages > 5000
        for: 5m
        labels:
          tier: "tier2"
          severity: "warning"
          operational_impact: "medium"
        annotations:
          summary: "Queue depth threshold exceeded"
          description: "Queue {{ $labels.queue }} has more than 5,000 messages on {{ $labels.instance }}"
          operational_impact: "Processing delays. Check consumer health and scaling."

      - alert: HighMessageRate
        expr: rate(rabbitmq_queue_messages_published_total[5m]) > 500
        for: 5m
        labels:
          tier: "tier2"
          severity: "info"
          operational_impact: "low"
        annotations:
          summary: "High message publishing rate"
          description: "Message publishing rate is above 500 msg/sec on {{ $labels.instance }}"
          operational_impact: "Monitor performance. Consider optimization if sustained."
```

### Tier 3: Very Detailed Technical Alerts
```yaml
# /etc/prometheus/tier3_alerts.yml
groups:
  - name: tier3_technical_alerts
    rules:
      - alert: HighChannelCount
        expr: rabbitmq_channels_total > 2000
        for: 5m
        labels:
          tier: "tier3"
          severity: "warning"
          technical_impact: "medium"
        annotations:
          summary: "High channel count detected"
          description: "More than 2000 channels on {{ $labels.instance }}"
          technical_impact: "Memory overhead. Check for channel leaks in applications."

      - alert: HighExchangeCount
        expr: rabbitmq_exchanges_total > 100
        for: 5m
        labels:
          tier: "tier3"
          severity: "info"
          technical_impact: "low"
        annotations:
          summary: "High exchange count"
          description: "More than 100 exchanges on {{ $labels.instance }}"
          technical_impact: "Configuration complexity. Consider consolidation."

      - alert: HighQueueCount
        expr: rabbitmq_queues_total > 200
        for: 5m
        labels:
          tier: "tier3"
          severity: "info"
          technical_impact: "low"
        annotations:
          summary: "High queue count"
          description: "More than 200 queues on {{ $labels.instance }}"
          technical_impact: "Resource overhead. Consider queue consolidation."

      - alert: HighConsumerCount
        expr: rabbitmq_consumers_total > 500
        for: 5m
        labels:
          tier: "tier3"
          severity: "info"
          technical_impact: "low"
        annotations:
          summary: "High consumer count"
          description: "More than 500 consumers on {{ $labels.instance }}"
          technical_impact: "Connection overhead. Monitor consumer efficiency."

      - alert: HighMessageRedelivery
        expr: rate(rabbitmq_queue_messages_redelivered_total[5m]) > 10
        for: 5m
        labels:
          tier: "tier3"
          severity: "warning"
          technical_impact: "medium"
        annotations:
          summary: "High message redelivery rate"
          description: "Message redelivery rate is above 10 msg/sec on {{ $labels.instance }}"
          technical_impact: "Consumer issues. Check application error handling."

      - alert: HighMessageAckRate
        expr: rate(rabbitmq_queue_messages_ack_total[5m]) > 1000
        for: 5m
        labels:
          tier: "tier3"
          severity: "info"
          technical_impact: "low"
        annotations:
          summary: "High message acknowledgment rate"
          description: "Message acknowledgment rate is above 1000 msg/sec on {{ $labels.instance }}"
          technical_impact: "High throughput. Monitor for performance issues."

      - alert: ClusterNetworkIssues
        expr: rabbitmq_cluster_links < 2
        for: 2m
        labels:
          tier: "tier3"
          severity: "warning"
          technical_impact: "medium"
        annotations:
          summary: "Cluster network connectivity issues"
          description: "Fewer than 2 cluster links on {{ $labels.instance }}"
          technical_impact: "Cluster communication degraded. Check network connectivity."

      - alert: HighProcessCount
        expr: rabbitmq_processes_total > 10000
        for: 5m
        labels:
          tier: "tier3"
          severity: "warning"
          technical_impact: "medium"
        annotations:
          summary: "High Erlang process count"
          description: "More than 10,000 Erlang processes on {{ $labels.instance }}"
          technical_impact: "Memory overhead. Check for process leaks."
```

## 📊 Dashboard Configurations

### Tier 1: High-Level Executive Dashboard
```json
{
  "dashboard": {
    "id": null,
    "title": "RabbitMQ - Executive Overview",
    "tags": ["rabbitmq", "executive", "tier1"],
    "style": "light",
    "timezone": "browser",
    "refresh": "5m",
    "panels": [
      {
        "id": 1,
        "title": "Service Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up{job=\"rabbitmq-core\"}",
            "legendFormat": "{{instance}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 1}
              ]
            },
            "mappings": [
              {"options": {"0": {"text": "DOWN"}}, "type": "value"},
              {"options": {"1": {"text": "UP"}}, "type": "value"}
            ]
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Cluster Health",
        "type": "stat",
        "targets": [
          {
            "expr": "rabbitmq_cluster_members",
            "legendFormat": "Active Nodes"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 2},
                {"color": "green", "value": 3}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Total Messages in Queues",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(rabbitmq_queue_messages)",
            "legendFormat": "Total Messages"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 10000},
                {"color": "red", "value": 100000}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Active Connections",
        "type": "stat",
        "targets": [
          {
            "expr": "rabbitmq_connections_total",
            "legendFormat": "Connections"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 500},
                {"color": "red", "value": 1000}
              ]
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      },
      {
        "id": 5,
        "title": "Message Processing Rate",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(rabbitmq_queue_messages_published_total[5m])",
            "legendFormat": "Published/sec"
          },
          {
            "expr": "rate(rabbitmq_queue_messages_delivered_total[5m])",
            "legendFormat": "Delivered/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
      }
    ]
  }
}
```

### Tier 2: Detailed Operations Dashboard
```json
{
  "dashboard": {
    "id": null,
    "title": "RabbitMQ - Operations Dashboard",
    "tags": ["rabbitmq", "operations", "tier2"],
    "style": "dark",
    "timezone": "browser",
    "refresh": "1m",
    "panels": [
      {
        "id": 1,
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
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
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
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Queue Depths",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_queue_messages",
            "legendFormat": "{{queue}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Connection Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_connections_total",
            "legendFormat": "Total Connections"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
      },
      {
        "id": 5,
        "title": "Channel Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_channels_total",
            "legendFormat": "Total Channels"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      },
      {
        "id": 6,
        "title": "Message Rates",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(rabbitmq_queue_messages_published_total[1m])",
            "legendFormat": "Published/sec"
          },
          {
            "expr": "rate(rabbitmq_queue_messages_delivered_total[1m])",
            "legendFormat": "Delivered/sec"
          },
          {
            "expr": "rate(rabbitmq_queue_messages_ack_total[1m])",
            "legendFormat": "Acknowledged/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32}
      }
    ]
  }
}
```

### Tier 3: Very Detailed Technical Dashboard
```json
{
  "dashboard": {
    "id": null,
    "title": "RabbitMQ - Technical Deep-Dive",
    "tags": ["rabbitmq", "technical", "tier3"],
    "style": "dark",
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "id": 1,
        "title": "Erlang Process Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_processes_total",
            "legendFormat": "Total Processes"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Exchange Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_exchanges_total",
            "legendFormat": "Total Exchanges"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Queue Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_queues_total",
            "legendFormat": "Total Queues"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Consumer Count",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_consumers_total",
            "legendFormat": "Total Consumers"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      },
      {
        "id": 5,
        "title": "Message Redelivery Rate",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(rabbitmq_queue_messages_redelivered_total[1m])",
            "legendFormat": "Redelivered/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16}
      },
      {
        "id": 6,
        "title": "Message Acknowledgment Rate",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(rabbitmq_queue_messages_ack_total[1m])",
            "legendFormat": "Acknowledged/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16}
      },
      {
        "id": 7,
        "title": "Cluster Links",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_cluster_links",
            "legendFormat": "Active Links"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24}
      },
      {
        "id": 8,
        "title": "Memory Breakdown",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rabbitmq_process_resident_memory_bytes",
            "legendFormat": "Process Memory"
          },
          {
            "expr": "rabbitmq_erlang_vm_memory_bytes_total",
            "legendFormat": "Total VM Memory"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette"},
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "linear",
              "barAlignment": 0,
              "lineWidth": 2,
              "fillOpacity": 10,
              "gradientMode": "none",
              "spanNulls": false,
              "showPoints": "never",
              "pointSize": 5,
              "stacking": {"mode": "none", "group": "A"},
              "axisLabel": "",
              "scaleDistribution": {"type": "linear"},
              "hideFrom": {"legend": false, "tooltip": false, "vis": false},
              "thresholdsStyle": {"mode": "off"}
            }
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32}
      }
    ]
  }
}
```

## 🔄 Update Monitoring Setup Script

The existing `setup-monitoring.sh` script will be enhanced to include these multi-tier configurations.
