# Dynamic RabbitMQ Cluster Configuration Guide

## Overview
This guide provides a flexible, scalable approach to configure RabbitMQ 4.1.x clusters with any number of nodes (3, 5, 7, 9+ nodes), supporting dynamic scaling and automatic cluster formation.

## Dynamic Cluster Architecture

### Supported Cluster Sizes
- **3 nodes**: Minimum recommended for production (fault tolerance: 1 node)
- **5 nodes**: High availability setup (fault tolerance: 2 nodes)
- **7 nodes**: Large-scale deployment (fault tolerance: 3 nodes)
- **9+ nodes**: Enterprise-scale deployment (fault tolerance: 4+ nodes)

### Cluster Node Types
1. **Disc Nodes**: Store metadata to disk (recommended: odd numbers)
2. **RAM Nodes**: Store metadata in memory only (optional, for performance)

## Dynamic Configuration Generator

### Universal Cluster Configuration Script
```bash
#!/bin/bash
# File: generate-dynamic-cluster-config.sh

set -e

echo "=== Dynamic RabbitMQ Cluster Configuration Generator ==="

# Read cluster parameters
read -p "Enter number of nodes: " NODE_COUNT
read -p "Enter cluster name prefix (e.g., 'rabbitmq'): " CLUSTER_PREFIX
read -p "Enter domain suffix (e.g., '.company.local'): " DOMAIN_SUFFIX
read -p "Enter base IP (e.g., '10.20.20'): " BASE_IP
read -p "Enter starting IP suffix (e.g., '10'): " START_IP

# Validate input
if [ $NODE_COUNT -lt 3 ]; then
    echo "Error: Minimum 3 nodes required for production cluster"
    exit 1
fi

if [ $((NODE_COUNT % 2)) -eq 0 ]; then
    echo "Warning: Even number of nodes may cause split-brain issues"
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

# Generate node list
declare -a NODE_NAMES
declare -a NODE_IPS
declare -a NODE_HOSTNAMES

for ((i=0; i<NODE_COUNT; i++)); do
    NODE_NUM=$((i + 1))
    IP_SUFFIX=$((START_IP + i))
    
    NODE_NAMES[$i]="${CLUSTER_PREFIX}-node-${NODE_NUM}"
    NODE_IPS[$i]="${BASE_IP}.${IP_SUFFIX}"
    NODE_HOSTNAMES[$i]="${CLUSTER_PREFIX}-node-${NODE_NUM}${DOMAIN_SUFFIX}"
done

echo "Generated cluster configuration:"
for ((i=0; i<NODE_COUNT; i++)); do
    echo "  Node $((i+1)): ${NODE_NAMES[$i]} (${NODE_IPS[$i]}) - ${NODE_HOSTNAMES[$i]}"
done

# Calculate partition handling strategy
MAJORITY_SIZE=$(((NODE_COUNT / 2) + 1))
echo "Cluster majority size: $MAJORITY_SIZE nodes"

# Generate configuration files
generate_rabbitmq_config() {
    local node_index=$1
    local node_name=${NODE_NAMES[$node_index]}
    local config_dir="/tmp/cluster-configs/$node_name"
    
    mkdir -p "$config_dir"
    
    cat > "$config_dir/rabbitmq.conf" << EOF
# Dynamic RabbitMQ Cluster Configuration
# Node: $node_name
# Cluster size: $NODE_COUNT nodes

# Cluster formation configuration
cluster_formation.peer_discovery_backend = classic_config
EOF

    # Add all cluster nodes to configuration
    for ((j=0; j<NODE_COUNT; j++)); do
        echo "cluster_formation.classic_config.nodes.$((j+1)) = rabbit@${NODE_HOSTNAMES[$j]}" >> "$config_dir/rabbitmq.conf"
    done

    cat >> "$config_dir/rabbitmq.conf" << EOF

# Network partition handling (optimized for $NODE_COUNT nodes)
cluster_partition_handling = pause_minority

# Performance settings (scaled for $NODE_COUNT nodes)
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
heartbeat = 60

# Channel and connection limits (scaled for cluster size)
channel_max = $((2048 * NODE_COUNT / 3))
connection_max = $((4096 * NODE_COUNT / 3))

# Management interface
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Logging
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info

# Cluster-specific optimizations
collect_statistics_interval = $((5000 + (NODE_COUNT * 500)))
delegate_count = $((16 + (NODE_COUNT * 2)))

# Quorum queue configuration (optimized for cluster size)
default_queue_type = quorum
quorum_commands_soft_limit = $((32 + (NODE_COUNT * 8)))

# Network settings
cluster_keepalive_interval = 10000
net_ticktime = 60

# Startup delay to prevent race conditions
cluster_formation.randomized_startup_delay_range.min = 5
cluster_formation.randomized_startup_delay_range.max = $((30 + (NODE_COUNT * 5)))
EOF

    echo "Generated configuration for $node_name: $config_dir/rabbitmq.conf"
}

# Generate advanced configuration
generate_advanced_config() {
    local node_index=$1
    local node_name=${NODE_NAMES[$node_index]}
    local config_dir="/tmp/cluster-configs/$node_name"
    
    cat > "$config_dir/advanced.config" << EOF
[
  {rabbit, [
    %% Dynamic cluster configuration for $NODE_COUNT nodes
    {cluster_nodes, {[$(printf "'rabbit@%s'" "${NODE_HOSTNAMES[0]}"; for ((k=1; k<NODE_COUNT; k++)); do printf ", 'rabbit@%s'" "${NODE_HOSTNAMES[$k]}"; done)], disc}},
    
    %% Network partition handling
    {cluster_partition_handling, pause_minority},
    
    %% TCP configuration (scaled for cluster size)
    {tcp_listeners, [5672]},
    {num_tcp_acceptors, $((10 + (NODE_COUNT * 2)))},
    {handshake_timeout, 10000},
    
    %% Memory and performance settings
    {vm_memory_high_watermark, 0.6},
    {vm_memory_calculation_strategy, rss},
    {disk_free_limit, {mem_relative, 2.0}},
    
    %% Connection management (scaled)
    {channel_max, $((2048 * NODE_COUNT / 3))},
    {connection_max, $((4096 * NODE_COUNT / 3))},
    {heartbeat, 60},
    
    %% Clustering performance (scaled)
    {delegate_count, $((16 + (NODE_COUNT * 2)))},
    {cluster_keepalive_interval, 10000},
    {collect_statistics_interval, $((5000 + (NODE_COUNT * 500)))},
    
    %% Quorum queue settings (optimized for cluster size)
    {default_queue_type, quorum},
    {quorum_commands_soft_limit, $((32 + (NODE_COUNT * 8)))},
    
    %% Network partition detection
    {net_ticktime, 60},
    
    %% Mnesia configuration for large clusters
    {mnesia_table_loading_retry_timeout, $((30000 + (NODE_COUNT * 5000)))},
    {mnesia_table_loading_retry_limit, 10}
  ]},
  
  {rabbitmq_management, [
    %% Management interface settings
    {listener, [
      {port, 15672},
      {ip, "0.0.0.0"}
    ]},
    
    %% Rates mode for large clusters
    {rates_mode, $([ $NODE_COUNT -gt 5 ] && echo "basic" || echo "detailed")},
    
    %% Sample retention (adjusted for cluster size)
    {sample_retention_policies, [
      {global, [
        {605, $([ $NODE_COUNT -gt 7 ] && echo "3" || echo "5")},
        {3660, $([ $NODE_COUNT -gt 7 ] && echo "30" || echo "60")},
        {29400, $([ $NODE_COUNT -gt 7 ] && echo "300" || echo "600")}
      ]}
    ]}
  ]},
  
  {kernel, [
    %% Network configuration
    {inet_default_connect_options, [
      {nodelay, true},
      {keepalive, true},
      {send_timeout, 15000},
      {send_timeout_close, true}
    ]},
    
    %% Erlang distribution (single port for simplicity)
    {inet_dist_listen_min, 25672},
    {inet_dist_listen_max, 25672}
  ]},
  
  {mnesia, [
    %% Mnesia optimization for cluster size
    {dump_log_write_threshold, $((50000 + (NODE_COUNT * 10000)))},
    {dc_dump_limit, $((40 + (NODE_COUNT * 5)))}
  ]}
].
EOF

    echo "Generated advanced configuration for $node_name: $config_dir/advanced.config"
}

# Generate all configurations
echo "Generating configurations for all nodes..."
for ((i=0; i<NODE_COUNT; i++)); do
    generate_rabbitmq_config $i
    generate_advanced_config $i
done

# Generate cluster deployment script
cat > "/tmp/cluster-configs/deploy-cluster.sh" << 'EOF'
#!/bin/bash
# Dynamic Cluster Deployment Script

set -e

NODES=($(echo "NODE_HOSTNAMES_PLACEHOLDER" | tr ' ' '\n'))
NODE_COUNT=${#NODES[@]}

echo "=== Deploying RabbitMQ Cluster ($NODE_COUNT nodes) ==="

# Function to deploy configuration to a node
deploy_to_node() {
    local node_hostname=$1
    local node_name=$2
    
    echo "Deploying configuration to $node_hostname..."
    
    # Copy configuration files
    scp "$node_name/rabbitmq.conf" "root@$node_hostname:/etc/rabbitmq/"
    scp "$node_name/advanced.config" "root@$node_hostname:/etc/rabbitmq/"
    
    # Set permissions
    ssh "root@$node_hostname" "chown rabbitmq:rabbitmq /etc/rabbitmq/*.conf /etc/rabbitmq/*.config"
    ssh "root@$node_hostname" "chmod 644 /etc/rabbitmq/*.conf /etc/rabbitmq/*.config"
    
    echo "Configuration deployed to $node_hostname"
}

# Deploy to all nodes
for ((i=0; i<NODE_COUNT; i++)); do
    NODE_HOSTNAME=${NODES[$i]}
    NODE_NAME="NODE_NAMES_PLACEHOLDER_$i"
    deploy_to_node "$NODE_HOSTNAME" "$NODE_NAME"
done

echo "All configurations deployed successfully!"
EOF

# Replace placeholders in deployment script
NODE_HOSTNAMES_STR=$(printf "%s " "${NODE_HOSTNAMES[@]}")
NODE_NAMES_STR=$(printf "%s " "${NODE_NAMES[@]}")

sed -i "s/NODE_HOSTNAMES_PLACEHOLDER/$NODE_HOSTNAMES_STR/g" "/tmp/cluster-configs/deploy-cluster.sh"

for ((i=0; i<NODE_COUNT; i++)); do
    sed -i "s/NODE_NAMES_PLACEHOLDER_$i/${NODE_NAMES[$i]}/g" "/tmp/cluster-configs/deploy-cluster.sh"
done

chmod +x "/tmp/cluster-configs/deploy-cluster.sh"

# Generate cluster startup script
generate_cluster_startup_script

echo "Dynamic cluster configuration completed!"
echo "Configuration files generated in: /tmp/cluster-configs/"
echo "Deployment script: /tmp/cluster-configs/deploy-cluster.sh"
```

