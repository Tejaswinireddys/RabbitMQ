#!/bin/bash
# RabbitMQ Cluster Auto-Recovery Script
# This script automatically recovers from common cluster issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT="${1:-qa}"
RECOVERY_MODE="${2:-auto}"
LOG_FILE="/var/log/rabbitmq/auto-recovery.log"
RECOVERY_LOG="/tmp/rabbitmq-recovery-actions.log"

# Load environment
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_recovery() {
    echo -e "${PURPLE}[RECOVERY]${NC} $1"
    echo "$(date): [RECOVERY] $1" >> "$LOG_FILE"
}

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    touch "$RECOVERY_LOG"
    print_info "Auto-recovery started for $ENVIRONMENT environment in $RECOVERY_MODE mode"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root for recovery operations"
        exit 1
    fi
}

# Check if RabbitMQ is running
check_rabbitmq_service() {
    if systemctl is-active --quiet rabbitmq-server; then
        print_status "RabbitMQ service is running"
        return 0
    else
        print_error "RabbitMQ service is not running"
        return 1
    fi
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

# Recover RabbitMQ service
recover_rabbitmq_service() {
    print_recovery "Attempting to recover RabbitMQ service..."
    
    # Stop service
    print_info "Stopping RabbitMQ service..."
    systemctl stop rabbitmq-server || true
    
    # Wait for service to stop
    sleep 5
    
    # Check if service is still running
    if systemctl is-active --quiet rabbitmq-server; then
        print_warning "Service is still running, forcing stop..."
        systemctl kill -9 rabbitmq-server || true
        sleep 2
    fi
    
    # Clean up any stale processes
    pkill -f rabbitmq || true
    sleep 2
    
    # Start service
    print_info "Starting RabbitMQ service..."
    systemctl start rabbitmq-server
    
    # Wait for service to start
    sleep 10
    
    # Check if service started successfully
    if systemctl is-active --quiet rabbitmq-server; then
        print_status "RabbitMQ service recovered successfully"
        return 0
    else
        print_error "Failed to recover RabbitMQ service"
        return 1
    fi
}

# Recover cluster membership
recover_cluster_membership() {
    print_recovery "Attempting to recover cluster membership..."
    
    # Get current node name
    CURRENT_NODE="rabbit@$(hostname)"
    
    # Check if we're already in a cluster
    CLUSTER_STATUS=$(rabbitmqctl cluster_status 2>/dev/null || echo "ERROR")
    
    if [[ "$CLUSTER_STATUS" != "ERROR" ]]; then
        CLUSTER_MEMBERS=$(echo "$CLUSTER_STATUS" | grep -c "rabbit@" || echo "0")
        if [[ $CLUSTER_MEMBERS -ge 2 ]]; then
            print_info "Already in cluster with $CLUSTER_MEMBERS members"
            return 0
        fi
    fi
    
    # Try to join cluster with primary node
    PRIMARY_NODE="rabbit@${RABBITMQ_NODE_1_HOSTNAME:-node1}"
    
    if [[ "$CURRENT_NODE" == "$PRIMARY_NODE" ]]; then
        print_info "This is the primary node, no need to join cluster"
        return 0
    fi
    
    print_info "Attempting to join cluster with $PRIMARY_NODE..."
    
    # Stop application but keep Erlang VM
    rabbitmqctl stop_app
    
    # Reset node
    rabbitmqctl reset
    
    # Join cluster
    if rabbitmqctl join_cluster "$PRIMARY_NODE"; then
        print_status "Successfully joined cluster with $PRIMARY_NODE"
        
        # Start application
        rabbitmqctl start_app
        
        # Wait for cluster to stabilize
        sleep 10
        
        # Verify cluster membership
        if check_cluster_status; then
            print_status "Cluster membership recovered successfully"
            return 0
        else
            print_warning "Cluster membership recovered but status check failed"
            return 1
        fi
    else
        print_error "Failed to join cluster with $PRIMARY_NODE"
        return 1
    fi
}

# Recover from network partitions
recover_network_partitions() {
    print_recovery "Attempting to recover from network partitions..."
    
    # Check for partitions
    CLUSTER_STATUS=$(rabbitmqctl cluster_status 2>/dev/null || echo "ERROR")
    
    if [[ "$CLUSTER_STATUS" != "ERROR" ]]; then
        PARTITIONS=$(echo "$CLUSTER_STATUS" | grep -A 10 "partitions" | grep "rabbit@" || echo "")
        
        if [[ -n "$PARTITIONS" ]]; then
            print_warning "Network partitions detected, attempting recovery..."
            
            # Try to heal partitions automatically
            if rabbitmqctl cluster_partition_healing on; then
                print_info "Enabled automatic partition healing"
                
                # Wait for healing to complete
                sleep 30
                
                # Check if partitions are resolved
                CLUSTER_STATUS_AFTER=$(rabbitmqctl cluster_status 2>/dev/null || echo "ERROR")
                PARTITIONS_AFTER=$(echo "$CLUSTER_STATUS_AFTER" | grep -A 10 "partitions" | grep "rabbit@" || echo "")
                
                if [[ -z "$PARTITIONS_AFTER" ]]; then
                    print_status "Network partitions recovered automatically"
                    return 0
                else
                    print_warning "Automatic partition healing failed, manual intervention may be required"
                    return 1
                fi
            else
                print_error "Failed to enable automatic partition healing"
                return 1
            fi
        else
            print_info "No network partitions detected"
            return 0
        fi
    else
        print_error "Cannot check for network partitions"
        return 1
    fi
}

# Recover queue consumers
recover_queue_consumers() {
    print_recovery "Attempting to recover queue consumers..."
    
    # Get queue information
    QUEUE_INFO=$(rabbitmqctl list_queues name messages consumers 2>/dev/null || echo "ERROR")
    
    if [[ "$QUEUE_INFO" == "ERROR" ]]; then
        print_error "Failed to get queue information"
        return 1
    fi
    
    # Check for queues with messages but no consumers
    QUEUES_WITHOUT_CONSUMERS=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[a-zA-Z] ]]; then
            QUEUE_NAME=$(echo "$line" | awk '{print $1}')
            MESSAGE_COUNT=$(echo "$line" | awk '{print $2}')
            CONSUMER_COUNT=$(echo "$line" | awk '{print $3}')
            
            if [[ "$MESSAGE_COUNT" -gt 0 && "$CONSUMER_COUNT" -eq 0 ]]; then
                print_warning "Queue $QUEUE_NAME has $MESSAGE_COUNT messages but no consumers"
                QUEUES_WITHOUT_CONSUMERS=$((QUEUES_WITHOUT_CONSUMERS + 1))
            fi
        fi
    done <<< "$QUEUE_INFO"
    
    if [[ $QUEUES_WITHOUT_CONSUMERS -gt 0 ]]; then
        print_warning "Found $QUEUES_WITHOUT_CONSUMERS queues without consumers"
        print_info "This may require application-level recovery - consumers need to reconnect"
        return 1
    else
        print_status "All queues have consumers"
        return 0
    fi
}

