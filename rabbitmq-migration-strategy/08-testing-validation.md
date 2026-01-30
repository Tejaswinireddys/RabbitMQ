# 08. Testing and Validation Strategy

## Overview

This document outlines the comprehensive testing strategy for validating the RabbitMQ migration from 3.12 to 4.1.4 with quorum queue conversion.

---

## 1. Testing Phases

```
┌─────────────────────────────────────────────────────────┐
│                   TESTING PHASES                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Phase 1: Unit Testing (Green Cluster)                  │
│  └── Basic connectivity, queue operations               │
│                                                          │
│  Phase 2: Integration Testing                           │
│  └── Application connectivity, message flow             │
│                                                          │
│  Phase 3: Performance Testing                           │
│  └── Throughput, latency, resource utilization          │
│                                                          │
│  Phase 4: Chaos Testing                                 │
│  └── Failure scenarios, recovery validation             │
│                                                          │
│  Phase 5: User Acceptance Testing                       │
│  └── End-to-end business workflows                      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Phase 1: Unit Testing

### 2.1 Cluster Health Tests

```bash
#!/bin/bash
# test-cluster-health.sh

echo "=== Cluster Health Tests ==="
PASS=0
FAIL=0

# Test 1: All nodes running
echo -n "Test 1: All nodes running... "
NODE_COUNT=$(rabbitmqctl cluster_status | grep -c "running_nodes")
if [ "$NODE_COUNT" -eq 3 ]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL (expected 3, got $NODE_COUNT)"
    ((FAIL++))
fi

# Test 2: No alarms
echo -n "Test 2: No local alarms... "
ALARMS=$(rabbitmq-diagnostics check_local_alarms 2>&1)
if [[ "$ALARMS" == *"ok"* ]]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL"
    ((FAIL++))
fi

# Test 3: Port connectivity
echo -n "Test 3: Port 5672 listening... "
if nc -z localhost 5672; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL"
    ((FAIL++))
fi

# Test 4: Management UI accessible
echo -n "Test 4: Management API accessible... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:15672/api/overview)
if [ "$HTTP_CODE" -eq 200 ]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL (HTTP $HTTP_CODE)"
    ((FAIL++))
fi

# Test 5: Disk space sufficient
echo -n "Test 5: Disk space check... "
DISK_OK=$(rabbitmq-diagnostics check_if_node_is_quorum_critical 2>&1)
if [[ "$DISK_OK" == *"ok"* ]]; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL"
    ((FAIL++))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
```

### 2.2 Quorum Queue Functionality Tests

```python
#!/usr/bin/env python3
# test_quorum_queues.py

import pika
import time
import sys

def test_quorum_queue_creation():
    """Test creating a quorum queue"""
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()

    # Declare quorum queue
    channel.queue_declare(
        queue='test-quorum-create',
        durable=True,
        arguments={'x-queue-type': 'quorum'}
    )

    # Verify queue type
    # (Check via management API or rabbitmqctl)

    channel.queue_delete(queue='test-quorum-create')
    connection.close()
    print("✓ Quorum queue creation test passed")

def test_publish_consume():
    """Test basic publish/consume on quorum queue"""
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()

    channel.queue_declare(
        queue='test-quorum-pubsub',
        durable=True,
        arguments={'x-queue-type': 'quorum'}
    )

    # Publish
    test_message = f"Test message {time.time()}"
    channel.basic_publish(
        exchange='',
        routing_key='test-quorum-pubsub',
        body=test_message,
        properties=pika.BasicProperties(delivery_mode=2)
    )

    # Consume
    method, properties, body = channel.basic_get('test-quorum-pubsub', auto_ack=True)

    assert body.decode() == test_message, "Message mismatch!"

    channel.queue_delete(queue='test-quorum-pubsub')
    connection.close()
    print("✓ Publish/consume test passed")

