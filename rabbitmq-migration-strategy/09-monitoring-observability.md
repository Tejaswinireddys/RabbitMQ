# 09. Monitoring and Observability

## Overview

This document outlines the monitoring strategy for the RabbitMQ migration, including metrics to track, alerting rules, and dashboard configurations.

---

## 1. Monitoring Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONITORING STACK                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     │
│  │  RabbitMQ    │────►│  Prometheus  │────►│   Grafana    │     │
│  │  (15692)     │     │              │     │              │     │
│  └──────────────┘     └──────────────┘     └──────────────┘     │
│         │                    │                    │              │
│         │                    ▼                    │              │
│         │             ┌──────────────┐            │              │
│         │             │ Alertmanager │            │              │
│         │             └──────────────┘            │              │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     │
│  │   Logs       │     │ PagerDuty/   │     │    Slack     │     │
│  │  (ELK/Loki)  │     │   OpsGenie   │     │              │     │
│  └──────────────┘     └──────────────┘     └──────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Key Metrics for Migration

### 2.1 Cluster Health Metrics

| Metric | PromQL | Alert Threshold | Description |
|--------|--------|-----------------|-------------|
| Node availability | `rabbitmq_identity_info` | < 3 nodes | Cluster node count |
| Node memory | `rabbitmq_process_resident_memory_bytes` | > 80% | Memory per node |
| Disk free | `rabbitmq_disk_space_available_bytes` | < 20% | Available disk |
| File descriptors | `rabbitmq_process_open_fds` | > 90% of limit | Open FDs |
| Erlang processes | `rabbitmq_erlang_processes_used` | > 90% of limit | VM processes |

### 2.2 Quorum Queue Specific Metrics

| Metric | PromQL | Alert Threshold | Description |
|--------|--------|-----------------|-------------|
| Raft term | `rabbitmq_raft_term_total` | Rapid increase | Leader elections |
| Log entries | `rabbitmq_raft_log_last_written_index` | Growing unbounded | Uncommitted entries |
| Commit index | `rabbitmq_raft_log_commit_index` | Lag > 1000 | Raft commit lag |
| Snapshot index | `rabbitmq_raft_log_snapshot_index` | | Last snapshot |
| Entry commit latency | `rabbitmq_raft_entry_commit_latency_seconds` | > 1s | Replication latency |

### 2.3 Message Flow Metrics

| Metric | PromQL | Alert Threshold | Description |
|--------|--------|-----------------|-------------|
| Publish rate | `rate(rabbitmq_channel_messages_published_total[5m])` | Baseline deviation | Messages published/s |
| Consume rate | `rate(rabbitmq_channel_messages_delivered_total[5m])` | Baseline deviation | Messages consumed/s |
| Queue depth | `rabbitmq_queue_messages` | App-specific | Messages in queue |
| Unacked messages | `rabbitmq_queue_messages_unacked` | > expected | Unacknowledged |
| Consumer count | `rabbitmq_queue_consumers` | < expected | Active consumers |

### 2.4 Connection Metrics

| Metric | PromQL | Alert Threshold | Description |
|--------|--------|-----------------|-------------|
| Connection count | `rabbitmq_connections` | Baseline deviation | Total connections |
| Channel count | `rabbitmq_channels` | > expected | Total channels |
| Connection churn | `rate(rabbitmq_connections_opened_total[5m])` | High rate | New connections/s |

---

## 3. Prometheus Configuration

### 3.1 Scrape Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Blue cluster (3.12) - during migration
  - job_name: 'rabbitmq-blue'
    static_configs:
      - targets:
        - 'rabbit-blue-1:15692'
        - 'rabbit-blue-2:15692'
        - 'rabbit-blue-3:15692'
    relabel_configs:
      - source_labels: [__address__]
        target_label: cluster
        replacement: 'blue'

  # Green cluster (4.1.4) - during migration
  - job_name: 'rabbitmq-green'
    static_configs:
      - targets:
        - 'rabbit-green-1:15692'
        - 'rabbit-green-2:15692'
        - 'rabbit-green-3:15692'
    relabel_configs:
      - source_labels: [__address__]
        target_label: cluster
        replacement: 'green'

