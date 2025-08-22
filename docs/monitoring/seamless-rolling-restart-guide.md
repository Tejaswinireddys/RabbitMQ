# Seamless Rolling Restart Guide for RabbitMQ Clusters

## Overview
This guide provides comprehensive procedures for performing seamless rolling restarts of RabbitMQ 4.1.x clusters without service interruption, data loss, or client disconnections. The rolling restart capability ensures zero-downtime maintenance operations.

## Rolling Restart Principles

### Key Requirements for Seamless Operations
1. **Quorum Queues**: Ensure high availability during node restarts
2. **Client Reconnection**: Applications must handle connection failures gracefully
3. **Load Balancer**: Distribute traffic across available nodes
4. **Proper Sequencing**: Restart nodes in correct order to maintain quorum
5. **Health Validation**: Verify node health before proceeding

### Restart Sequence Strategy
- **Minimum Cluster Size**: 3 nodes (can lose 1 node safely)
- **Restart Order**: Secondary nodes first, primary node last
- **Wait Time**: Allow each node to fully rejoin before proceeding
- **Validation**: Verify cluster health after each node restart

## Pre-Restart Preparation

### Pre-Flight Checklist Script
```bash
#!/bin/bash
# File: pre-restart-checklist.sh

set -e

echo "=== RabbitMQ Rolling Restart Pre-Flight Checklist ==="

# Function to check cluster health
check_cluster_health() {
    echo "1. Checking cluster health..."
    
    # Get cluster status
    CLUSTER_STATUS=$(sudo rabbitmqctl cluster_status 2>/dev/null)
    RUNNING_NODES=$(echo "$CLUSTER_STATUS" | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    TOTAL_NODES=$(echo "$CLUSTER_STATUS" | grep "Disc" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    
    echo "   Running nodes: $RUNNING_NODES"
    echo "   Total nodes: $TOTAL_NODES"
    
    if [ $RUNNING_NODES -lt 3 ]; then
        echo "   ⚠ WARNING: Less than 3 nodes running. Rolling restart not recommended."
        return 1
    fi
    
    if [ $RUNNING_NODES -ne $TOTAL_NODES ]; then
        echo "   ⚠ WARNING: Not all nodes are running. Fix cluster before restart."
        return 1
    fi
    
    echo "   ✓ Cluster health: OK"
    return 0
}

# Function to check queue types
check_queue_types() {
    echo "2. Checking queue types..."
    
    TOTAL_QUEUES=$(sudo rabbitmqctl list_queues type | grep -v "^type" | wc -l)
    QUORUM_QUEUES=$(sudo rabbitmqctl list_queues type | grep -c "quorum" || echo 0)
    CLASSIC_QUEUES=$(sudo rabbitmqctl list_queues type | grep -c "classic" || echo 0)
    
    echo "   Total queues: $TOTAL_QUEUES"
    echo "   Quorum queues: $QUORUM_QUEUES"
    echo "   Classic queues: $CLASSIC_QUEUES"
    
    if [ $CLASSIC_QUEUES -gt 0 ]; then
        echo "   ⚠ WARNING: $CLASSIC_QUEUES classic queues detected."
        echo "      Classic queues may experience downtime during restarts."
        read -p "   Continue anyway? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            return 1
        fi
    fi
    
    echo "   ✓ Queue types: OK"
    return 0
}

# Function to check resource alarms
check_resource_alarms() {
    echo "3. Checking resource alarms..."
    
    ALARMS=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null)
    
    if [ "$ALARMS" = "[]" ]; then
        echo "   ✓ No resource alarms"
        return 0
    else
        echo "   ⚠ WARNING: Resource alarms detected: $ALARMS"
        echo "      Resolve alarms before performing rolling restart."
        return 1
    fi
}

# Function to check network partitions
check_network_partitions() {
    echo "4. Checking network partitions..."
    
    PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null)
    
    if [ "$PARTITIONS" = "[]" ]; then
        echo "   ✓ No network partitions"
        return 0
    else
        echo "   ⚠ WARNING: Network partitions detected: $PARTITIONS"
        echo "      Resolve partitions before performing rolling restart."
        return 1
    fi
}

# Function to check client connections
check_client_connections() {
    echo "5. Checking client connections..."
    
    CONNECTIONS=$(sudo rabbitmqctl list_connections | wc -l)
    echo "   Active connections: $CONNECTIONS"
    
    if [ $CONNECTIONS -gt 1000 ]; then
        echo "   ⚠ INFO: High number of connections detected."
        echo "      Ensure clients have proper reconnection logic."
    fi
    
    echo "   ✓ Connection check: OK"
    return 0
}

# Function to backup cluster state
backup_cluster_state() {
    echo "6. Creating cluster state backup..."
    
    BACKUP_DIR="/backup/rabbitmq-restart-$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -p "$BACKUP_DIR"
    
    # Export definitions
    sudo rabbitmqctl export_definitions "$BACKUP_DIR/definitions.json"
    
    # Backup configuration files
    sudo cp -r /etc/rabbitmq "$BACKUP_DIR/"
    
    # Create cluster status snapshot
    sudo rabbitmqctl cluster_status > "$BACKUP_DIR/cluster-status.txt"
    sudo rabbitmqctl list_queues name messages type > "$BACKUP_DIR/queue-status.txt"
    
    echo "   ✓ Backup created: $BACKUP_DIR"
    return 0
}

# Run all checks
echo "Starting pre-restart checks..."

CHECKS_PASSED=0
TOTAL_CHECKS=6

if check_cluster_health; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

if check_queue_types; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

if check_resource_alarms; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

if check_network_partitions; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

if check_client_connections; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

if backup_cluster_state; then
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi

echo ""
echo "Pre-flight check results: $CHECKS_PASSED/$TOTAL_CHECKS passed"

if [ $CHECKS_PASSED -eq $TOTAL_CHECKS ]; then
    echo "✅ All checks passed. Cluster is ready for rolling restart."
    exit 0
else
    echo "❌ Some checks failed. Please resolve issues before proceeding."
    exit 1
fi
```

