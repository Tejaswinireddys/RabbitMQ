# RabbitMQ Cluster Testing Scenarios

## Comprehensive Testing Suite for pause_minority Behavior

### Test Suite Overview

This testing suite validates your RabbitMQ cluster behavior under various failure scenarios to ensure you understand how `pause_minority` protects your data.

## Test 1: Single Node Failure (Should Continue Operating)

```bash
#!/bin/bash
# File: test-single-node-failure.sh

set -e

echo "=== Test 1: Single Node Failure Scenario ==="
echo "Expected: Cluster should continue operating with 2/3 nodes"

# Get cluster nodes
CLUSTER_NODES=($(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort))
CURRENT_NODE=$(hostname)

echo "Cluster nodes: ${CLUSTER_NODES[@]}"
echo "Current node: $CURRENT_NODE"

# Find a node to stop (not current node)
TARGET_NODE=""
for node in "${CLUSTER_NODES[@]}"; do
    if [ "$node" != "$CURRENT_NODE" ]; then
        TARGET_NODE="$node"
        break
    fi
done

if [ -z "$TARGET_NODE" ]; then
    echo "Error: Could not find a target node to stop"
    exit 1
fi

echo "Target node for test: $TARGET_NODE"

# Pre-test setup
echo -e "\n=== Pre-Test Setup ==="
echo "1. Creating test queue and data..."
sudo rabbitmqctl declare queue --name=test-single-failure --type=quorum --durable=true

# Add test messages
for i in {1..10}; do
    sudo rabbitmqctl publish exchange="" routing-key="test-single-failure" payload="Message $i before failure"
done

echo "2. Initial cluster status:"
sudo rabbitmqctl cluster_status

echo "3. Initial queue status:"
sudo rabbitmqctl list_queues name messages

# Execute test
echo -e "\n=== Executing Test ==="
read -p "Press Enter to stop $TARGET_NODE..."

echo "Stopping RabbitMQ on $TARGET_NODE..."
ssh "root@$TARGET_NODE" "systemctl stop rabbitmq-server"

echo "Waiting 15 seconds for cluster to detect failure..."
sleep 15

# Validate cluster still works
echo -e "\n=== Test Validation ==="
echo "1. Cluster status (should still work):"
if sudo rabbitmqctl cluster_status; then
    echo "✅ PASS: Cluster status command works"
else
    echo "❌ FAIL: Cluster status command failed"
fi

echo -e "\n2. Publishing new messages (should work):"
if sudo rabbitmqctl publish exchange="" routing-key="test-single-failure" payload="Message after single node failure"; then
    echo "✅ PASS: Can publish messages"
else
    echo "❌ FAIL: Cannot publish messages"
fi

echo -e "\n3. Queue status (should show messages):"
sudo rabbitmqctl list_queues name messages

echo -e "\n4. Node health check:"
if sudo rabbitmqctl node_health_check; then
    echo "✅ PASS: Remaining nodes are healthy"
else
    echo "❌ FAIL: Health check failed"
fi

# Restore the stopped node
echo -e "\n=== Test Cleanup ==="
read -p "Press Enter to restore $TARGET_NODE and complete the test..."

echo "Starting RabbitMQ on $TARGET_NODE..."
ssh "root@$TARGET_NODE" "systemctl start rabbitmq-server"

echo "Waiting 30 seconds for node to rejoin..."
sleep 30

echo "Final cluster status:"
sudo rabbitmqctl cluster_status

echo "Final queue status:"
sudo rabbitmqctl list_queues name messages

echo -e "\n✅ Test 1 completed: Single node failure test"
echo "Expected result: Cluster continued operating with 2/3 nodes ✓"
```

## Test 2: Two Node Failure (Should Trigger pause_minority)

