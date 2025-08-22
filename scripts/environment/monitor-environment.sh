#!/bin/bash
# File: monitor-environment.sh
# Environment-Aware RabbitMQ Monitoring Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT=""
MONITOR_MODE="once"
INTERVAL=30
OUTPUT_FORMAT="text"
LOG_FILE=""
ALERT_MODE="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "success") echo -e "${GREEN}✓${NC} [$timestamp] $message" ;;
        "error") echo -e "${RED}✗${NC} [$timestamp] $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} [$timestamp] $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} [$timestamp] $message" ;;
    esac
    
    # Log to file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$status] $message" >> "$LOG_FILE"
    fi
}

# Function to display usage
usage() {
    echo "Environment-Aware RabbitMQ Monitoring"
    echo ""
    echo "Usage: $0 -e <environment> [options]"
    echo ""
    echo "Required Arguments:"
    echo "  -e <environment>   Environment name (qa, staging, prod, etc.)"
    echo ""
    echo "Options:"
    echo "  -m <mode>         Monitor mode: once, continuous, daemon (default: once)"
    echo "  -i <seconds>      Interval for continuous monitoring (default: 30)"
    echo "  -f <format>       Output format: text, json, prometheus (default: text)"
    echo "  -l <logfile>      Log output to file"
    echo "  -a                Enable alert mode (send alerts on issues)"
    echo "  -h                Show this help"
    echo ""
    echo "Monitor Modes:"
    echo "  once             Run monitoring checks once and exit"
    echo "  continuous       Run monitoring continuously with specified interval"
    echo "  daemon           Run as background daemon"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod -m once              # Single check of production"
    echo "  $0 -e qa -m continuous -i 60    # Continuous QA monitoring every 60s"
    echo "  $0 -e staging -m daemon -a      # Daemon mode with alerts"
    exit 1
}

# Parse command line arguments
while getopts "e:m:i:f:l:ah" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        m) MONITOR_MODE="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        f) OUTPUT_FORMAT="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        a) ALERT_MODE="true" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$ENVIRONMENT" ]; then
    print_status "error" "Environment is required"
    usage
fi

# Validate monitor mode
if [[ ! "$MONITOR_MODE" =~ ^(once|continuous|daemon)$ ]]; then
    print_status "error" "Invalid monitor mode: $MONITOR_MODE"
    exit 1
fi

# Validate output format
if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json|prometheus)$ ]]; then
    print_status "error" "Invalid output format: $OUTPUT_FORMAT"
    exit 1
fi

# Create log file if specified
if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
fi

print_status "info" "Starting environment-aware monitoring"
print_status "info" "Environment: $ENVIRONMENT"
print_status "info" "Mode: $MONITOR_MODE"

# Load environment configuration
print_status "info" "Loading environment configuration..."
if ! source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"; then
    print_status "error" "Failed to load environment: $ENVIRONMENT"
    exit 1
fi

print_status "success" "Environment loaded: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"

# Global monitoring state
declare -A LAST_ALERT_TIME
declare -A ALERT_COUNTS

# Function to send alert
send_alert() {
    local alert_key="$1"
    local message="$2"
    local priority="$3"
    
    if [ "$ALERT_MODE" = "false" ]; then
        return 0
    fi
    
    local current_time=$(date +%s)
    local last_time=${LAST_ALERT_TIME[$alert_key]:-0}
    local cooldown=300  # 5 minutes
    
    # Check cooldown
    if [ $((current_time - last_time)) -lt $cooldown ]; then
        return 0
    fi
    
    LAST_ALERT_TIME[$alert_key]=$current_time
    ALERT_COUNTS[$alert_key]=$((${ALERT_COUNTS[$alert_key]:-0} + 1))
    
    # Send email if configured
    if [ -n "$EMAIL_ALERTS" ]; then
        echo "$message" | mail -s "[$priority] RabbitMQ Alert: $ENVIRONMENT_NAME - $alert_key" "$EMAIL_ALERTS"
        print_status "info" "Email alert sent: $alert_key"
    fi
    
    # Send Slack notification if configured
    if [ -n "$SLACK_WEBHOOK" ]; then
        local color="danger"
        if [ "$priority" = "WARNING" ]; then
            color="warning"
        elif [ "$priority" = "INFO" ]; then
            color="good"
        fi
        
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1
        print_status "info" "Slack alert sent: $alert_key"
    fi
}

