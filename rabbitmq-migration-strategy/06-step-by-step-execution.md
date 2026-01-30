# 06. Step-by-Step Execution Plan

## Overview

This document provides the detailed execution steps for migrating a 3-node RabbitMQ cluster from 3.12 to 4.1.4 using the hybrid approach.

---

## Migration Timeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MIGRATION TIMELINE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Week 1          Week 2          Week 3          Week 4                     │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ASSESSMENT│    │ PREPARE  │    │ MIGRATE  │    │ VALIDATE │              │
│  │          │    │          │    │          │    │          │              │
│  │• Inventory│   │• Deploy  │    │• Enable  │    │• Monitor │              │
│  │• Health   │   │  green   │    │  Shovels │    │• Test    │              │
│  │• Backup   │   │• Test    │    │• Switch  │    │• Cleanup │              │
│  │• Planning │   │  setup   │    │  traffic │    │• Document│              │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Pre-Migration Assessment (Week 1)

### Day 1: Environment Audit

#### Step 1.1: Cluster Health Check

```bash
# Run on each node
echo "=== Node Health Check ==="
echo "Hostname: $(hostname)"
echo "RabbitMQ Version: $(rabbitmqctl version)"
echo "Erlang Version: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell)"

# Cluster status
rabbitmqctl cluster_status

# Node health
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_local_alarms
rabbitmq-diagnostics check_port_connectivity
```

#### Step 1.2: Collect Inventory

```bash
# Export definitions (includes users, vhosts, permissions, exchanges, queues, bindings)
rabbitmqadmin export definitions.json

# Detailed queue inventory
rabbitmqctl list_queues name type durable exclusive auto_delete arguments \
    messages consumers memory policy --formatter=json > queues_inventory.json

# Exchange inventory
rabbitmqctl list_exchanges name type durable auto_delete arguments \
    --formatter=json > exchanges_inventory.json

# Binding inventory
rabbitmqctl list_bindings source_name source_kind destination_name \
    destination_kind routing_key arguments --formatter=json > bindings_inventory.json

# User inventory
rabbitmqctl list_users --formatter=json > users_inventory.json

# Policies
rabbitmqctl list_policies --formatter=json > policies_inventory.json
```

### Day 2: Feature Flags and Compatibility

#### Step 1.3: Check Feature Flags

```bash
# List all feature flags
rabbitmqctl list_feature_flags name state stability

# Enable all stable feature flags (required for 4.x)
rabbitmqctl enable_feature_flag all

# Verify all required flags are enabled
echo "=== Required Feature Flags for 4.x ==="
rabbitmqctl list_feature_flags | grep -E "(quorum_queue|stream_queue|feature_flags_v2)"
```

#### Step 1.4: Check Deprecated Features

```bash
# Check for classic mirrored queues (deprecated in 4.x)
echo "=== Classic Mirrored Queues (to be migrated) ==="
rabbitmqctl list_policies | grep -E "ha-mode|ha-params"

# Check for deprecated configuration
grep -r "ha-mode\|ha-params\|ha-sync" /etc/rabbitmq/
```

### Day 3: Backup Everything

#### Step 1.5: Full Backup

```bash
#!/bin/bash
# backup-cluster.sh

BACKUP_DIR="/backup/rabbitmq/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup in $BACKUP_DIR"

# 1. Export definitions
rabbitmqadmin export "$BACKUP_DIR/definitions.json"

# 2. Backup configuration files
cp -r /etc/rabbitmq/* "$BACKUP_DIR/config/"

# 3. Backup Mnesia directory (includes queue data for classic queues)
systemctl stop rabbitmq-server
cp -r /var/lib/rabbitmq/mnesia "$BACKUP_DIR/mnesia/"
systemctl start rabbitmq-server

# 4. Document current state
rabbitmqctl cluster_status > "$BACKUP_DIR/cluster_status.txt"
rabbitmqctl list_queues name type messages > "$BACKUP_DIR/queue_status.txt"

# 5. Create checksum
find "$BACKUP_DIR" -type f -exec sha256sum {} \; > "$BACKUP_DIR/checksums.txt"

echo "Backup completed: $BACKUP_DIR"
```

### Day 4-5: Plan Queue Migration

#### Step 1.6: Classify Queues

Create a queue migration plan spreadsheet:

| Queue Name | Type | Messages | Durable | Exclusive | Auto-Delete | Priority | Migration Decision | Notes |
|------------|------|----------|---------|-----------|-------------|----------|-------------------|-------|
| orders | classic | 1500 | true | false | false | false | MIGRATE | Critical |
| notifications | classic | 500 | true | false | false | false | MIGRATE | |
| rpc.replies | classic | 0 | false | true | true | false | KEEP | RPC pattern |
| priority.tasks | classic | 200 | true | false | false | true | KEEP | Uses priority |