def test_message_persistence():
    """Test message persistence across restart"""
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()

    channel.queue_declare(
        queue='test-quorum-persist',
        durable=True,
        arguments={'x-queue-type': 'quorum'}
    )

    # Publish persistent message
    channel.basic_publish(
        exchange='',
        routing_key='test-quorum-persist',
        body='Persistent test message',
        properties=pika.BasicProperties(delivery_mode=2)
    )

    connection.close()

    # Reconnect and verify
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()

    method, properties, body = channel.basic_get('test-quorum-persist', auto_ack=True)
    assert body == b'Persistent test message', "Persistent message lost!"

    channel.queue_delete(queue='test-quorum-persist')
    connection.close()
    print("✓ Message persistence test passed")

def test_delivery_limit():
    """Test poison message handling with delivery limit"""
    connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
    channel = connection.channel()

    # Declare DLX
    channel.exchange_declare(exchange='test-dlx', exchange_type='direct')
    channel.queue_declare(queue='test-dlq', durable=True)
    channel.queue_bind(queue='test-dlq', exchange='test-dlx', routing_key='poison')

    # Declare quorum queue with delivery limit
    channel.queue_declare(
        queue='test-quorum-dlimit',
        durable=True,
        arguments={
            'x-queue-type': 'quorum',
            'x-delivery-limit': 3,
            'x-dead-letter-exchange': 'test-dlx',
            'x-dead-letter-routing-key': 'poison'
        }
    )

    # Publish message
    channel.basic_publish(
        exchange='',
        routing_key='test-quorum-dlimit',
        body='Poison message test',
        properties=pika.BasicProperties(delivery_mode=2)
    )

    # Simulate failed processing (nack/requeue)
    for i in range(4):
        method, properties, body = channel.basic_get('test-quorum-dlimit', auto_ack=False)
        if method:
            channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        time.sleep(0.5)

    # Message should be in DLQ
    time.sleep(1)
    method, properties, body = channel.basic_get('test-dlq', auto_ack=True)
    assert body == b'Poison message test', "Message not in DLQ!"

    # Cleanup
    channel.queue_delete(queue='test-quorum-dlimit')
    channel.queue_delete(queue='test-dlq')
    channel.exchange_delete(exchange='test-dlx')
    connection.close()
    print("✓ Delivery limit test passed")

if __name__ == '__main__':
    try:
        test_quorum_queue_creation()
        test_publish_consume()
        test_message_persistence()
        test_delivery_limit()
        print("\n✓ All quorum queue tests passed!")
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
```

---

## 3. Phase 2: Integration Testing

### 3.1 Application Connectivity Tests

```python
#!/usr/bin/env python3
# test_application_connectivity.py

import pika
import json
import time

class ApplicationConnectivityTest:
    def __init__(self, host, port=5672, vhost='/', user='guest', password='guest'):
        self.credentials = pika.PlainCredentials(user, password)
        self.parameters = pika.ConnectionParameters(
            host=host,
            port=port,
            virtual_host=vhost,
            credentials=self.credentials,
            heartbeat=60,
            connection_attempts=3,
            retry_delay=5
        )

    def test_connection(self):
        """Test basic connection"""
        connection = pika.BlockingConnection(self.parameters)
        assert connection.is_open, "Connection not open"
        connection.close()
        print("✓ Connection test passed")

    def test_channel_operations(self):
        """Test channel operations"""
        connection = pika.BlockingConnection(self.parameters)
        channel = connection.channel()

        # Test queue operations
        channel.queue_declare(queue='test-integration', durable=True,
                             arguments={'x-queue-type': 'quorum'})

        # Test exchange operations
        channel.exchange_declare(exchange='test-exchange', exchange_type='direct')

        # Test binding
        channel.queue_bind(queue='test-integration',
                          exchange='test-exchange',
                          routing_key='test-key')

        # Cleanup
        channel.queue_unbind(queue='test-integration',
                            exchange='test-exchange',
                            routing_key='test-key')
        channel.queue_delete(queue='test-integration')
        channel.exchange_delete(exchange='test-exchange')

        connection.close()
        print("✓ Channel operations test passed")

    def test_publish_confirm(self):
        """Test publisher confirms"""
        connection = pika.BlockingConnection(self.parameters)
        channel = connection.channel()
        channel.confirm_delivery()

        channel.queue_declare(queue='test-confirms', durable=True,
                             arguments={'x-queue-type': 'quorum'})

        # Publish with confirm
        channel.basic_publish(
            exchange='',
            routing_key='test-confirms',
            body='Test message',
            properties=pika.BasicProperties(delivery_mode=2),
            mandatory=True
        )

        channel.queue_delete(queue='test-confirms')
        connection.close()
        print("✓ Publisher confirms test passed")

    def test_consumer_ack(self):
        """Test consumer acknowledgments"""
        connection = pika.BlockingConnection(self.parameters)
        channel = connection.channel()

        channel.queue_declare(queue='test-consumer', durable=True,
                             arguments={'x-queue-type': 'quorum'})

        # Publish
        channel.basic_publish(exchange='', routing_key='test-consumer',
                             body='Test', properties=pika.BasicProperties(delivery_mode=2))

        # Consume with manual ack
        channel.basic_qos(prefetch_count=1)
        method, properties, body = channel.basic_get('test-consumer', auto_ack=False)
        assert method is not None, "No message received"
        channel.basic_ack(delivery_tag=method.delivery_tag)

        channel.queue_delete(queue='test-consumer')
        connection.close()
        print("✓ Consumer acknowledgment test passed")

    def run_all_tests(self):
        """Run all integration tests"""
        self.test_connection()
        self.test_channel_operations()
        self.test_publish_confirm()
        self.test_consumer_ack()
        print("\n✓ All integration tests passed!")