# Function to check cluster health
check_cluster_health() {
    local issues=()
    local health_status="OK"
    
    print_status "info" "Checking cluster health for environment: $ENVIRONMENT_NAME"
    
    # Test 1: Basic cluster status
    if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        health_status="CRITICAL"
        issues+=("Cluster status command failed - possible majority partition")
        send_alert "cluster_status_failed" "RabbitMQ cluster status failed in $ENVIRONMENT_NAME environment" "CRITICAL"
    fi
    
    # Test 2: Node count verification
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        local expected_nodes=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
        
        if [ $running_nodes -lt $expected_nodes ]; then
            if [ $running_nodes -lt 2 ]; then
                health_status="CRITICAL"
                issues+=("Only $running_nodes out of $expected_nodes nodes running - cluster at risk")
                send_alert "low_node_count" "Low node count in $ENVIRONMENT_NAME: $running_nodes/$expected_nodes" "CRITICAL"
            else
                health_status="WARNING"
                issues+=("$running_nodes out of $expected_nodes nodes running")
                send_alert "node_down" "Node down in $ENVIRONMENT_NAME: $running_nodes/$expected_nodes running" "WARNING"
            fi
        fi
    fi
    
    # Test 3: Verify cluster name matches environment
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local actual_cluster_name=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' | sed 's/<<"\(.*\)">>/\1/')
        if [ "$actual_cluster_name" != "$RABBITMQ_CLUSTER_NAME" ]; then
            health_status="WARNING"
            issues+=("Cluster name mismatch: expected $RABBITMQ_CLUSTER_NAME, got $actual_cluster_name")
            send_alert "cluster_name_mismatch" "Cluster name mismatch in $ENVIRONMENT_NAME" "WARNING"
        fi
    fi
    
    # Test 4: Resource alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
    if [ "$alarms" != "[]" ]; then
        health_status="WARNING"
        issues+=("Resource alarms detected: $alarms")
        send_alert "resource_alarms" "Resource alarms in $ENVIRONMENT_NAME: $alarms" "WARNING"
    fi
    
    # Test 5: Network partitions
    local partitions=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "[]")
    if [ "$partitions" != "[]" ]; then
        health_status="CRITICAL"
        issues+=("Network partitions detected: $partitions")
        send_alert "network_partition" "Network partitions in $ENVIRONMENT_NAME: $partitions" "CRITICAL"
    fi
    
    # Test 6: Environment-specific queue checks
    if sudo rabbitmqctl list_queues >/dev/null 2>&1; then
        local env_queues=$(sudo rabbitmqctl list_queues name messages | grep "^$ENVIRONMENT_NAME-" | wc -l)
        if [ $env_queues -eq 0 ] && [ "$ENVIRONMENT_TYPE" != "development" ]; then
            health_status="WARNING"
            issues+=("No environment-specific queues found")
            send_alert "no_env_queues" "No environment-specific queues in $ENVIRONMENT_NAME" "WARNING"
        fi
        
        # Check for high queue depths
        local max_messages=$(sudo rabbitmqctl list_queues messages | tail -n +2 | sort -nr | head -1 || echo "0")
        local queue_threshold=${ALERT_QUEUE_DEPTH_THRESHOLD:-50000}
        if [ "$max_messages" -gt "$queue_threshold" ]; then
            health_status="WARNING"
            issues+=("High queue depth detected: $max_messages messages")
            send_alert "high_queue_depth" "High queue depth in $ENVIRONMENT_NAME: $max_messages messages" "WARNING"
        fi
    fi
    
    # Output results based on format
    case $OUTPUT_FORMAT in
        "json")
            echo "{"
            echo "  \"environment\": \"$ENVIRONMENT_NAME\","
            echo "  \"environment_type\": \"$ENVIRONMENT_TYPE\","
            echo "  \"cluster_name\": \"$RABBITMQ_CLUSTER_NAME\","
            echo "  \"timestamp\": \"$(date -Iseconds)\","
            echo "  \"health_status\": \"$health_status\","
            echo "  \"issues\": [$(printf '"%s",' "${issues[@]}" | sed 's/,$//')]"
            echo "}"
            ;;
        "prometheus")
            echo "# HELP rabbitmq_cluster_health_status Cluster health status (0=OK, 1=WARNING, 2=CRITICAL)"
            echo "# TYPE rabbitmq_cluster_health_status gauge"
            local status_value=0
            if [ "$health_status" = "WARNING" ]; then
                status_value=1
            elif [ "$health_status" = "CRITICAL" ]; then
                status_value=2
            fi
            echo "rabbitmq_cluster_health_status{environment=\"$ENVIRONMENT_NAME\",cluster=\"$RABBITMQ_CLUSTER_NAME\"} $status_value"
            ;;
        *)
            if [ "$health_status" = "OK" ]; then
                print_status "success" "Cluster health check: OK"
            else
                print_status "error" "Cluster health check: $health_status - Issues: ${issues[*]}"
            fi
            ;;
    esac
    
    return 0
}

