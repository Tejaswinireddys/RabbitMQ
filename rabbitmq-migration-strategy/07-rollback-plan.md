# 07. Rollback Plan

## Overview

This document outlines comprehensive rollback procedures for the RabbitMQ migration. A well-tested rollback plan is essential for minimizing risk and ensuring business continuity.

---

## 1. Rollback Decision Framework

### 1.1 Rollback Triggers

```
┌─────────────────────────────────────────────────────────┐
│              ROLLBACK DECISION MATRIX                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  CRITICAL (Immediate Rollback):                         │
│  ├── Complete cluster unavailability                    │
│  ├── Data loss detected                                 │
│  ├── Message delivery failures > 5%                     │
│  └── Security vulnerability discovered                  │
│                                                          │
│  HIGH (Rollback within 1 hour):                         │
│  ├── Performance degradation > 50%                      │
│  ├── Multiple application failures                      │
│  ├── Quorum queue leader elections failing              │
│  └── Consumer lag growing unbounded                     │
│                                                          │
│  MEDIUM (Evaluate and decide):                          │
│  ├── Single application issues                          │
│  ├── Minor performance impact < 20%                     │
│  ├── Non-critical queue issues                          │
│  └── Monitoring gaps                                    │
│                                                          │
│  LOW (Continue with mitigation):                        │
│  ├── Cosmetic UI issues                                 │
│  ├── Log format changes                                 │
│  └── Minor metric discrepancies                         │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Rollback Authority Matrix

| Scenario | Who Can Authorize | Notification Required |
|----------|-------------------|----------------------|
| Critical | On-call engineer | Post-facto to management |
| High | Team lead + On-call | Immediate to stakeholders |
| Medium | Migration lead | Team notification |
| Low | Individual engineer | Document in ticket |

---

## 2. Pre-Rollback Checklist

### 2.1 Before Initiating Rollback

```bash
#!/bin/bash
# pre-rollback-checklist.sh

echo "=== Pre-Rollback Verification ==="

# 1. Confirm issue severity
echo "[ ] Issue severity confirmed as requiring rollback"
echo "[ ] Mitigation alternatives exhausted"

# 2. Check blue cluster availability
echo "Checking blue cluster..."
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    if ssh $node "rabbitmqctl cluster_status" 2>/dev/null; then
        echo "✓ $node is reachable"
    else
        echo "✗ $node is NOT reachable - INVESTIGATE"
    fi
done

# 3. Check message state
echo "Current message counts on green cluster:"
rabbitmqctl list_queues name messages_ready messages_unacknowledged

# 4. Document current state
echo "Saving current state..."
rabbitmqctl cluster_status > /tmp/green_cluster_state_$(date +%s).txt
rabbitmqctl list_queues > /tmp/green_queue_state_$(date +%s).txt

# 5. Notify stakeholders
echo "[ ] Stakeholders notified"
echo "[ ] War room established (if needed)"
```

---

## 3. Rollback Procedures

### 3.1 Phase-Based Rollback

#### Rollback During Phase 1 (Assessment)
**Risk: Very Low**
No changes made yet - nothing to rollback.

#### Rollback During Phase 2 (Preparation)
**Risk: Low**

```bash
# Simply tear down green cluster
# No production impact

# Stop green cluster nodes
for node in rabbit-green-1 rabbit-green-2 rabbit-green-3; do
    ssh $node "systemctl stop rabbitmq-server"
done

# Optionally, terminate instances
# Blue cluster continues operating normally
```

#### Rollback During Phase 3 (Migration - Shovel Active)
**Risk: Medium**

```bash
#!/bin/bash
# rollback-phase3.sh

echo "=== Phase 3 Rollback ==="

# 1. Stop new messages from going to green
echo "Step 1: Removing Shovels..."
rabbitmqctl list_parameters shovel | awk '{print $2}' | while read shovel; do
    rabbitmqctl clear_parameter shovel "$shovel"
done

# 2. Reverse Shovel - move messages from green back to blue
echo "Step 2: Setting up reverse Shovels..."
QUEUES=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues name --quiet)
for queue in $QUEUES; do
    # Skip if no messages
    MSG_COUNT=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues name messages \
        --quiet | grep "^$queue" | awk '{print $2}')
    if [ "$MSG_COUNT" -gt 0 ]; then
        echo "Reversing $queue ($MSG_COUNT messages)..."
        rabbitmqctl set_parameter shovel "reverse-$queue" "{
            \"src-uri\": \"amqp://rabbit-green-1\",
            \"src-queue\": \"$queue\",
            \"dest-uri\": \"amqp://rabbit-blue-1\",
            \"dest-queue\": \"$queue\",
            \"ack-mode\": \"on-confirm\"
        }"
    fi