### Cluster Startup Script Generator
```bash
generate_cluster_startup_script() {
    cat > "/tmp/cluster-configs/start-cluster.sh" << EOF
#!/bin/bash
# Dynamic Cluster Startup Script

set -e

# Cluster configuration
NODES=(${NODE_HOSTNAMES[@]})
NODE_COUNT=\${#NODES[@]}
PRIMARY_NODE=\${NODES[0]}

echo "=== Starting RabbitMQ Cluster (\$NODE_COUNT nodes) ==="
echo "Primary node: \$PRIMARY_NODE"

# Function to start RabbitMQ on a node
start_node() {
    local node_hostname=\$1
    local is_primary=\$2
    
    echo "Starting RabbitMQ on \$node_hostname..."
    
    # Start RabbitMQ service
    ssh "root@\$node_hostname" "systemctl start rabbitmq-server"
    
    # Wait for service to be ready
    sleep 10
    
    if [ "\$is_primary" = "false" ]; then
        echo "Joining \$node_hostname to cluster..."
        ssh "root@\$node_hostname" "rabbitmqctl stop_app"
        ssh "root@\$node_hostname" "rabbitmqctl reset"
        ssh "root@\$node_hostname" "rabbitmqctl join_cluster rabbit@\$PRIMARY_NODE"
        ssh "root@\$node_hostname" "rabbitmqctl start_app"
    else
        echo "Setting up primary node \$node_hostname..."
        # Create users on primary node
        ssh "root@\$node_hostname" "rabbitmqctl add_user admin admin123"
        ssh "root@\$node_hostname" "rabbitmqctl set_user_tags admin administrator"
        ssh "root@\$node_hostname" "rabbitmqctl set_permissions -p / admin '.*' '.*' '.*'"
        
        ssh "root@\$node_hostname" "rabbitmqctl add_user teja Teja@2024"
        ssh "root@\$node_hostname" "rabbitmqctl set_user_tags teja management"
        ssh "root@\$node_hostname" "rabbitmqctl set_permissions -p / teja '.*' '.*' '.*'"
        
        ssh "root@\$node_hostname" "rabbitmqctl add_user aswini Aswini@2024"
        ssh "root@\$node_hostname" "rabbitmqctl set_user_tags aswini management"
        ssh "root@\$node_hostname" "rabbitmqctl set_permissions -p / aswini '.*' '.*' '.*'"
        
        # Remove default guest user
        ssh "root@\$node_hostname" "rabbitmqctl delete_user guest"
    fi
    
    echo "Node \$node_hostname ready"
}

# Start primary node first
start_node "\$PRIMARY_NODE" "true"

# Start remaining nodes
for ((i=1; i<NODE_COUNT; i++)); do
    start_node "\${NODES[\$i]}" "false"
    sleep 5  # Stagger node joins
done

# Verify cluster status
echo "Verifying cluster status..."
ssh "root@\$PRIMARY_NODE" "rabbitmqctl cluster_status"

echo "Cluster startup completed successfully!"
echo "Management interfaces available at:"
for ((i=0; i<NODE_COUNT; i++)); do
    echo "  http://\${NODES[\$i]}:15672"
done
EOF

    chmod +x "/tmp/cluster-configs/start-cluster.sh"
    echo "Generated cluster startup script: /tmp/cluster-configs/start-cluster.sh"
}
```