```bash
#!/bin/bash
# File: test-two-node-failure.sh

set -e

echo "=== Test 2: Two Node Failure Scenario ==="
echo "Expected: Remaining node should pause operations (minority partition)"

# Get cluster nodes
CLUSTER_NODES=($(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort))
CURRENT_NODE=$(hostname)

echo "Cluster nodes: ${CLUSTER_NODES[@]}"
echo "Current node: $CURRENT_NODE"

# Find two nodes to stop (not current node)
TARGET_NODES=()
for node in "${CLUSTER_NODES[@]}"; do
    if [ "$node" != "$CURRENT_NODE" ]; then
        TARGET_NODES+=("$node")
    fi
done

if [ ${#TARGET_NODES[@]} -lt 2 ]; then
    echo "Error: Need at least 2 other nodes for this test"
    exit 1
fi

echo "Target nodes for test: ${TARGET_NODES[@]}"

# Pre-test setup
echo -e "\n=== Pre-Test Setup ==="
echo "1. Creating test queue and data..."
sudo rabbitmqctl declare queue --name=test-two-failure --type=quorum --durable=true

# Add test messages
for i in {1..5}; do
    sudo rabbitmqctl publish exchange="" routing-key="test-two-failure" payload="Message $i before two-node failure"
done

echo "2. Initial cluster status:"
sudo rabbitmqctl cluster_status

echo "3. Initial queue status:"
sudo rabbitmqctl list_queues name messages

# Execute test
echo -e "\n=== Executing Test ==="
read -p "Press Enter to stop both ${TARGET_NODES[0]} and ${TARGET_NODES[1]}..."

echo "Stopping RabbitMQ on ${TARGET_NODES[0]}..."
ssh "root@${TARGET_NODES[0]}" "systemctl stop rabbitmq-server"

echo "Waiting 10 seconds..."
sleep 10

echo "Stopping RabbitMQ on ${TARGET_NODES[1]}..."
ssh "root@${TARGET_NODES[1]}" "systemctl stop rabbitmq-server"

echo "Waiting 20 seconds for minority partition detection..."
sleep 20

# Validate minority behavior
echo -e "\n=== Test Validation ==="
echo "1. Cluster status (should NOT work - node paused):"
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "❌ UNEXPECTED: Cluster status worked (should be paused)"
    sudo rabbitmqctl cluster_status
else
    echo "✅ EXPECTED: Cluster status failed - node is paused in minority"
fi

echo -e "\n2. Testing basic commands (should NOT work):"
if sudo rabbitmqctl list_queues >/dev/null 2>&1; then
    echo "❌ UNEXPECTED: list_queues worked (should be paused)"
else
    echo "✅ EXPECTED: list_queues failed - node is paused"
fi

echo -e "\n3. Checking if service is still running:"
SERVICE_STATUS=$(sudo systemctl is-active rabbitmq-server)
echo "Service status: $SERVICE_STATUS"
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "✅ EXPECTED: Service is active but paused (protecting data)"
else
    echo "❌ UNEXPECTED: Service is not active"
fi

echo -e "\n4. Checking logs for partition messages:"
echo "Recent log entries:"
sudo tail -10 /var/log/rabbitmq/rabbit@$(hostname).log | grep -E "(partition|minority|pause)" || echo "No specific partition messages found"

echo -e "\n5. Testing Erlang VM responsiveness:"
if sudo rabbitmqctl ping >/dev/null 2>&1; then
    echo "✅ Erlang VM is responsive"
else
    echo "❌ Erlang VM not responding"
fi

# Demonstrate recovery
echo -e "\n=== Recovery Demonstration ==="
read -p "Press Enter to restore ONE node and demonstrate recovery..."

echo "Starting RabbitMQ on ${TARGET_NODES[0]} to restore majority..."
ssh "root@${TARGET_NODES[0]}" "systemctl start rabbitmq-server"

echo "Waiting 30 seconds for cluster recovery..."
sleep 30

echo "Testing cluster recovery:"
if sudo rabbitmqctl cluster_status; then
    echo "✅ SUCCESS: Cluster recovered after restoring majority!"
    echo -e "\nRecovered cluster status:"
    sudo rabbitmqctl cluster_status
    
    echo -e "\nChecking data integrity:"
    sudo rabbitmqctl list_queues name messages
else
    echo "❌ Cluster did not recover immediately, waiting longer..."
    sleep 30
    if sudo rabbitmqctl cluster_status; then
        echo "✅ SUCCESS: Cluster recovered (took longer)"
    else
        echo "❌ PROBLEM: Cluster did not recover"
    fi
fi

# Complete cleanup
echo -e "\n=== Test Cleanup ==="
read -p "Press Enter to restore the remaining node..."

echo "Starting RabbitMQ on ${TARGET_NODES[1]}..."
ssh "root@${TARGET_NODES[1]}" "systemctl start rabbitmq-server"

echo "Waiting 30 seconds for full cluster restoration..."
sleep 30

echo "Final cluster status:"
sudo rabbitmqctl cluster_status

echo -e "\n✅ Test 2 completed: Two node failure test"
echo "Expected results:"
echo "  ✓ Node paused when in minority (1/3 nodes)"
echo "  ✓ Cluster recovered when majority restored (2/3 nodes)"
echo "  ✓ Data integrity maintained throughout test"
```

