#!/bin/bash
# File: auto-force-boot.sh
# Auto Force Boot Recovery for RabbitMQ Cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=""
FORCE_BOOT_TIMEOUT=300  # 5 minutes
FORCE_IMMEDIATE="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅${NC} $message" ;;
        "error") echo -e "${RED}❌${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

usage() {
    echo "Auto Force Boot Recovery for RabbitMQ Cluster"
    echo ""
    echo "Usage: $0 -e <environment> [options]"
    echo ""
    echo "Required:"
    echo "  -e <env>     Environment name"
    echo ""
    echo "Options:"
    echo "  -t <timeout> Timeout in seconds before force boot (default: 300)"
    echo "  -f           Force boot immediately without waiting"
    echo "  -h           Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod                   # Wait 5 minutes then force boot if needed"
    echo "  $0 -e qa -f                  # Force boot immediately"
    echo "  $0 -e staging -t 600         # Wait 10 minutes then force boot"
    exit 1
}

while getopts "e:t:fh" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        t) FORCE_BOOT_TIMEOUT="$OPTARG" ;;
        f) FORCE_IMMEDIATE="true" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    print_status "error" "Environment required"
    usage
fi

# Load environment
print_status "info" "Loading environment configuration..."
if ! source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"; then
    print_status "error" "Failed to load environment: $ENVIRONMENT"
    exit 1
fi

print_status "info" "=== Auto Force Boot Recovery for $ENVIRONMENT_NAME ==="
print_status "info" "Cluster: $RABBITMQ_CLUSTER_NAME"
print_status "info" "Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"

# Check if cluster is already operational
print_status "info" "Checking current cluster status..."
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    print_status "success" "Cluster is already operational"
    sudo rabbitmqctl cluster_status
    exit 0
fi

print_status "warning" "Cluster not responding, initiating recovery process..."

# Check if RabbitMQ service is running
if ! sudo systemctl is-active rabbitmq-server >/dev/null 2>&1; then
    print_status "info" "RabbitMQ service is not running, starting it first..."
    sudo systemctl start rabbitmq-server
    sleep 30
    
    # Check again after starting service
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        print_status "success" "Cluster recovered after service start"
        exit 0
    fi
fi

# Wait for timeout or force immediate
if [ "$FORCE_IMMEDIATE" != "true" ]; then
    print_status "info" "Waiting ${FORCE_BOOT_TIMEOUT}s for automatic recovery..."
    print_status "info" "Press Ctrl+C to skip waiting and force boot immediately"
    
    local waited=0
    while [ $waited -lt $FORCE_BOOT_TIMEOUT ]; do
        # Check every 30 seconds during wait
        if [ $((waited % 30)) -eq 0 ] && [ $waited -gt 0 ]; then
            if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
                print_status "success" "Cluster recovered automatically during wait"
                exit 0
            fi
            print_status "info" "Still waiting... ($waited/${FORCE_BOOT_TIMEOUT}s)"
        fi
        sleep 10
        waited=$((waited + 10))
    done
    
    # Final check after timeout
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        print_status "success" "Cluster recovered automatically"
        exit 0
    fi
fi

print_status "warning" "Automatic recovery failed or timeout reached, forcing boot..."

# Create backup before force boot
BACKUP_DIR="/backup/force-boot-$(date +%Y%m%d-%H%M%S)-$ENVIRONMENT"
print_status "info" "Creating backup before force boot: $BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"

# Backup Mnesia database if possible
if [ -d "/var/lib/rabbitmq/mnesia" ]; then
    sudo cp -r /var/lib/rabbitmq/mnesia "$BACKUP_DIR/" 2>/dev/null || print_status "warning" "Could not backup Mnesia database"
fi

# Backup configuration
sudo cp -r /etc/rabbitmq "$BACKUP_DIR/" 2>/dev/null || print_status "warning" "Could not backup configuration"

print_status "info" "Backup completed: $BACKUP_DIR"

# Stop RabbitMQ application
print_status "info" "Stopping RabbitMQ application..."
sudo rabbitmqctl stop_app 2>/dev/null || true

