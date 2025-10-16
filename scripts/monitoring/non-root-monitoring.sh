#!/bin/bash

# RabbitMQ Non-Root Monitoring Script
# Provides comprehensive monitoring and health checks for non-root users
# Version: 1.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
MONITORING_DIR="$SCRIPT_DIR/../monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as non-root user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        error "This script must be run as a non-root user"
        exit 1
    fi
}

# Check RabbitMQ service status
check_service_status() {
    if sudo systemctl is-active --quiet rabbitmq-server; then
        return 0
    else
        return 1
    fi
}

# Get system metrics
get_system_metrics() {
    log "=== System Metrics ==="
    
    echo "1. CPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1
    
    echo ""
    echo "2. Memory Usage:"
    free -h
    
    echo ""
    echo "3. Disk Usage:"
    df -h /var/lib/rabbitmq /var/log/rabbitmq
    
    echo ""
    echo "4. Load Average:"
    uptime
}

# Get RabbitMQ metrics
get_rabbitmq_metrics() {
    log "=== RabbitMQ Metrics ==="
    
    echo "1. Service Status:"
    if check_service_status; then
        echo "   ✓ RabbitMQ service is running"
    else
        echo "   ✗ RabbitMQ service is not running"
        return 1
    fi
    
    echo ""
    echo "2. Cluster Status:"
    sudo rabbitmqctl cluster_status
    
    echo ""
    echo "3. Node Health:"
    sudo rabbitmqctl node_health_check
    
    echo ""
    echo "4. Memory Usage:"
    sudo rabbitmqctl status | grep -A 5 "Memory"
    
    echo ""
    echo "5. Active Connections:"
    local conn_count=$(sudo rabbitmqctl list_connections | wc -l)
    echo "   Active connections: $((conn_count - 1))"
    
    echo ""
    echo "6. Queue Overview:"
    sudo rabbitmqctl list_queues name type messages consumers
    
    echo ""
    echo "7. Exchange Overview:"
    sudo rabbitmqctl list_exchanges name type
    
    echo ""
    echo "8. Binding Overview:"
    sudo rabbitmqctl list_bindings | head -20
}

# Check for alarms
check_alarms() {
    log "=== Alarm Check ==="
    
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().')
    
    if [[ "$alarms" == "[]" ]]; then
        echo "✓ No alarms detected"
    else
        echo "✗ Alarms detected:"
        echo "$alarms"
    fi
}