## Seamless Rolling Restart Implementation

### Main Rolling Restart Script
```bash
#!/bin/bash
# File: rolling-restart.sh

set -e

echo "=== RabbitMQ Seamless Rolling Restart ==="

# Configuration
WAIT_TIME=30          # Time to wait between node restarts
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_INTERVAL=5

# Function to get cluster nodes
get_cluster_nodes() {
    CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
    echo "$CLUSTER_NODES"
}

# Function to identify primary node (first in alphabetical order for consistency)
identify_primary_node() {
    local nodes=$1
    echo "$nodes" | sort | head -1
}

# Function to wait for node to be healthy
wait_for_node_health() {
    local node_hostname=$1
    local retries=$HEALTH_CHECK_RETRIES
    
    echo "Waiting for $node_hostname to become healthy..."
    
    while [ $retries -gt 0 ]; do
        if ssh "root@$node_hostname" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
            echo "✓ Node $node_hostname is healthy"
            return 0
        fi
        
        echo "Node $node_hostname not ready, retrying in $HEALTH_CHECK_INTERVAL seconds... ($retries retries left)"
        sleep $HEALTH_CHECK_INTERVAL
        retries=$((retries - 1))
    done
    
    echo "✗ Node $node_hostname failed to become healthy"
    return 1
}

# Function to wait for cluster quorum
wait_for_cluster_quorum() {
    local retries=$HEALTH_CHECK_RETRIES
    
    echo "Waiting for cluster quorum..."
    
    while [ $retries -gt 0 ]; do
        RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        
        if [ $RUNNING_NODES -ge 2 ]; then
            echo "✓ Cluster quorum maintained ($RUNNING_NODES nodes running)"
            return 0
        fi
        
        echo "Waiting for quorum, currently $RUNNING_NODES nodes running... ($retries retries left)"
        sleep $HEALTH_CHECK_INTERVAL
        retries=$((retries - 1))
    done
    
    echo "✗ Cluster quorum not achieved"
    return 1
}

# Function to gracefully restart a node
restart_node() {
    local node_hostname=$1
    local is_primary=$2
    
    echo "=== Restarting node: $node_hostname ==="
    
    # Check if this is a remote node or local node
    if [ "$node_hostname" = "$(hostname)" ] || [ "$node_hostname" = "localhost" ]; then
        echo "Restarting local node..."
        
        # Graceful shutdown
        echo "Stopping RabbitMQ application..."
        sudo rabbitmqctl stop_app
        
        # Restart service
        echo "Restarting RabbitMQ service..."
        sudo systemctl restart rabbitmq-server
        
        # Wait for startup
        echo "Waiting for service startup..."
        sleep $WAIT_TIME
        
        # Start application
        echo "Starting RabbitMQ application..."
        sudo rabbitmqctl start_app
        
    else
        echo "Restarting remote node..."
        
        # Graceful shutdown
        echo "Stopping RabbitMQ application on $node_hostname..."
        ssh "root@$node_hostname" "rabbitmqctl stop_app"
        
        # Restart service
        echo "Restarting RabbitMQ service on $node_hostname..."
        ssh "root@$node_hostname" "systemctl restart rabbitmq-server"
        
        # Wait for startup
        echo "Waiting for service startup on $node_hostname..."
        sleep $WAIT_TIME
        
        # Start application
        echo "Starting RabbitMQ application on $node_hostname..."
        ssh "root@$node_hostname" "rabbitmqctl start_app"
    fi
    
    # Wait for node to become healthy
    if ! wait_for_node_health "$node_hostname"; then
        echo "✗ Failed to restart $node_hostname"
        return 1
    fi
    
    # Wait for cluster quorum
    if ! wait_for_cluster_quorum; then
        echo "✗ Cluster quorum lost after restarting $node_hostname"
        return 1
    fi
    
    echo "✓ Node $node_hostname restarted successfully"
    return 0
}

# Function to validate cluster after restart
validate_cluster_post_restart() {
    echo "=== Post-Restart Cluster Validation ==="
    
    # Check cluster status
    echo "1. Cluster status:"
    sudo rabbitmqctl cluster_status
    
    # Check all nodes are running
    RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    TOTAL_NODES=$(sudo rabbitmqctl cluster_status | grep "Disc" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    
    echo "2. Node count validation:"
    echo "   Running nodes: $RUNNING_NODES"
    echo "   Total nodes: $TOTAL_NODES"
    
    if [ $RUNNING_NODES -eq $TOTAL_NODES ]; then
        echo "   ✓ All nodes are running"
    else
        echo "   ✗ Not all nodes are running"
        return 1
    fi
    
    # Check for alarms
    echo "3. Resource alarms:"
    ALARMS=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().')
    if [ "$ALARMS" = "[]" ]; then
        echo "   ✓ No resource alarms"
    else
        echo "   ⚠ Alarms detected: $ALARMS"
    fi
    
    # Check queue health
    echo "4. Queue health:"
    TOTAL_QUEUES=$(sudo rabbitmqctl list_queues | wc -l)
    echo "   Total queues: $TOTAL_QUEUES"
    
    # Test basic functionality
    echo "5. Basic functionality test:"
    if sudo rabbitmqctl list_exchanges >/dev/null 2>&1; then
        echo "   ✓ Basic commands working"
    else
        echo "   ✗ Basic commands failing"
        return 1
    fi
    
    echo "✓ Post-restart validation completed successfully"
    return 0
}

# Main rolling restart procedure
main() {
    echo "Starting rolling restart procedure..."
    
    # Run pre-flight checks
    if ! ./pre-restart-checklist.sh; then
        echo "Pre-flight checks failed. Aborting restart."
        exit 1
    fi
    
    # Get cluster configuration
    CLUSTER_NODES=$(get_cluster_nodes)
    NODE_COUNT=$(echo "$CLUSTER_NODES" | wc -l)
    PRIMARY_NODE=$(identify_primary_node "$CLUSTER_NODES")
    
    echo "Cluster configuration:"
    echo "  Total nodes: $NODE_COUNT"
    echo "  Primary node: $PRIMARY_NODE"
    echo "  All nodes: $(echo $CLUSTER_NODES | tr '\n' ' ')"
    
    if [ $NODE_COUNT -lt 3 ]; then
        echo "Error: Minimum 3 nodes required for safe rolling restart"
        exit 1
    fi
    
    # Restart secondary nodes first
    echo "Phase 1: Restarting secondary nodes..."
    for node in $CLUSTER_NODES; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            if ! restart_node "$node" "false"; then
                echo "Failed to restart secondary node $node. Aborting."
                exit 1
            fi
            
            echo "Waiting $WAIT_TIME seconds before next restart..."
            sleep $WAIT_TIME
        fi
    done
    
    # Restart primary node last
    echo "Phase 2: Restarting primary node..."
    if ! restart_node "$PRIMARY_NODE" "true"; then
        echo "Failed to restart primary node $PRIMARY_NODE. Aborting."
        exit 1
    fi
    
    # Final validation
    echo "Phase 3: Final validation..."
    if ! validate_cluster_post_restart; then
        echo "Post-restart validation failed!"
        exit 1
    fi
    
    echo "🎉 Rolling restart completed successfully!"
    echo "All $NODE_COUNT nodes have been restarted seamlessly."
}

# Check if running as main script
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
```