# Force boot
print_status "warning" "Force booting cluster..."
if sudo rabbitmqctl force_boot; then
    print_status "success" "Force boot command executed successfully"
else
    print_status "error" "Force boot command failed"
    exit 1
fi

# Start application
print_status "info" "Starting RabbitMQ application..."
if sudo rabbitmqctl start_app; then
    print_status "success" "RabbitMQ application started"
else
    print_status "error" "Failed to start RabbitMQ application"
    exit 1
fi

# Verify recovery
print_status "info" "Verifying cluster recovery..."
sleep 10

if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    print_status "success" "Force boot successful, cluster recovered!"
    
    # Show cluster status
    print_status "info" "Current cluster status:"
    sudo rabbitmqctl cluster_status
    
    # Check cluster name
    ACTUAL_CLUSTER_NAME=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' | sed 's/<<"\(.*\)">>/\1/')
    if [ "$ACTUAL_CLUSTER_NAME" = "$RABBITMQ_CLUSTER_NAME" ]; then
        print_status "success" "Cluster name verified: $ACTUAL_CLUSTER_NAME"
    else
        print_status "warning" "Cluster name mismatch: expected $RABBITMQ_CLUSTER_NAME, got $ACTUAL_CLUSTER_NAME"
    fi
    
    # Trigger other nodes to rejoin
    print_status "info" "Notifying other nodes to rejoin cluster..."
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" != "$(hostname)" ]; then
            print_status "info" "Triggering rejoin on $hostname..."
            if ssh -o ConnectTimeout=5 "root@$hostname" "systemctl restart rabbitmq-server" >/dev/null 2>&1 &; then
                print_status "info" "Restart command sent to $hostname"
            else
                print_status "warning" "Could not reach $hostname for restart"
            fi
        fi
    done
    
    # Wait for other nodes to join
    print_status "info" "Waiting 60 seconds for other nodes to rejoin..."
    sleep 60
    
    # Final cluster status
    print_status "info" "Final cluster status after node rejoin:"
    sudo rabbitmqctl cluster_status
    
    # Count running nodes
    RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    EXPECTED_NODES=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
    
    if [ $RUNNING_NODES -eq $EXPECTED_NODES ]; then
        print_status "success" "All nodes successfully rejoined cluster ($RUNNING_NODES/$EXPECTED_NODES)"
    else
        print_status "warning" "Some nodes still missing ($RUNNING_NODES/$EXPECTED_NODES running)"
        print_status "info" "You may need to manually restart missing nodes"
    fi
    
    # Verify no alarms
    ALARMS=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
    if [ "$ALARMS" = "[]" ]; then
        print_status "success" "No resource alarms detected"
    else
        print_status "warning" "Resource alarms detected: $ALARMS"
    fi
    
    print_status "success" "Force boot recovery completed successfully!"
    
else
    print_status "error" "Force boot failed - cluster still not operational"
    print_status "info" "Check logs for more information:"
    print_status "info" "  sudo journalctl -u rabbitmq-server -f"
    print_status "info" "  sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log"
    exit 1
fi

# Summary
echo ""
print_status "info" "=== Recovery Summary ==="
echo "  Environment: $ENVIRONMENT_NAME"
echo "  Cluster: $RABBITMQ_CLUSTER_NAME"
echo "  Recovery Method: Force Boot"
echo "  Backup Location: $BACKUP_DIR"
echo "  Running Nodes: $RUNNING_NODES/$EXPECTED_NODES"
echo "  Status: $([ $RUNNING_NODES -eq $EXPECTED_NODES ] && echo "✅ Complete" || echo "⚠ Partial")"
echo ""

print_status "info" "Next steps:"
echo "  1. Monitor cluster for stability"
echo "  2. Verify all applications can connect"
echo "  3. Check queue states and message counts"
echo "  4. Review logs for any errors"

if [ $RUNNING_NODES -lt $EXPECTED_NODES ]; then
    echo "  5. Manually restart missing nodes if needed"
fi