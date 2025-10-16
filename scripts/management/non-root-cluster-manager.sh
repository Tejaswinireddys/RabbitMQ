#!/bin/bash

# RabbitMQ Non-Root Cluster Management Script
# Provides comprehensive cluster management for non-root users
# Version: 1.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")/../installation/rabbitmq-deployment"

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

# Start RabbitMQ service
start_service() {
    log "Starting RabbitMQ service..."
    sudo systemctl start rabbitmq-server
    sleep 5
    
    if check_service_status; then
        log "RabbitMQ service started successfully"
    else
        error "Failed to start RabbitMQ service"
        exit 1
    fi
}

# Stop RabbitMQ service
stop_service() {
    log "Stopping RabbitMQ service..."
    sudo systemctl stop rabbitmq-server
    
    if ! check_service_status; then
        log "RabbitMQ service stopped successfully"
    else
        error "Failed to stop RabbitMQ service"
        exit 1
    fi
}

# Restart RabbitMQ service
restart_service() {
    log "Restarting RabbitMQ service..."
    sudo systemctl restart rabbitmq-server
    sleep 5
    
    if check_service_status; then
        log "RabbitMQ service restarted successfully"
    else
        error "Failed to restart RabbitMQ service"
        exit 1
    fi
}

# Get cluster status
get_cluster_status() {
    log "Getting cluster status..."
    sudo rabbitmqctl cluster_status
}

# Join cluster
join_cluster() {
    local primary_node="$1"
    
    if [[ -z "$primary_node" ]]; then
        error "Primary node hostname is required"
        exit 1
    fi
    
    log "Joining cluster with primary node: $primary_node"
    
    # Stop app but keep Erlang VM running
    sudo rabbitmqctl stop_app
    
    # Reset node
    sudo rabbitmqctl reset
    
    # Join cluster
    sudo rabbitmqctl join_cluster "rabbit@$primary_node"
    
    # Start app
    sudo rabbitmqctl start_app
    
    log "Successfully joined cluster with $primary_node"
}

# Leave cluster
leave_cluster() {
    log "Leaving cluster..."
    
    # Stop app
    sudo rabbitmqctl stop_app
    
    # Reset node
    sudo rabbitmqctl reset
    
    # Start app
    sudo rabbitmqctl start_app
    
    log "Successfully left cluster"
}

# List cluster nodes
list_cluster_nodes() {
    log "Cluster nodes:"
    sudo rabbitmqctl cluster_status | grep -A 10 "Cluster nodes"
}

# Check node health
check_node_health() {
    log "Checking node health..."
    sudo rabbitmqctl node_health_check
}

# Get cluster overview
get_cluster_overview() {
    log "=== RabbitMQ Cluster Overview ==="
    
    echo "1. Service Status:"
    if check_service_status; then
        echo "   ✓ RabbitMQ service is running"
    else
        echo "   ✗ RabbitMQ service is not running"
    fi
    
    echo ""
    echo "2. Cluster Status:"
    get_cluster_status
    
    echo ""
    echo "3. Node Health:"
    check_node_health
    
    echo ""
    echo "4. Active Connections:"
    local conn_count=$(sudo rabbitmqctl list_connections | wc -l)
    echo "   Active connections: $((conn_count - 1))"
    
    echo ""
    echo "5. Queue Overview:"
    sudo rabbitmqctl list_queues name type messages consumers
    
    echo ""
    echo "6. Memory Usage:"
    sudo rabbitmqctl status | grep -A 3 "Memory"
    
    echo ""
    echo "7. Cluster Alarms:"
    sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'
}

# Backup cluster configuration
backup_cluster() {
    local backup_dir="$DEPLOYMENT_DIR/backup/$(date +%Y%m%d_%H%M%S)"
    
    log "Creating cluster backup in: $backup_dir"
    mkdir -p "$backup_dir"
    
    # Export definitions
    sudo rabbitmqctl export_definitions "$backup_dir/definitions.json"
    
    # Backup configuration files
    sudo cp /etc/rabbitmq/rabbitmq.conf "$backup_dir/" 2>/dev/null || true
    sudo cp /etc/rabbitmq/advanced.config "$backup_dir/" 2>/dev/null || true
    sudo cp /etc/rabbitmq/enabled_plugins "$backup_dir/" 2>/dev/null || true
    
    # Create system information snapshot
    cat > "$backup_dir/system_info.txt" << EOF
Backup Date: $(date)
Hostname: $(hostname)
RabbitMQ Version: $(sudo rabbitmqctl version)
Cluster Status: $(sudo rabbitmqctl cluster_status)
Queue List: $(sudo rabbitmqctl list_queues name type messages)
EOF
    
    log "Backup completed: $backup_dir"
}

# Restore cluster configuration
restore_cluster() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        error "Backup file path is required"
        exit 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log "Restoring cluster configuration from: $backup_file"
    
    # Stop RabbitMQ
    sudo systemctl stop rabbitmq-server
    
    # Import definitions
    sudo rabbitmqctl import_definitions "$backup_file"
    
    # Start RabbitMQ
    sudo systemctl start rabbitmq-server
    
    log "Cluster configuration restored successfully"
}

# List available backups
list_backups() {
    local backup_dir="$DEPLOYMENT_DIR/backup"
    
    if [[ -d "$backup_dir" ]]; then
        log "Available backups:"
        ls -la "$backup_dir"
    else
        warn "No backup directory found"
    fi
}

# Monitor cluster in real-time
monitor_cluster() {
    log "Starting real-time cluster monitoring (Press Ctrl+C to stop)..."
    
    while true; do
        clear
        echo "=== RabbitMQ Cluster Monitor - $(date) ==="
        echo ""
        
        # Service status
        if check_service_status; then
            echo "✓ Service: Running"
        else
            echo "✗ Service: Stopped"
        fi
        
        # Cluster status
        echo ""
        echo "Cluster Status:"
        sudo rabbitmqctl cluster_status | head -10
        
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
        
        sleep 5
    done
}

# Show usage information
show_usage() {
    cat << EOF
RabbitMQ Non-Root Cluster Management Script

Usage: $0 <command> [options]

Commands:
    start                   Start RabbitMQ service
    stop                    Stop RabbitMQ service
    restart                 Restart RabbitMQ service
    status                  Show service status
    cluster-status          Show cluster status
    join <primary-node>     Join cluster with primary node
    leave                   Leave cluster
    nodes                   List cluster nodes
    health                  Check node health
    overview                Show comprehensive cluster overview
    backup                  Create cluster backup
    restore <backup-file>   Restore cluster from backup
    list-backups            List available backups
    monitor                 Start real-time monitoring
    help                    Show this help message

Examples:
    $0 start
    $0 join node1
    $0 overview
    $0 backup
    $0 restore /path/to/backup/definitions.json
    $0 monitor

EOF
}

# Main function
main() {
    check_user
    
    case "${1:-help}" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            if check_service_status; then
                log "RabbitMQ service is running"
            else
                log "RabbitMQ service is not running"
            fi
            ;;
        cluster-status)
            get_cluster_status
            ;;
        join)
            join_cluster "$2"
            ;;
        leave)
            leave_cluster
            ;;
        nodes)
            list_cluster_nodes
            ;;
        health)
            check_node_health
            ;;
        overview)
            get_cluster_overview
            ;;
        backup)
            backup_cluster
            ;;
        restore)
            restore_cluster "$2"
            ;;
        list-backups)
            list_backups
            ;;
        monitor)
            monitor_cluster
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
