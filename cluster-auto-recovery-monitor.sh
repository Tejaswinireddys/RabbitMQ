#!/bin/bash
# File: cluster-auto-recovery-monitor.sh
# Continuous Monitoring and Auto-Recovery for RabbitMQ Cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=""
CHECK_INTERVAL=60
RECOVERY_TIMEOUT=300
LOG_FILE=""
DAEMON_MODE="false"
PID_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "success") echo -e "${GREEN}✅${NC} [$timestamp] $message" ;;
        "error") echo -e "${RED}❌${NC} [$timestamp] $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} [$timestamp] $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} [$timestamp] $message" ;;
    esac
    
    # Log to file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "[$timestamp] [$status] $message" >> "$LOG_FILE"
    fi
}

usage() {
    echo "Cluster Auto-Recovery Monitor for RabbitMQ"
    echo ""
    echo "Usage: $0 -e <environment> [options]"
    echo ""
    echo "Required:"
    echo "  -e <env>         Environment name"
    echo ""
    echo "Options:"
    echo "  -i <seconds>     Check interval (default: 60)"
    echo "  -t <seconds>     Recovery timeout (default: 300)"
    echo "  -l <logfile>     Log file path"
    echo "  -d               Run as daemon"
    echo "  -p <pidfile>     PID file for daemon mode"
    echo "  -h               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod                                    # Monitor production"
    echo "  $0 -e qa -i 30 -t 180                        # QA with custom timings"
    echo "  $0 -e prod -d -l /var/log/rabbitmq-monitor.log # Daemon mode"
    exit 1
}

while getopts "e:i:t:l:dp:h" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        i) CHECK_INTERVAL="$OPTARG" ;;
        t) RECOVERY_TIMEOUT="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        d) DAEMON_MODE="true" ;;
        p) PID_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    print_status "error" "Environment required"
    usage
fi

# Setup logging
if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
fi

# Setup daemon mode
if [ "$DAEMON_MODE" = "true" ]; then
    if [ -z "$PID_FILE" ]; then
        PID_FILE="/var/run/rabbitmq-auto-recovery-$ENVIRONMENT.pid"
    fi
    
    # Check if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        print_status "error" "Monitor already running (PID: $(cat "$PID_FILE"))"
        exit 1
    fi
    
    # Write PID file
    echo $$ > "$PID_FILE"
    
    # Set default log file if not specified
    if [ -z "$LOG_FILE" ]; then
        LOG_FILE="/var/log/rabbitmq-auto-recovery-$ENVIRONMENT.log"
        mkdir -p "$(dirname "$LOG_FILE")"
    fi
fi

# Load environment
print_status "info" "Loading environment configuration..."
if ! source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"; then
    print_status "error" "Failed to load environment: $ENVIRONMENT"
    exit 1
fi

print_status "info" "=== Cluster Auto-Recovery Monitor Started ==="
print_status "info" "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
print_status "info" "Cluster: $RABBITMQ_CLUSTER_NAME"
print_status "info" "Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"
print_status "info" "Check Interval: ${CHECK_INTERVAL}s"
print_status "info" "Recovery Timeout: ${RECOVERY_TIMEOUT}s"
print_status "info" "Daemon Mode: $DAEMON_MODE"
if [ -n "$LOG_FILE" ]; then
    print_status "info" "Log File: $LOG_FILE"
fi
if [ -n "$PID_FILE" ]; then
    print_status "info" "PID File: $PID_FILE"
fi

# Track consecutive failures and recovery state
consecutive_failures=0
max_failures=3
last_recovery_attempt=0
recovery_cooldown=1800  # 30 minutes between recovery attempts
total_checks=0
total_failures=0
total_recoveries=0