if __name__ == '__main__':
    import sys
    host = sys.argv[1] if len(sys.argv) > 1 else 'localhost'
    tester = ApplicationConnectivityTest(host)
    tester.run_all_tests()
```

### 3.2 End-to-End Message Flow Test

```python
#!/usr/bin/env python3
# test_e2e_message_flow.py

import pika
import json
import threading
import time
import uuid

class E2EMessageFlowTest:
    def __init__(self, host):
        self.host = host
        self.received_messages = []
        self.test_id = str(uuid.uuid4())[:8]

    def producer(self, count=100):
        """Producer thread"""
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(self.host)
        )
        channel = connection.channel()

        for i in range(count):
            message = json.dumps({
                'test_id': self.test_id,
                'sequence': i,
                'timestamp': time.time()
            })
            channel.basic_publish(
                exchange='',
                routing_key='test-e2e-flow',
                body=message,
                properties=pika.BasicProperties(delivery_mode=2)
            )

        connection.close()
        print(f"Producer: Sent {count} messages")

    def consumer(self, expected_count=100, timeout=60):
        """Consumer thread"""
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(self.host)
        )
        channel = connection.channel()

        start_time = time.time()
        while len(self.received_messages) < expected_count:
            if time.time() - start_time > timeout:
                break

            method, properties, body = channel.basic_get('test-e2e-flow', auto_ack=True)
            if method:
                msg = json.loads(body)
                if msg['test_id'] == self.test_id:
                    self.received_messages.append(msg)

            time.sleep(0.01)

        connection.close()
        print(f"Consumer: Received {len(self.received_messages)} messages")

    def run_test(self, message_count=100):
        """Run end-to-end test"""
        # Setup
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(self.host)
        )
        channel = connection.channel()
        channel.queue_declare(
            queue='test-e2e-flow',
            durable=True,
            arguments={'x-queue-type': 'quorum'}
        )
        connection.close()

        # Run producer and consumer
        producer_thread = threading.Thread(target=self.producer, args=(message_count,))
        consumer_thread = threading.Thread(target=self.consumer, args=(message_count, 60))

        producer_thread.start()
        time.sleep(1)  # Let producer get ahead
        consumer_thread.start()

        producer_thread.join()
        consumer_thread.join()

        # Validate
        assert len(self.received_messages) == message_count, \
            f"Message loss: sent {message_count}, received {len(self.received_messages)}"

        # Check ordering
        sequences = [m['sequence'] for m in self.received_messages]
        assert sequences == sorted(sequences), "Messages out of order"

        # Cleanup
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(self.host)
        )
        channel = connection.channel()
        channel.queue_delete(queue='test-e2e-flow')
        connection.close()

        print("✓ End-to-end message flow test passed!")

if __name__ == '__main__':
    import sys
    host = sys.argv[1] if len(sys.argv) > 1 else 'localhost'
    tester = E2EMessageFlowTest(host)
    tester.run_test(1000)