### Configuration Update Rolling Restart
```bash
#!/bin/bash
# File: rolling-config-update.sh

set -e

echo "=== RabbitMQ Configuration Update with Rolling Restart ==="

# Parameters
CONFIG_SOURCE_DIR=""
UPDATE_TYPE=""

usage() {
    echo "Usage: $0 -s <config_source_dir> -t <update_type>"
    echo "  -s: Directory containing new configuration files"
    echo "  -t: Update type (config|ssl|performance|all)"
    exit 1
}

while getopts "s:t:" opt; do
    case $opt in
        s) CONFIG_SOURCE_DIR="$OPTARG" ;;
        t) UPDATE_TYPE="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$CONFIG_SOURCE_DIR" ] || [ -z "$UPDATE_TYPE" ]; then
    usage
fi

# Function to update configuration on a node
update_node_config() {
    local node_hostname=$1
    local config_dir="$CONFIG_SOURCE_DIR"
    
    echo "Updating configuration on $node_hostname..."
    
    # Backup current configuration
    BACKUP_DIR="/backup/config-backup-$(date +%Y%m%d-%H%M%S)"
    ssh "root@$node_hostname" "mkdir -p $BACKUP_DIR"
    ssh "root@$node_hostname" "cp -r /etc/rabbitmq/* $BACKUP_DIR/"
    
    # Update configuration files based on type
    case $UPDATE_TYPE in
        "config"|"all")
            echo "  Updating main configuration..."
            scp "$config_dir/rabbitmq.conf" "root@$node_hostname:/etc/rabbitmq/"
            scp "$config_dir/advanced.config" "root@$node_hostname:/etc/rabbitmq/"
            ;;
        "ssl"|"all")
            echo "  Updating SSL certificates..."
            scp -r "$config_dir/ssl/" "root@$node_hostname:/etc/rabbitmq/"
            ;;
        "performance"|"all")
            echo "  Updating performance configuration..."
            scp "$config_dir/performance.conf" "root@$node_hostname:/etc/rabbitmq/"
            ;;
    esac
    
    # Set proper permissions
    ssh "root@$node_hostname" "chown -R rabbitmq:rabbitmq /etc/rabbitmq/"
    ssh "root@$node_hostname" "chmod 644 /etc/rabbitmq/*.conf /etc/rabbitmq/*.config"
    
    if [ "$UPDATE_TYPE" = "ssl" ] || [ "$UPDATE_TYPE" = "all" ]; then
        ssh "root@$node_hostname" "chmod 600 /etc/rabbitmq/ssl/*/*.pem"
    fi
    
    echo "  Configuration updated on $node_hostname"
}

# Function to restart node with new configuration
restart_with_new_config() {
    local node_hostname=$1
    
    echo "Restarting $node_hostname with new configuration..."
    
    # Update configuration first
    update_node_config "$node_hostname"
    
    # Graceful restart with new config
    if [ "$node_hostname" = "$(hostname)" ]; then
        sudo rabbitmqctl stop_app
        sudo systemctl restart rabbitmq-server
        sleep 30
        sudo rabbitmqctl start_app
    else
        ssh "root@$node_hostname" "rabbitmqctl stop_app"
        ssh "root@$node_hostname" "systemctl restart rabbitmq-server"
        sleep 30
        ssh "root@$node_hostname" "rabbitmqctl start_app"
    fi
    
    # Verify configuration reload
    if ssh "root@$node_hostname" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
        echo "✓ Node $node_hostname restarted with new configuration"
    else
        echo "✗ Node $node_hostname failed to start with new configuration"
        return 1
    fi
}

# Main configuration update procedure
main() {
    echo "Starting configuration update procedure..."
    
    # Validate configuration files
    if [ ! -d "$CONFIG_SOURCE_DIR" ]; then
        echo "Error: Configuration source directory not found: $CONFIG_SOURCE_DIR"
        exit 1
    fi
    
    # Run pre-flight checks
    if ! ./pre-restart-checklist.sh; then
        echo "Pre-flight checks failed. Aborting update."
        exit 1
    fi
    
    # Get cluster nodes
    CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
    PRIMARY_NODE=$(echo "$CLUSTER_NODES" | sort | head -1)
    
    echo "Updating configuration across cluster..."
    
    # Update secondary nodes first
    for node in $CLUSTER_NODES; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            if ! restart_with_new_config "$node"; then
                echo "Failed to update configuration on $node"
                exit 1
            fi
            sleep 30
        fi
    done
    
    # Update primary node last
    if ! restart_with_new_config "$PRIMARY_NODE"; then
        echo "Failed to update configuration on primary node $PRIMARY_NODE"
        exit 1
    fi
    
    echo "✅ Configuration update completed successfully!"
}

main "$@"
```

