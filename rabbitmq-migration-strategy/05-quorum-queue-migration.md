# 05. Classic to Quorum Queue Migration

## Overview

This document provides detailed guidance for migrating Classic Queues to Quorum Queues as part of the RabbitMQ 3.12 to 4.1.4 upgrade.

---

## 1. Understanding the Differences

### 1.1 Architectural Comparison

```
CLASSIC QUEUE                          QUORUM QUEUE
┌─────────────────────────────┐       ┌─────────────────────────────┐
│  Single leader process      │       │  Raft-based consensus       │
│  Optional mirroring (HA)    │       │  Built-in replication       │
│  Async replication          │       │  Sync replication (Raft)    │
│  Memory-first storage       │       │  Disk-first storage         │
│  Fast for transient msgs    │       │  Optimized for durability   │
└─────────────────────────────┘       └─────────────────────────────┘
```

### 1.2 Feature Compatibility Matrix

| Feature | Classic Queue | Quorum Queue | Migration Notes |
|---------|--------------|--------------|-----------------|
| Durability | Optional | Always durable | Ensure all msgs are durable |
| Replication | Mirror policy | Built-in (Raft) | No policy needed |
| Exclusive queues | ✅ Supported | ❌ Not supported | Keep as classic |
| Auto-delete | ✅ Supported | ❌ Not supported | Keep as classic |
| TTL (per-message) | ✅ Supported | ✅ Supported | Works same way |
| TTL (per-queue) | ✅ Supported | ✅ Supported | Configure via policy |
| Max-length | ✅ Supported | ✅ Supported | Configure via args |
| Max-length-bytes | ✅ Supported | ✅ Supported | Configure via args |
| Dead-letter exchange | ✅ Supported | ✅ Supported | Works same way |
| Dead-letter routing key | ✅ Supported | ✅ Supported | Works same way |
| Priority queues | ✅ Supported | ❌ Not supported | Keep as classic |
| Lazy queues | ✅ Supported | N/A (inherent) | No config needed |
| Single active consumer | ✅ Supported | ✅ Supported | Works same way |
| Overflow behavior | drop-head | drop-head/reject-publish | Same behavior |
| Delivery limit | ❌ Not available | ✅ Built-in | New feature |
| Poison message handling | Manual | ✅ Automatic | New feature |

### 1.3 Performance Characteristics

| Metric | Classic Queue | Quorum Queue | Notes |
|--------|--------------|--------------|-------|
| Publish latency | Lower | Slightly higher | Raft consensus overhead |
| Throughput | Higher (transient) | High (durable) | Optimized for safety |
| Memory usage | Higher | Lower (disk-based) | Better for large queues |
| Disk I/O | Lower | Higher | More writes for safety |
| Recovery time | Longer | Faster | Raft snapshots |
| Failover time | Manual/slow | Automatic (<30s) | Significant improvement |

---

## 2. Queue Classification

### 2.1 Decision Tree for Queue Migration

```
                    ┌─────────────────────────────────────┐
                    │         QUEUE MIGRATION             │
                    │         DECISION TREE               │
                    └─────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │     Is the queue durable?     │
                    └───────────────┬───────────────┘
                           ┌────────┴────────┐
                          NO                YES
                           │                 │
                    ┌──────┴──────┐   ┌──────┴──────┐
                    │ Keep as     │   │ Is queue    │
                    │ Classic     │   │ exclusive?  │
                    └─────────────┘   └──────┬──────┘
                                      ┌──────┴──────┐
                                     YES           NO
                                      │             │
                               ┌──────┴──────┐ ┌────┴────────┐
                               │ Keep as     │ │ Auto-delete?│
                               │ Classic     │ └──────┬──────┘
                               └─────────────┘ ┌──────┴──────┐
                                              YES           NO
                                               │             │
                                        ┌──────┴──────┐ ┌────┴────────┐
                                        │ Keep as     │ │ Priority    │
                                        │ Classic     │ │ queue?      │
                                        └─────────────┘ └──────┬──────┘
                                                        ┌──────┴──────┐
                                                       YES           NO
                                                        │             │
                                                 ┌──────┴──────┐ ┌────┴────┐
                                                 │ Keep as     │ │ MIGRATE │
                                                 │ Classic     │ │ TO      │
                                                 └─────────────┘ │ QUORUM  │
                                                                 └─────────┘
```