## Cluster Scaling Operations

### Add Node to Existing Cluster Script
```bash
#!/bin/bash
# File: add-node-to-cluster.sh

set -e

echo "=== Add Node to Existing RabbitMQ Cluster ==="

# Get cluster information
read -p "Enter existing cluster primary node hostname: " PRIMARY_NODE
read -p "Enter new node hostname: " NEW_NODE
read -p "Enter new node IP: " NEW_NODE_IP

echo "Adding $NEW_NODE to cluster via $PRIMARY_NODE..."

# Get current cluster configuration from primary node
echo "Retrieving current cluster configuration..."
CURRENT_NODES=$(ssh "root@$PRIMARY_NODE" "rabbitmqctl cluster_status" | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
NEW_NODE_COUNT=$((CURRENT_NODES + 1))

echo "Current cluster size: $CURRENT_NODES nodes"
echo "New cluster size: $NEW_NODE_COUNT nodes"

# Generate configuration for new node
echo "Generating configuration for new node..."
mkdir -p "/tmp/new-node-config"

# Get existing node list from primary
EXISTING_NODES=$(ssh "root@$PRIMARY_NODE" "rabbitmqctl cluster_status" | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")

# Create new node configuration
cat > "/tmp/new-node-config/rabbitmq.conf" << EOF
# RabbitMQ Configuration for new cluster node
cluster_formation.peer_discovery_backend = classic_config
EOF

# Add existing nodes to configuration
node_index=1
for node in $EXISTING_NODES; do
    echo "cluster_formation.classic_config.nodes.$node_index = rabbit@$node" >> "/tmp/new-node-config/rabbitmq.conf"
    node_index=$((node_index + 1))
done

# Add new node to configuration
echo "cluster_formation.classic_config.nodes.$node_index = rabbit@$NEW_NODE" >> "/tmp/new-node-config/rabbitmq.conf"

cat >> "/tmp/new-node-config/rabbitmq.conf" << EOF

# Network partition handling
cluster_partition_handling = pause_minority

# Performance settings (scaled for $NEW_NODE_COUNT nodes)
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
heartbeat = 60

# Scaled settings for larger cluster
channel_max = $((2048 * NEW_NODE_COUNT / 3))
connection_max = $((4096 * NEW_NODE_COUNT / 3))
collect_statistics_interval = $((5000 + (NEW_NODE_COUNT * 500)))
delegate_count = $((16 + (NEW_NODE_COUNT * 2)))

# Management interface
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Logging
log.console = true
log.file = /var/log/rabbitmq/rabbit.log
EOF

# Deploy configuration to new node
echo "Deploying configuration to new node..."
scp "/tmp/new-node-config/rabbitmq.conf" "root@$NEW_NODE:/etc/rabbitmq/"
ssh "root@$NEW_NODE" "chown rabbitmq:rabbitmq /etc/rabbitmq/rabbitmq.conf"

# Start RabbitMQ on new node
echo "Starting RabbitMQ on new node..."
ssh "root@$NEW_NODE" "systemctl enable rabbitmq-server"
ssh "root@$NEW_NODE" "systemctl start rabbitmq-server"
sleep 10

# Join new node to cluster
echo "Joining new node to cluster..."
ssh "root@$NEW_NODE" "rabbitmqctl stop_app"
ssh "root@$NEW_NODE" "rabbitmqctl reset"
ssh "root@$NEW_NODE" "rabbitmqctl join_cluster rabbit@$PRIMARY_NODE"
ssh "root@$NEW_NODE" "rabbitmqctl start_app"

# Verify cluster status
echo "Verifying updated cluster status..."
ssh "root@$PRIMARY_NODE" "rabbitmqctl cluster_status"

echo "Node $NEW_NODE successfully added to cluster!"
echo "New cluster size: $NEW_NODE_COUNT nodes"
```