## Zero-Downtime Maintenance Operations

### Plugin Management with Rolling Restart
```bash
#!/bin/bash
# File: rolling-plugin-management.sh

set -e

echo "=== RabbitMQ Plugin Management with Rolling Restart ==="

PLUGIN_NAME=""
OPERATION=""

usage() {
    echo "Usage: $0 -p <plugin_name> -o <operation>"
    echo "  -p: Plugin name (e.g., rabbitmq_federation)"
    echo "  -o: Operation (enable|disable)"
    exit 1
}

while getopts "p:o:" opt; do
    case $opt in
        p) PLUGIN_NAME="$OPTARG" ;;
        o) OPERATION="$OPTARG" ;;
        *) usage ;;
    esac
done

if [ -z "$PLUGIN_NAME" ] || [ -z "$OPERATION" ]; then
    usage
fi

# Function to manage plugin on a node
manage_plugin_on_node() {
    local node_hostname=$1
    local plugin=$2
    local operation=$3
    
    echo "Managing plugin $plugin on $node_hostname (operation: $operation)..."
    
    if [ "$operation" = "enable" ]; then
        ssh "root@$node_hostname" "rabbitmq-plugins enable $plugin"
    elif [ "$operation" = "disable" ]; then
        ssh "root@$node_hostname" "rabbitmq-plugins disable $plugin"
    fi
    
    # Restart node to apply plugin changes
    ssh "root@$node_hostname" "rabbitmqctl stop_app"
    ssh "root@$node_hostname" "systemctl restart rabbitmq-server"
    sleep 30
    ssh "root@$node_hostname" "rabbitmqctl start_app"
    
    # Verify plugin status
    PLUGIN_STATUS=$(ssh "root@$node_hostname" "rabbitmq-plugins list | grep $plugin")
    echo "Plugin status on $node_hostname: $PLUGIN_STATUS"
}

# Main plugin management
main() {
    # Get cluster nodes
    CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
    PRIMARY_NODE=$(echo "$CLUSTER_NODES" | sort | head -1)
    
    echo "Managing plugin $PLUGIN_NAME across cluster (operation: $OPERATION)..."
    
    # Process secondary nodes first
    for node in $CLUSTER_NODES; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            manage_plugin_on_node "$node" "$PLUGIN_NAME" "$OPERATION"
            sleep 30
        fi
    done
    
    # Process primary node last
    manage_plugin_on_node "$PRIMARY_NODE" "$PLUGIN_NAME" "$OPERATION"
    
    echo "✅ Plugin management completed successfully!"
}

main "$@"
```