```

---

## 4. Phase 3: Performance Testing

### 4.1 Throughput Test

```bash
#!/bin/bash
# test-throughput.sh

echo "=== RabbitMQ Throughput Test ==="

# Using PerfTest tool
docker run -it --rm --network host pivotalrabbitmq/perf-test:latest \
    --uri amqp://guest:guest@localhost:5672 \
    --producers 10 \
    --consumers 10 \
    --queue perf-test-queue \
    --quorum-queue \
    --auto-delete false \
    --time 300 \
    --producer-rate 10000 \
    --consumer-rate 10000 \
    --confirm 100 \
    --qos 500 \
    --size 1024 \
    --metrics-prometheus

# Expected results for 3-node quorum queue:
# Publish rate: 8,000-15,000 msg/s (depends on hardware)
# Consume rate: 10,000-20,000 msg/s
# Latency (99th percentile): < 50ms
```

### 4.2 Latency Test

```bash
#!/bin/bash
# test-latency.sh

echo "=== RabbitMQ Latency Test ==="

docker run -it --rm --network host pivotalrabbitmq/perf-test:latest \
    --uri amqp://guest:guest@localhost:5672 \
    --producers 1 \
    --consumers 1 \
    --queue latency-test-queue \
    --quorum-queue \
    --time 120 \
    --producer-rate 100 \
    --size 256 \
    --confirm 1 \
    --qos 1 \
    --latency-percentiles 50,75,90,95,99

# Expected results:
# 50th percentile: < 5ms
# 99th percentile: < 50ms
```

### 4.3 Resource Utilization Test

```bash
#!/bin/bash
# test-resource-utilization.sh

echo "=== Resource Utilization During Load ==="

# Start load test in background
docker run -d --name perf-test --network host pivotalrabbitmq/perf-test:latest \
    --uri amqp://guest:guest@localhost:5672 \
    --producers 5 \
    --consumers 5 \
    --queue resource-test \
    --quorum-queue \
    --time 300

# Monitor resources
for i in {1..60}; do
    echo "=== Minute $i ==="

    # Memory
    rabbitmqctl status | grep -A 5 "Memory"

    # Disk
    df -h /var/lib/rabbitmq

    # Erlang processes
    rabbitmqctl eval 'length(erlang:processes()).'

    # File descriptors
    rabbitmqctl status | grep "file_descriptors"

    sleep 5
done

docker stop perf-test
docker rm perf-test
```

---

## 5. Phase 4: Chaos Testing

### 5.1 Node Failure Test

```bash
#!/bin/bash
# test-node-failure.sh

echo "=== Node Failure Chaos Test ==="

# Prerequisites: 3-node cluster running, active traffic

# Test 1: Kill one node
echo "Test 1: Simulating node 3 failure..."
ssh rabbit-3 "systemctl stop rabbitmq-server"

sleep 10

# Verify cluster still operational
echo "Checking cluster status..."
rabbitmqctl cluster_status

# Verify quorum queues elected new leader
echo "Checking quorum queue leaders..."
rabbitmqctl list_queues name leader

# Verify message flow continues
echo "Checking message rates..."
rabbitmqctl list_queues name message_stats.publish_details.rate

# Restore node
echo "Restoring node 3..."
ssh rabbit-3 "systemctl start rabbitmq-server"

sleep 30

# Verify recovery
echo "Verifying recovery..."
rabbitmqctl cluster_status
rabbitmqctl list_queues name type members online
```

### 5.2 Network Partition Test

```bash
#!/bin/bash
# test-network-partition.sh

echo "=== Network Partition Chaos Test ==="

# Create network partition (node 3 isolated)
echo "Creating network partition..."
ssh rabbit-3 "iptables -A INPUT -s rabbit-1 -j DROP && iptables -A INPUT -s rabbit-2 -j DROP"

sleep 30

# Check cluster handling
echo "Cluster status during partition..."
rabbitmqctl cluster_status

# Node 3 should be paused (pause_minority strategy)
ssh rabbit-3 "rabbitmqctl cluster_status" 2>&1

