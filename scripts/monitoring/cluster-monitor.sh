#!/bin/bash
# RabbitMQ Cluster Monitoring Script
# This script monitors cluster health and provides detailed status reporting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-qa}"
LOG_FILE="/var/log/rabbitmq/cluster-monitor.log"
ALERT_FILE="/tmp/rabbitmq-cluster-alerts.json"

# Load environment
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date): [WARNING] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date): [ERROR] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" >> "$LOG_FILE"
}

# Initialize log file
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    print_info "Cluster monitoring started for $ENVIRONMENT environment"
}

# Check if RabbitMQ is running
check_rabbitmq_service() {
    if ! systemctl is-active --quiet rabbitmq-server; then
        print_error "RabbitMQ service is not running"
        return 1
    fi
    print_status "RabbitMQ service is running"
    return 0
}

# Check cluster status
check_cluster_status() {
    print_info "Checking cluster status..."
    
    if ! command -v rabbitmqctl &> /dev/null; then
        print_error "rabbitmqctl command not found"
        return 1
    fi
    
    # Get cluster status
    CLUSTER_STATUS=$(rabbitmqctl cluster_status 2>/dev/null || echo "ERROR")
    
    if [[ "$CLUSTER_STATUS" == "ERROR" ]]; then
        print_error "Failed to get cluster status"
        return 1
    fi
    
    # Extract cluster information
    CLUSTER_MEMBERS=$(echo "$CLUSTER_STATUS" | grep -c "rabbit@" || echo "0")
    CLUSTER_PARTITIONS=$(echo "$CLUSTER_STATUS" | grep -c "partitions" || echo "0")
    
    print_info "Cluster members: $CLUSTER_MEMBERS"
    print_info "Cluster partitions: $CLUSTER_PARTITIONS"
    
    # Check for expected cluster size
    EXPECTED_NODES=3
    if [[ $CLUSTER_MEMBERS -lt $EXPECTED_NODES ]]; then
        print_warning "Cluster has fewer than $EXPECTED_NODES nodes ($CLUSTER_MEMBERS)"
        return 1
    fi
    
    if [[ $CLUSTER_PARTITIONS -gt 0 ]]; then
        print_warning "Cluster has partitions detected"
        return 1
    fi
    
    print_status "Cluster status is healthy"
    return 0
}

# Check node connectivity
check_node_connectivity() {
    print_info "Checking node connectivity..."
    
    # Get list of cluster nodes
    NODES=$(rabbitmqctl cluster_status 2>/dev/null | grep "rabbit@" | awk '{print $1}' | sed 's/rabbit@//')
    
    if [[ -z "$NODES" ]]; then
        print_error "No cluster nodes found"
        return 1
    fi
    
    CONNECTIVITY_ISSUES=0
    
    for node in $NODES; do
        if [[ "$node" == "$(hostname)" ]]; then
            continue  # Skip self
        fi
        
        # Check if we can reach the node
        if ! ping -c 1 -W 5 "$node" &>/dev/null; then
            print_warning "Cannot reach node: $node"
            CONNECTIVITY_ISSUES=$((CONNECTIVITY_ISSUES + 1))
        else
            print_status "Node $node is reachable"
        fi
    done
    
    if [[ $CONNECTIVITY_ISSUES -gt 0 ]]; then
        print_warning "Connectivity issues detected with $CONNECTIVITY_ISSUES nodes"
        return 1
    fi
    
    print_status "All nodes are reachable"
    return 0
}