# Recover from high memory usage
recover_memory_usage() {
    print_recovery "Attempting to recover from high memory usage..."
    
    # Check memory usage
    MEMORY_INFO=$(rabbitmqctl status 2>/dev/null | grep -A 5 "Memory" || echo "ERROR")
    
    if [[ "$MEMORY_INFO" != "ERROR" ]]; then
        MEMORY_USAGE=$(echo "$MEMORY_INFO" | grep "total" | awk '{print $2}' | sed 's/,//')
        
        if [[ -n "$MEMORY_USAGE" ]]; then
            print_info "Current memory usage: $MEMORY_USAGE"
            
            # Try to force garbage collection
            print_info "Forcing garbage collection..."
            rabbitmqctl eval 'erlang:garbage_collect().'
            
            # Wait for GC to complete
            sleep 5
            
            # Check memory usage after GC
            MEMORY_INFO_AFTER=$(rabbitmqctl status 2>/dev/null | grep -A 5 "Memory" || echo "ERROR")
            MEMORY_USAGE_AFTER=$(echo "$MEMORY_INFO_AFTER" | grep "total" | awk '{print $2}' | sed 's/,//')
            
            if [[ -n "$MEMORY_USAGE_AFTER" ]]; then
                print_info "Memory usage after GC: $MEMORY_USAGE_AFTER"
                
                # Calculate memory reduction
                if [[ "$MEMORY_USAGE" != "$MEMORY_USAGE_AFTER" ]]; then
                    print_status "Memory usage reduced through garbage collection"
                    return 0
                else
                    print_warning "Garbage collection did not reduce memory usage"
                    return 1
                fi
            fi
        fi
    fi
    
    print_warning "Cannot determine memory usage, recovery status unknown"
    return 1
}