---

## Phase 2: Preparation (Week 2)

### Day 1-2: Deploy Green Cluster

#### Step 2.1: Infrastructure Provisioning

```bash
# Using Terraform/CloudFormation or manual provisioning
# Provision 3 new nodes with:
# - Same instance type as current cluster
# - Same network configuration
# - SSD storage (minimum 3x current disk)
# - Network connectivity to blue cluster

# Node naming convention:
# rabbit-green-1.example.com
# rabbit-green-2.example.com
# rabbit-green-3.example.com
```

#### Step 2.2: Install Erlang 26.x

```bash
# On each green node (Ubuntu/Debian)
# Add Erlang Solutions repository
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
apt-get update

# Install Erlang 26
apt-get install -y esl-erlang=1:26.2*

# Verify
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
```

#### Step 2.3: Install RabbitMQ 4.1.4

```bash
# On each green node
# Add RabbitMQ repository
curl -1sLf 'https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh' | bash

# Install RabbitMQ 4.1.4
apt-get install -y rabbitmq-server=4.1.4-1

# Don't start yet - configure first
systemctl stop rabbitmq-server
```

#### Step 2.4: Configure Green Cluster

```bash
# /etc/rabbitmq/rabbitmq.conf on each node

# Cluster configuration
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config
cluster_formation.classic_config.nodes.1 = rabbit@rabbit-green-1
cluster_formation.classic_config.nodes.2 = rabbit@rabbit-green-2
cluster_formation.classic_config.nodes.3 = rabbit@rabbit-green-3

# Quorum queue defaults
default_queue_type = quorum
quorum_queue.default_target_replica_count = 3

# Resource limits
vm_memory_high_watermark.relative = 0.7
disk_free_limit.relative = 1.5

# Management
management.listener.port = 15672
management.listener.ssl = false

# Prometheus metrics
prometheus.return_per_object_metrics = true
```

```bash
# /etc/rabbitmq/enabled_plugins
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel,rabbitmq_shovel_management].
```

#### Step 2.5: Form Green Cluster

```bash
# On rabbit-green-1 (first node)
systemctl start rabbitmq-server
rabbitmqctl cluster_status

# On rabbit-green-2
systemctl start rabbitmq-server
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl join_cluster rabbit@rabbit-green-1
rabbitmqctl start_app

# On rabbit-green-3
systemctl start rabbitmq-server
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl join_cluster rabbit@rabbit-green-1
rabbitmqctl start_app

# Verify cluster
rabbitmqctl cluster_status
```

### Day 3: Import Definitions

#### Step 2.6: Prepare Definitions for Import

```bash
# Modify definitions to use quorum queues
# (Python script to convert queue definitions)

python3 << 'EOF'
import json

with open('definitions.json', 'r') as f:
    definitions = json.load(f)

# Convert classic queues to quorum (where eligible)
for queue in definitions.get('queues', []):
    args = queue.get('arguments', {})

    # Skip if already quorum
    if args.get('x-queue-type') == 'quorum':
        continue

    # Skip exclusive or auto-delete
    if queue.get('auto_delete') or queue.get('exclusive'):
        continue

    # Skip non-durable
    if not queue.get('durable'):
        continue

    # Skip priority queues
    if 'x-max-priority' in args:
        continue

    # Convert to quorum
    args['x-queue-type'] = 'quorum'
    args['x-quorum-initial-group-size'] = 3
    queue['arguments'] = args

# Remove HA policies (not needed for quorum)
definitions['policies'] = [
    p for p in definitions.get('policies', [])
    if 'ha-mode' not in p.get('definition', {})
]

with open('definitions_quorum.json', 'w') as f:
    json.dump(definitions, f, indent=2)

print("Converted definitions saved to definitions_quorum.json")
EOF
```

#### Step 2.7: Import to Green Cluster

```bash
# Import modified definitions
rabbitmqadmin -H rabbit-green-1 import definitions_quorum.json

# Verify import
rabbitmqctl list_queues name type
rabbitmqctl list_exchanges name type
rabbitmqctl list_users
```

### Day 4-5: Testing

#### Step 2.8: Functional Testing

```bash
# Test publish/consume cycle
# Python test script
python3 << 'EOF'
import pika

connection = pika.BlockingConnection(
    pika.ConnectionParameters('rabbit-green-1')
)
channel = connection.channel()

# Declare test quorum queue
channel.queue_declare(
    queue='test-migration',
    durable=True,
    arguments={'x-queue-type': 'quorum'}
)

# Publish test message
channel.basic_publish(
    exchange='',
    routing_key='test-migration',
    body='Test message',
    properties=pika.BasicProperties(delivery_mode=2)
)

# Consume test message
method, properties, body = channel.basic_get('test-migration', auto_ack=True)
assert body == b'Test message', "Message mismatch!"

print("✓ Publish/consume test passed")
channel.queue_delete('test-migration')
connection.close()
EOF
```