### 2.2 Queue Inventory Script

```bash
#!/bin/bash
# queue-inventory.sh - Analyze queues for migration eligibility

echo "=== Queue Migration Eligibility Report ==="
echo "Generated: $(date)"
echo ""

# Get all queues with properties
rabbitmqctl list_queues name type durable exclusive auto_delete arguments \
    --formatter=json | jq -r '
    .[] |
    if .type == "quorum" then
        "\(.name) | Already Quorum | N/A"
    elif .exclusive == true then
        "\(.name) | Keep Classic | Exclusive queue"
    elif .auto_delete == true then
        "\(.name) | Keep Classic | Auto-delete queue"
    elif .durable == false then
        "\(.name) | Keep Classic | Non-durable"
    elif (.arguments | has("x-max-priority")) then
        "\(.name) | Keep Classic | Priority queue"
    else
        "\(.name) | MIGRATE | Eligible for quorum"
    end
' | column -t -s '|'

echo ""
echo "=== Summary ==="
rabbitmqctl list_queues type --quiet | sort | uniq -c
```

### 2.3 Classification Results Template

| Queue Name | Current Type | Migration Decision | Reason |
|------------|-------------|-------------------|--------|
| orders | classic | MIGRATE | Durable, no blockers |
| notifications | classic | MIGRATE | Durable, no blockers |
| temp-replies | classic | KEEP CLASSIC | Auto-delete |
| session-data | classic | KEEP CLASSIC | Exclusive |
| priority-tasks | classic | KEEP CLASSIC | Uses priorities |
| events | quorum | ALREADY QUORUM | No action |

---

## 3. Migration Methods

### 3.1 Method 1: Create New Queue + Shovel

**Best for: Production queues with active traffic**

```
┌─────────────────────────────────────────────────────────┐
│           METHOD 1: SHOVEL MIGRATION                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Step 1: Create new quorum queue                        │
│  ┌─────────────┐                                        │
│  │ orders      │  ──► │ orders-quorum │                 │
│  │ (classic)   │      │ (quorum)      │                 │
│  └─────────────┘      └───────────────┘                 │
│                                                          │
│  Step 2: Configure Shovel                               │
│  orders (classic) ────Shovel────► orders-quorum         │
│                                                          │
│  Step 3: Switch publishers to orders-quorum             │
│  Step 4: Drain orders (classic) via Shovel              │
│  Step 5: Switch consumers to orders-quorum              │
│  Step 6: Delete orders (classic)                        │
│  Step 7: Rename orders-quorum to orders (optional)      │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Step 1: Create quorum queue
rabbitmqadmin declare queue name=orders-quorum durable=true \
    arguments='{"x-queue-type": "quorum"}'

# Step 2: Configure Shovel
rabbitmqctl set_parameter shovel migrate-orders '{
    "src-protocol": "amqp091",
    "src-uri": "amqp://localhost",
    "src-queue": "orders",
    "dest-protocol": "amqp091",
    "dest-uri": "amqp://localhost",
    "dest-queue": "orders-quorum",
    "ack-mode": "on-confirm",
    "reconnect-delay": 5
}'

# Step 3-5: Update applications (requires deployment)

# Step 6: Delete old queue (after drain)
rabbitmqadmin delete queue name=orders
```

### 3.2 Method 2: Policy-Based Conversion (Future Messages)

**Best for: Low-traffic queues that can be drained**