### Remove Node from Cluster Script
```bash
#!/bin/bash
# File: remove-node-from-cluster.sh

set -e

echo "=== Remove Node from RabbitMQ Cluster ==="

# Get cluster information
read -p "Enter cluster primary node hostname: " PRIMARY_NODE
read -p "Enter node to remove hostname: " REMOVE_NODE

echo "Removing $REMOVE_NODE from cluster..."

# Check if node to remove is the primary
if [ "$REMOVE_NODE" = "$PRIMARY_NODE" ]; then
    echo "Error: Cannot remove primary node. Please choose a different primary node first."
    exit 1
fi

# Get current cluster status
echo "Current cluster status:"
ssh "root@$PRIMARY_NODE" "rabbitmqctl cluster_status"

# Gracefully stop applications on node to remove
echo "Stopping applications on $REMOVE_NODE..."
ssh "root@$REMOVE_NODE" "rabbitmqctl stop_app" || true

# Remove node from cluster
echo "Removing $REMOVE_NODE from cluster..."
ssh "root@$PRIMARY_NODE" "rabbitmqctl forget_cluster_node rabbit@$REMOVE_NODE"

# Stop RabbitMQ service on removed node
echo "Stopping RabbitMQ service on $REMOVE_NODE..."
ssh "root@$REMOVE_NODE" "systemctl stop rabbitmq-server"
ssh "root@$REMOVE_NODE" "systemctl disable rabbitmq-server"

# Clean up removed node
echo "Cleaning up $REMOVE_NODE..."
ssh "root@$REMOVE_NODE" "rm -rf /var/lib/rabbitmq/mnesia"

# Verify updated cluster status
echo "Verifying updated cluster status..."
ssh "root@$PRIMARY_NODE" "rabbitmqctl cluster_status"

echo "Node $REMOVE_NODE successfully removed from cluster!"
```