# Check queue health
check_queue_health() {
    print_info "Checking queue health..."
    
    # Get queue information
    QUEUE_INFO=$(rabbitmqctl list_queues name messages consumers 2>/dev/null || echo "ERROR")
    
    if [[ "$QUEUE_INFO" == "ERROR" ]]; then
        print_error "Failed to get queue information"
        return 1
    fi
    
    # Check for queues with high message counts
    HIGH_QUEUE_COUNT=0
    EMPTY_QUEUE_COUNT=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[a-zA-Z] ]]; then
            QUEUE_NAME=$(echo "$line" | awk '{print $1}')
            MESSAGE_COUNT=$(echo "$line" | awk '{print $2}')
            CONSUMER_COUNT=$(echo "$line" | awk '{print $3}')
            
            if [[ "$MESSAGE_COUNT" -gt 10000 ]]; then
                print_warning "Queue $QUEUE_NAME has high message count: $MESSAGE_COUNT"
                HIGH_QUEUE_COUNT=$((HIGH_QUEUE_COUNT + 1))
            fi
            
            if [[ "$MESSAGE_COUNT" -gt 0 && "$CONSUMER_COUNT" -eq 0 ]]; then
                print_warning "Queue $QUEUE_NAME has messages but no consumers"
                EMPTY_QUEUE_COUNT=$((EMPTY_QUEUE_COUNT + 1))
            fi
        fi
    done <<< "$QUEUE_INFO"
    
    if [[ $HIGH_QUEUE_COUNT -gt 0 ]]; then
        print_warning "Found $HIGH_QUEUE_COUNT queues with high message counts"
    fi
    
    if [[ $EMPTY_QUEUE_COUNT -gt 0 ]]; then
        print_warning "Found $EMPTY_QUEUE_COUNT queues with messages but no consumers"
    fi
    
    if [[ $HIGH_QUEUE_COUNT -eq 0 && $EMPTY_QUEUE_COUNT -eq 0 ]]; then
        print_status "Queue health is good"
        return 0
    else
        return 1
    fi
}

# Check connection health
check_connection_health() {
    print_info "Checking connection health..."
    
    # Get connection information
    CONNECTION_INFO=$(rabbitmqctl list_connections name state 2>/dev/null || echo "ERROR")
    
    if [[ "$CONNECTION_INFO" == "ERROR" ]]; then
        print_error "Failed to get connection information"
        return 1
    fi
    
    TOTAL_CONNECTIONS=$(echo "$CONNECTION_INFO" | grep -c "^[a-zA-Z]" || echo "0")
    ESTABLISHED_CONNECTIONS=$(echo "$CONNECTION_INFO" | grep -c "established" || echo "0")
    
    print_info "Total connections: $TOTAL_CONNECTIONS"
    print_info "Established connections: $ESTABLISHED_CONNECTIONS"
    
    if [[ $TOTAL_CONNECTIONS -gt 1000 ]]; then
        print_warning "High connection count: $TOTAL_CONNECTIONS"
        return 1
    fi
    
    if [[ $ESTABLISHED_CONNECTIONS -lt $TOTAL_CONNECTIONS ]]; then
        print_warning "Some connections are not established"
        return 1
    fi
    
    print_status "Connection health is good"
    return 0
}

# Check resource usage
check_resource_usage() {
    print_info "Checking resource usage..."
    
    # Check memory usage
    MEMORY_INFO=$(rabbitmqctl status 2>/dev/null | grep -A 5 "Memory" || echo "ERROR")
    
    if [[ "$MEMORY_INFO" != "ERROR" ]]; then
        MEMORY_USAGE=$(echo "$MEMORY_INFO" | grep "total" | awk '{print $2}' | sed 's/,//')
        if [[ -n "$MEMORY_USAGE" ]]; then
            print_info "Memory usage: $MEMORY_USAGE"
        fi
    fi
    
    # Check disk space
    DISK_FREE=$(df /var/lib/rabbitmq | tail -1 | awk '{print $4}')
    DISK_FREE_GB=$((DISK_FREE / 1024 / 1024))
    
    print_info "Disk free space: ${DISK_FREE_GB}GB"
    
    if [[ $DISK_FREE_GB -lt 5 ]]; then
        print_warning "Low disk space: ${DISK_FREE_GB}GB"
        return 1
    fi
    
    print_status "Resource usage is acceptable"
    return 0
}