# Heal partition
echo "Healing partition..."
ssh rabbit-3 "iptables -D INPUT -s rabbit-1 -j DROP && iptables -D INPUT -s rabbit-2 -j DROP"

sleep 30

# Verify recovery
echo "Verifying recovery..."
rabbitmqctl cluster_status
```

### 5.3 Leader Election Test

```bash
#!/bin/bash
# test-leader-election.sh

echo "=== Quorum Queue Leader Election Test ==="

# Get current leader
QUEUE="orders"
LEADER=$(rabbitmqctl list_queues name leader --quiet | grep "$QUEUE" | awk '{print $2}')
echo "Current leader for $QUEUE: $LEADER"

# Kill leader node
LEADER_HOST=$(echo $LEADER | sed 's/rabbit@//')
echo "Stopping leader node: $LEADER_HOST"

START_TIME=$(date +%s)
ssh $LEADER_HOST "systemctl stop rabbitmq-server"

# Wait for new leader
sleep 5

NEW_LEADER=$(rabbitmqctl list_queues name leader --quiet | grep "$QUEUE" | awk '{print $2}')
END_TIME=$(date +%s)

ELECTION_TIME=$((END_TIME - START_TIME))
echo "New leader: $NEW_LEADER"
echo "Leader election time: ${ELECTION_TIME}s"

# Verify no message loss
MSG_COUNT=$(rabbitmqctl list_queues name messages --quiet | grep "$QUEUE" | awk '{print $2}')
echo "Messages in queue: $MSG_COUNT"

# Restore old leader
ssh $LEADER_HOST "systemctl start rabbitmq-server"
```

---

## 6. Phase 5: User Acceptance Testing

### 6.1 Business Workflow Tests

```markdown
## UAT Test Cases

### TC-001: Order Processing Workflow
1. Submit new order via API
2. Verify order message reaches order-queue
3. Verify order processor consumes message
4. Verify order confirmation published
5. Verify notification sent

Expected: Complete workflow in < 5 seconds

### TC-002: Payment Processing Workflow
1. Initiate payment
2. Verify payment message reaches payment-queue
3. Verify payment processor handles transaction
4. Verify payment confirmation
5. Verify audit log updated

Expected: Complete workflow with proper idempotency

### TC-003: Bulk Operation Workflow
1. Submit batch of 1000 items
2. Verify all messages queued
3. Verify parallel processing
4. Verify completion notification
5. Verify no message loss

Expected: All items processed, no duplicates
```

### 6.2 Acceptance Criteria Checklist

```markdown
## Migration Acceptance Criteria

### Functional Requirements
- [ ] All queues accessible
- [ ] All exchanges functional
- [ ] All bindings preserved
- [ ] User authentication works
- [ ] Permissions enforced
- [ ] TLS connections work

### Performance Requirements
- [ ] Publish latency < 50ms (99th percentile)
- [ ] Throughput ≥ baseline
- [ ] Memory usage within limits
- [ ] Disk usage reasonable

### Reliability Requirements
- [ ] Single node failure: no message loss
- [ ] Leader election: < 30 seconds
- [ ] Application reconnection: automatic
- [ ] Shovel/Federation: functional

### Operational Requirements
- [ ] Monitoring dashboards accurate
- [ ] Alerts firing correctly
- [ ] Logs accessible and parseable
- [ ] Backup/restore tested
```

---

## 7. Validation Reports

### 7.1 Test Results Template

```markdown
# Migration Test Results Report

## Summary
| Category | Total | Passed | Failed | Skipped |
|----------|-------|--------|--------|---------|
| Unit Tests | | | | |
| Integration Tests | | | | |
| Performance Tests | | | | |
| Chaos Tests | | | | |
| UAT Tests | | | | |

## Test Environment
- RabbitMQ Version: 4.1.4
- Erlang Version: 26.2
- Cluster Nodes: 3
- Test Date:

## Detailed Results
[Include detailed test output]

## Issues Found
| ID | Severity | Description | Resolution |
|----|----------|-------------|------------|
| | | | |

## Recommendation
[ ] APPROVED for production migration
[ ] BLOCKED - issues must be resolved
```

---

**Next Step**: [09-monitoring-observability.md](./09-monitoring-observability.md)
