# RabbitMQ Cluster Monitoring and Alerting System

## Overview
This comprehensive monitoring system provides real-time visibility into cluster health, automated alerting for failures, and proactive notifications to prevent downtime.

## Monitoring Architecture

### Components
1. **Health Monitoring Service** - Continuous cluster health checks
2. **Alert Manager** - Intelligent alerting with escalation
3. **Metrics Collector** - Performance and resource monitoring
4. **Dashboard Interface** - Real-time visual monitoring
5. **Log Analyzer** - Pattern detection and anomaly alerting

## Core Monitoring Service

### Main Monitoring Daemon
```bash
#!/bin/bash
# File: rabbitmq-monitor-daemon.sh

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="/var/run/rabbitmq-monitor.pid"
LOG_FILE="/var/log/rabbitmq-monitor.log"
CONFIG_FILE="/etc/rabbitmq-monitor.conf"
INTERVAL=30  # Check every 30 seconds

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Default values if not in config
EMAIL_ALERTS=${EMAIL_ALERTS:-"admin@company.com"}
SLACK_WEBHOOK=${SLACK_WEBHOOK:-""}
PROMETHEUS_PUSHGATEWAY=${PROMETHEUS_PUSHGATEWAY:-""}
ALERT_COOLDOWN=${ALERT_COOLDOWN:-300}  # 5 minutes between same alerts

# State tracking
declare -A LAST_ALERT_TIME
declare -A ALERT_COUNTS

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Send email alert
send_email_alert() {
    local subject="$1"
    local message="$2"
    local priority="$3"
    
    if [ -n "$EMAIL_ALERTS" ]; then
        echo "$message" | mail -s "[$priority] RabbitMQ Alert: $subject" "$EMAIL_ALERTS"
        log "Email alert sent: $subject"
    fi
}

# Send Slack notification
send_slack_alert() {
    local message="$1"
    local priority="$2"
    local color="danger"
    
    if [ "$priority" = "WARNING" ]; then
        color="warning"
    elif [ "$priority" = "INFO" ]; then
        color="good"
    fi
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1
        log "Slack alert sent: $message"
    fi
}

# Check if alert should be sent (cooldown logic)
should_send_alert() {
    local alert_key="$1"
    local current_time=$(date +%s)
    local last_time=${LAST_ALERT_TIME[$alert_key]:-0}
    
    if [ $((current_time - last_time)) -gt $ALERT_COOLDOWN ]; then
        LAST_ALERT_TIME[$alert_key]=$current_time
        return 0
    fi
    return 1
}

# Send alert with cooldown protection
send_alert() {
    local alert_key="$1"
    local subject="$2"
    local message="$3"
    local priority="$4"
    
    if should_send_alert "$alert_key"; then
        send_email_alert "$subject" "$message" "$priority"
        send_slack_alert "$message" "$priority"
        ALERT_COUNTS[$alert_key]=$((${ALERT_COUNTS[$alert_key]:-0} + 1))
    fi
}

# Check cluster health
check_cluster_health() {
    local health_status="OK"
    local issues=()
    
    log "Starting cluster health check..."
    
    # Test 1: Basic cluster status
    if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        health_status="CRITICAL"
        issues+=("Cluster status command failed - possible majority partition")
        send_alert "cluster_status_failed" "Cluster Status Failed" \
            "RabbitMQ cluster status command failed. This typically indicates:\n- Majority partition (most nodes down)\n- Node is paused due to pause_minority\n- Service is stopped\n\nImmediate investigation required." \
            "CRITICAL"
    fi
    
    # Test 2: Node count verification
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        local total_nodes=$(sudo rabbitmqctl cluster_status | grep "Disc" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        
        if [ $running_nodes -lt $total_nodes ]; then
            if [ $running_nodes -lt 2 ]; then
                health_status="CRITICAL"
                issues+=("Only $running_nodes out of $total_nodes nodes running - cluster at risk")
                send_alert "low_node_count" "Low Node Count" \
                    "RabbitMQ cluster has only $running_nodes out of $total_nodes nodes running.\nCluster is at risk of total failure." \
                    "CRITICAL"
            else
                health_status="WARNING"
                issues+=("$running_nodes out of $total_nodes nodes running")
                send_alert "node_down" "Node Down" \
                    "RabbitMQ cluster has $running_nodes out of $total_nodes nodes running.\nSome nodes are down but cluster is still operational." \
                    "WARNING"
            fi
        fi
    fi
    
    # Test 3: Resource alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
    if [ "$alarms" != "[]" ]; then
        health_status="WARNING"
        issues+=("Resource alarms detected: $alarms")
        send_alert "resource_alarms" "Resource Alarms" \
            "RabbitMQ resource alarms detected:\n$alarms\n\nCheck memory and disk usage immediately." \
            "WARNING"
    fi
    
    # Test 4: Network partitions
    local partitions=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "[]")
    if [ "$partitions" != "[]" ]; then
        health_status="CRITICAL"
        issues+=("Network partitions detected: $partitions")
        send_alert "network_partition" "Network Partition" \
            "RabbitMQ network partitions detected:\n$partitions\n\nThis indicates network connectivity issues between cluster nodes." \
            "CRITICAL"
    fi
    
    # Test 5: Queue health (high message counts)
    if sudo rabbitmqctl list_queues messages >/dev/null 2>&1; then
        local max_messages=$(sudo rabbitmqctl list_queues messages | tail -n +2 | sort -nr | head -1)
        if [ "$max_messages" -gt 50000 ]; then
            health_status="WARNING"
            issues+=("High queue depth detected: $max_messages messages")
            send_alert "high_queue_depth" "High Queue Depth" \
                "RabbitMQ queue has high message count: $max_messages messages.\nThis may indicate slow consumers or processing issues." \
                "WARNING"
        fi
    fi
    
    # Test 6: Memory usage
    if sudo rabbitmqctl status >/dev/null 2>&1; then
        local memory_usage=$(sudo rabbitmqctl status | grep -A 1 "Memory" | tail -1 | awk '{print $2}' | tr -d ',' || echo "0")
        # Convert to percentage if needed (this is simplified)
        if [ "$memory_usage" -gt 1000000000 ]; then  # 1GB as example threshold
            health_status="WARNING"
            issues+=("High memory usage: $memory_usage bytes")
            send_alert "high_memory" "High Memory Usage" \
                "RabbitMQ memory usage is high: $memory_usage bytes.\nConsider reviewing vm_memory_high_watermark setting." \
                "WARNING"
        fi
    fi
    
    # Log health status
    if [ "$health_status" = "OK" ]; then
        log "Cluster health check: OK"
    else
        log "Cluster health check: $health_status - Issues: ${issues[*]}"
    fi
    
    return 0
}

# Check individual node health
check_node_health() {
    local node="$1"
    
    if [ "$node" = "$(hostname)" ]; then
        # Local node
        if sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
            log "Node health check ($node): OK"
        else
            log "Node health check ($node): FAILED"
            send_alert "node_health_$node" "Node Health Failed" \
                "RabbitMQ node $node failed health check.\nNode may be experiencing issues." \
                "WARNING"
        fi
    else
        # Remote node
        if ssh -o ConnectTimeout=5 "root@$node" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
            log "Node health check ($node): OK"
        else
            log "Node health check ($node): FAILED or unreachable"
            send_alert "node_health_$node" "Node Health Failed" \
                "RabbitMQ node $node failed health check or is unreachable.\nCheck node status and network connectivity." \
                "WARNING"
        fi
    fi
}

# Check all configured nodes
check_all_nodes() {
    local cluster_nodes=$(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort -u)
    
    for node in $cluster_nodes; do
        check_node_health "$node"
    done
}

# Performance monitoring
check_performance_metrics() {
    log "Collecting performance metrics..."
    
    # Connection count
    local connections=$(sudo rabbitmqctl list_connections | wc -l)
    log "Active connections: $connections"
    
    # Channel count
    local channels=$(sudo rabbitmqctl list_channels | wc -l)
    log "Active channels: $channels"
    
    # Queue count
    local queues=$(sudo rabbitmqctl list_queues | wc -l)
    log "Total queues: $queues"
    
    # Send to Prometheus if configured
    if [ -n "$PROMETHEUS_PUSHGATEWAY" ]; then
        cat << EOF | curl --data-binary @- "$PROMETHEUS_PUSHGATEWAY/metrics/job/rabbitmq_monitor/instance/$(hostname)"
rabbitmq_connections $connections
rabbitmq_channels $channels
rabbitmq_queues $queues
EOF
    fi
}

# Main monitoring loop
main_monitor_loop() {
    log "Starting RabbitMQ monitoring daemon (PID: $$)"
    
    while true; do
        check_cluster_health
        check_all_nodes
        check_performance_metrics
        
        log "Monitoring cycle completed, sleeping for $INTERVAL seconds"
        sleep $INTERVAL
    done
}

# Signal handlers
cleanup() {
    log "Monitoring daemon shutting down"
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Daemon management
case "${1:-start}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Monitoring daemon already running (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        
        echo "Starting RabbitMQ monitoring daemon..."
        echo $$ > "$PID_FILE"
        main_monitor_loop
        ;;
    
    stop)
        if [ -f "$PID_FILE" ]; then
            local pid=$(cat "$PID_FILE")
            echo "Stopping monitoring daemon (PID: $pid)"
            kill "$pid"
            rm -f "$PID_FILE"
        else
            echo "Monitoring daemon not running"
        fi
        ;;
    
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Monitoring daemon is running (PID: $(cat "$PID_FILE"))"
        else
            echo "Monitoring daemon is not running"
        fi
        ;;
    
    test)
        echo "Running single monitoring check..."
        check_cluster_health
        check_all_nodes
        check_performance_metrics
        ;;
    
    *)
        echo "Usage: $0 {start|stop|restart|status|test}"
        exit 1
        ;;
esac
```

