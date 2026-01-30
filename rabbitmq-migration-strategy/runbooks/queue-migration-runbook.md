# Queue Migration Runbook

## Purpose
Procedure for migrating a classic queue to a quorum queue with zero message loss.

---

## Prerequisites

- [ ] Queue identified for migration
- [ ] Queue eligibility confirmed (durable, non-exclusive, non-auto-delete)
- [ ] Application team notified
- [ ] Backup taken

---

## Queue Information

| Field | Value |
|-------|-------|
| Queue Name | |
| Current Type | classic |
| Target Type | quorum |
| Message Count | |
| Consumer Count | |
| Application(s) | |

---

## Migration Options

### Option A: Shovel-Based (Recommended for Production)
Best for: Active queues with ongoing traffic

### Option B: Drain and Recreate
Best for: Low-traffic queues, can tolerate brief pause

---

## Option A: Shovel-Based Migration

### Step 1: Create Quorum Queue

```bash
QUEUE_NAME="your-queue-name"
QUORUM_QUEUE="${QUEUE_NAME}-quorum"

# Create new quorum queue
rabbitmqadmin declare queue name="${QUORUM_QUEUE}" \
    durable=true \
    arguments='{"x-queue-type":"quorum","x-quorum-initial-group-size":3,"x-delivery-limit":5}'

# Verify creation
rabbitmqctl list_queues name type | grep "${QUORUM_QUEUE}"
```

### Step 2: Copy Bindings

```bash
# List current bindings
rabbitmqctl list_bindings | grep "${QUEUE_NAME}"

# Recreate each binding for new queue
# Example:
rabbitmqadmin declare binding \
    source="exchange-name" \
    destination="${QUORUM_QUEUE}" \
    routing_key="routing-key"
```

### Step 3: Configure Shovel

```bash
# Setup Shovel to move messages
rabbitmqctl set_parameter shovel "migrate-${QUEUE_NAME}" "{
    \"src-protocol\": \"amqp091\",
    \"src-uri\": \"amqp://localhost\",
    \"src-queue\": \"${QUEUE_NAME}\",
    \"dest-protocol\": \"amqp091\",
    \"dest-uri\": \"amqp://localhost\",
    \"dest-queue\": \"${QUORUM_QUEUE}\",
    \"ack-mode\": \"on-confirm\",
    \"reconnect-delay\": 5
}"

# Verify Shovel running
rabbitmqctl shovel_status
```

### Step 4: Monitor Message Transfer

```bash
# Watch queue depths
watch -n 5 "rabbitmqctl list_queues name messages | grep -E '${QUEUE_NAME}|${QUORUM_QUEUE}'"

# Wait for classic queue to drain
while true; do
    COUNT=$(rabbitmqctl list_queues name messages --quiet | grep "^${QUEUE_NAME}" | awk '{print $2}')
    if [ "$COUNT" -eq 0 ]; then
        echo "Classic queue drained"
        break
    fi
    echo "Messages remaining: $COUNT"
    sleep 5
done
```

### Step 5: Switch Applications

```bash
# Update application configuration to use new queue name
# OR rename queues (see below)

# Notify application team to deploy with new queue name
```

### Step 6: Cleanup

```bash
# Remove Shovel
rabbitmqctl clear_parameter shovel "migrate-${QUEUE_NAME}"

# Delete classic queue (after verification)
rabbitmqadmin delete queue name="${QUEUE_NAME}"

# Optional: Rename quorum queue to original name
# (Requires deleting and recreating with bindings)
```

---

## Option B: Drain and Recreate

### Step 1: Stop Publishers

Coordinate with application team to stop publishing to the queue.

### Step 2: Drain Queue

```bash
QUEUE_NAME="your-queue-name"

# Wait for consumers to process all messages
while true; do
    COUNT=$(rabbitmqctl list_queues name messages --quiet | grep "^${QUEUE_NAME}" | awk '{print $2}')
    if [ "$COUNT" -eq 0 ]; then
        echo "Queue drained"
        break
    fi
    echo "Messages remaining: $COUNT"
    sleep 5
done
```

### Step 3: Record Bindings

```bash
# Save current bindings
rabbitmqctl list_bindings | grep "${QUEUE_NAME}" > /tmp/bindings-${QUEUE_NAME}.txt
cat /tmp/bindings-${QUEUE_NAME}.txt
```

### Step 4: Delete Classic Queue

```bash
# Delete the classic queue
rabbitmqadmin delete queue name="${QUEUE_NAME}"

# Verify deleted
rabbitmqctl list_queues name | grep "${QUEUE_NAME}"
```

### Step 5: Create Quorum Queue

```bash
# Create quorum queue with same name
rabbitmqadmin declare queue name="${QUEUE_NAME}" \
    durable=true \
    arguments='{"x-queue-type":"quorum","x-quorum-initial-group-size":3,"x-delivery-limit":5}'

# Verify creation
rabbitmqctl list_queues name type | grep "${QUEUE_NAME}"
```

### Step 6: Recreate Bindings

```bash
# Recreate bindings from saved file
# (Parse bindings file and recreate each)
```

### Step 7: Resume Publishers

Notify application team to resume publishing.

---

## Validation

```bash
QUEUE_NAME="your-queue-name"

# Verify queue type
rabbitmqctl list_queues name type | grep "${QUEUE_NAME}"

# Verify replicas
rabbitmqctl list_queues name type members | grep "${QUEUE_NAME}"

# Verify bindings
rabbitmqctl list_bindings | grep "${QUEUE_NAME}"

# Verify message flow (after publishers resume)
watch -n 5 "rabbitmqctl list_queues name messages | grep ${QUEUE_NAME}"
```

---

## Rollback

If migration fails:

### For Shovel Method
```bash
# Stop Shovel
rabbitmqctl clear_parameter shovel "migrate-${QUEUE_NAME}"

# Keep using classic queue
# Delete quorum queue if not needed
rabbitmqadmin delete queue name="${QUORUM_QUEUE}"
```

### For Drain Method
```bash
# Recreate classic queue with same name
rabbitmqadmin declare queue name="${QUEUE_NAME}" durable=true

# Recreate bindings
# Resume publishers
```

---

## Completion Checklist

- [ ] Quorum queue created
- [ ] All messages transferred (zero loss)
- [ ] Bindings in place
- [ ] Applications updated
- [ ] Classic queue removed
- [ ] Shovel removed (if used)
- [ ] Monitoring updated
