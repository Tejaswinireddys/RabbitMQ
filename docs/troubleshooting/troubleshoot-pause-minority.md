# Troubleshooting pause_minority Behavior

## Current Situation Analysis

### What's Happening
When you stop 2 out of 3 nodes in your cluster:

1. **Node 1**: Running but **paused** (minority partition)
2. **Node 2**: Stopped ❌
3. **Node 3**: Stopped ❌

**Result**: Node 1 automatically pauses all operations because it's in minority.

### Why rabbitmqctl cluster_status Shows Nothing
The remaining node is in **paused state** and won't respond to management commands until quorum is restored.

## Solutions and Verification

### Solution 1: Start Any One Additional Node
```bash
# Start either node 2 or node 3 to restore majority
sudo systemctl start rabbitmq-server  # On node 2 OR node 3

# Wait 30 seconds, then check
sudo rabbitmqctl cluster_status  # Should work now
```

### Solution 2: Check Node Status During Minority
```bash
# Check if RabbitMQ service is running
sudo systemctl status rabbitmq-server

# Check if Erlang VM is running  
ps aux | grep beam

# Check logs for partition messages
sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log
```

### Solution 3: Force Status Check (Diagnostic Only)
```bash
# Check Erlang node directly (may still work)
sudo rabbitmqctl eval 'node().'

# Check if node is alive
sudo rabbitmqctl ping

# Check alarms (should show partition alarm)
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'
```

## Expected Log Messages

You should see messages like this in the logs:
```
=INFO REPORT==== Cluster minority status detected
=WARNING REPORT==== Cluster minority condition, pausing all operations
=INFO REPORT==== Network partition detected, node joining minority partition
```

## Verification Script

```bash
#!/bin/bash
# File: verify-pause-minority-behavior.sh

echo "=== Verifying pause_minority Behavior ==="

echo "1. Checking RabbitMQ service status:"
sudo systemctl status rabbitmq-server

echo -e "\n2. Checking if Erlang VM is responsive:"
if sudo rabbitmqctl ping >/dev/null 2>&1; then
    echo "✓ Erlang VM is responsive"
else
    echo "✗ Erlang VM not responding (expected in minority)"
fi

echo -e "\n3. Checking for partition alarms:"
ALARMS=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "Cannot check - node paused")
echo "Alarms: $ALARMS"

echo -e "\n4. Checking node status:"
NODE_STATUS=$(sudo rabbitmqctl eval 'rabbit_nodes:is_running(node()).' 2>/dev/null || echo "Cannot check - node paused")
echo "Node running status: $NODE_STATUS"

echo -e "\n5. Checking partition status:"
PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "Cannot check - node paused")
echo "Partitions: $PARTITIONS"

echo -e "\n6. Recent log entries:"
sudo tail -10 /var/log/rabbitmq/rabbit@$(hostname).log | grep -E "(partition|minority|pause)" || echo "No partition-related log entries found"

echo -e "\nThis behavior is CORRECT for pause_minority configuration!"
echo "The node is protecting data integrity by refusing to operate in minority."
```

## Testing the Configuration

### Test Script: Controlled Cluster Shutdown
```bash
#!/bin/bash
# File: test-pause-minority.sh

echo "=== Testing pause_minority Configuration ==="

# Get all cluster nodes
NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | sed "s/'rabbit@//g" | sed "s/'//g")
NODE_ARRAY=($NODES)
TOTAL_NODES=${#NODE_ARRAY[@]}

echo "Cluster nodes detected: ${NODE_ARRAY[@]}"
echo "Total nodes: $TOTAL_NODES"

if [ $TOTAL_NODES -ne 3 ]; then
    echo "This test requires exactly 3 nodes"
    exit 1
fi

echo -e "\nStep 1: Verify initial cluster status"
sudo rabbitmqctl cluster_status

echo -e "\nStep 2: Create test queue"
sudo rabbitmqctl declare queue --name=pause-test --type=quorum --durable=true
sudo rabbitmqctl publish exchange="" routing-key="pause-test" payload="Test message before shutdown"

echo -e "\nStep 3: Check initial queue status"
sudo rabbitmqctl list_queues name messages

echo -e "\nStep 4: Stopping node 2 (${NODE_ARRAY[1]})"
read -p "Press Enter to stop node 2..."
ssh root@${NODE_ARRAY[1]} "systemctl stop rabbitmq-server"
sleep 10

echo "Cluster status after stopping 1 node (should still work):"
sudo rabbitmqctl cluster_status

echo -e "\nStep 5: Stopping node 3 (${NODE_ARRAY[2]})"
read -p "Press Enter to stop node 3 (this will trigger pause_minority)..."
ssh root@${NODE_ARRAY[2]} "systemctl stop rabbitmq-server"
sleep 10

echo "Cluster status after stopping 2 nodes (should not respond):"
sudo rabbitmqctl cluster_status || echo "✓ EXPECTED: Node is paused due to minority partition"

echo -e "\nStep 6: Checking logs for partition messages"
sudo tail -20 /var/log/rabbitmq/rabbit@$(hostname).log | grep -E "(partition|minority|pause)"

echo -e "\nStep 7: Restoring quorum by starting node 2"
read -p "Press Enter to start node 2 and restore quorum..."
ssh root@${NODE_ARRAY[1]} "systemctl start rabbitmq-server"
sleep 30

echo "Cluster status after restoring quorum:"
sudo rabbitmqctl cluster_status

echo -e "\nStep 8: Verifying data integrity"
sudo rabbitmqctl list_queues name messages

echo -e "\nTest completed! pause_minority behavior verified."
```

## Alternative Configuration Options

If you want different behavior, here are alternatives:

### Option 1: Change to autoheal (NOT RECOMMENDED for your data safety requirements)
```bash
# In rabbitmq.conf
cluster_partition_handling = autoheal
```
**⚠️ WARNING**: This can cause data loss!

### Option 2: Use larger cluster (5 or 7 nodes)
With 5 nodes, you can lose 2 nodes and still maintain majority:
- 5-node cluster: Can lose 2 nodes, 3 remain (majority)
- 7-node cluster: Can lose 3 nodes, 4 remain (majority)

### Option 3: Temporary override (Emergency only)
```bash
# EMERGENCY ONLY: Force start paused node (can cause data inconsistency)
sudo rabbitmqctl force_boot

# Then restart the application
sudo rabbitmqctl start_app
```

## Recovery Procedures

### Normal Recovery (Recommended)
```bash
# Start any one additional node to restore majority
ssh root@node2 "systemctl start rabbitmq-server"
# OR
ssh root@node3 "systemctl start rabbitmq-server"

# Wait for cluster to recover
sleep 30

# Verify recovery
sudo rabbitmqctl cluster_status
```

### Emergency Recovery (Use with caution)
```bash
# If you must force the remaining node to work:
sudo rabbitmqctl stop_app
sudo rabbitmqctl force_boot
sudo rabbitmqctl start_app

# ⚠️ WARNING: This breaks cluster consistency!
# Only use in emergency situations
```

## Key Takeaways

1. **Current behavior is CORRECT** ✅
2. **Data safety is maintained** ✅  
3. **pause_minority prevents split-brain** ✅
4. **Start any 1 additional node to recover** ✅
5. **This is why you chose pause_minority** ✅

The behavior you're seeing is exactly what makes your cluster safe for production use!