# Recover from disk space issues
recover_disk_space() {
    print_recovery "Attempting to recover from disk space issues..."
    
    # Check disk space
    DISK_FREE=$(df /var/lib/rabbitmq | tail -1 | awk '{print $4}')
    DISK_FREE_GB=$((DISK_FREE / 1024 / 1024))
    
    print_info "Current disk free space: ${DISK_FREE_GB}GB"
    
    if [[ $DISK_FREE_GB -lt 5 ]]; then
        print_warning "Low disk space detected, attempting cleanup..."
        
        # Clean up old log files
        print_info "Cleaning up old log files..."
        find /var/log/rabbitmq -name "*.log.*" -mtime +7 -delete 2>/dev/null || true
        
        # Clean up old crash dumps
        print_info "Cleaning up old crash dumps..."
        find /var/lib/rabbitmq -name "*.crashdump" -mtime +1 -delete 2>/dev/null || true
        
        # Check disk space after cleanup
        sleep 2
        DISK_FREE_AFTER=$(df /var/lib/rabbitmq | tail -1 | awk '{print $4}')
        DISK_FREE_AFTER_GB=$((DISK_FREE_AFTER / 1024 / 1024))
        
        print_info "Disk free space after cleanup: ${DISK_FREE_AFTER_GB}GB"
        
        if [[ $DISK_FREE_AFTER_GB -gt $DISK_FREE_GB ]]; then
            print_status "Disk space recovered through cleanup"
            return 0
        else
            print_warning "Cleanup did not significantly improve disk space"
            return 1
        fi
    else
        print_info "Sufficient disk space available"
        return 0
    fi
}

