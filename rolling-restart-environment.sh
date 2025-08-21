#!/bin/bash
# File: rolling-restart-environment.sh
# Environment-Aware RabbitMQ Rolling Restart Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT=""
WAIT_TIME=30
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_INTERVAL=5
FORCE_RESTART="false"
SKIP_VALIDATION="false"

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
    case $status in
        "success") echo -e "${GREEN}✓${NC} $message" ;;
        "error") echo -e "${RED}✗${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

# Function to display usage
usage() {
    echo "Environment-Aware RabbitMQ Rolling Restart"
    echo ""
    echo "Usage: $0 -e <environment> [options]"
    echo ""
    echo "Required Arguments:"
    echo "  -e <environment>   Environment name (qa, staging, prod, etc.)"
    echo ""
    echo "Options:"
    echo "  -w <seconds>       Wait time between node restarts (default: 30)"
    echo "  -r <count>         Health check retries (default: 10)"
    echo "  -i <seconds>       Health check interval (default: 5)"
    echo "  -f                 Force restart (skip confirmations)"
    echo "  -s                 Skip pre-restart validation"
    echo "  -h                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod                    # Rolling restart production cluster"
    echo "  $0 -e qa -w 60               # QA restart with 60s wait time"
    echo "  $0 -e staging -f             # Force restart staging without prompts"
    exit 1
}

# Parse command line arguments
while getopts "e:w:r:i:fsh" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        w) WAIT_TIME="$OPTARG" ;;
        r) HEALTH_CHECK_RETRIES="$OPTARG" ;;
        i) HEALTH_CHECK_INTERVAL="$OPTARG" ;;
        f) FORCE_RESTART="true" ;;
        s) SKIP_VALIDATION="true" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$ENVIRONMENT" ]; then
    print_status "error" "Environment is required"
    usage
fi

print_status "info" "Starting environment-aware rolling restart"
print_status "info" "Environment: $ENVIRONMENT"

# Load environment configuration
print_status "info" "Loading environment configuration..."
if ! source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"; then
    print_status "error" "Failed to load environment: $ENVIRONMENT"
    exit 1
fi

print_status "success" "Environment loaded: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
print_status "info" "Cluster Name: $RABBITMQ_CLUSTER_NAME"
print_status "info" "Cluster Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"

# Get cluster nodes as array
CLUSTER_NODES_ARRAY=($RABBITMQ_CLUSTER_HOSTNAMES)
CURRENT_NODE=$(hostname)
PRIMARY_NODE="$RABBITMQ_NODE_1_HOSTNAME"

print_status "info" "Current node: $CURRENT_NODE"
print_status "info" "Primary node: $PRIMARY_NODE"

# Function to wait for node health
wait_for_node_health() {
    local node_hostname=$1
    local retries=$HEALTH_CHECK_RETRIES
    
    print_status "info" "Waiting for $node_hostname to become healthy..."
    
    while [ $retries -gt 0 ]; do
        if [ "$node_hostname" = "$CURRENT_NODE" ]; then
            # Local node health check
            if sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
                print_status "success" "Node $node_hostname is healthy"
                return 0
            fi
        else
            # Remote node health check
            if ssh "root@$node_hostname" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
                print_status "success" "Node $node_hostname is healthy"
                return 0
            fi
        fi
        
        print_status "info" "Node $node_hostname not ready, retrying in $HEALTH_CHECK_INTERVAL seconds... ($retries retries left)"
        sleep $HEALTH_CHECK_INTERVAL
        retries=$((retries - 1))
    done
    
    print_status "error" "Node $node_hostname failed to become healthy"
    return 1
}

# Function to wait for cluster quorum
wait_for_cluster_quorum() {
    local retries=$HEALTH_CHECK_RETRIES
    
    print_status "info" "Waiting for cluster quorum..."
    
    while [ $retries -gt 0 ]; do
        if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
            local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
            
            if [ $running_nodes -ge 2 ]; then
                print_status "success" "Cluster quorum maintained ($running_nodes nodes running)"
                return 0
            fi
        fi
        
        print_status "info" "Waiting for quorum... ($retries retries left)"
        sleep $HEALTH_CHECK_INTERVAL
        retries=$((retries - 1))
    done
    
    print_status "error" "Cluster quorum not achieved"
    return 1
}

