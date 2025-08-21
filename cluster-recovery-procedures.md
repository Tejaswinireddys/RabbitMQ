# RabbitMQ Cluster Recovery Procedures

## Immediate Recovery Steps

### Step 1: Restore Your Cluster Right Now

```bash
#!/bin/bash
# File: restore-cluster-now.sh

echo "=== RabbitMQ Cluster Recovery Procedure ==="

# Check current situation
echo "1. Checking current node status..."
echo "Current node ($(hostname)):"
sudo systemctl status rabbitmq-server | grep "Active:"

# Get cluster nodes from configuration
echo -e "\n2. Identifying cluster nodes..."
CLUSTER_NODES=$(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort -u)
echo "Configured cluster nodes:"
echo "$CLUSTER_NODES"

# Test connectivity to other nodes
echo -e "\n3. Testing connectivity to other nodes..."
for node in $CLUSTER_NODES; do
    if [ "$node" != "$(hostname)" ]; then
        echo -n "Testing $node: "
        if ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
            echo "✓ Network reachable"
            
            # Check if RabbitMQ service is running
            echo -n "  RabbitMQ service: "
            if ssh -o ConnectTimeout=5 "root@$node" "systemctl is-active rabbitmq-server" 2>/dev/null | grep -q "active"; then
                echo "✓ Running"
            else
                echo "✗ Stopped"
                
                # Offer to start this node
                read -p "  Start RabbitMQ on $node? (y/n): " start_node
                if [ "$start_node" = "y" ]; then
                    echo "  Starting RabbitMQ on $node..."
                    ssh "root@$node" "systemctl start rabbitmq-server"
                    echo "  ✓ Service start command sent"
                fi
            fi
        else
            echo "✗ Network unreachable"
        fi
    fi
done

# Wait for cluster recovery
echo -e "\n4. Waiting for cluster recovery..."
sleep 30

# Test cluster status
echo -e "\n5. Testing cluster status..."
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "✅ Cluster is operational!"
    echo -e "\nCluster Status:"
    sudo rabbitmqctl cluster_status
else
    echo "❌ Cluster still not operational"
    echo "Try starting another node or check logs:"
    echo "  sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log"
fi
```

### Step 2: Manual Recovery Commands

```bash
# Quick manual recovery (run these commands in order):

# A. Check what nodes you have configured
grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf

# B. Start RabbitMQ on any one stopped node
ssh root@node2 "systemctl start rabbitmq-server"
# OR
ssh root@node3 "systemctl start rabbitmq-server"

# C. Wait 30 seconds
sleep 30

# D. Test if cluster is working
sudo rabbitmqctl cluster_status

# E. If still not working, check logs
sudo tail -20 /var/log/rabbitmq/rabbit@$(hostname).log
```

### Step 3: Advanced Recovery with Validation