```
┌─────────────────────────────────────────────────────────┐
│           METHOD 2: DRAIN AND RECREATE                  │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Step 1: Stop publishers                                │
│  Step 2: Drain queue completely                         │
│  Step 3: Delete classic queue                           │
│  Step 4: Create quorum queue with same name             │
│  Step 5: Resume publishers                              │
│                                                          │
│  Note: Brief downtime for this queue                    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Step 1: Stop publishers (application-level)

# Step 2: Wait for queue to drain
while true; do
    COUNT=$(rabbitmqctl list_queues name messages | grep "^orders" | awk '{print $2}')
    if [ "$COUNT" -eq 0 ]; then
        break
    fi
    echo "Waiting... $COUNT messages remaining"
    sleep 5
done

# Step 3: Delete classic queue
rabbitmqadmin delete queue name=orders

# Step 4: Create quorum queue
rabbitmqadmin declare queue name=orders durable=true \
    arguments='{"x-queue-type": "quorum"}'

# Step 5: Resume publishers
```

### 3.3 Method 3: Default Queue Type Policy

**Best for: New deployments, greenfield migrations**

```bash
# Set default queue type for virtual host
rabbitmqctl set_policy quorum-by-default ".*" \
    '{"x-queue-type": "quorum"}' \
    --priority 1 \
    --apply-to queues

# Note: Only affects NEW queues, not existing ones
```

### 3.4 Method 4: Parallel Queue with Consumer Switch

**Best for: Critical queues requiring zero message loss**

```
┌─────────────────────────────────────────────────────────┐
│         METHOD 4: PARALLEL QUEUE MIGRATION              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Phase 1: Parallel Operation                            │
│  ┌────────────┐                                         │
│  │ Publisher  │───┬───► orders (classic) ───► Consumer  │
│  └────────────┘   │                                     │
│                   └───► orders-quorum ───► (no consumer)│
│                                                          │
│  Phase 2: Switch Consumers                              │
│  ┌────────────┐                                         │
│  │ Publisher  │───┬───► orders (classic) ───► (drain)   │
│  └────────────┘   │                                     │
│                   └───► orders-quorum ───► Consumer     │
│                                                          │
│  Phase 3: Switch Publishers                             │
│  ┌────────────┐                                         │
│  │ Publisher  │───────► orders-quorum ───► Consumer     │
│  └────────────┘                                         │
│                   orders (classic) deleted              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Quorum Queue Configuration

### 4.1 Queue Declaration

**AMQP 0-9-1 (Client Library):**

```python
# Python (pika)
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={
        'x-queue-type': 'quorum',
        'x-quorum-initial-group-size': 3,
        'x-delivery-limit': 5,
        'x-dead-letter-exchange': 'dlx',
        'x-dead-letter-routing-key': 'orders.dead'
    }
)
```

```java
// Java
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "quorum");
args.put("x-quorum-initial-group-size", 3);
args.put("x-delivery-limit", 5);

channel.queueDeclare("orders", true, false, false, args);
```

```javascript
// Node.js (amqplib)
await channel.assertQueue('orders', {
    durable: true,
    arguments: {
        'x-queue-type': 'quorum',
        'x-quorum-initial-group-size': 3,
        'x-delivery-limit': 5
    }
});
```

### 4.2 Policy-Based Configuration

```bash
# Create policy for quorum queues
rabbitmqctl set_policy quorum-orders "^orders.*" '{
    "x-queue-type": "quorum",
    "x-quorum-initial-group-size": 3,
    "x-delivery-limit": 5,
    "x-dead-letter-exchange": "dlx",
    "x-message-ttl": 86400000
}' --priority 10 --apply-to queues
```

### 4.3 Recommended Configuration

```json
{
    "x-queue-type": "quorum",
    "x-quorum-initial-group-size": 3,
    "x-delivery-limit": 5,
    "x-dead-letter-exchange": "dlx",
    "x-dead-letter-routing-key": "poison",
    "x-max-length": 1000000,
    "x-overflow": "reject-publish"
}
```

| Argument | Recommended Value | Purpose |
|----------|------------------|---------|
| x-queue-type | "quorum" | Declares quorum queue |
| x-quorum-initial-group-size | 3 (for 3-node) | Replication factor |
| x-delivery-limit | 3-10 | Poison message protection |
| x-dead-letter-exchange | "dlx" | Route failed messages |
| x-max-length | Application-specific | Prevent unbounded growth |
| x-overflow | "reject-publish" | Back-pressure behavior |

---

## 5. Application Code Changes

### 5.1 Publisher Changes

```python
# BEFORE: Classic queue (no specific type)
channel.queue_declare(queue='orders', durable=True)