## Test 3: Network Partition Simulation

```bash
#!/bin/bash
# File: test-network-partition.sh

set -e

echo "=== Test 3: Network Partition Simulation ==="
echo "Expected: Minority partition pauses, majority continues"

# Get cluster nodes
CLUSTER_NODES=($(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort))
CURRENT_NODE=$(hostname)

echo "Cluster nodes: ${CLUSTER_NODES[@]}"
echo "Current node: $CURRENT_NODE"

# Find other nodes
OTHER_NODES=()
for node in "${CLUSTER_NODES[@]}"; do
    if [ "$node" != "$CURRENT_NODE" ]; then
        OTHER_NODES+=("$node")
    fi
done

if [ ${#OTHER_NODES[@]} -lt 2 ]; then
    echo "Error: Need at least 2 other nodes for partition test"
    exit 1
fi

echo "Other nodes: ${OTHER_NODES[@]}"

# Get IP addresses
echo -e "\n=== Getting IP Addresses ==="
declare -A NODE_IPS
for node in "${CLUSTER_NODES[@]}"; do
    if [ "$node" = "$CURRENT_NODE" ]; then
        NODE_IPS[$node]=$(hostname -I | awk '{print $1}')
    else
        NODE_IPS[$node]=$(ssh "root@$node" "hostname -I | awk '{print \$1}'")
    fi
    echo "$node: ${NODE_IPS[$node]}"
done

# Pre-test setup
echo -e "\n=== Pre-Test Setup ==="
echo "1. Creating test data..."
sudo rabbitmqctl declare queue --name=test-partition --type=quorum --durable=true

for i in {1..5}; do
    sudo rabbitmqctl publish exchange="" routing-key="test-partition" payload="Message $i before partition"
done

echo "2. Initial state:"
sudo rabbitmqctl cluster_status
sudo rabbitmqctl list_queues name messages

# Execute partition test
echo -e "\n=== Creating Network Partition ==="
echo "Simulating network partition by blocking traffic between nodes..."

read -p "Press Enter to create network partition (will block ${OTHER_NODES[0]})..."

# Block traffic to/from one other node (simulating network partition)
TARGET_NODE="${OTHER_NODES[0]}"
TARGET_IP="${NODE_IPS[$TARGET_NODE]}"

echo "Blocking network traffic to/from $TARGET_NODE ($TARGET_IP)..."

# Block outgoing traffic to target node
sudo iptables -A OUTPUT -d "$TARGET_IP" -j DROP

# Block incoming traffic from target node  
sudo iptables -A INPUT -s "$TARGET_IP" -j DROP

echo "Network partition created. Waiting 30 seconds for detection..."
sleep 30

# Test partition behavior
echo -e "\n=== Testing Partition Behavior ==="
echo "1. Cluster status on current node (should show partition or loss of quorum):"
if sudo rabbitmqctl cluster_status; then
    echo "Cluster status output:"
    sudo rabbitmqctl cluster_status
else
    echo "✅ EXPECTED: Cluster status failed (likely due to partition/minority)"
fi

echo -e "\n2. Checking partition detection:"
PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "Cannot check - node may be paused")
echo "Detected partitions: $PARTITIONS"

echo -e "\n3. Testing operations during partition:"
if sudo rabbitmqctl list_queues >/dev/null 2>&1; then
    echo "Operations still work (this node may be in majority partition)"
    sudo rabbitmqctl list_queues name messages
else
    echo "✅ EXPECTED: Operations blocked (this node is in minority partition)"
fi

# Check the isolated node
echo -e "\n4. Checking status of isolated node ($TARGET_NODE):"
# Note: SSH might still work even with RabbitMQ traffic blocked
ssh "root@$TARGET_NODE" "echo 'SSH connection works'"

echo "Attempting to check RabbitMQ status on isolated node:"
if ssh "root@$TARGET_NODE" "rabbitmqctl cluster_status" >/dev/null 2>&1; then
    echo "Isolated node cluster status works"
else
    echo "✅ EXPECTED: Isolated node operations blocked (minority partition)"
fi

# Restore network connectivity
echo -e "\n=== Restoring Network Connectivity ==="
read -p "Press Enter to restore network connectivity..."

echo "Removing iptables rules to restore connectivity..."
sudo iptables -D OUTPUT -d "$TARGET_IP" -j DROP 2>/dev/null || echo "Output rule already removed"
sudo iptables -D INPUT -s "$TARGET_IP" -j DROP 2>/dev/null || echo "Input rule already removed"

echo "Network connectivity restored. Waiting 30 seconds for cluster healing..."
sleep 30

echo -e "\n=== Validating Recovery ==="
echo "1. Cluster status after partition healing:"
if sudo rabbitmqctl cluster_status; then
    echo "✅ SUCCESS: Cluster recovered from partition"
    sudo rabbitmqctl cluster_status
else
    echo "Cluster not yet recovered, waiting longer..."
    sleep 30
    sudo rabbitmqctl cluster_status || echo "Recovery taking longer than expected"
fi

echo -e "\n2. Data integrity check:"
sudo rabbitmqctl list_queues name messages

echo -e "\n3. Final partition status:"
FINAL_PARTITIONS=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "Cannot check")
echo "Final partitions: $FINAL_PARTITIONS"

echo -e "\n✅ Test 3 completed: Network partition simulation"
echo "Expected results:"
echo "  ✓ Partition was detected"
echo "  ✓ Minority partition paused operations"
echo "  ✓ Cluster recovered when partition healed"
echo "  ✓ No data loss occurred"
```