# Force cluster recovery (last resort)
force_cluster_recovery() {
    print_recovery "Attempting forced cluster recovery (last resort)..."
    
    # This is a destructive operation - only proceed in auto mode
    if [[ "$RECOVERY_MODE" != "auto" ]]; then
        print_warning "Forced recovery requires auto mode - skipping"
        return 1
    fi
    
    print_warning "This is a destructive operation that will reset the node"
    
    # Stop RabbitMQ
    systemctl stop rabbitmq-server
    
    # Wait for service to stop
    sleep 5
    
    # Backup important data
    BACKUP_DIR="/backup/rabbitmq/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d "/var/lib/rabbitmq/mnesia" ]]; then
        print_info "Backing up mnesia data..."
        cp -r /var/lib/rabbitmq/mnesia "$BACKUP_DIR/" || true
    fi
    
    if [[ -d "/etc/rabbitmq" ]]; then
        print_info "Backing up configuration..."
        cp -r /etc/rabbitmq "$BACKUP_DIR/" || true
    fi
    
    # Remove mnesia data
    print_info "Removing mnesia data..."
    rm -rf /var/lib/rabbitmq/mnesia/*
    
    # Start RabbitMQ
    print_info "Starting RabbitMQ with clean state..."
    systemctl start rabbitmq-server
    
    # Wait for service to start
    sleep 15
    
    # Check if service started
    if ! systemctl is-active --quiet rabbitmq-server; then
        print_error "Failed to start RabbitMQ after forced recovery"
        return 1
    fi
    
    # Try to rejoin cluster
    if recover_cluster_membership; then
        print_status "Forced cluster recovery completed successfully"
        return 0
    else
        print_error "Forced cluster recovery failed"
        return 1
    fi
}

# Main recovery function
perform_recovery() {
    print_info "Starting cluster recovery process..."
    
    # Initialize logging
    init_logging
    
    # Check if running as root
    check_root
    
    # Track recovery actions
    RECOVERY_ACTIONS=0
    SUCCESSFUL_RECOVERIES=0
    
    # Step 1: Check RabbitMQ service
    if ! check_rabbitmq_service; then
        print_recovery "Recovery needed: RabbitMQ service is down"
        RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
        
        if recover_rabbitmq_service; then
            SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
        fi
    fi
    
    # Step 2: Check cluster status
    if ! check_cluster_status; then
        print_recovery "Recovery needed: Cluster status is unhealthy"
        RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
        
        if recover_cluster_membership; then
            SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
        fi
    fi
    
    # Step 3: Check for network partitions
    RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
    if recover_network_partitions; then
        SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
    fi
    
    # Step 4: Check queue consumers
    RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
    if recover_queue_consumers; then
        SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
    fi
    
    # Step 5: Check memory usage
    RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
    if recover_memory_usage; then
        SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
    fi
    
    # Step 6: Check disk space
    RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
    if recover_disk_space; then
        SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
    fi
    
    # Final cluster status check
    if ! check_cluster_status; then
        print_warning "Cluster still unhealthy after recovery attempts"
        
        if [[ "$RECOVERY_MODE" == "auto" ]]; then
            print_recovery "Attempting forced cluster recovery..."
            RECOVERY_ACTIONS=$((RECOVERY_ACTIONS + 1))
            
            if force_cluster_recovery; then
                SUCCESSFUL_RECOVERIES=$((SUCCESSFUL_RECOVERIES + 1))
            fi
        else
            print_warning "Forced recovery skipped (not in auto mode)"
        fi
    fi
    
    # Generate recovery report
    echo ""
    echo "=== RabbitMQ Cluster Recovery Report ==="
    echo "Environment: $ENVIRONMENT"
    echo "Recovery Mode: $RECOVERY_MODE"
    echo "Timestamp: $(date)"
    echo "Total Recovery Actions: $RECOVERY_ACTIONS"
    echo "Successful Recoveries: $SUCCESSFUL_RECOVERIES"
    echo "Recovery Success Rate: $((SUCCESSFUL_RECOVERIES * 100 / RECOVERY_ACTIONS))%"
    echo ""
    
    # Log recovery summary
    print_info "Recovery completed: $SUCCESSFUL_RECOVERIES/$RECOVERY_ACTIONS actions successful"
    
    # Final status check
    if check_cluster_status; then
        print_status "Cluster recovery completed successfully"
        echo "Final Status: RECOVERED" >> "$LOG_FILE"
        exit 0
    else
        print_error "Cluster recovery failed - manual intervention required"
        echo "Final Status: FAILED" >> "$LOG_FILE"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [environment] [recovery_mode]"
        echo "  environment: qa, staging, prod (default: qa)"
        echo "  recovery_mode: auto, manual (default: auto)"
        echo ""
        echo "Recovery Modes:"
        echo "  auto:   Automatic recovery with forced recovery if needed"
        echo "  manual: Manual recovery without destructive operations"
        echo ""
        echo "This script automatically recovers from common RabbitMQ cluster issues."
        exit 0
        ;;
    *)
        perform_recovery "$@"
        ;;
esac