# AFTER: Quorum queue (explicit type)
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={'x-queue-type': 'quorum'}
)

# IMPORTANT: Ensure messages are published as persistent
channel.basic_publish(
    exchange='',
    routing_key='orders',
    body=message,
    properties=pika.BasicProperties(
        delivery_mode=2,  # Persistent
    )
)
```

### 5.2 Consumer Changes

```python
# BEFORE: Classic queue consumer
def callback(ch, method, properties, body):
    process_message(body)
    ch.basic_ack(delivery_tag=method.delivery_tag)

# AFTER: Quorum queue consumer (handle redelivery)
def callback(ch, method, properties, body):
    try:
        process_message(body)
        ch.basic_ack(delivery_tag=method.delivery_tag)
    except ProcessingError as e:
        # Message will be requeued up to delivery-limit times
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
```

### 5.3 Connection Handling

```python
# Enhanced connection handling for quorum queues
import pika
from pika.adapters.blocking_connection import BlockingConnection

def create_connection():
    parameters = pika.ConnectionParameters(
        host='rabbitmq.example.com',
        port=5672,
        heartbeat=60,
        blocked_connection_timeout=300,
        connection_attempts=3,
        retry_delay=5
    )
    return BlockingConnection(parameters)

# Handle leader election during connection
def with_retry(func):
    def wrapper(*args, **kwargs):
        max_retries = 3
        for attempt in range(max_retries):
            try:
                return func(*args, **kwargs)
            except pika.exceptions.ChannelClosedByBroker as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                else:
                    raise
    return wrapper
```

---

## 6. Migration Execution Plan

### 6.1 Pre-Migration Steps

```bash
# 1. Document current queue state
rabbitmqctl list_queues name type messages consumers memory \
    --formatter=json > pre_migration_queues.json

# 2. Identify queue bindings
rabbitmqctl list_bindings source_name destination_name routing_key \
    --formatter=json > pre_migration_bindings.json

# 3. Create migration tracking spreadsheet
echo "Queue,Type,Messages,Status,MigratedAt" > migration_tracking.csv
```

### 6.2 Queue-by-Queue Migration

```bash
#!/bin/bash
# migrate-queue.sh <queue-name>

QUEUE_NAME=$1
QUORUM_QUEUE="${QUEUE_NAME}"

echo "Migrating queue: $QUEUE_NAME"

# 1. Create quorum queue on new cluster
rabbitmqadmin -H new-cluster declare queue name="$QUORUM_QUEUE" \
    durable=true \
    arguments='{"x-queue-type":"quorum","x-quorum-initial-group-size":3}'

# 2. Copy bindings
BINDINGS=$(rabbitmqctl list_bindings -s destination_name routing_key \
    | grep "^$QUEUE_NAME" | awk '{print $2}')

for ROUTING_KEY in $BINDINGS; do
    rabbitmqadmin -H new-cluster declare binding \
        source=amq.direct \
        destination="$QUORUM_QUEUE" \
        routing_key="$ROUTING_KEY"
done

# 3. Configure Shovel
rabbitmqctl set_parameter shovel "migrate-$QUEUE_NAME" "{
    \"src-uri\": \"amqp://old-cluster\",
    \"src-queue\": \"$QUEUE_NAME\",
    \"dest-uri\": \"amqp://new-cluster\",
    \"dest-queue\": \"$QUORUM_QUEUE\",
    \"ack-mode\": \"on-confirm\"
}"