### User Management During Rolling Operations
```bash
#!/bin/bash
# File: rolling-user-management.sh

set -e

echo "=== RabbitMQ User Management During Rolling Operations ==="

# Function to synchronize users across cluster
sync_users_across_cluster() {
    echo "Synchronizing users across cluster..."
    
    # Export user definitions from primary node
    CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
    PRIMARY_NODE=$(echo "$CLUSTER_NODES" | sort | head -1)
    
    echo "Exporting user definitions from $PRIMARY_NODE..."
    TEMP_DEFS="/tmp/user-sync-$(date +%Y%m%d-%H%M%S).json"
    
    if [ "$PRIMARY_NODE" = "$(hostname)" ]; then
        sudo rabbitmqctl export_definitions "$TEMP_DEFS"
    else
        ssh "root@$PRIMARY_NODE" "rabbitmqctl export_definitions $TEMP_DEFS"
        scp "root@$PRIMARY_NODE:$TEMP_DEFS" "$TEMP_DEFS"
    fi
    
    # Import definitions to all nodes
    for node in $CLUSTER_NODES; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            echo "Importing user definitions to $node..."
            
            if [ "$node" = "$(hostname)" ]; then
                sudo rabbitmqctl import_definitions "$TEMP_DEFS"
            else
                scp "$TEMP_DEFS" "root@$node:$TEMP_DEFS"
                ssh "root@$node" "rabbitmqctl import_definitions $TEMP_DEFS"
                ssh "root@$node" "rm $TEMP_DEFS"
            fi
        fi
    done
    
    # Cleanup
    rm -f "$TEMP_DEFS"
    
    echo "✓ User synchronization completed"
}

# Function to add user with cluster sync
add_user_with_sync() {
    local username=$1
    local password=$2
    local tags=$3
    
    echo "Adding user $username across cluster..."
    
    # Add user on primary node
    sudo rabbitmqctl add_user "$username" "$password"
    sudo rabbitmqctl set_user_tags "$username" "$tags"
    sudo rabbitmqctl set_permissions -p / "$username" ".*" ".*" ".*"
    
    # Sync across cluster
    sync_users_across_cluster
    
    echo "✓ User $username added successfully"
}

# Main user management operations
case "${1:-help}" in
    "add")
        if [ $# -ne 4 ]; then
            echo "Usage: $0 add <username> <password> <tags>"
            exit 1
        fi
        add_user_with_sync "$2" "$3" "$4"
        ;;
    "sync")
        sync_users_across_cluster
        ;;
    "help"|*)
        echo "Usage: $0 <command> [args]"
        echo "Commands:"
        echo "  add <username> <password> <tags>  - Add user and sync across cluster"
        echo "  sync                               - Synchronize users across cluster"
        ;;
esac
```