```bash
#!/bin/bash
# File: advanced-cluster-recovery.sh

set -e

echo "=== Advanced Cluster Recovery with Full Validation ==="

# Function to check if a node is responsive
check_node_responsive() {
    local node=$1
    local timeout=5
    
    echo "Checking if $node is responsive..."
    
    # Check network connectivity
    if ! ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
        echo "  ✗ Network unreachable"
        return 1
    fi
    
    # Check SSH connectivity
    if ! ssh -o ConnectTimeout=5 "root@$node" "echo 'SSH OK'" >/dev/null 2>&1; then
        echo "  ✗ SSH unreachable"
        return 1
    fi
    
    # Check if RabbitMQ service exists
    if ! ssh "root@$node" "systemctl list-unit-files | grep rabbitmq-server" >/dev/null 2>&1; then
        echo "  ✗ RabbitMQ service not installed"
        return 1
    fi
    
    echo "  ✓ Node is responsive"
    return 0
}

# Function to start RabbitMQ on a node
start_rabbitmq_on_node() {
    local node=$1
    
    echo "Starting RabbitMQ on $node..."
    
    # Check current service status
    local current_status=$(ssh "root@$node" "systemctl is-active rabbitmq-server" 2>/dev/null || echo "unknown")
    echo "  Current status: $current_status"
    
    if [ "$current_status" = "active" ]; then
        echo "  ✓ Already running"
        return 0
    fi
    
    # Start the service
    echo "  Starting service..."
    ssh "root@$node" "systemctl start rabbitmq-server"
    
    # Wait for startup
    echo "  Waiting for startup..."
    local retries=12
    while [ $retries -gt 0 ]; do
        local status=$(ssh "root@$node" "systemctl is-active rabbitmq-server" 2>/dev/null || echo "unknown")
        if [ "$status" = "active" ]; then
            echo "  ✓ Service started successfully"
            return 0
        fi
        echo "  Waiting... ($retries retries left)"
        sleep 5
        retries=$((retries - 1))
    done
    
    echo "  ✗ Service failed to start"
    return 1
}

# Function to wait for cluster quorum
wait_for_cluster_quorum() {
    echo "Waiting for cluster quorum restoration..."
    
    local retries=20
    while [ $retries -gt 0 ]; do
        if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
            echo "✅ Cluster quorum restored!"
            return 0
        fi
        
        echo "Waiting for quorum... ($retries retries left)"
        sleep 3
        retries=$((retries - 1))
    done
    
    echo "❌ Cluster quorum not restored within timeout"
    return 1
}

# Main recovery procedure
main() {
    echo "Starting advanced cluster recovery..."
    
    # Get cluster nodes from configuration
    CLUSTER_NODES=$(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort -u)
    CURRENT_NODE=$(hostname)
    
    echo "Cluster nodes: $CLUSTER_NODES"
    echo "Current node: $CURRENT_NODE"
    
    # Check current cluster state
    echo -e "\n=== Current Cluster State ==="
    echo "Testing cluster status on current node..."
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        echo "✅ Cluster is already operational!"
        sudo rabbitmqctl cluster_status
        exit 0
    else
        echo "❌ Cluster is not operational (expected for minority partition)"
    fi
    
    # Analyze each node
    echo -e "\n=== Node Analysis ==="
    declare -a available_nodes
    declare -a stopped_nodes
    
    for node in $CLUSTER_NODES; do
        if [ "$node" = "$CURRENT_NODE" ]; then
            echo "$node (current): Assumed running but paused"
            available_nodes+=("$node")
        else
            if check_node_responsive "$node"; then
                local rmq_status=$(ssh "root@$node" "systemctl is-active rabbitmq-server" 2>/dev/null || echo "inactive")
                if [ "$rmq_status" = "active" ]; then
                    echo "$node: ✓ Running"
                    available_nodes+=("$node")
                else
                    echo "$node: ✗ Service stopped"
                    stopped_nodes+=("$node")
                fi
            else
                echo "$node: ✗ Unreachable"
                stopped_nodes+=("$node")
            fi
        fi
    done
    
    echo -e "\nAvailable nodes: ${available_nodes[@]}"
    echo "Stopped/unreachable nodes: ${stopped_nodes[@]}"
    
    # Calculate if we need to start nodes
    total_nodes=${#CLUSTER_NODES[@]}
    running_nodes=${#available_nodes[@]}
    majority_needed=$(((total_nodes / 2) + 1))
    
    echo -e "\nCluster analysis:"
    echo "  Total nodes: $total_nodes"
    echo "  Currently running: $running_nodes"
    echo "  Majority needed: $majority_needed"
    
    if [ $running_nodes -ge $majority_needed ]; then
        echo "✅ Sufficient nodes for majority, waiting for recovery..."
        wait_for_cluster_quorum
    else
        nodes_to_start=$((majority_needed - running_nodes))
        echo "❌ Need to start $nodes_to_start more node(s)"
        
        # Start required nodes
        local started_count=0
        for node in "${stopped_nodes[@]}"; do
            if [ $started_count -ge $nodes_to_start ]; then
                break
            fi
            
            echo -e "\n=== Starting Node: $node ==="
            if check_node_responsive "$node"; then
                if start_rabbitmq_on_node "$node"; then
                    started_count=$((started_count + 1))
                    echo "✓ Successfully started $node"
                else
                    echo "✗ Failed to start $node"
                fi
            else
                echo "✗ Cannot start $node - not responsive"
            fi
        done
        
        if [ $started_count -gt 0 ]; then
            echo -e "\n=== Waiting for Cluster Recovery ==="
            wait_for_cluster_quorum
        else
            echo "❌ Failed to start any additional nodes"
            exit 1
        fi
    fi
    
    # Final validation
    echo -e "\n=== Final Validation ==="
    if sudo rabbitmqctl cluster_status; then
        echo -e "\n✅ Cluster recovery completed successfully!"
        
        # Additional checks
        echo -e "\n=== Additional Health Checks ==="
        echo "Node health check:"
        sudo rabbitmqctl node_health_check
        
        echo -e "\nQueue status:"
        sudo rabbitmqctl list_queues name messages type
        
        echo -e "\nResource alarms:"
        sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'
        
    else
        echo "❌ Cluster recovery failed"
        echo "Check logs for more information:"
        echo "  sudo journalctl -u rabbitmq-server -f"
        exit 1
    fi
}

# Run main procedure
main "$@"
```

## Emergency Recovery Procedures

### When Normal Recovery Fails

```bash
#!/bin/bash
# File: emergency-recovery.sh

echo "=== EMERGENCY Cluster Recovery ==="
echo "⚠️  WARNING: Use only when normal recovery fails"
echo "⚠️  WARNING: May cause temporary data inconsistency"

read -p "Are you sure you want to proceed with emergency recovery? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Emergency recovery aborted"
    exit 1
fi

echo "1. Creating backup before emergency recovery..."
BACKUP_DIR="/backup/emergency-recovery-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# Backup current state
sudo cp -r /var/lib/rabbitmq "$BACKUP_DIR/" 2>/dev/null || echo "Could not backup data directory"
sudo cp -r /etc/rabbitmq "$BACKUP_DIR/" 2>/dev/null || echo "Could not backup config directory"

echo "2. Stopping RabbitMQ application..."
sudo rabbitmqctl stop_app 2>/dev/null || echo "App already stopped"

echo "3. Force booting the cluster..."
sudo rabbitmqctl force_boot

echo "4. Starting RabbitMQ application..."
sudo rabbitmqctl start_app

echo "5. Testing cluster status..."
if sudo rabbitmqctl cluster_status; then
    echo "✅ Emergency recovery successful"
    echo ""
    echo "⚠️  IMPORTANT: Start other nodes ASAP to restore proper clustering"
    echo "⚠️  IMPORTANT: Verify data integrity after all nodes join"
else
    echo "❌ Emergency recovery failed"
    echo "Check logs: sudo journalctl -u rabbitmq-server -f"
fi
```

This recovery section provides immediate solutions to get your cluster operational again. The scripts are designed to handle different failure scenarios and provide clear guidance on what to do next.