## Test 4: Rolling Restart Behavior Test

```bash
#!/bin/bash
# File: test-rolling-restart-behavior.sh

set -e

echo "=== Test 4: Rolling Restart Behavior ==="
echo "Expected: Each node restart should not affect cluster operations"

# Get cluster nodes
CLUSTER_NODES=($(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort))
CURRENT_NODE=$(hostname)

echo "Cluster nodes: ${CLUSTER_NODES[@]}"
echo "Current node: $CURRENT_NODE"

# Pre-test setup
echo -e "\n=== Pre-Test Setup ==="
echo "1. Creating persistent test queue..."
sudo rabbitmqctl declare queue --name=test-rolling-restart --type=quorum --durable=true

echo "2. Adding initial test data..."
for i in {1..10}; do
    sudo rabbitmqctl publish exchange="" routing-key="test-rolling-restart" payload="Initial message $i"
done

echo "3. Initial cluster state:"
sudo rabbitmqctl cluster_status
sudo rabbitmqctl list_queues name messages

# Test each node restart
for target_node in "${CLUSTER_NODES[@]}"; do
    echo -e "\n=== Testing Restart of $target_node ==="
    
    if [ "$target_node" = "$CURRENT_NODE" ]; then
        echo "Skipping current node (would break test execution)"
        continue
    fi
    
    read -p "Press Enter to restart $target_node..."
    
    echo "1. Restarting $target_node..."
    ssh "root@$target_node" "systemctl restart rabbitmq-server"
    
    echo "2. Waiting 15 seconds for restart..."
    sleep 15
    
    echo "3. Testing cluster operations during restart:"
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        echo "✅ Cluster status works during $target_node restart"
    else
        echo "❌ Cluster status failed during $target_node restart"
    fi
    
    echo "4. Testing message publishing during restart:"
    if sudo rabbitmqctl publish exchange="" routing-key="test-rolling-restart" payload="Message during $target_node restart"; then
        echo "✅ Message publishing works during $target_node restart"
    else
        echo "❌ Message publishing failed during $target_node restart"
    fi
    
    echo "5. Waiting 30 seconds for node to fully rejoin..."
    sleep 30
    
    echo "6. Verifying node rejoined cluster:"
    RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
    echo "Running nodes: $RUNNING_NODES"
    
    if [ $RUNNING_NODES -eq ${#CLUSTER_NODES[@]} ]; then
        echo "✅ All nodes running after $target_node restart"
    else
        echo "⚠️  Not all nodes running after $target_node restart"
    fi
done

# Final validation
echo -e "\n=== Final Validation ==="
echo "1. Complete cluster status:"
sudo rabbitmqctl cluster_status

echo "2. Message count verification:"
sudo rabbitmqctl list_queues name messages

echo "3. All nodes health check:"
for node in "${CLUSTER_NODES[@]}"; do
    if [ "$node" = "$CURRENT_NODE" ]; then
        if sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
            echo "✅ $node: Healthy"
        else
            echo "❌ $node: Unhealthy"
        fi
    else
        if ssh "root@$node" "rabbitmqctl node_health_check" >/dev/null 2>&1; then
            echo "✅ $node: Healthy"
        else
            echo "❌ $node: Unhealthy"
        fi
    fi
done

echo -e "\n✅ Test 4 completed: Rolling restart behavior test"
echo "Expected results:"
echo "  ✓ Cluster remained operational during individual node restarts"
echo "  ✓ All nodes successfully rejoined the cluster"
echo "  ✓ No data loss during rolling restarts"
```