# Check disk space
check_disk_space() {
    log "=== Disk Space Check ==="
    
    local rabbitmq_disk=$(df /var/lib/rabbitmq | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    local log_disk=$(df /var/log/rabbitmq | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    
    echo "RabbitMQ data directory usage: ${rabbitmq_disk}%"
    echo "RabbitMQ log directory usage: ${log_disk}%"
    
    if [[ $rabbitmq_disk -gt 80 ]]; then
        warn "RabbitMQ data directory is ${rabbitmq_disk}% full"
    fi
    
    if [[ $log_disk -gt 80 ]]; then
        warn "RabbitMQ log directory is ${log_disk}% full"
    fi
}

# Check memory usage
check_memory_usage() {
    log "=== Memory Usage Check ==="
    
    local memory_info=$(sudo rabbitmqctl status | grep -A 5 "Memory")
    echo "$memory_info"
    
    # Extract memory usage percentage
    local memory_pct=$(echo "$memory_info" | grep "memory" | awk '{print $2}' | cut -d'%' -f1)
    
    if [[ -n "$memory_pct" && $memory_pct -gt 80 ]]; then
        warn "RabbitMQ memory usage is high: ${memory_pct}%"
    fi
}

# Check connection limits
check_connection_limits() {
    log "=== Connection Limits Check ==="
    
    local conn_count=$(sudo rabbitmqctl list_connections | wc -l)
    local max_connections=$(sudo rabbitmqctl environment | grep connection_max | awk '{print $2}')
    
    echo "Current connections: $((conn_count - 1))"
    echo "Maximum connections: $max_connections"
    
    if [[ $((conn_count - 1)) -gt $((max_connections * 80 / 100)) ]]; then
        warn "Connection count is approaching limit"
    fi
}

# Check queue health
check_queue_health() {
    log "=== Queue Health Check ==="
    
    echo "Queue Statistics:"
    sudo rabbitmqctl list_queues name messages consumers | head -20
    
    # Check for queues with high message counts
    local high_message_queues=$(sudo rabbitmqctl list_queues name messages | awk 'NR>1 && $2>1000 {print $1 ":" $2}')
    
    if [[ -n "$high_message_queues" ]]; then
        warn "Queues with high message counts:"
        echo "$high_message_queues"
    fi
}

# Generate monitoring report
generate_report() {
    local report_file="$MONITORING_DIR/rabbitmq-report-$(date +%Y%m%d_%H%M%S).txt"
    
    log "Generating monitoring report: $report_file"
    
    mkdir -p "$MONITORING_DIR"
    
    {
        echo "=== RabbitMQ Monitoring Report ==="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo ""
        
        echo "=== System Metrics ==="
        get_system_metrics
        echo ""
        
        echo "=== RabbitMQ Metrics ==="
        get_rabbitmq_metrics
        echo ""
        
        echo "=== Alarm Check ==="
        check_alarms
        echo ""
        
        echo "=== Disk Space Check ==="
        check_disk_space
        echo ""
        
        echo "=== Memory Usage Check ==="
        check_memory_usage
        echo ""
        
        echo "=== Connection Limits Check ==="
        check_connection_limits
        echo ""
        
        echo "=== Queue Health Check ==="
        check_queue_health
        
    } > "$report_file"
    
    log "Monitoring report generated: $report_file"
}

# Real-time monitoring
real_time_monitor() {
    log "Starting real-time monitoring (Press Ctrl+C to stop)..."
    
    while true; do
        clear
        echo "=== RabbitMQ Real-Time Monitor - $(date) ==="
        echo ""
        
        # Service status
        if check_service_status; then
            echo "✓ Service: Running"
        else
            echo "✗ Service: Stopped"
        fi
        
        # Memory usage
        echo ""
        echo "Memory Usage:"
        sudo rabbitmqctl status | grep -A 3 "Memory"
        
        # Connection count
        local conn_count=$(sudo rabbitmqctl list_connections | wc -l)
        echo ""
        echo "Active Connections: $((conn_count - 1))"
        
        # Queue count
        local queue_count=$(sudo rabbitmqctl list_queues | wc -l)
        echo "Total Queues: $((queue_count - 1))"
        
        # Disk usage
        echo ""
        echo "Disk Usage:"
        df -h /var/lib/rabbitmq /var/log/rabbitmq | tail -2
        
        # Load average
        echo ""
        echo "Load Average:"
        uptime | awk -F'load average:' '{print $2}'
        
        sleep 5
    done
}

# Health check
health_check() {
    log "=== RabbitMQ Health Check ==="
    
    local health_status=0
    
    # Check service status
    if ! check_service_status; then
        error "RabbitMQ service is not running"
        health_status=1
    fi
    
    # Check node health
    if ! sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
        error "RabbitMQ node health check failed"
        health_status=1
    fi
    
    # Check for alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().')
    if [[ "$alarms" != "[]" ]]; then
        warn "Alarms detected: $alarms"
        health_status=1
    fi
    
    # Check disk space
    local rabbitmq_disk=$(df /var/lib/rabbitmq | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    if [[ $rabbitmq_disk -gt 90 ]]; then
        error "RabbitMQ data directory is ${rabbitmq_disk}% full"
        health_status=1
    fi
    
    # Check memory usage
    local memory_pct=$(sudo rabbitmqctl status | grep "memory" | awk '{print $2}' | cut -d'%' -f1)
    if [[ -n "$memory_pct" && $memory_pct -gt 90 ]]; then
        error "RabbitMQ memory usage is critical: ${memory_pct}%"
        health_status=1
    fi
    
    if [[ $health_status -eq 0 ]]; then
        log "✓ RabbitMQ health check passed"
    else
        error "✗ RabbitMQ health check failed"
    fi
    
    return $health_status
}

# Performance metrics
performance_metrics() {
    log "=== Performance Metrics ==="
    
    echo "1. Message Rates:"
    sudo rabbitmqctl list_queues name message_stats.publish_details.rate message_stats.deliver_details.rate | head -10
    
    echo ""
    echo "2. Connection Rates:"
    sudo rabbitmqctl list_connections name state | head -10
    
    echo ""
    echo "3. Channel Rates:"
    sudo rabbitmqctl list_channels name state | head -10
    
    echo ""
    echo "4. Exchange Rates:"
    sudo rabbitmqctl list_exchanges name type | head -10
}

# Show usage information
show_usage() {
    cat << EOF
RabbitMQ Non-Root Monitoring Script

Usage: $0 <command> [options]

Commands:
    system-metrics          Show system metrics
    rabbitmq-metrics        Show RabbitMQ metrics
    alarms                 Check for alarms
    disk-space             Check disk space usage
    memory-usage           Check memory usage
    connection-limits      Check connection limits
    queue-health           Check queue health
    health-check           Perform comprehensive health check
    performance-metrics    Show performance metrics
    generate-report        Generate monitoring report
    real-time              Start real-time monitoring
    help                   Show this help message

Examples:
    $0 system-metrics
    $0 rabbitmq-metrics
    $0 health-check
    $0 generate-report
    $0 real-time

EOF
}

# Main function
main() {
    check_user
    
    case "${1:-help}" in
        system-metrics)
            get_system_metrics
            ;;
        rabbitmq-metrics)
            get_rabbitmq_metrics
            ;;
        alarms)
            check_alarms
            ;;
        disk-space)
            check_disk_space
            ;;
        memory-usage)
            check_memory_usage
            ;;
        connection-limits)
            check_connection_limits
            ;;
        queue-health)
            check_queue_health
            ;;
        health-check)
            health_check
            ;;
        performance-metrics)
            performance_metrics
            ;;
        generate-report)
            generate_report
            ;;
        real-time)
            real_time_monitor
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