### Configuration File
```bash
#!/bin/bash
# File: create-monitor-config.sh

cat > /etc/rabbitmq-monitor.conf << 'EOF'
# RabbitMQ Monitoring Configuration

# Email alerting configuration
EMAIL_ALERTS="admin@company.com,ops-team@company.com"

# Slack webhook URL for notifications
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Prometheus push gateway for metrics
PROMETHEUS_PUSHGATEWAY="http://prometheus-pushgateway:9091"

# Monitoring intervals (seconds)
INTERVAL=30
ALERT_COOLDOWN=300

# Thresholds
MAX_QUEUE_DEPTH=50000
MEMORY_WARNING_THRESHOLD=1073741824  # 1GB in bytes
CONNECTION_WARNING_THRESHOLD=1000

# Node-specific settings
CLUSTER_NODES="node1 node2 node3"

# Log retention
LOG_RETENTION_DAYS=30
EOF

echo "Configuration file created: /etc/rabbitmq-monitor.conf"
echo "Please edit the file to configure your specific settings"
```

## Advanced Alert Management

### Intelligent Alert Manager
```bash
#!/bin/bash
# File: alert-manager.sh

set -e

# Configuration
ALERT_STATE_FILE="/var/lib/rabbitmq-monitor/alert-states.json"
ESCALATION_CONFIG="/etc/rabbitmq-monitor/escalation.conf"

# Create state directory
mkdir -p "$(dirname "$ALERT_STATE_FILE")"

# Initialize alert state if doesn't exist
if [ ! -f "$ALERT_STATE_FILE" ]; then
    echo '{}' > "$ALERT_STATE_FILE"
fi

# Function to update alert state
update_alert_state() {
    local alert_key="$1"
    local state="$2"
    local timestamp=$(date +%s)
    
    # Create temporary file with updated state
    jq --arg key "$alert_key" --arg state "$state" --arg timestamp "$timestamp" \
        '.[$key] = {state: $state, timestamp: ($timestamp | tonumber), count: ((.[$key].count // 0) + 1)}' \
        "$ALERT_STATE_FILE" > "${ALERT_STATE_FILE}.tmp"
    
    mv "${ALERT_STATE_FILE}.tmp" "$ALERT_STATE_FILE"
}

# Function to get alert state
get_alert_state() {
    local alert_key="$1"
    jq -r --arg key "$alert_key" '.[$key].state // "NONE"' "$ALERT_STATE_FILE"
}

# Function to check escalation criteria
should_escalate() {
    local alert_key="$1"
    local current_time=$(date +%s)
    
    local alert_count=$(jq -r --arg key "$alert_key" '.[$key].count // 0' "$ALERT_STATE_FILE")
    local first_occurrence=$(jq -r --arg key "$alert_key" '.[$key].timestamp // 0' "$ALERT_STATE_FILE")
    
    # Escalate if alert has occurred 3+ times in 15 minutes
    if [ "$alert_count" -ge 3 ] && [ $((current_time - first_occurrence)) -lt 900 ]; then
        return 0
    fi
    
    return 1
}

# Escalation notification
send_escalation() {
    local alert_key="$1"
    local message="$2"
    
    # Send to on-call engineer
    if [ -f "$ESCALATION_CONFIG" ]; then
        source "$ESCALATION_CONFIG"
        
        # SMS notification (example using AWS SNS)
        if [ -n "$ONCALL_PHONE" ]; then
            aws sns publish --phone-number "$ONCALL_PHONE" \
                --message "ESCALATED RabbitMQ Alert: $message" >/dev/null 2>&1
        fi
        
        # PagerDuty integration
        if [ -n "$PAGERDUTY_API_KEY" ]; then
            curl -X POST "https://events.pagerduty.com/v2/enqueue" \
                -H "Content-Type: application/json" \
                -d "{
                    \"routing_key\": \"$PAGERDUTY_API_KEY\",
                    \"event_action\": \"trigger\",
                    \"dedup_key\": \"$alert_key\",
                    \"payload\": {
                        \"summary\": \"RabbitMQ Alert: $alert_key\",
                        \"source\": \"$(hostname)\",
                        \"severity\": \"critical\",
                        \"custom_details\": {\"message\": \"$message\"}
                    }
                }" >/dev/null 2>&1
        fi
    fi
}

# Smart alert processing
process_alert() {
    local alert_key="$1"
    local message="$2"
    local priority="$3"
    
    local current_state=$(get_alert_state "$alert_key")
    
    case "$priority" in
        "CRITICAL")
            if [ "$current_state" != "CRITICAL" ]; then
                # New critical alert
                update_alert_state "$alert_key" "CRITICAL"
                echo "CRITICAL alert: $message"
                
                # Immediate notification
                send_email_alert "$alert_key" "$message" "CRITICAL"
                send_slack_alert "$message" "CRITICAL"
                
                # Check for escalation
                if should_escalate "$alert_key"; then
                    send_escalation "$alert_key" "$message"
                fi
            fi
            ;;
        
        "WARNING")
            if [ "$current_state" != "WARNING" ] && [ "$current_state" != "CRITICAL" ]; then
                update_alert_state "$alert_key" "WARNING"
                echo "WARNING alert: $message"
                send_email_alert "$alert_key" "$message" "WARNING"
                send_slack_alert "$message" "WARNING"
            fi
            ;;
        
        "RESOLVED")
            if [ "$current_state" != "NONE" ]; then
                update_alert_state "$alert_key" "NONE"
                echo "RESOLVED alert: $alert_key"
                send_email_alert "$alert_key" "Alert resolved: $message" "INFO"
                send_slack_alert "✅ Resolved: $message" "INFO"
            fi
            ;;
    esac
}

# Command line interface
case "${1:-help}" in
    alert)
        process_alert "$2" "$3" "$4"
        ;;
    
    status)
        echo "Current alert states:"
        jq -r 'to_entries[] | "\(.key): \(.value.state) (count: \(.value.count))"' "$ALERT_STATE_FILE"
        ;;
    
    clear)
        echo '{}' > "$ALERT_STATE_FILE"
        echo "Alert states cleared"
        ;;
    
    help|*)
        echo "Usage: $0 {alert|status|clear}"
        echo "  alert <key> <message> <priority>  - Process an alert"
        echo "  status                             - Show current alert states"
        echo "  clear                              - Clear all alert states"
        ;;
esac
```