# Function to restart a node
restart_node() {
    local node_hostname=$1
    local is_primary=$2
    
    print_status "info" "=== Restarting node: $node_hostname ==="
    
    if [ "$node_hostname" = "$CURRENT_NODE" ]; then
        # Local node restart
        print_status "info" "Restarting local node..."
        
        # Graceful shutdown
        print_status "info" "Stopping RabbitMQ application..."
        sudo rabbitmqctl stop_app
        
        # Restart service
        print_status "info" "Restarting RabbitMQ service..."
        sudo systemctl restart rabbitmq-server
        
        # Wait for startup
        print_status "info" "Waiting for service startup..."
        sleep $WAIT_TIME
        
        # Start application
        print_status "info" "Starting RabbitMQ application..."
        sudo rabbitmqctl start_app
        
    else
        # Remote node restart
        print_status "info" "Restarting remote node..."
        
        # Graceful shutdown
        print_status "info" "Stopping RabbitMQ application on $node_hostname..."
        ssh "root@$node_hostname" "rabbitmqctl stop_app"
        
        # Restart service
        print_status "info" "Restarting RabbitMQ service on $node_hostname..."
        ssh "root@$node_hostname" "systemctl restart rabbitmq-server"
        
        # Wait for startup
        print_status "info" "Waiting for service startup on $node_hostname..."
        sleep $WAIT_TIME
        
        # Start application
        print_status "info" "Starting RabbitMQ application on $node_hostname..."
        ssh "root@$node_hostname" "rabbitmqctl start_app"
    fi
    
    # Wait for node to become healthy
    if ! wait_for_node_health "$node_hostname"; then
        print_status "error" "Failed to restart $node_hostname"
        return 1
    fi
    
    # Wait for cluster quorum
    if ! wait_for_cluster_quorum; then
        print_status "error" "Cluster quorum lost after restarting $node_hostname"
        return 1
    fi
    
    print_status "success" "Node $node_hostname restarted successfully"
    return 0
}

# Function to run pre-restart validation
validate_pre_restart() {
    print_status "info" "Running pre-restart validation..."
    
    # Check cluster health
    if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        print_status "error" "Cluster status check failed"
        return 1
    fi
    
    # Get cluster status
    local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    local total_nodes=${#CLUSTER_NODES_ARRAY[@]}
    
    print_status "info" "Running nodes: $running_nodes/$total_nodes"
    
    if [ $running_nodes -lt 3 ]; then
        print_status "warning" "Less than 3 nodes running. Rolling restart not recommended."
        if [ "$FORCE_RESTART" = "false" ]; then
            read -p "Continue anyway? (y/n): " continue_restart
            if [ "$continue_restart" != "y" ]; then
                return 1
            fi
        fi
    fi
    
    if [ $running_nodes -ne $total_nodes ]; then
        print_status "warning" "Not all nodes are running. Fix cluster before restart."
        if [ "$FORCE_RESTART" = "false" ]; then
            read -p "Continue anyway? (y/n): " continue_restart
            if [ "$continue_restart" != "y" ]; then
                return 1
            fi
        fi
    fi
    
    # Check for resource alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null)
    if [ "$alarms" != "[]" ]; then
        print_status "warning" "Resource alarms detected: $alarms"
        if [ "$FORCE_RESTART" = "false" ]; then
            read -p "Continue anyway? (y/n): " continue_restart
            if [ "$continue_restart" != "y" ]; then
                return 1
            fi
        fi
    fi
    
    # Check for network partitions
    local partitions=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null)
    if [ "$partitions" != "[]" ]; then
        print_status "warning" "Network partitions detected: $partitions"
        if [ "$FORCE_RESTART" = "false" ]; then
            read -p "Continue anyway? (y/n): " continue_restart
            if [ "$continue_restart" != "y" ]; then
                return 1
            fi
        fi
    fi
    
    print_status "success" "Pre-restart validation completed"
    return 0
}