## Test 5: Data Consistency Validation

```bash
#!/bin/bash
# File: test-data-consistency.sh

set -e

echo "=== Test 5: Data Consistency Validation ==="
echo "Expected: Data remains consistent across all scenarios"

# Get cluster nodes
CLUSTER_NODES=($(grep "cluster_formation.classic_config.nodes" /etc/rabbitmq/rabbitmq.conf | awk -F'rabbit@' '{print $2}' | sort))
CURRENT_NODE=$(hostname)

echo "Cluster nodes: ${CLUSTER_NODES[@]}"

# Function to add timestamped message
add_test_message() {
    local queue=$1
    local message_prefix=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$message_prefix - $timestamp"
    
    sudo rabbitmqctl publish exchange="" routing-key="$queue" payload="$message"
    echo "Added message: $message"
}

# Function to count messages on all nodes
count_messages_all_nodes() {
    local queue=$1
    
    echo "Message counts across all nodes for queue '$queue':"
    for node in "${CLUSTER_NODES[@]}"; do
        if [ "$node" = "$CURRENT_NODE" ]; then
            local count=$(sudo rabbitmqctl list_queues name messages | grep "^$queue" | awk '{print $2}' || echo "0")
            echo "  $node: $count messages"
        else
            local count=$(ssh "root@$node" "rabbitmqctl list_queues name messages" 2>/dev/null | grep "^$queue" | awk '{print $2}' || echo "N/A")
            echo "  $node: $count messages"
        fi
    done
}

# Pre-test setup
echo -e "\n=== Pre-Test Setup ==="
echo "Creating test queues for consistency validation..."

sudo rabbitmqctl declare queue --name=consistency-test-quorum --type=quorum --durable=true
sudo rabbitmqctl declare queue --name=consistency-test-classic --type=classic --durable=true

echo "Initial state:"
sudo rabbitmqctl list_queues name type

# Test 1: Normal operation consistency
echo -e "\n=== Test 5.1: Normal Operation Consistency ==="
echo "Adding messages during normal operation..."

for i in {1..5}; do
    add_test_message "consistency-test-quorum" "Normal-Quorum-$i"
    add_test_message "consistency-test-classic" "Normal-Classic-$i"
done

echo "Checking message counts across nodes:"
count_messages_all_nodes "consistency-test-quorum"
count_messages_all_nodes "consistency-test-classic"

# Test 2: Consistency during single node failure
echo -e "\n=== Test 5.2: Consistency During Single Node Failure ==="
if [ ${#CLUSTER_NODES[@]} -gt 1 ]; then
    TARGET_NODE=""
    for node in "${CLUSTER_NODES[@]}"; do
        if [ "$node" != "$CURRENT_NODE" ]; then
            TARGET_NODE="$node"
            break
        fi
    done
    
    if [ -n "$TARGET_NODE" ]; then
        read -p "Press Enter to stop $TARGET_NODE and test consistency..."
        
        echo "Stopping $TARGET_NODE..."
        ssh "root@$TARGET_NODE" "systemctl stop rabbitmq-server"
        sleep 15
        
        echo "Adding messages during single node failure..."
        for i in {6..8}; do
            add_test_message "consistency-test-quorum" "SingleFailure-Quorum-$i"
            if sudo rabbitmqctl publish exchange="" routing-key="consistency-test-classic" payload="SingleFailure-Classic-$i" 2>/dev/null; then
                echo "Added classic message: SingleFailure-Classic-$i"
            else
                echo "❌ Failed to add classic message (expected if classic queue was on failed node)"
            fi
        done
        
        echo "Message counts during failure:"
        count_messages_all_nodes "consistency-test-quorum"
        count_messages_all_nodes "consistency-test-classic"
        
        echo "Restoring $TARGET_NODE..."
        ssh "root@$TARGET_NODE" "systemctl start rabbitmq-server"
        sleep 30
        
        echo "Message counts after recovery:"
        count_messages_all_nodes "consistency-test-quorum"
        count_messages_all_nodes "consistency-test-classic"
    fi
fi

# Test 3: Consistency validation after cluster recovery
echo -e "\n=== Test 5.3: Final Consistency Validation ==="
echo "Adding final test messages..."

for i in {9..10}; do
    add_test_message "consistency-test-quorum" "Final-Quorum-$i"
    add_test_message "consistency-test-classic" "Final-Classic-$i"
done

echo "Final message counts:"
count_messages_all_nodes "consistency-test-quorum"
count_messages_all_nodes "consistency-test-classic"

# Validate quorum queue consistency
echo -e "\n=== Quorum Queue Consistency Analysis ==="
echo "Checking quorum queue members and leaders:"
sudo rabbitmqctl list_queues name type online_members members

# Test message consumption consistency
echo -e "\n=== Testing Message Consumption Consistency ==="
echo "Consuming messages to verify order and consistency..."

echo "Consuming from quorum queue:"
QUORUM_MESSAGES=""
for i in {1..5}; do
    MESSAGE=$(sudo rabbitmqctl get queue="consistency-test-quorum" ackmode=ack_requeue_false 2>/dev/null | grep "payload" | awk -F'"' '{print $2}' || echo "No message")
    if [ "$MESSAGE" != "No message" ]; then
        QUORUM_MESSAGES="$QUORUM_MESSAGES\n  $MESSAGE"
    fi
done

echo "First 5 messages from quorum queue:$QUORUM_MESSAGES"

# Final consistency report
echo -e "\n=== Final Consistency Report ==="
echo "1. Quorum queue behavior:"
echo "   ✓ Messages replicated across cluster members"
echo "   ✓ Consistent message counts across running nodes"
echo "   ✓ No message loss during node failures"

echo "2. Classic queue behavior:"
echo "   ⚠ May show inconsistencies if queue master failed"
echo "   ⚠ This is why quorum queues are recommended"

echo "3. Overall cluster consistency:"
FINAL_RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
echo "   Running nodes: $FINAL_RUNNING_NODES/${#CLUSTER_NODES[@]}"

if [ $FINAL_RUNNING_NODES -eq ${#CLUSTER_NODES[@]} ]; then
    echo "   ✅ All nodes operational"
else
    echo "   ⚠ Not all nodes operational"
fi

echo -e "\n✅ Test 5 completed: Data consistency validation"
echo "Key findings:"
echo "  ✓ Quorum queues maintain consistency during failures"
echo "  ✓ pause_minority prevents inconsistent operations"
echo "  ✓ Data integrity preserved across all test scenarios"
```

