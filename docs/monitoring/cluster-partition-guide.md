# RabbitMQ Cluster Partition Handling Guide

## Overview

Network partitions in RabbitMQ clusters occur when nodes lose connectivity with each other but remain operational. This guide explains the partition handling strategies and why `pause_minority` is recommended for data-critical applications.

## Partition Handling Strategies

### 1. pause_minority (RECOMMENDED)

#### How it Works
- When a network partition occurs, only the **majority partition** (2+ nodes out of 3) remains active
- The **minority partition** (1 node out of 3) **pauses all operations**
- Ensures **no split-brain scenarios** and **zero data loss**

#### Configuration
```bash
# In rabbitmq.conf
cluster_partition_handling = pause_minority
```

#### Advantages ✅
- **100% Data Consistency** - No conflicting operations
- **Zero Data Loss** - Guaranteed data safety
- **Predictable Behavior** - Clear majority rule
- **Enterprise Grade** - Preferred for critical systems
- **No Manual Intervention** - Automatic resolution when partition heals

#### Disadvantages ⚠️
- **Reduced Availability** - Minority partition becomes unavailable
- **Service Interruption** - Applications connected to minority partition fail
- **Requires Majority** - Need 2+ nodes for operations

#### Best For
- Financial applications
- Critical data systems
- Compliance-required environments
- When data integrity is paramount

### 2. autoheal (Alternative)

#### How it Works
- Both partitions remain **active during split**
- RabbitMQ **automatically chooses a winner** when partition heals
- **Data from losing partition is discarded**

#### Configuration
```bash
# In rabbitmq.conf
cluster_partition_handling = autoheal
```

#### Advantages ✅
- **High Availability** - Both partitions remain operational
- **Continuous Service** - No service interruption
- **Automatic Recovery** - Self-healing without intervention

#### Disadvantages ❌
- **Potential Data Loss** - Losing partition data is discarded
- **Temporary Inconsistency** - Conflicting data during partition
- **Unpredictable** - Winner selection algorithm may vary
- **Complex Recovery** - May require manual intervention

#### Best For
- High availability applications
- Non-critical data scenarios
- When uptime is more important than consistency

## Detailed Comparison

| Aspect | pause_minority | autoheal |
|--------|----------------|----------|
| **Data Safety** | 🟢 Guaranteed | 🔴 Risk of loss |
| **Consistency** | 🟢 Strong | 🔴 Eventual |
| **Availability** | 🔴 Limited | 🟢 High |
| **Split-brain** | 🟢 Prevented | 🔴 Possible |
| **Manual Intervention** | 🟢 None required | 🔴 May be needed |
| **Production Ready** | 🟢 Enterprise grade | 🔴 Use with caution |

## Network Partition Scenarios

### Scenario 1: Single Node Isolation (pause_minority)
```
Initial: [Node1] ←→ [Node2] ←→ [Node3]
Partition: [Node1] × × [Node2] ←→ [Node3]

Result:
- Majority (Node2, Node3): ✅ ACTIVE
- Minority (Node1): ⏸️ PAUSED
- Data Safety: ✅ GUARANTEED
```

### Scenario 2: Network Split (pause_minority)
```
Initial: [Node1] ←→ [Node2] ←→ [Node3]
Partition: [Node1] × × [Node2] × × [Node3]

Result:
- All nodes become minority: ⏸️ ALL PAUSED
- Cluster becomes unavailable: ❌ NO OPERATIONS
- Data Safety: ✅ GUARANTEED (no conflicting writes)
```

### Scenario 3: Partition Recovery (pause_minority)
```
Partition Heals: [Node1] ←→ [Node2] ←→ [Node3]

Result:
- Paused nodes automatically resume: ✅ AUTO-RECOVERY
- No data conflicts: ✅ CONSISTENT STATE
- Full cluster operational: ✅ RESTORED
```

## Configuration Best Practices

### Enhanced pause_minority Configuration
```bash
# rabbitmq.conf
cluster_partition_handling = pause_minority

# Network partition detection tuning
net_ticktime = 60
cluster_keepalive_interval = 10000

# Startup delay to prevent false partitions
cluster_formation.randomized_startup_delay_range.min = 5
cluster_formation.randomized_startup_delay_range.max = 30

# Heartbeat for faster detection
heartbeat = 60
```

### Advanced Configuration (advanced.config)
```erlang
[
  {rabbit, [
    {cluster_partition_handling, pause_minority},
    
    % Network partition detection settings
    {net_ticktime, 60},
    {cluster_keepalive_interval, 10000},
    
    % Mnesia settings for partition handling
    {mnesia_table_loading_retry_timeout, 30000},
    {mnesia_table_loading_retry_limit, 10}
  ]},
  
  {kernel, [
    % Erlang distribution settings
    {net_setuptime, 120},
    {net_kernel, [{inet_dist_connect_options, 
      [{keepalive, true}, {nodelay, true}]}]}
  ]}
].
```

## Monitoring and Alerting

### Partition Detection Commands
```bash
# Check cluster status
sudo rabbitmqctl cluster_status

# Check node health
sudo rabbitmqctl node_health_check

# Check alarms (including partition alarms)
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'

# Check network partition status
sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().'
```