done

# 3. Wait for drain
echo "Step 3: Waiting for queues to drain..."
while true; do
    TOTAL=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues messages \
        --quiet | awk '{sum+=$1} END {print sum}')
    if [ "$TOTAL" -eq 0 ]; then
        echo "All messages transferred back to blue"
        break
    fi
    echo "Messages remaining on green: $TOTAL"
    sleep 10
done

# 4. Update applications to point back to blue
echo "Step 4: Applications need to be updated to point to blue cluster"
echo "ACTION REQUIRED: Deploy application config changes"
```

#### Rollback During Phase 3 (Migration - After Traffic Switch)
**Risk: High**

```bash
#!/bin/bash
# rollback-post-switch.sh

echo "=== Post-Switch Rollback (CRITICAL) ==="
echo "Time: $(date)"

# 1. IMMEDIATE: Switch load balancer back to blue
echo "Step 1: SWITCH LOAD BALANCER NOW"
echo "Contact: Network team / AWS console"
echo "Target: Blue cluster nodes"
read -p "Press enter when LB switch is complete..."

# 2. Verify blue cluster is healthy
echo "Step 2: Verifying blue cluster..."
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status
if [ $? -ne 0 ]; then
    echo "CRITICAL: Blue cluster not healthy!"
    echo "Starting blue cluster nodes..."
    for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
        ssh $node "systemctl start rabbitmq-server"
    done
    sleep 30
    rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status
fi

# 3. Set up reverse Shovels for accumulated messages
echo "Step 3: Setting up reverse Shovels..."
# (Same as phase 3 reverse Shovel setup)

# 4. Monitor message flow
echo "Step 4: Monitoring message flow..."
watch -n 5 'echo "Blue connections: $(rabbitmqctl -n rabbit@rabbit-blue-1 list_connections | wc -l)"; echo "Green messages: $(rabbitmqctl -n rabbit@rabbit-green-1 list_queues messages --quiet | awk "{sum+=\$1} END {print sum}")"'
```

### 3.2 Component-Specific Rollback

#### Rollback Single Queue

```bash
#!/bin/bash
# rollback-queue.sh <queue-name>

QUEUE=$1
echo "Rolling back queue: $QUEUE"

# 1. Stop Shovel for this queue
rabbitmqctl clear_parameter shovel "migrate-$QUEUE" 2>/dev/null

# 2. Set up reverse Shovel
MSG_COUNT=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues name messages \
    --quiet | grep "^$QUEUE" | awk '{print $2}')

if [ "$MSG_COUNT" -gt 0 ]; then
    echo "Moving $MSG_COUNT messages back to blue..."
    rabbitmqctl set_parameter shovel "reverse-$QUEUE" "{
        \"src-uri\": \"amqp://rabbit-green-1\",
        \"src-queue\": \"$QUEUE\",
        \"dest-uri\": \"amqp://rabbit-blue-1\",
        \"dest-queue\": \"$QUEUE\",
        \"ack-mode\": \"on-confirm\"
    }"

    # Wait for drain
    while true; do
        COUNT=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues name messages \
            --quiet | grep "^$QUEUE" | awk '{print $2}')
        if [ "$COUNT" -eq 0 ]; then
            break
        fi
        sleep 5
    done

    # Remove reverse Shovel
    rabbitmqctl clear_parameter shovel "reverse-$QUEUE"
fi

# 3. Update application configuration for this queue
echo "Update applications using queue '$QUEUE' to point to blue cluster"
```

#### Rollback Single Application

```bash
#!/bin/bash
# rollback-application.sh <app-name>

APP=$1
echo "Rolling back application: $APP"

# 1. Update application configuration
# (Kubernetes example)
kubectl set env deployment/$APP RABBITMQ_HOST=rabbit-blue.example.com

# 2. Restart application
kubectl rollout restart deployment/$APP
kubectl rollout status deployment/$APP

# 3. Verify connectivity
kubectl logs deployment/$APP | grep -i "rabbitmq\|amqp" | tail -20
```

---

## 4. Rollback Validation

### 4.1 Post-Rollback Verification

```bash
#!/bin/bash
# verify-rollback.sh

echo "=== Post-Rollback Verification ==="

# 1. Cluster health
echo "1. Checking cluster health..."
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status
rabbitmq-diagnostics -n rabbit@rabbit-blue-1 check_running
rabbitmq-diagnostics -n rabbit@rabbit-blue-1 check_local_alarms

# 2. Queue health
echo "2. Checking queue health..."
rabbitmqctl -n rabbit@rabbit-blue-1 list_queues name messages consumers