# Function to check individual node health
check_node_health() {
    print_status "info" "Checking individual node health..."
    
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        local node_status="OK"
        
        if [ "$hostname" = "$(hostname)" ]; then
            # Local node
            if ! sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
                node_status="FAILED"
                send_alert "node_health_$hostname" "Node health check failed for $hostname in $ENVIRONMENT_NAME" "WARNING"
            fi
        else
            # Remote node
            if ! ssh -o ConnectTimeout=5 "root@$hostname" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
                node_status="FAILED"
                send_alert "node_health_$hostname" "Node health check failed for $hostname in $ENVIRONMENT_NAME" "WARNING"
            fi
        fi
        
        case $OUTPUT_FORMAT in
            "json")
                echo "  {\"node\": \"$hostname\", \"status\": \"$node_status\"},"
                ;;
            "prometheus")
                local status_value=0
                if [ "$node_status" = "FAILED" ]; then
                    status_value=1
                fi
                echo "rabbitmq_node_health_status{environment=\"$ENVIRONMENT_NAME\",node=\"$hostname\"} $status_value"
                ;;
            *)
                if [ "$node_status" = "OK" ]; then
                    print_status "success" "Node health check ($hostname): OK"
                else
                    print_status "error" "Node health check ($hostname): FAILED"
                fi
                ;;
        esac
    done
}

# Function to collect performance metrics
collect_performance_metrics() {
    print_status "info" "Collecting performance metrics..."
    
    # Basic metrics
    local connections=$(sudo rabbitmqctl list_connections 2>/dev/null | wc -l || echo "0")
    local channels=$(sudo rabbitmqctl list_channels 2>/dev/null | wc -l || echo "0")
    local queues=$(sudo rabbitmqctl list_queues 2>/dev/null | wc -l || echo "0")
    local env_queues=$(sudo rabbitmqctl list_queues name 2>/dev/null | grep "^$ENVIRONMENT_NAME-" | wc -l || echo "0")
    
    # Memory usage
    local memory_used="0"
    if sudo rabbitmqctl status >/dev/null 2>&1; then
        memory_used=$(sudo rabbitmqctl status | grep -A 1 "Memory" | tail -1 | awk '{print $2}' | tr -d ',' || echo "0")
    fi
    
    case $OUTPUT_FORMAT in
        "json")
            echo "{"
            echo "  \"environment\": \"$ENVIRONMENT_NAME\","
            echo "  \"timestamp\": \"$(date -Iseconds)\","
            echo "  \"metrics\": {"
            echo "    \"connections\": $connections,"
            echo "    \"channels\": $channels,"
            echo "    \"total_queues\": $queues,"
            echo "    \"environment_queues\": $env_queues,"
            echo "    \"memory_used\": $memory_used"
            echo "  }"
            echo "}"
            ;;
        "prometheus")
            echo "# HELP rabbitmq_connections Number of client connections"
            echo "# TYPE rabbitmq_connections gauge"
            echo "rabbitmq_connections{environment=\"$ENVIRONMENT_NAME\"} $connections"
            
            echo "# HELP rabbitmq_channels Number of channels"
            echo "# TYPE rabbitmq_channels gauge"
            echo "rabbitmq_channels{environment=\"$ENVIRONMENT_NAME\"} $channels"
            
            echo "# HELP rabbitmq_queues_total Total number of queues"
            echo "# TYPE rabbitmq_queues_total gauge"
            echo "rabbitmq_queues_total{environment=\"$ENVIRONMENT_NAME\"} $queues"
            
            echo "# HELP rabbitmq_environment_queues Environment-specific queues"
            echo "# TYPE rabbitmq_environment_queues gauge"
            echo "rabbitmq_environment_queues{environment=\"$ENVIRONMENT_NAME\"} $env_queues"
            ;;
        *)
            print_status "info" "Performance Metrics for $ENVIRONMENT_NAME:"
            echo "  Active connections: $connections"
            echo "  Active channels: $channels"
            echo "  Total queues: $queues"
            echo "  Environment queues: $env_queues"
            echo "  Memory used: $memory_used bytes"
            ;;
    esac
    
    # Send to Prometheus if configured
    if [ -n "$PROMETHEUS_PUSHGATEWAY" ] && [ "$OUTPUT_FORMAT" != "prometheus" ]; then
        cat << EOF | curl --data-binary @- "$PROMETHEUS_PUSHGATEWAY/metrics/job/rabbitmq_monitor/instance/$(hostname)/environment/$ENVIRONMENT_NAME" >/dev/null 2>&1 || true