# Function to validate post-restart
validate_post_restart() {
    print_status "info" "=== Post-Restart Cluster Validation ==="
    
    # Check cluster status
    print_status "info" "Cluster status:"
    if ! sudo rabbitmqctl cluster_status; then
        print_status "error" "Cluster status check failed"
        return 1
    fi
    
    # Check all nodes are running
    local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    local total_nodes=${#CLUSTER_NODES_ARRAY[@]}
    
    print_status "info" "Node count validation:"
    print_status "info" "Running nodes: $running_nodes"
    print_status "info" "Total nodes: $total_nodes"
    
    if [ $running_nodes -eq $total_nodes ]; then
        print_status "success" "All nodes are running"
    else
        print_status "error" "Not all nodes are running"
        return 1
    fi
    
    # Check for alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().')
    if [ "$alarms" = "[]" ]; then
        print_status "success" "No resource alarms"
    else
        print_status "warning" "Alarms detected: $alarms"
    fi
    
    # Verify cluster name
    local actual_cluster_name=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' | sed 's/<<"\(.*\)">>/\1/')
    if [ "$actual_cluster_name" = "$RABBITMQ_CLUSTER_NAME" ]; then
        print_status "success" "Cluster name verified: $actual_cluster_name"
    else
        print_status "warning" "Cluster name mismatch. Expected: $RABBITMQ_CLUSTER_NAME, Actual: $actual_cluster_name"
    fi
    
    print_status "success" "Post-restart validation completed successfully"
    return 0
}

# Main rolling restart procedure
main() {
    print_status "info" "Starting rolling restart procedure for environment: $ENVIRONMENT_NAME"
    
    # Pre-restart validation
    if [ "$SKIP_VALIDATION" = "false" ]; then
        if ! validate_pre_restart; then
            print_status "error" "Pre-restart validation failed. Aborting restart."
            exit 1
        fi
    fi
    
    # Show restart plan
    print_status "info" "Rolling restart plan:"
    print_status "info" "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
    print_status "info" "Cluster: $RABBITMQ_CLUSTER_NAME"
    print_status "info" "Nodes: ${CLUSTER_NODES_ARRAY[*]}"
    print_status "info" "Primary node: $PRIMARY_NODE (will be restarted last)"
    print_status "info" "Wait time between restarts: ${WAIT_TIME}s"
    
    if [ "$FORCE_RESTART" = "false" ]; then
        echo ""
        read -p "Proceed with rolling restart? (y/n): " proceed
        if [ "$proceed" != "y" ]; then
            print_status "info" "Rolling restart cancelled by user"
            exit 0
        fi
    fi
    
    # Create backup before restart
    print_status "info" "Creating pre-restart backup..."
    backup_dir="/backup/rabbitmq-restart-$(date +%Y%m%d-%H%M%S)-$ENVIRONMENT"
    sudo mkdir -p "$backup_dir"
    sudo rabbitmqctl export_definitions "$backup_dir/definitions.json"
    sudo cp -r /etc/rabbitmq "$backup_dir/"
    sudo rabbitmqctl cluster_status > "$backup_dir/cluster-status.txt"
    print_status "success" "Backup created: $backup_dir"
    
    # Restart secondary nodes first
    print_status "info" "Phase 1: Restarting secondary nodes..."
    for node in "${CLUSTER_NODES_ARRAY[@]}"; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            if ! restart_node "$node" "false"; then
                print_status "error" "Failed to restart secondary node $node. Aborting."
                exit 1
            fi
            
            print_status "info" "Waiting ${WAIT_TIME}s before next restart..."
            sleep $WAIT_TIME
        fi
    done
    
    # Restart primary node last
    print_status "info" "Phase 2: Restarting primary node..."
    if ! restart_node "$PRIMARY_NODE" "true"; then
        print_status "error" "Failed to restart primary node $PRIMARY_NODE. Aborting."
        exit 1
    fi
    
    # Final validation
    print_status "info" "Phase 3: Final validation..."
    if ! validate_post_restart; then
        print_status "error" "Post-restart validation failed!"
        exit 1
    fi
    
    print_status "success" "🎉 Rolling restart completed successfully!"
    
    # Show summary
    echo ""
    echo "=== Rolling Restart Summary ==="
    echo "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
    echo "Cluster: $RABBITMQ_CLUSTER_NAME"
    echo "Nodes restarted: ${CLUSTER_NODES_ARRAY[*]}"
    echo "Backup location: $backup_dir"
    echo "Management UI: http://$PRIMARY_NODE:$RABBITMQ_MANAGEMENT_PORT"
    echo ""
    print_status "success" "All nodes have been restarted seamlessly!"
}

# Run main procedure
main "$@"