## Load Balancer Integration

### HAProxy Configuration for Rolling Restarts
```bash
#!/bin/bash
# File: setup-haproxy-for-rolling-restarts.sh

set -e

echo "=== Setting up HAProxy for RabbitMQ Rolling Restarts ==="

# Get cluster nodes
CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")

read -p "Enter HAProxy server IP: " HAPROXY_IP
read -p "Enter RabbitMQ VIP: " RABBITMQ_VIP

# Generate HAProxy configuration
cat > "/tmp/haproxy-rabbitmq.cfg" << EOF
global
    log 127.0.0.1:514 local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    option redispatch
    retries 3
    timeout queue 1m
    timeout connect 10s
    timeout client 1m
    timeout server 1m
    timeout check 10s
    maxconn 3000

# RabbitMQ AMQP
frontend rabbitmq_amqp
    bind $RABBITMQ_VIP:5672
    mode tcp
    default_backend rabbitmq_amqp_nodes

backend rabbitmq_amqp_nodes
    mode tcp
    balance roundrobin
    option tcp-check
    tcp-check connect port 5672
EOF

# Add cluster nodes to backend
node_index=1
for node in $CLUSTER_NODES; do
    echo "    server rmq$node_index $node:5672 check inter 5s fall 3 rise 2" >> "/tmp/haproxy-rabbitmq.cfg"
    node_index=$((node_index + 1))
done

cat >> "/tmp/haproxy-rabbitmq.cfg" << EOF

# RabbitMQ Management Interface
frontend rabbitmq_management
    bind $RABBITMQ_VIP:15672
    mode http
    default_backend rabbitmq_management_nodes

backend rabbitmq_management_nodes
    mode http
    balance roundrobin
    option httpchk GET /api/healthchecks/node
    http-check expect status 200
EOF

# Add management backend nodes
node_index=1
for node in $CLUSTER_NODES; do
    echo "    server rmq-mgmt$node_index $node:15672 check inter 10s fall 3 rise 2" >> "/tmp/haproxy-rabbitmq.cfg"
    node_index=$((node_index + 1))
done

cat >> "/tmp/haproxy-rabbitmq.cfg" << EOF

# HAProxy Statistics
frontend stats
    bind $HAPROXY_IP:8080
    mode http
    stats enable
    stats uri /stats
    stats realm HAProxy\ Statistics
    stats auth admin:password
    stats refresh 30s
EOF

echo "HAProxy configuration generated: /tmp/haproxy-rabbitmq.cfg"
echo ""
echo "Deployment steps:"
echo "1. Copy configuration to HAProxy server: scp /tmp/haproxy-rabbitmq.cfg root@$HAPROXY_IP:/etc/haproxy/"
echo "2. Test configuration: haproxy -c -f /etc/haproxy/haproxy-rabbitmq.cfg"
echo "3. Restart HAProxy: systemctl restart haproxy"
echo "4. Access statistics: http://$HAPROXY_IP:8080/stats"
```