## Automatic Cluster Discovery

### DNS-Based Cluster Discovery
```bash
#!/bin/bash
# File: setup-dns-discovery.sh

set -e

echo "=== Setting up DNS-based Cluster Discovery ==="

read -p "Enter DNS domain for cluster discovery (e.g., 'rabbitmq.service.consul'): " DNS_DOMAIN
read -p "Enter cluster name: " CLUSTER_NAME

# Generate DNS-based configuration
cat > "/tmp/dns-discovery-config.conf" << EOF
# DNS-based cluster discovery configuration
cluster_formation.peer_discovery_backend = dns
cluster_formation.dns.hostname = $DNS_DOMAIN

# DNS resolution settings
cluster_formation.node_cleanup.interval = 30
cluster_formation.node_cleanup.only_log_warning = true

# Cluster name
cluster_name = $CLUSTER_NAME

# Network partition handling
cluster_partition_handling = pause_minority

# Other standard settings
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
default_queue_type = quorum
EOF

echo "DNS discovery configuration generated: /tmp/dns-discovery-config.conf"
echo "Add this configuration to your rabbitmq.conf file"
echo ""
echo "DNS Setup Requirements:"
echo "1. Create DNS A records for all cluster nodes:"
echo "   $DNS_DOMAIN -> node1-ip"
echo "   $DNS_DOMAIN -> node2-ip" 
echo "   $DNS_DOMAIN -> node3-ip"
echo "   ..."
echo ""
echo "2. Ensure all nodes can resolve $DNS_DOMAIN"
echo "3. Configure DNS with appropriate TTL (30-60 seconds recommended)"
```