# Check consumer health
check_consumer_health() {
    print_info "Checking consumer health..."
    
    # Get consumer information
    CONSUMER_INFO=$(rabbitmqctl list_consumers 2>/dev/null || echo "ERROR")
    
    if [[ "$CONSUMER_INFO" == "ERROR" ]]; then
        print_error "Failed to get consumer information"
        return 1
    fi
    
    TOTAL_CONSUMERS=$(echo "$CONSUMER_INFO" | grep -c "^[a-zA-Z]" || echo "0")
    
    print_info "Total consumers: $TOTAL_CONSUMERS"
    
    if [[ $TOTAL_CONSUMERS -lt 10 ]]; then
        print_warning "Low consumer count: $TOTAL_CONSUMERS"
        return 1
    fi
    
    print_status "Consumer health is good"
    return 0
}

# Generate health report
generate_health_report() {
    print_info "Generating health report..."
    
    # Initialize counters
    TOTAL_CHECKS=6
    PASSED_CHECKS=0
    FAILED_CHECKS=0
    WARNINGS=0
    
    # Run all health checks
    if check_rabbitmq_service; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    
    if check_cluster_status; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
    
    if check_node_connectivity; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
    
    if check_queue_health; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
    
    if check_connection_health; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
    
    if check_resource_usage; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Generate summary
    echo ""
    echo "=== RabbitMQ Cluster Health Report ==="
    echo "Environment: $ENVIRONMENT"
    echo "Timestamp: $(date)"
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Passed: $PASSED_CHECKS"
    echo "Failed: $FAILED_CHECKS"
    echo "Warnings: $WARNINGS"
    echo ""
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        print_status "All health checks passed - Cluster is healthy"
        echo "Status: HEALTHY" >> "$LOG_FILE"
        return 0
    elif [[ $WARNINGS -gt 0 && $FAILED_CHECKS -eq $WARNINGS ]]; then
        print_warning "Cluster has warnings but no critical failures"
        echo "Status: WARNING" >> "$LOG_FILE"
        return 1
    else
        print_error "Cluster has critical health issues"
        echo "Status: CRITICAL" >> "$LOG_FILE"
        return 2
    fi
}

# Send alerts to monitoring system
send_alerts() {
    print_info "Sending alerts to monitoring system..."
    
    # Create alert payload
    cat > "$ALERT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "cluster": "$(hostname)",
  "status": "$(grep "Status:" "$LOG_FILE" | tail -1 | awk '{print $2}')",
  "checks_passed": $PASSED_CHECKS,
  "checks_failed": $FAILED_CHECKS,
  "warnings": $WARNINGS,
  "log_file": "$LOG_FILE"
}
EOF
    
    # Send to Prometheus if available
    if curl -s http://localhost:9090/api/v1/query?query=up > /dev/null 2>&1; then
        print_info "Prometheus is available - metrics can be queried"
    fi
    
    # Send to external monitoring system if configured
    if [[ -n "$EXTERNAL_MONITORING_URL" ]]; then
        if curl -X POST "$EXTERNAL_MONITORING_URL" -H "Content-Type: application/json" -d @"$ALERT_FILE" > /dev/null 2>&1; then
            print_status "Alert sent to external monitoring system"
        else
            print_warning "Failed to send alert to external monitoring system"
        fi
    fi
    
    print_status "Alerts processed"
}

# Main execution
main() {
    print_info "Starting RabbitMQ cluster monitoring..."
    
    # Initialize logging
    init_logging
    
    # Check if running as root (optional)
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root - some checks may not work properly"
    fi
    
    # Run health checks and generate report
    generate_health_report
    HEALTH_STATUS=$?
    
    # Send alerts
    send_alerts
    
    # Clean up
    rm -f "$ALERT_FILE"
    
    # Exit with appropriate code
    case $HEALTH_STATUS in
        0)  print_status "Cluster monitoring completed successfully"
            exit 0
            ;;
        1)  print_warning "Cluster monitoring completed with warnings"
            exit 1
            ;;
        2)  print_error "Cluster monitoring detected critical issues"
            exit 2
            ;;
        *)  print_error "Unknown health status: $HEALTH_STATUS"
            exit 3
            ;;
    esac
}

# Handle script arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [environment]"
        echo "  environment: qa, staging, prod (default: qa)"
        echo ""
        echo "This script monitors RabbitMQ cluster health and generates reports."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