## Real-time Dashboard

### Web Dashboard Generator
```bash
#!/bin/bash
# File: generate-dashboard.sh

set -e

DASHBOARD_DIR="/var/www/rabbitmq-monitor"
DASHBOARD_PORT="8080"

echo "=== Generating RabbitMQ Monitoring Dashboard ==="

# Create dashboard directory
sudo mkdir -p "$DASHBOARD_DIR"

# Generate HTML dashboard
cat > "$DASHBOARD_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RabbitMQ Cluster Monitor</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 30px; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .status-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .status-ok { border-left: 5px solid #4CAF50; }
        .status-warning { border-left: 5px solid #FF9800; }
        .status-critical { border-left: 5px solid #F44336; }
        .metric { display: flex; justify-content: space-between; margin: 10px 0; }
        .metric-value { font-weight: bold; }
        .refresh-btn { background: #2196F3; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        .timestamp { text-align: center; color: #666; margin-top: 20px; }
        .alert-list { background: white; padding: 20px; border-radius: 8px; margin-top: 20px; }
        .alert-item { padding: 10px; margin: 5px 0; border-radius: 4px; }
        .alert-critical { background-color: #ffebee; border-left: 4px solid #f44336; }
        .alert-warning { background-color: #fff3e0; border-left: 4px solid #ff9800; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🐰 RabbitMQ Cluster Monitor</h1>
            <button class="refresh-btn" onclick="loadStatus()">Refresh Status</button>
        </div>
        
        <div class="status-grid" id="statusGrid">
            <!-- Status cards will be populated by JavaScript -->
        </div>
        
        <div class="alert-list">
            <h3>Recent Alerts</h3>
            <div id="alertList">
                <!-- Alerts will be populated by JavaScript -->
            </div>
        </div>
        
        <div class="timestamp" id="timestamp"></div>
    </div>

    <script>
        function loadStatus() {
            // This would normally fetch from a real API
            // For demo purposes, we'll show sample data
            
            const statusData = {
                cluster: {
                    status: 'ok',
                    runningNodes: 3,
                    totalNodes: 3,
                    partitions: 0
                },
                performance: {
                    connections: 245,
                    channels: 1024,
                    queues: 42,
                    messages: 1532
                },
                resources: {
                    memoryUsage: '2.1 GB',
                    diskFree: '85%',
                    cpuUsage: '23%'
                },
                alerts: [
                    {type: 'warning', message: 'High connection count detected', time: '2 minutes ago'},
                    {type: 'info', message: 'Node node2 restarted successfully', time: '15 minutes ago'}
                ]
            };
            
            displayStatus(statusData);
        }
        
        function displayStatus(data) {
            const grid = document.getElementById('statusGrid');
            const clusterStatus = data.cluster.runningNodes === data.cluster.totalNodes ? 'ok' : 
                                 data.cluster.runningNodes >= 2 ? 'warning' : 'critical';
            
            grid.innerHTML = `
                <div class="status-card status-${clusterStatus}">
                    <h3>Cluster Health</h3>
                    <div class="metric">
                        <span>Running Nodes:</span>
                        <span class="metric-value">${data.cluster.runningNodes}/${data.cluster.totalNodes}</span>
                    </div>
                    <div class="metric">
                        <span>Partitions:</span>
                        <span class="metric-value">${data.cluster.partitions}</span>
                    </div>
                    <div class="metric">
                        <span>Status:</span>
                        <span class="metric-value">${clusterStatus.toUpperCase()}</span>
                    </div>
                </div>
                
                <div class="status-card status-ok">
                    <h3>Performance Metrics</h3>
                    <div class="metric">
                        <span>Connections:</span>
                        <span class="metric-value">${data.performance.connections}</span>
                    </div>
                    <div class="metric">
                        <span>Channels:</span>
                        <span class="metric-value">${data.performance.channels}</span>
                    </div>
                    <div class="metric">
                        <span>Queues:</span>
                        <span class="metric-value">${data.performance.queues}</span>
                    </div>
                    <div class="metric">
                        <span>Messages:</span>
                        <span class="metric-value">${data.performance.messages}</span>
                    </div>
                </div>
                
                <div class="status-card status-ok">
                    <h3>Resource Usage</h3>
                    <div class="metric">
                        <span>Memory:</span>
                        <span class="metric-value">${data.resources.memoryUsage}</span>
                    </div>
                    <div class="metric">
                        <span>Disk Free:</span>
                        <span class="metric-value">${data.resources.diskFree}</span>
                    </div>
                    <div class="metric">
                        <span>CPU Usage:</span>
                        <span class="metric-value">${data.resources.cpuUsage}</span>
                    </div>
                </div>
            `;
            
            // Display alerts
            const alertList = document.getElementById('alertList');
            alertList.innerHTML = data.alerts.map(alert => 
                `<div class="alert-item alert-${alert.type}">
                    <strong>${alert.type.toUpperCase()}:</strong> ${alert.message} <em>(${alert.time})</em>
                </div>`
            ).join('');
            
            // Update timestamp
            document.getElementById('timestamp').textContent = 
                `Last updated: ${new Date().toLocaleString()}`;
        }
        
        // Load status on page load
        loadStatus();
        
        // Auto-refresh every 30 seconds
        setInterval(loadStatus, 30000);
    </script>
</body>
</html>
EOF

# Generate API endpoint script
cat > "$DASHBOARD_DIR/api.sh" << 'EOF'
#!/bin/bash
# Simple API endpoint for dashboard data

case "$1" in
    status)
        # Collect real-time status
        if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
            RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
            TOTAL_NODES=$(sudo rabbitmqctl cluster_status | grep "Disc" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        else
            RUNNING_NODES=0
            TOTAL_NODES=3
        fi
        
        CONNECTIONS=$(sudo rabbitmqctl list_connections 2>/dev/null | wc -l || echo 0)
        CHANNELS=$(sudo rabbitmqctl list_channels 2>/dev/null | wc -l || echo 0)
        QUEUES=$(sudo rabbitmqctl list_queues 2>/dev/null | wc -l || echo 0)
        
        cat << JSON
{
    "cluster": {
        "runningNodes": $RUNNING_NODES,
        "totalNodes": $TOTAL_NODES,
        "partitions": 0
    },
    "performance": {
        "connections": $CONNECTIONS,
        "channels": $CHANNELS,
        "queues": $QUEUES,
        "messages": 0
    },
    "resources": {
        "memoryUsage": "$(free -h | awk '/^Mem:/ {print $3}')",
        "diskFree": "$(df -h / | awk 'NR==2{print $5}')",
        "cpuUsage": "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
    },
    "timestamp": "$(date -Iseconds)"
}
JSON
        ;;
esac
EOF

chmod +x "$DASHBOARD_DIR/api.sh"

# Setup simple HTTP server
cat > "$DASHBOARD_DIR/start-server.sh" << EOF
#!/bin/bash
echo "Starting RabbitMQ monitoring dashboard on port $DASHBOARD_PORT"
echo "Access at: http://\$(hostname):$DASHBOARD_PORT"
cd "$DASHBOARD_DIR"
python3 -m http.server $DASHBOARD_PORT
EOF

chmod +x "$DASHBOARD_DIR/start-server.sh"

echo "Dashboard generated at: $DASHBOARD_DIR"
echo "To start dashboard: $DASHBOARD_DIR/start-server.sh"
echo "Access at: http://$(hostname):$DASHBOARD_PORT"
```