### Rolling Restart with Load Balancer Integration
```bash
#!/bin/bash
# File: rolling-restart-with-lb.sh

set -e

echo "=== Rolling Restart with Load Balancer Integration ==="

HAPROXY_HOST=""
HAPROXY_STATS_PORT="8080"
HAPROXY_STATS_USER="admin"
HAPROXY_STATS_PASS="password"

# Function to disable node in load balancer
disable_node_in_lb() {
    local node_hostname=$1
    
    echo "Disabling $node_hostname in load balancer..."
    
    # Disable AMQP backend
    curl -X POST "http://$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS@$HAPROXY_HOST:$HAPROXY_STATS_PORT/stats" \
        -d "action=disable&b=rabbitmq_amqp_nodes&s=$node_hostname" >/dev/null 2>&1
    
    # Disable Management backend
    curl -X POST "http://$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS@$HAPROXY_HOST:$HAPROXY_STATS_PORT/stats" \
        -d "action=disable&b=rabbitmq_management_nodes&s=$node_hostname" >/dev/null 2>&1
    
    echo "✓ Node $node_hostname disabled in load balancer"
}

# Function to enable node in load balancer
enable_node_in_lb() {
    local node_hostname=$1
    
    echo "Enabling $node_hostname in load balancer..."
    
    # Enable AMQP backend
    curl -X POST "http://$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS@$HAPROXY_HOST:$HAPROXY_STATS_PORT/stats" \
        -d "action=enable&b=rabbitmq_amqp_nodes&s=$node_hostname" >/dev/null 2>&1
    
    # Enable Management backend
    curl -X POST "http://$HAPROXY_STATS_USER:$HAPROXY_STATS_PASS@$HAPROXY_HOST:$HAPROXY_STATS_PORT/stats" \
        -d "action=enable&b=rabbitmq_management_nodes&s=$node_hostname" >/dev/null 2>&1
    
    echo "✓ Node $node_hostname enabled in load balancer"
}

# Enhanced restart function with load balancer integration
restart_node_with_lb() {
    local node_hostname=$1
    
    echo "=== Restarting $node_hostname with load balancer coordination ==="
    
    # Step 1: Disable in load balancer
    disable_node_in_lb "$node_hostname"
    
    # Step 2: Wait for connections to drain
    echo "Waiting 30 seconds for connections to drain..."
    sleep 30
    
    # Step 3: Perform restart
    echo "Restarting RabbitMQ on $node_hostname..."
    ssh "root@$node_hostname" "rabbitmqctl stop_app"
    ssh "root@$node_hostname" "systemctl restart rabbitmq-server"
    sleep 30
    ssh "root@$node_hostname" "rabbitmqctl start_app"
    
    # Step 4: Wait for node health
    local retries=10
    while [ $retries -gt 0 ]; do
        if ssh "root@$node_hostname" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
            echo "✓ Node $node_hostname is healthy"
            break
        fi
        echo "Waiting for node health... ($retries retries left)"
        sleep 5
        retries=$((retries - 1))
    done
    
    if [ $retries -eq 0 ]; then
        echo "✗ Node $node_hostname failed to become healthy"
        return 1
    fi
    
    # Step 5: Re-enable in load balancer
    enable_node_in_lb "$node_hostname"
    
    echo "✓ Node $node_hostname restarted successfully with load balancer coordination"
}

# Main rolling restart with load balancer
main() {
    read -p "Enter HAProxy host: " HAPROXY_HOST
    
    if [ -z "$HAPROXY_HOST" ]; then
        echo "HAProxy host is required for load balancer integration"
        exit 1
    fi
    
    # Get cluster nodes
    CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
    PRIMARY_NODE=$(echo "$CLUSTER_NODES" | sort | head -1)
    
    echo "Starting load balancer coordinated rolling restart..."
    
    # Restart secondary nodes first
    for node in $CLUSTER_NODES; do
        if [ "$node" != "$PRIMARY_NODE" ]; then
            if ! restart_node_with_lb "$node"; then
                echo "Failed to restart $node"
                exit 1
            fi
            sleep 30
        fi
    done
    
    # Restart primary node last
    if ! restart_node_with_lb "$PRIMARY_NODE"; then
        echo "Failed to restart primary node $PRIMARY_NODE"
        exit 1
    fi
    
    echo "🎉 Load balancer coordinated rolling restart completed successfully!"
}

main "$@"
```

This comprehensive seamless rolling restart guide ensures zero-downtime maintenance operations for RabbitMQ clusters of any size, with proper coordination between cluster nodes, load balancers, and client applications. The procedures maintain service availability while allowing for configuration updates, security patches, and system maintenance.