# 3. Connection count
echo "3. Checking connections..."
CONN_COUNT=$(rabbitmqctl -n rabbit@rabbit-blue-1 list_connections | wc -l)
echo "Active connections: $CONN_COUNT"

# 4. Message flow
echo "4. Checking message flow..."
for i in {1..3}; do
    rabbitmqctl -n rabbit@rabbit-blue-1 list_queues name \
        message_stats.publish_details.rate \
        message_stats.deliver_get_details.rate | head -10
    sleep 10
done

# 5. Application health
echo "5. Checking application health..."
# (Application-specific health checks)

# 6. Generate report
echo "=== Rollback Verification Complete ==="
echo "Time: $(date)"
echo "Status: $(rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status | head -1)"
```

### 4.2 Rollback Success Criteria

| Criteria | Check Command | Expected Result |
|----------|---------------|-----------------|
| Cluster healthy | `cluster_status` | All nodes running |
| No alarms | `check_local_alarms` | No alarms active |
| Connections restored | `list_connections \| wc -l` | ≥ pre-migration count |
| Message flow | `list_queues` publish rate | > 0 for active queues |
| Consumer active | `list_consumers` | All expected consumers |
| Zero message loss | Compare queue depths | Within acceptable range |

---

## 5. Post-Rollback Actions

### 5.1 Immediate Actions

```markdown
## Post-Rollback Immediate Checklist

- [ ] Notify all stakeholders of rollback completion
- [ ] Document rollback trigger and symptoms
- [ ] Preserve logs from green cluster
- [ ] Export definitions from green cluster
- [ ] Schedule post-mortem meeting
```

### 5.2 Root Cause Analysis

```markdown
## Rollback Post-Mortem Template

### Incident Summary
- **Date/Time**:
- **Duration**:
- **Trigger**:
- **Impact**:

### Timeline
| Time | Event |
|------|-------|
| | Migration started |
| | Issue detected |
| | Rollback initiated |
| | Rollback completed |

### Root Cause
[Detailed analysis]

### Contributing Factors
1.
2.
3.

### Lessons Learned
1.
2.

### Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| | | |

### Retry Plan
- [ ] Issues addressed
- [ ] Test plan updated
- [ ] New migration date scheduled
```

---

## 6. Blue Cluster Preservation

### 6.1 Keep Blue Running

During migration, always keep blue cluster running until validation is complete:

```bash
# Blue cluster preservation checklist
- [ ] Blue cluster remains in running state
- [ ] Monitoring continues on blue
- [ ] Backups continue on blue
- [ ] Network routes preserved (can switch back)
- [ ] SSL certificates valid
- [ ] User credentials unchanged
```

### 6.2 Blue Cluster State Capture

```bash
#!/bin/bash
# capture-blue-state.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATE_DIR="/backup/rollback-point-$TIMESTAMP"
mkdir -p $STATE_DIR

# Capture cluster state
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status > $STATE_DIR/cluster_status.txt

# Capture definitions
rabbitmqadmin -H rabbit-blue-1 export $STATE_DIR/definitions.json

# Capture queue state
rabbitmqctl -n rabbit@rabbit-blue-1 list_queues name type messages \
    > $STATE_DIR/queue_state.txt

# Capture connection state
rabbitmqctl -n rabbit@rabbit-blue-1 list_connections name peer_host \
    > $STATE_DIR/connections.txt

echo "Blue cluster state captured: $STATE_DIR"
```

---

## 7. Communication Templates

### 7.1 Rollback Initiation

```
Subject: [ALERT] RabbitMQ Migration Rollback Initiated

Team,

We are initiating a rollback of the RabbitMQ migration due to:
- Issue: [Describe issue]
- Impact: [Describe impact]
- Severity: [Critical/High/Medium]

Current Status:
- Green cluster: [State]
- Blue cluster: [State]
- Applications: [State]

Actions in Progress:
1. [Current action]
2. [Next steps]

Expected Resolution Time: [ETA]

Updates will follow in 30-minute intervals.

[Your Name]
Migration Lead
```

### 7.2 Rollback Completion

```
Subject: [RESOLVED] RabbitMQ Migration Rollback Complete

Team,

The RabbitMQ migration rollback has been completed successfully.

Summary:
- Rollback trigger: [Reason]
- Rollback duration: [Time]
- Current state: Operating on blue cluster (3.12)
- Message loss: [None/Details]
- Application impact: [Details]

Verification:
- Cluster health: ✓
- Message flow: ✓
- All applications connected: ✓

Next Steps:
1. Post-mortem scheduled for [Date/Time]
2. Root cause analysis in progress
3. Migration retry TBD

Please report any lingering issues to [contact].

[Your Name]
Migration Lead
```

---

**Next Step**: [08-testing-validation.md](./08-testing-validation.md)