## System Integration

### Systemd Service Setup
```bash
#!/bin/bash
# File: setup-monitoring-service.sh

echo "=== Setting up RabbitMQ Monitoring as System Service ==="

# Create systemd service file
sudo tee /etc/systemd/system/rabbitmq-monitor.service << 'EOF'
[Unit]
Description=RabbitMQ Cluster Monitoring Service
After=network.target rabbitmq-server.service
Wants=rabbitmq-server.service

[Service]
Type=forking
User=root
Group=root
ExecStart=/usr/local/bin/rabbitmq-monitor-daemon.sh start
ExecStop=/usr/local/bin/rabbitmq-monitor-daemon.sh stop
ExecReload=/usr/local/bin/rabbitmq-monitor-daemon.sh restart
PIDFile=/var/run/rabbitmq-monitor.pid
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Copy monitoring script to system location
sudo cp rabbitmq-monitor-daemon.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/rabbitmq-monitor-daemon.sh

# Create log directory
sudo mkdir -p /var/log/rabbitmq
sudo chown rabbitmq:rabbitmq /var/log/rabbitmq

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-monitor.service
sudo systemctl start rabbitmq-monitor.service

echo "Monitoring service installed and started"
echo "Service status:"
sudo systemctl status rabbitmq-monitor.service
```

This comprehensive monitoring and alerting system provides enterprise-grade visibility into your RabbitMQ cluster, with intelligent alerting, escalation procedures, and real-time dashboards to prevent downtime and ensure optimal performance.