#### Step 2.9: Load Testing

```bash
# Use PerfTest tool
docker run -it --rm pivotalrabbitmq/perf-test:latest \
    --uri amqp://guest:guest@rabbit-green-1:5672 \
    --producers 5 \
    --consumers 5 \
    --queue test-load \
    --quorum-queue \
    --time 60

# Expected: Similar throughput to blue cluster
```

---

## Phase 3: Migration Execution (Week 3)

### Day 1: Configure Message Bridge

#### Step 3.1: Setup Shovel from Blue to Green

```bash
# On BLUE cluster - configure Shovel for each queue
# Run this script for each queue to migrate

#!/bin/bash
# setup-shovel.sh

BLUE_CLUSTER="amqp://user:password@rabbit-blue-1:5672"
GREEN_CLUSTER="amqp://user:password@rabbit-green-1:5672"

# List of queues to migrate
QUEUES=(
    "orders"
    "notifications"
    "events"
    "user-updates"
)

for QUEUE in "${QUEUES[@]}"; do
    echo "Setting up Shovel for queue: $QUEUE"

    rabbitmqctl set_parameter shovel "migrate-${QUEUE}" "{
        \"src-protocol\": \"amqp091\",
        \"src-uri\": \"$BLUE_CLUSTER\",
        \"src-queue\": \"$QUEUE\",
        \"src-delete-after\": \"never\",
        \"dest-protocol\": \"amqp091\",
        \"dest-uri\": \"$GREEN_CLUSTER\",
        \"dest-queue\": \"$QUEUE\",
        \"dest-add-forward-headers\": false,
        \"ack-mode\": \"on-confirm\",
        \"reconnect-delay\": 5
    }"

    echo "Shovel configured for $QUEUE"
done

# Verify Shovels
rabbitmqctl shovel_status
```

#### Step 3.2: Verify Message Flow

```bash
# Monitor Shovel status
watch -n 5 'rabbitmqctl shovel_status'

# Check messages are flowing to green
# On GREEN cluster:
watch -n 5 'rabbitmqctl list_queues name messages_ready messages_unacknowledged'
```

### Day 2-3: Application Migration (Staged)

#### Step 3.3: Migrate Non-Critical Applications First

```yaml
# Example Kubernetes deployment update
# applications/logging-service/deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: logging-service
spec:
  template:
    spec:
      containers:
      - name: logging-service
        env:
        - name: RABBITMQ_HOST
          # value: "rabbit-blue.example.com"  # OLD
          value: "rabbit-green.example.com"   # NEW
        - name: RABBITMQ_PORT
          value: "5672"
```

```bash
# Rolling deployment
kubectl apply -f applications/logging-service/deployment.yaml
kubectl rollout status deployment/logging-service
```

#### Step 3.4: Verify Application Connectivity

```bash
# Check connections on GREEN cluster
rabbitmqctl list_connections client_properties name peer_host

# Verify message flow
rabbitmqctl list_queues name messages_ready consumers
```

### Day 4: Migrate Critical Applications

#### Step 3.5: Pre-Migration Checks for Critical Apps

```bash
# Verify Shovel has caught up
rabbitmqctl list_queues name messages --quiet | while read queue messages; do
    if [ "$messages" -gt 100 ]; then
        echo "WARNING: Queue $queue has $messages pending messages"
    fi
done

# Check consumer count on both clusters
echo "=== Blue Cluster Consumers ==="
rabbitmqctl -n rabbit@rabbit-blue-1 list_consumers queue_name

echo "=== Green Cluster Consumers ==="
rabbitmqctl -n rabbit@rabbit-green-1 list_consumers queue_name
```

#### Step 3.6: Switch Critical Applications

```bash
# 1. Announce maintenance window to stakeholders
# 2. Stop publishers on critical apps (brief pause)
kubectl scale deployment/order-service --replicas=0

# 3. Wait for in-flight messages to complete
sleep 30

# 4. Update configuration and restart
kubectl set env deployment/order-service RABBITMQ_HOST=rabbit-green.example.com
kubectl scale deployment/order-service --replicas=3
kubectl rollout status deployment/order-service

# 5. Verify message flow
rabbitmqctl list_queues name messages consumers | grep orders
```

### Day 5: Traffic Cutover

#### Step 3.7: Load Balancer Switch

```bash
# Option A: AWS Application Load Balancer
aws elbv2 modify-listener --listener-arn $LISTENER_ARN \
    --default-actions Type=forward,TargetGroupArn=$GREEN_TARGET_GROUP

# Option B: HAProxy configuration update
# /etc/haproxy/haproxy.cfg
# backend rabbitmq_backend
#     server rabbit-green-1 192.168.1.10:5672 check
#     server rabbit-green-2 192.168.1.11:5672 check
#     server rabbit-green-3 192.168.1.12:5672 check

# Option C: DNS update
# Update rabbitmq.example.com to point to green cluster IPs
```