echo "Shovel configured. Monitor: rabbitmqctl shovel_status"
```

### 6.3 Validation Steps

```bash
#!/bin/bash
# validate-queue-migration.sh <queue-name>

QUEUE_NAME=$1

# Check quorum queue exists and has replicas
rabbitmqctl list_quorum_queue_members "$QUEUE_NAME"

# Verify bindings
rabbitmqctl list_bindings | grep "$QUEUE_NAME"

# Check message flow
watch -n 5 "rabbitmqctl list_queues name messages_ready messages_unacknowledged | grep $QUEUE_NAME"
```

---

## 7. Handling Edge Cases

### 7.1 Large Queue Migration

For queues with millions of messages:

```bash
# Option 1: Increase Shovel throughput
rabbitmqctl set_parameter shovel migrate-large-queue '{
    "src-uri": "amqp://old-cluster",
    "src-queue": "large-queue",
    "dest-uri": "amqp://new-cluster",
    "dest-queue": "large-queue-quorum",
    "ack-mode": "on-confirm",
    "src-prefetch-count": 1000
}'

# Option 2: Multiple parallel Shovels (for very large queues)
# Split by routing key or create multiple source queues
```

### 7.2 Queues with Priority

Priority queues cannot be migrated to quorum. Options:

```
Option A: Keep as classic queue
- Simplest approach
- Loses quorum queue benefits

Option B: Split into multiple quorum queues
- orders-high (quorum) ← high priority
- orders-medium (quorum) ← medium priority
- orders-low (quorum) ← low priority
- Application routes based on priority

Option C: Use streams for ordering
- RabbitMQ Streams provide ordering
- Different consumption model
```

### 7.3 Exclusive/Auto-delete Queues

These cannot be quorum queues. Common patterns:

```
Pattern: RPC Reply Queues
- Keep as classic exclusive queues
- These are transient by nature
- Low risk, no HA needed

Pattern: Session Queues
- Keep as classic auto-delete
- Consider alternative (Redis, etc.)
- No migration needed
```

---

## 8. Rollback Procedures

### 8.1 Per-Queue Rollback

```bash
# If issues with specific quorum queue:

# 1. Stop Shovel
rabbitmqctl clear_parameter shovel migrate-orders

# 2. Switch applications back to classic queue
# (Application deployment)

# 3. Delete quorum queue (if not needed)
rabbitmqadmin delete queue name=orders-quorum

# 4. Verify classic queue operational
rabbitmqctl list_queues name type messages | grep orders
```

### 8.2 Full Migration Rollback

```bash
# If entire quorum migration needs rollback:

# 1. Switch load balancer back to old cluster
# (Infrastructure change)

# 2. Stop all Shovels
rabbitmqctl list_parameters shovel | awk '{print $1}' | \
    xargs -I {} rabbitmqctl clear_parameter shovel {}

# 3. Verify old cluster operational
rabbitmqctl cluster_status

# 4. Document lessons learned
```

---

## 9. Post-Migration Verification

### 9.1 Quorum Queue Health Checks

```bash
# Check all quorum queues have proper replica count
rabbitmqctl list_queues name type members online | grep quorum

# Check for under-replicated queues
rabbitmq-diagnostics check_if_node_is_quorum_critical

# Verify Raft state
rabbitmqctl list_queues name type leader | grep quorum
```

### 9.2 Performance Comparison

```bash
# Compare metrics before/after
# Publish rate
rabbitmqctl list_queues name message_stats.publish_details.rate

# Consume rate
rabbitmqctl list_queues name message_stats.deliver_get_details.rate

# Memory usage
rabbitmqctl list_queues name memory
```

---

**Next Step**: [06-step-by-step-execution.md](./06-step-by-step-execution.md)