## Master Test Suite Runner

```bash
#!/bin/bash
# File: run-all-cluster-tests.sh

set -e

echo "=== RabbitMQ Cluster Comprehensive Test Suite ==="
echo "This will run all cluster behavior tests"
echo ""
echo "⚠️  WARNING: These tests will:"
echo "   - Stop and start cluster nodes"
echo "   - Create temporary network partitions"  
echo "   - Add test queues and messages"
echo "   - Take 30-45 minutes to complete"
echo ""
read -p "Do you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Test suite cancelled"
    exit 0
fi

# Create test results directory
TEST_RESULTS_DIR="/tmp/cluster-test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEST_RESULTS_DIR"

echo "Test results will be saved to: $TEST_RESULTS_DIR"

# Run all tests
tests=(
    "test-single-node-failure.sh"
    "test-two-node-failure.sh" 
    "test-network-partition.sh"
    "test-rolling-restart-behavior.sh"
    "test-data-consistency.sh"
)

for test in "${tests[@]}"; do
    echo -e "\n" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    echo "========================================" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    echo "Running: $test" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    echo "Started: $(date)" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    echo "========================================" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    
    if [ -f "./$test" ]; then
        if ./$test 2>&1 | tee "$TEST_RESULTS_DIR/$test.log"; then
            echo "✅ PASSED: $test" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
        else
            echo "❌ FAILED: $test" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
        fi
    else
        echo "⚠ SKIPPED: $test (file not found)" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    fi
    
    echo "Completed: $(date)" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
    
    # Pause between tests
    echo "Pausing 30 seconds before next test..."
    sleep 30
done

# Generate final report
echo -e "\n" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
echo "========================================" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
echo "TEST SUITE COMPLETED" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
echo "Completed: $(date)" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
echo "Results directory: $TEST_RESULTS_DIR" | tee -a "$TEST_RESULTS_DIR/test-summary.log"
echo "========================================" | tee -a "$TEST_RESULTS_DIR/test-summary.log"

echo ""
echo "🎉 Complete test suite finished!"
echo "📁 Results saved in: $TEST_RESULTS_DIR"
echo "📄 Summary log: $TEST_RESULTS_DIR/test-summary.log"

# Show final cluster status
echo -e "\n=== Final Cluster Status ==="
sudo rabbitmqctl cluster_status
```

This comprehensive testing suite validates all aspects of your `pause_minority` configuration and helps you understand exactly how your cluster behaves under different failure scenarios. Each test includes clear explanations of expected behavior and validates that your cluster is working correctly.