#### Step 3.8: Verify Complete Cutover

```bash
# No connections should remain on blue cluster
rabbitmqctl -n rabbit@rabbit-blue-1 list_connections | wc -l

# All connections on green cluster
rabbitmqctl -n rabbit@rabbit-green-1 list_connections | wc -l

# Queue depths should be normal
rabbitmqctl list_queues name messages_ready messages_unacknowledged
```

---

## Phase 4: Validation and Cleanup (Week 4)

### Day 1-2: Monitoring and Validation

#### Step 4.1: Health Monitoring

```bash
# Continuous monitoring script
#!/bin/bash
# monitor-migration.sh

while true; do
    echo "=== $(date) ==="

    # Cluster health
    rabbitmq-diagnostics check_running
    rabbitmq-diagnostics check_local_alarms

    # Queue health
    rabbitmqctl list_queues name type messages consumers | head -20

    # Connection count
    echo "Connections: $(rabbitmqctl list_connections | wc -l)"

    # Quorum queue status
    echo "Quorum queue leaders:"
    rabbitmqctl list_queues name type leader | grep quorum

    sleep 60
done
```

#### Step 4.2: Performance Validation

```bash
# Compare metrics with baseline
# Prometheus queries:

# Publish rate
rate(rabbitmq_channel_messages_published_total[5m])

# Consume rate
rate(rabbitmq_channel_messages_delivered_total[5m])

# Queue depth trend
rabbitmq_queue_messages

# Memory usage
rabbitmq_process_resident_memory_bytes
```

### Day 3: Cleanup

#### Step 4.3: Remove Shovels

```bash
# Remove all migration Shovels from blue cluster
rabbitmqctl list_parameters shovel | awk '{print $2}' | while read shovel; do
    if [[ $shovel == migrate-* ]]; then
        echo "Removing Shovel: $shovel"
        rabbitmqctl clear_parameter shovel "$shovel"
    fi
done
```

#### Step 4.4: Decommission Blue Cluster

```bash
# CAUTION: Only after thorough validation!

# 1. Final backup of blue cluster
./backup-cluster.sh

# 2. Stop RabbitMQ on all blue nodes
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "systemctl stop rabbitmq-server"
done

# 3. Archive configuration and data
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "tar -czvf /backup/rabbitmq-blue-final.tar.gz /var/lib/rabbitmq /etc/rabbitmq"
done

# 4. Terminate instances (after retention period)
# Keep blue cluster data for 30 days before deletion
```

### Day 4-5: Documentation and Handover

#### Step 4.5: Update Documentation

```markdown
## Updated RabbitMQ Architecture

### Cluster Information
- **Version**: RabbitMQ 4.1.4
- **Erlang**: 26.2
- **Nodes**:
  - rabbit-green-1.example.com
  - rabbit-green-2.example.com
  - rabbit-green-3.example.com

### Queue Types
- **Quorum Queues**: orders, notifications, events, user-updates
- **Classic Queues**: rpc.replies (exclusive), priority.tasks (priority)

### Monitoring
- Prometheus endpoint: http://rabbit-green-1:15692/metrics
- Grafana dashboard: [Link]
- Alertmanager rules: [Link]

### Runbooks
- [Node restart procedure]
- [Queue troubleshooting]
- [Emergency rollback]
```

#### Step 4.6: Team Knowledge Transfer

```
TRAINING CHECKLIST:

[ ] Quorum queue operations (vs classic)
[ ] New management UI features
[ ] Updated CLI commands
[ ] Monitoring and alerting changes
[ ] Disaster recovery procedures
[ ] Performance tuning for quorum queues
```

---

## Emergency Procedures

### Emergency Rollback

```bash
#!/bin/bash
# emergency-rollback.sh

echo "EMERGENCY ROLLBACK INITIATED"
echo "Time: $(date)"

# 1. Switch load balancer back to blue
# (Manual step - coordinate with networking team)

# 2. Start blue cluster if stopped
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "systemctl start rabbitmq-server"
done

# 3. Verify blue cluster health
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status

# 4. Reverse Shovels (green to blue) for any accumulated messages
rabbitmqctl set_parameter shovel emergency-reverse '{
    "src-uri": "amqp://rabbit-green-1",
    "src-queue": "orders",
    "dest-uri": "amqp://rabbit-blue-1",
    "dest-queue": "orders",
    "ack-mode": "on-confirm"
}'

# 5. Update applications to point back to blue
# (Requires application deployments)

echo "Rollback completed. Verify traffic on blue cluster."
```

---

**Next Step**: [07-rollback-plan.md](./07-rollback-plan.md)