rule_files:
  - 'rabbitmq-alerts.yml'
```

### 3.2 Recording Rules

```yaml
# rabbitmq-recording-rules.yml
groups:
  - name: rabbitmq-recording-rules
    rules:
      # Message rates
      - record: rabbitmq:messages_published:rate5m
        expr: sum(rate(rabbitmq_channel_messages_published_total[5m])) by (cluster)

      - record: rabbitmq:messages_delivered:rate5m
        expr: sum(rate(rabbitmq_channel_messages_delivered_total[5m])) by (cluster)

      # Queue depth
      - record: rabbitmq:queue_messages:total
        expr: sum(rabbitmq_queue_messages) by (cluster)

      # Quorum queue health
      - record: rabbitmq:quorum_queues:leader_per_node
        expr: count(rabbitmq_queue_info{type="quorum"}) by (node, cluster)

      # Raft lag
      - record: rabbitmq:raft:commit_lag
        expr: rabbitmq_raft_log_last_written_index - rabbitmq_raft_log_commit_index
```

---

## 4. Alerting Rules

### 4.1 Critical Alerts

```yaml
# rabbitmq-alerts.yml
groups:
  - name: rabbitmq-critical
    rules:
      # Cluster availability
      - alert: RabbitMQClusterDown
        expr: count(rabbitmq_identity_info) by (cluster) < 2
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ cluster {{ $labels.cluster }} has insufficient nodes"
          description: "Only {{ $value }} nodes available. Quorum lost."

      # Node down
      - alert: RabbitMQNodeDown
        expr: up{job=~"rabbitmq.*"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ node {{ $labels.instance }} is down"

      # Disk space critical
      - alert: RabbitMQDiskSpaceCritical
        expr: rabbitmq_disk_space_available_bytes < 1073741824
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ disk space critical on {{ $labels.instance }}"
          description: "Less than 1GB available"

      # Memory alarm
      - alert: RabbitMQMemoryAlarm
        expr: rabbitmq_alarms_memory_used_watermark == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "RabbitMQ memory alarm on {{ $labels.instance }}"

  - name: rabbitmq-quorum-alerts
    rules:
      # Quorum queue unavailable
      - alert: RabbitMQQuorumQueueUnavailable
        expr: rabbitmq_queue_info{type="quorum"} unless on(queue) rabbitmq_queue_messages
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Quorum queue {{ $labels.queue }} is unavailable"

      # High Raft term (excessive leader elections)
      - alert: RabbitMQExcessiveLeaderElections
        expr: increase(rabbitmq_raft_term_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Excessive Raft leader elections on {{ $labels.queue }}"
          description: "{{ $value }} elections in last 5 minutes"

      # Raft commit lag
      - alert: RabbitMQRaftCommitLag
        expr: (rabbitmq_raft_log_last_written_index - rabbitmq_raft_log_commit_index) > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Raft commit lag on {{ $labels.queue }}"
          description: "Lag of {{ $value }} entries"

  - name: rabbitmq-migration-alerts
    rules:
      # Shovel not running
      - alert: RabbitMQShovelNotRunning
        expr: rabbitmq_shovel_state{state!="running"} == 1
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Shovel {{ $labels.shovel }} is not running"

      # Message backlog growing
      - alert: RabbitMQMessageBacklogGrowing
        expr: delta(rabbitmq_queue_messages[10m]) > 10000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Message backlog growing on {{ $labels.queue }}"

      # Consumer count dropped
      - alert: RabbitMQConsumersDrop
        expr: delta(rabbitmq_queue_consumers[5m]) < -5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Consumer count dropped on {{ $labels.queue }}"
```

---

## 5. Grafana Dashboards

### 5.1 Migration Dashboard

```json
{
  "title": "RabbitMQ Migration Dashboard",
  "panels": [
    {
      "title": "Cluster Comparison",
      "type": "stat",
      "targets": [
        {
          "expr": "count(rabbitmq_identity_info) by (cluster)",
          "legendFormat": "{{cluster}} nodes"
        }
      ]
    },
    {
      "title": "Message Rate Comparison",
      "type": "graph",
      "targets": [
        {
          "expr": "rabbitmq:messages_published:rate5m",
          "legendFormat": "{{cluster}} publish"
        },
        {
          "expr": "rabbitmq:messages_delivered:rate5m",
          "legendFormat": "{{cluster}} consume"
        }
      ]
    },
    {
      "title": "Queue Depth by Cluster",
      "type": "graph",
      "targets": [
        {
          "expr": "rabbitmq:queue_messages:total",
          "legendFormat": "{{cluster}}"
        }
      ]
    },
    {
      "title": "Shovel Status",
      "type": "table",
      "targets": [
        {
          "expr": "rabbitmq_shovel_state",
          "format": "table"
        }
      ]
    },
    {
      "title": "Connection Distribution",
      "type": "piechart",
      "targets": [
        {
          "expr": "sum(rabbitmq_connections) by (cluster)",
          "legendFormat": "{{cluster}}"
        }
      ]
    }
  ]
}
```

### 5.2 Quorum Queue Dashboard

```json
{
  "title": "Quorum Queue Health",
  "panels": [
    {
      "title": "Quorum Queue Count",
      "type": "stat",
      "targets": [
        {
          "expr": "count(rabbitmq_queue_info{type=\"quorum\"})"
        }
      ]
    },
    {
      "title": "Raft Term Changes",
      "type": "graph",
      "targets": [
        {
          "expr": "increase(rabbitmq_raft_term_total[5m])",
          "legendFormat": "{{queue}}"
        }
      ]
    },
    {
      "title": "Commit Latency",
      "type": "heatmap",
      "targets": [
        {
          "expr": "rate(rabbitmq_raft_entry_commit_latency_seconds_bucket[5m])"
        }
      ]
    },
    {
      "title": "Leader Distribution",
      "type": "table",
      "targets": [
        {
          "expr": "count by (node) (rabbitmq_queue_info{type=\"quorum\"} == 1)",
          "format": "table"
        }
      ]
    },
    {
      "title": "Raft Log Size",
      "type": "graph",
      "targets": [
        {
          "expr": "rabbitmq_raft_log_last_written_index",
          "legendFormat": "{{queue}}"
        }
      ]
    }
  ]
}
```

---

## 6. Log Monitoring

### 6.1 Log Collection Configuration

```yaml
# filebeat.yml for RabbitMQ logs
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/rabbitmq/*.log
    fields:
      service: rabbitmq
      cluster: green
    multiline:
      pattern: '^\d{4}-\d{2}-\d{2}'
      negate: true
      match: after

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "rabbitmq-logs-%{+yyyy.MM.dd}"

# Or for Loki
# output.loki:
#   url: "http://loki:3100/loki/api/v1/push"
```

### 6.2 Key Log Patterns to Monitor

```bash
# Critical patterns
"alarm"                    # Memory/disk alarms
"error"                    # General errors
"crash"                    # Process crashes
"partition"                # Network partitions
"timeout"                  # Timeout errors

# Migration-specific patterns
"shovel"                   # Shovel status
"federation"               # Federation status
"joining"                  # Node joining cluster
"leaving"                  # Node leaving cluster
"leader"                   # Leader election events

# Quorum queue patterns
"ra_log"                   # Raft log events
"snapshot"                 # Snapshot events
"election"                 # Election events
```

### 6.3 Log Alert Examples

```yaml
# Elasticsearch Watcher example
{
  "trigger": {
    "schedule": {"interval": "1m"}
  },
  "input": {
    "search": {
      "request": {
        "indices": ["rabbitmq-logs-*"],
        "body": {
          "query": {
            "bool": {
              "must": [
                {"match": {"message": "error"}},
                {"range": {"@timestamp": {"gte": "now-1m"}}}
              ]
            }
          }
        }
      }
    }
  },
  "condition": {
    "compare": {"ctx.payload.hits.total.value": {"gt": 10}}
  },
  "actions": {
    "notify": {
      "webhook": {
        "url": "https://hooks.slack.com/...",
        "body": "High error rate in RabbitMQ logs"
      }
    }
  }
}
```

---

## 7. Migration-Specific Monitoring

### 7.1 Pre-Migration Baseline

```bash
#!/bin/bash
# capture-baseline.sh

echo "=== Capturing Pre-Migration Baseline ==="
DATE=$(date +%Y%m%d_%H%M%S)
BASELINE_DIR="/metrics/baseline_$DATE"
mkdir -p $BASELINE_DIR

# Capture current metrics via Prometheus API
curl -s "http://prometheus:9090/api/v1/query?query=rabbitmq_connections" \
    > $BASELINE_DIR/connections.json

curl -s "http://prometheus:9090/api/v1/query?query=rate(rabbitmq_channel_messages_published_total[5m])" \
    > $BASELINE_DIR/publish_rate.json

curl -s "http://prometheus:9090/api/v1/query?query=rabbitmq_queue_messages" \
    > $BASELINE_DIR/queue_depths.json

# Save cluster state
rabbitmqctl cluster_status > $BASELINE_DIR/cluster_status.txt
rabbitmqctl list_queues name messages consumers > $BASELINE_DIR/queue_state.txt

echo "Baseline captured: $BASELINE_DIR"
```

### 7.2 Migration Progress Dashboard

```markdown
## Real-time Migration Status

### Traffic Distribution
| Metric | Blue Cluster | Green Cluster | Target |
|--------|-------------|---------------|--------|
| Connections | X | Y | 100% Green |
| Publish Rate | X msg/s | Y msg/s | 100% Green |
| Queue Depth | X | Y | Minimize Blue |

### Shovel Status
| Shovel | State | Messages/s | Lag |
|--------|-------|------------|-----|
| migrate-orders | running | 500 | 0 |
| migrate-events | running | 1000 | 100 |

### Queue Migration Progress
| Queue | Blue Messages | Green Messages | Status |
|-------|--------------|----------------|--------|
| orders | 0 | 1500 | ✓ Complete |
| events | 500 | 5000 | In Progress |
```

### 7.3 Post-Migration Comparison

```bash
#!/bin/bash
# compare-metrics.sh

echo "=== Post-Migration Metrics Comparison ==="

# Compare with baseline
BASELINE_CONNECTIONS=$(cat /metrics/baseline/connections.json | jq '.data.result[0].value[1]')
CURRENT_CONNECTIONS=$(curl -s "http://prometheus:9090/api/v1/query?query=rabbitmq_connections" \
    | jq '.data.result[0].value[1]')

echo "Connections: Baseline=$BASELINE_CONNECTIONS, Current=$CURRENT_CONNECTIONS"

# Compare publish rates
BASELINE_RATE=$(cat /metrics/baseline/publish_rate.json | jq '.data.result[0].value[1]')
CURRENT_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=rate(rabbitmq_channel_messages_published_total[5m])" \
    | jq '.data.result[0].value[1]')

echo "Publish Rate: Baseline=$BASELINE_RATE, Current=$CURRENT_RATE"

# Calculate percentage difference
RATE_DIFF=$(echo "scale=2; (($CURRENT_RATE - $BASELINE_RATE) / $BASELINE_RATE) * 100" | bc)
echo "Rate Difference: ${RATE_DIFF}%"
```

---

## 8. Runbook Integration

### 8.1 Auto-Remediation

```yaml
# alertmanager.yml
route:
  receiver: 'default'
  routes:
    - match:
        alertname: RabbitMQNodeDown
      receiver: 'pagerduty-critical'
      continue: true

    - match:
        alertname: RabbitMQMessageBacklogGrowing
      receiver: 'slack-warning'

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'xxx'
        severity: critical

  - name: 'slack-warning'
    slack_configs:
      - api_url: 'https://hooks.slack.com/xxx'
        channel: '#rabbitmq-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ .Annotations.description }}'
```

---

**Next Step**: [10-risk-assessment.md](./10-risk-assessment.md)