# Cleanup function for daemon mode
cleanup() {
    print_status "info" "Auto-recovery monitor shutting down"
    if [ -n "$PID_FILE" ]; then
        rm -f "$PID_FILE"
    fi
    
    print_status "info" "=== Monitor Session Summary ==="
    print_status "info" "Total checks performed: $total_checks"
    print_status "info" "Total failures detected: $total_failures"
    print_status "info" "Total recovery attempts: $total_recoveries"
    
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Function to check cluster health comprehensively
check_cluster_health() {
    local health_issues=0
    
    # Check 1: Basic cluster status
    if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        print_status "error" "Cluster status command failed"
        health_issues=$((health_issues + 1))
    fi
    
    # Check 2: Node count verification
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        local expected_nodes=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
        
        if [ $running_nodes -lt $expected_nodes ]; then
            print_status "warning" "Node count mismatch: $running_nodes/$expected_nodes running"
            if [ $running_nodes -eq 0 ]; then
                health_issues=$((health_issues + 2))  # More severe
            else
                health_issues=$((health_issues + 1))
            fi
        fi
    else
        health_issues=$((health_issues + 2))  # Can't even get status
    fi
    
    # Check 3: Service status
    if ! sudo systemctl is-active rabbitmq-server >/dev/null 2>&1; then
        print_status "error" "RabbitMQ service is not active"
        health_issues=$((health_issues + 2))
    fi
    
    # Check 4: Node health
    if ! sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
        print_status "warning" "Node health check failed"
        health_issues=$((health_issues + 1))
    fi
    
    # Check 5: Alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "ERROR")
    if [ "$alarms" = "ERROR" ]; then
        health_issues=$((health_issues + 1))
    elif [ "$alarms" != "[]" ]; then
        print_status "warning" "Resource alarms detected: $alarms"
        # Don't count alarms as critical failure for recovery
    fi
    
    return $health_issues
}

# Function to check if recovery is needed and allowed
should_attempt_recovery() {
    local current_time=$(date +%s)
    
    # Check if enough time has passed since last recovery
    if [ $((current_time - last_recovery_attempt)) -lt $recovery_cooldown ]; then
        local remaining=$((recovery_cooldown - (current_time - last_recovery_attempt)))
        print_status "info" "Recovery cooldown active, ${remaining}s remaining"
        return 1
    fi
    
    return 0
}

# Function to attempt cluster recovery
attempt_recovery() {
    local current_time=$(date +%s)
    last_recovery_attempt=$current_time
    total_recoveries=$((total_recoveries + 1))
    
    print_status "warning" "=== Initiating Cluster Recovery (Attempt #$total_recoveries) ==="
    
    # Step 1: Check if it's a service issue
    if ! sudo systemctl is-active rabbitmq-server >/dev/null 2>&1; then
        print_status "info" "RabbitMQ service is down, attempting restart..."
        
        if sudo systemctl restart rabbitmq-server; then
            print_status "info" "Service restarted, waiting for cluster formation..."
            sleep 60
            
            if check_cluster_health; then
                print_status "success" "Recovery successful via service restart"
                consecutive_failures=0
                return 0
            fi
        else
            print_status "error" "Service restart failed"
        fi
    fi
    
    # Step 2: Check if nodes are reachable
    print_status "info" "Checking node connectivity..."
    local reachable_nodes=0
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" = "$(hostname)" ]; then
            reachable_nodes=$((reachable_nodes + 1))
        elif ping -c 1 -W 2 "$hostname" >/dev/null 2>&1; then
            reachable_nodes=$((reachable_nodes + 1))
            print_status "info" "$hostname is reachable"
        else
            print_status "warning" "$hostname is not reachable"
        fi
    done
    
    print_status "info" "Reachable nodes: $reachable_nodes/$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)"
    
    # Step 3: If most nodes are reachable, try force boot recovery
    if [ $reachable_nodes -ge 2 ]; then
        print_status "info" "Attempting force boot recovery..."
        
        if "$SCRIPT_DIR/auto-force-boot.sh" -e "$ENVIRONMENT" -t "$RECOVERY_TIMEOUT"; then
            print_status "success" "Recovery successful via force boot"
            consecutive_failures=0
            return 0
        else
            print_status "error" "Force boot recovery failed"
        fi
    else
        print_status "warning" "Too few nodes reachable for automatic recovery"
    fi
    
    # Step 4: Try restarting all reachable nodes
    print_status "info" "Attempting cluster-wide restart..."
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" = "$(hostname)" ]; then
            print_status "info" "Restarting local RabbitMQ service..."
            sudo systemctl restart rabbitmq-server &
        elif ping -c 1 -W 2 "$hostname" >/dev/null 2>&1; then
            print_status "info" "Restarting RabbitMQ on $hostname..."
            ssh -o ConnectTimeout=5 "root@$hostname" "systemctl restart rabbitmq-server" &
        fi
    done
    
    wait
    print_status "info" "Waiting for cluster formation after restart..."
    sleep 90
    
    if check_cluster_health; then
        print_status "success" "Recovery successful via cluster restart"
        consecutive_failures=0
        return 0
    fi
    
    print_status "error" "All recovery attempts failed"
    return 1
}

# Function to send critical alerts
send_critical_alert() {
    local message="$1"
    
    # Send email if configured
    if [ -n "$EMAIL_ALERTS" ]; then
        echo "$message" | mail -s "[CRITICAL] RabbitMQ Auto-Recovery: $ENVIRONMENT_NAME" "$EMAIL_ALERTS" 2>/dev/null || true
    fi
    
    # Send Slack notification if configured
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"attachments\":[{\"color\":\"danger\",\"text\":\"🚨 $message\"}]}" \
            "$SLACK_WEBHOOK" >/dev/null 2>&1 || true
    fi
}

# Main monitoring loop
print_status "info" "Starting monitoring loop..."

while true; do
    total_checks=$((total_checks + 1))
    
    if [ $((total_checks % 10)) -eq 0 ]; then
        print_status "info" "Monitoring check #$total_checks (failures: $total_failures, recoveries: $total_recoveries)"
    fi
    
    # Perform health check
    if check_cluster_health; then
        # Cluster is healthy
        if [ $consecutive_failures -gt 0 ]; then
            print_status "success" "Cluster health restored (was failing for $consecutive_failures checks)"
            consecutive_failures=0
        fi
    else
        # Cluster has issues
        consecutive_failures=$((consecutive_failures + 1))
        total_failures=$((total_failures + 1))
        
        print_status "error" "Cluster health check failed (consecutive failure #$consecutive_failures)"
        
        # Check if we need to attempt recovery
        if [ $consecutive_failures -ge $max_failures ]; then
            print_status "warning" "Maximum consecutive failures reached ($consecutive_failures/$max_failures)"
            
            if should_attempt_recovery; then
                if attempt_recovery; then
                    print_status "success" "Automatic recovery successful"
                    send_critical_alert "RabbitMQ cluster $RABBITMQ_CLUSTER_NAME recovered automatically after $consecutive_failures failures"
                else
                    print_status "error" "Automatic recovery failed"
                    send_critical_alert "RabbitMQ cluster $RABBITMQ_CLUSTER_NAME automatic recovery FAILED after $consecutive_failures failures. Manual intervention required."
                    
                    # Reset failure count to prevent constant recovery attempts
                    consecutive_failures=0
                fi
            else
                print_status "info" "Recovery needed but cooldown period active"
            fi
        elif [ $consecutive_failures -eq 1 ]; then
            # First failure, send warning
            send_critical_alert "RabbitMQ cluster $RABBITMQ_CLUSTER_NAME health check failing (first failure detected)"
        fi
    fi
    
    # Sleep until next check
    sleep $CHECK_INTERVAL
done