### Consul-Based Cluster Discovery
```bash
#!/bin/bash
# File: setup-consul-discovery.sh

set -e

echo "=== Setting up Consul-based Cluster Discovery ==="

read -p "Enter Consul server address: " CONSUL_HOST
read -p "Enter Consul port (default 8500): " CONSUL_PORT
CONSUL_PORT=${CONSUL_PORT:-8500}
read -p "Enter service name for RabbitMQ: " SERVICE_NAME

# Generate Consul-based configuration
cat > "/tmp/consul-discovery-config.conf" << EOF
# Consul-based cluster discovery configuration
cluster_formation.peer_discovery_backend = consul
cluster_formation.consul.host = $CONSUL_HOST
cluster_formation.consul.port = $CONSUL_PORT
cluster_formation.consul.scheme = http
cluster_formation.consul.acl_token = 
cluster_formation.consul.svc = $SERVICE_NAME
cluster_formation.consul.svc_addr_auto = true
cluster_formation.consul.svc_addr_use_nodename = true

# Service registration settings
cluster_formation.consul.deregister_after = 60
cluster_formation.consul.cleanup_interval = 30

# Cluster settings
cluster_name = $SERVICE_NAME
cluster_partition_handling = pause_minority

# Standard performance settings
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
default_queue_type = quorum
EOF

echo "Consul discovery configuration generated: /tmp/consul-discovery-config.conf"
echo "Add this configuration to your rabbitmq.conf file"
echo ""
echo "Consul Setup Requirements:"
echo "1. Install and configure Consul on all nodes"
echo "2. Ensure RabbitMQ nodes can communicate with Consul at $CONSUL_HOST:$CONSUL_PORT"
echo "3. Configure appropriate ACL tokens if Consul ACLs are enabled"
```

## Cluster Health and Monitoring

### Dynamic Cluster Health Monitor
```bash
#!/bin/bash
# File: monitor-dynamic-cluster.sh

set -e

echo "=== Dynamic RabbitMQ Cluster Health Monitor ==="

# Auto-detect cluster nodes
CLUSTER_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
NODE_COUNT=$(echo "$CLUSTER_NODES" | wc -l)

echo "Detected cluster with $NODE_COUNT nodes:"
echo "$CLUSTER_NODES"
echo ""

# Monitor cluster health
monitor_cluster_health() {
    echo "=== Cluster Health Report $(date) ==="
    
    # Overall cluster status
    echo "1. Cluster Status:"
    sudo rabbitmqctl cluster_status
    echo ""
    
    # Node-specific health
    echo "2. Node Health:"
    for node in $CLUSTER_NODES; do
        echo "   Node: $node"
        if ssh "root@$node" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
            echo "     Status: ✓ Healthy"
            
            # Get node metrics
            MEMORY=$(ssh "root@$node" "rabbitmqctl status" | grep "Memory" | head -1)
            FD_USAGE=$(ssh "root@$node" "rabbitmqctl status" | grep "file_descriptors")
            echo "     Memory: $MEMORY"
            echo "     File Descriptors: $FD_USAGE"
        else
            echo "     Status: ✗ Unhealthy"
        fi
        echo ""
    done
    
    # Partition detection
    echo "3. Network Partitions:"
    PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().')
    if [ "$PARTITIONS" = "[]" ]; then
        echo "   ✓ No partitions detected"
    else
        echo "   ⚠ Partitions detected: $PARTITIONS"
    fi
    echo ""
    
    # Queue distribution
    echo "4. Queue Distribution:"
    sudo rabbitmqctl list_queues name node | grep -v "^name" | awk '{nodes[$2]++} END {for (node in nodes) print "   " node ": " nodes[node] " queues"}'
    echo ""
    
    # Resource alarms
    echo "5. Resource Alarms:"
    ALARMS=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().')
    if [ "$ALARMS" = "[]" ]; then
        echo "   ✓ No resource alarms"
    else
        echo "   ⚠ Active alarms: $ALARMS"
    fi
    echo ""
}

# Continuous monitoring
if [ "$1" = "--continuous" ]; then
    while true; do
        monitor_cluster_health
        echo "Sleeping for 60 seconds..."
        sleep 60
    done
else
    monitor_cluster_health
fi
```

This dynamic cluster configuration system provides the flexibility to deploy RabbitMQ clusters of any size while maintaining optimal performance, fault tolerance, and operational simplicity. The automated scripts handle the complexity of scaling configurations based on cluster size, ensuring consistent and reliable deployments.