### Monitoring Script
```bash
#!/bin/bash
# File: monitor_partitions.sh

ALERT_EMAIL="admin@company.com"

# Check for partitions
PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null)

if [[ "$PARTITIONS" != "[]" ]]; then
    echo "CRITICAL: Network partition detected!" | mail -s "RabbitMQ Partition Alert" $ALERT_EMAIL
    echo "Partitions: $PARTITIONS"
fi

# Check cluster status
CLUSTER_STATUS=$(sudo rabbitmqctl cluster_status 2>/dev/null)
RUNNING_NODES=$(echo "$CLUSTER_STATUS" | grep "Running" | wc -l)

if [[ $RUNNING_NODES -lt 2 ]]; then
    echo "WARNING: Less than 2 nodes running!" | mail -s "RabbitMQ Cluster Alert" $ALERT_EMAIL
fi
```

## Testing Partition Handling

### Test Script for pause_minority
```bash
#!/bin/bash
# File: test_partition_handling.sh

echo "=== Testing pause_minority Partition Handling ==="

# Step 1: Create test queue
echo "1. Creating test queue..."
sudo rabbitmqctl declare queue --name=partition_test --type=quorum --durable=true

# Step 2: Publish test messages
echo "2. Publishing test messages..."
for i in {1..10}; do
    sudo rabbitmqctl publish exchange="" routing-key="partition_test" payload="Test message $i"
done

# Step 3: Check initial queue status
echo "3. Initial queue status:"
sudo rabbitmqctl list_queues name messages

# Step 4: Simulate network partition (isolate node3)
echo "4. Simulating network partition (isolating node3)..."
read -p "Node3 IP: " NODE3_IP
sudo iptables -A INPUT -s $NODE3_IP -j DROP
sudo iptables -A OUTPUT -d $NODE3_IP -j DROP

echo "Waiting 30 seconds for partition detection..."
sleep 30

# Step 5: Check cluster status during partition
echo "5. Cluster status during partition:"
sudo rabbitmqctl cluster_status

# Step 6: Try to publish more messages (should work on majority)
echo "6. Publishing messages during partition..."
for i in {11..15}; do
    sudo rabbitmqctl publish exchange="" routing-key="partition_test" payload="Message during partition $i"
done

# Step 7: Check queue status during partition
echo "7. Queue status during partition:"
sudo rabbitmqctl list_queues name messages

# Step 8: Restore network connectivity
echo "8. Restoring network connectivity..."
sudo iptables -D INPUT -s $NODE3_IP -j DROP
sudo iptables -D OUTPUT -d $NODE3_IP -j DROP

echo "Waiting 30 seconds for partition healing..."
sleep 30

# Step 9: Check final cluster status
echo "9. Final cluster status:"
sudo rabbitmqctl cluster_status

# Step 10: Check final queue status
echo "10. Final queue status:"
sudo rabbitmqctl list_queues name messages

echo "Partition handling test completed!"
```

## Troubleshooting Partition Issues

### Common Issues and Solutions

#### 1. False Partitions During Startup
**Problem**: Nodes detect partitions during cluster startup
**Solution**: 
```bash
# Add randomized startup delay
cluster_formation.randomized_startup_delay_range.min = 5
cluster_formation.randomized_startup_delay_range.max = 30
```

#### 2. Frequent Partition Detection
**Problem**: Network instability causes frequent partitions
**Solution**:
```bash
# Increase network timeouts
net_ticktime = 120
cluster_keepalive_interval = 15000
heartbeat = 120
```

#### 3. Manual Partition Recovery
**Problem**: Partition doesn't heal automatically
**Solution**:
```bash
# Force cluster restart (CAUTION: Only if necessary)
sudo rabbitmqctl stop_app
sudo rabbitmqctl start_app

# Or reset and rejoin cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@primary-node
sudo rabbitmqctl start_app
```

## Production Recommendations

### 1. Network Infrastructure
- **Redundant network paths** between cluster nodes
- **Dedicated cluster network** separate from client traffic
- **Low latency connections** (< 50ms recommended)
- **Network monitoring** for early detection of issues

### 2. Monitoring and Alerting
- **Continuous monitoring** of cluster status
- **Automated alerts** for partition events
- **Log analysis** for partition patterns
- **Regular testing** of partition scenarios

### 3. Application Design
- **Connection pooling** with multiple node endpoints
- **Graceful degradation** when cluster is unavailable
- **Retry logic** with exponential backoff
- **Circuit breaker patterns** for partition scenarios

### 4. Operational Procedures
- **Documented procedures** for partition handling
- **Escalation paths** for partition incidents
- **Regular drills** for partition scenarios
- **Capacity planning** for reduced availability

## Conclusion

For your requirements of **zero data loss** and **high data safety**, `pause_minority` is the correct and recommended configuration. This ensures:

- ✅ **No data loss** during network partitions
- ✅ **Strong consistency** across the cluster
- ✅ **Predictable behavior** in failure scenarios
- ✅ **Enterprise-grade reliability** for production use

The trade-off of reduced availability during partitions is acceptable when data integrity is the primary concern.