rabbitmq_connections{environment="$ENVIRONMENT_NAME"} $connections
rabbitmq_channels{environment="$ENVIRONMENT_NAME"} $channels
rabbitmq_queues_total{environment="$ENVIRONMENT_NAME"} $queues
rabbitmq_environment_queues{environment="$ENVIRONMENT_NAME"} $env_queues
EOF
    fi
}

# Function to run single monitoring cycle
run_monitoring_cycle() {
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        echo "{"
        echo "  \"monitoring_cycle\": {"
        echo "    \"environment\": \"$ENVIRONMENT_NAME\","
        echo "    \"timestamp\": \"$(date -Iseconds)\","
        echo "    \"cluster_health\": $(check_cluster_health),"
        echo "    \"node_health\": ["
        check_node_health
        echo "    ],"
        echo "    \"performance_metrics\": $(collect_performance_metrics)"
        echo "  }"
        echo "}"
    else
        check_cluster_health
        check_node_health
        collect_performance_metrics
    fi
    
    print_status "info" "Monitoring cycle completed for environment: $ENVIRONMENT_NAME"
}

# Function to run in daemon mode
run_daemon() {
    local pid_file="/var/run/rabbitmq-monitor-$ENVIRONMENT.pid"
    
    print_status "info" "Starting monitoring daemon for environment: $ENVIRONMENT_NAME"
    print_status "info" "PID file: $pid_file"
    print_status "info" "Log file: ${LOG_FILE:-/var/log/rabbitmq-monitor-$ENVIRONMENT.log}"
    
    # Write PID file
    echo $$ > "$pid_file"
    
    # Set default log file if not specified
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="/var/log/rabbitmq-monitor-$ENVIRONMENT.log"
        mkdir -p "$(dirname "$LOG_FILE")"
    fi
    
    # Cleanup function
    cleanup() {
        print_status "info" "Monitoring daemon shutting down"
        rm -f "$pid_file"
        exit 0
    }
    
    trap cleanup SIGTERM SIGINT
    
    # Main daemon loop
    while true; do
        run_monitoring_cycle
        print_status "info" "Sleeping for $INTERVAL seconds..."
        sleep $INTERVAL
    done
}

# Main function
main() {
    case $MONITOR_MODE in
        "once")
            run_monitoring_cycle
            ;;
        "continuous")
            print_status "info" "Starting continuous monitoring (interval: ${INTERVAL}s)"
            while true; do
                run_monitoring_cycle
                print_status "info" "Sleeping for $INTERVAL seconds..."
                sleep $INTERVAL
            done
            ;;
        "daemon")
            run_daemon
            ;;
    esac
}

# Run main function
main "$@"