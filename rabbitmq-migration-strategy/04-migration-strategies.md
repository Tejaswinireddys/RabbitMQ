# 04. Migration Strategies

## Overview

This document evaluates different migration strategies for upgrading a three-node RabbitMQ cluster from 3.12 to 4.1.4. Each strategy has trade-offs in terms of downtime, risk, complexity, and resource requirements.

---

## 1. Strategy Comparison Matrix

| Strategy | Downtime | Risk Level | Complexity | Resource Cost | Rollback Ease |
|----------|----------|------------|------------|---------------|---------------|
| Rolling Upgrade | Minutes | Medium | Low | None | Medium |
| Blue-Green | Zero | Low | High | 2x Infrastructure | Easy |
| Federation Bridge | Zero | Low | Medium | 1.5x Infrastructure | Easy |
| Shovel Migration | Zero | Low | Medium | 1.5x Infrastructure | Easy |
| Hybrid (Recommended) | Zero | Low | Medium | 1.5x Infrastructure | Easy |

---

## 2. Strategy 1: Rolling Upgrade

### 2.1 Overview

Upgrade nodes one at a time while maintaining cluster quorum.

```
┌─────────────────────────────────────────────────────────┐
│                   ROLLING UPGRADE                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Phase 1: Node 3 (upgrade while 1,2 serve traffic)      │
│  ┌─────┐  ┌─────┐  ┌─────┐                              │
│  │ 3.12│  │ 3.12│  │ 4.1 │ ◄── Upgraded                │
│  │ N1  │  │ N2  │  │ N3  │                              │
│  └─────┘  └─────┘  └─────┘                              │
│                                                          │
│  Phase 2: Node 2 (upgrade while 1,3 serve traffic)      │
│  ┌─────┐  ┌─────┐  ┌─────┐                              │
│  │ 3.12│  │ 4.1 │  │ 4.1 │                              │
│  │ N1  │  │ N2  │  │ N3  │                              │
│  └─────┘  └─────┘  └─────┘                              │
│                                                          │
│  Phase 3: Node 1 (upgrade while 2,3 serve traffic)      │
│  ┌─────┐  ┌─────┐  ┌─────┐                              │
│  │ 4.1 │  │ 4.1 │  │ 4.1 │                              │
│  │ N1  │  │ N2  │  │ N3  │                              │
│  └─────┘  └─────┘  └─────┘                              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Prerequisites

- All feature flags enabled on 3.12
- Upgrade to 3.13 first (if direct 3.12→4.x not supported)
- Compatible Erlang version installed
- Load balancer with health checks

### 2.3 Procedure

```bash
# For each node (starting with least critical):

# 1. Enable maintenance mode
rabbitmqctl enable_maintenance_mode

# 2. Wait for connections to drain
rabbitmqctl list_connections | wc -l

# 3. Stop RabbitMQ
systemctl stop rabbitmq-server

# 4. Upgrade Erlang (if needed)
# Debian/Ubuntu:
apt-get update && apt-get install erlang-nox

# 5. Upgrade RabbitMQ
apt-get install rabbitmq-server=4.1.4-1

# 6. Start RabbitMQ
systemctl start rabbitmq-server

# 7. Verify node joined cluster
rabbitmqctl cluster_status

# 8. Disable maintenance mode
rabbitmqctl disable_maintenance_mode

# 9. Verify traffic flowing
rabbitmqctl list_connections
```

### 2.4 Pros and Cons

| Pros | Cons |
|------|------|
| No additional infrastructure | Mixed-version cluster during upgrade |
| Simple procedure | Rollback requires re-upgrade |
| Minimal planning | Potential compatibility issues |
| Lower cost | Queue leader movements |

### 2.5 Risk Mitigation

- Start with the node hosting fewest queue leaders
- Maintain backups before each node upgrade
- Have rollback packages ready
- Monitor closely during mixed-version state

---

## 3. Strategy 2: Blue-Green Deployment

### 3.1 Overview

Deploy a completely new 4.1.4 cluster and migrate traffic.

```
┌─────────────────────────────────────────────────────────┐
│                  BLUE-GREEN DEPLOYMENT                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  BLUE CLUSTER (Current - 3.12)                          │
│  ┌─────┐  ┌─────┐  ┌─────┐                              │
│  │ 3.12│  │ 3.12│  │ 3.12│                              │
│  │ N1  │  │ N2  │  │ N3  │                              │
│  └──┬──┘  └──┬──┘  └──┬──┘                              │
│     │        │        │                                  │
│     └────────┼────────┘                                  │
│              │                                           │
│         Federation/Shovel                                │
│              │                                           │
│     ┌────────┼────────┐                                  │
│     │        │        │                                  │
│  ┌──┴──┐  ┌──┴──┐  ┌──┴──┐                              │
│  │ 4.1 │  │ 4.1 │  │ 4.1 │                              │
│  │ N1' │  │ N2' │  │ N3' │                              │
│  └─────┘  └─────┘  └─────┘                              │
│  GREEN CLUSTER (New - 4.1.4)                            │
│                                                          │
│  Traffic Switch: DNS or Load Balancer                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Prerequisites

- 2x infrastructure capacity
- Federation or Shovel plugin
- DNS or load balancer control
- Message replay capability (for cutover)

### 3.3 Procedure

```bash
# Phase 1: Deploy Green Cluster
# Deploy new 3-node cluster with RabbitMQ 4.1.4

# Phase 2: Configure Federation
# On GREEN cluster:
rabbitmqctl set_parameter federation-upstream blue-cluster \
    '{"uri":"amqp://user:pass@blue-lb:5672","ack-mode":"on-confirm"}'

# Phase 3: Create Federation Policies
rabbitmqctl set_policy federate-all ".*" \
    '{"federation-upstream-set":"all"}' \
    --apply-to queues

# Phase 4: Validate Sync
# Monitor federation status
rabbitmqctl eval 'rabbit_federation_status:status().'

# Phase 5: Switch Traffic
# Update DNS or load balancer to point to GREEN

# Phase 6: Drain Blue Cluster
# Wait for remaining messages to federate
# Monitor: rabbitmqctl list_queues messages

# Phase 7: Decommission Blue
# After validation period, tear down blue cluster
```

### 3.4 Pros and Cons

| Pros | Cons |
|------|------|
| Zero downtime | Requires 2x infrastructure |
| Easy rollback (switch back to blue) | Complex setup |
| Clean installation | Message ordering challenges |
| Full testing before cutover | Federation overhead |

### 3.5 Cost Estimate

```
BLUE-GREEN INFRASTRUCTURE:

Temporary additional cost:
├── 3 additional nodes (compute)
├── Storage for new cluster
├── Network (inter-cluster traffic)
└── Duration: 1-2 weeks for validation

Total: ~2x normal operating cost for migration period
```

---

## 4. Strategy 3: Shovel-Based Migration

### 4.1 Overview

Use Shovel plugin to move messages from old to new cluster.

```
┌─────────────────────────────────────────────────────────┐
│                  SHOVEL MIGRATION                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  SOURCE CLUSTER (3.12)          TARGET CLUSTER (4.1.4)  │
│  ┌─────────────────┐            ┌─────────────────┐     │
│  │                 │   Shovel   │                 │     │
│  │  Queue: orders  │ ─────────► │  Queue: orders  │     │
│  │                 │            │  (Quorum)       │     │
│  └─────────────────┘            └─────────────────┘     │
│                                                          │
│  Shovel Configuration:                                   │
│  • Consumes from source queue                           │
│  • Publishes to target queue                            │
│  • Acknowledgment-based (no message loss)               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Shovel Configuration

```bash
# Configure shovel for each queue
rabbitmqctl set_parameter shovel migrate-orders '{
    "src-protocol": "amqp091",
    "src-uri": "amqp://user:pass@old-cluster:5672",
    "src-queue": "orders",
    "dest-protocol": "amqp091",
    "dest-uri": "amqp://user:pass@new-cluster:5672",
    "dest-queue": "orders",
    "ack-mode": "on-confirm",
    "src-delete-after": "never"
}'
```

### 4.3 Shovel vs Federation

| Feature | Shovel | Federation |
|---------|--------|------------|
| Direction | Unidirectional | Bidirectional capable |
| Message source | Consumes from queue | Subscribes to exchange |
| Ordering | Preserved per shovel | May vary |
| Configuration | Per-queue | Policy-based |
| Overhead | Lower | Higher |
| Use case | Migration | Ongoing replication |

### 4.4 Pros and Cons

| Pros | Cons |
|------|------|
| Fine-grained control | Per-queue configuration |
| Message ordering preserved | Manual setup for many queues |
| Lower overhead than federation | One-time migration only |
| Simple to understand | Need to handle new messages |

---

## 5. Strategy 4: Hybrid Approach (Recommended)

### 5.1 Overview

Combine strategies for optimal migration with zero downtime.

```
┌─────────────────────────────────────────────────────────┐
│              HYBRID MIGRATION STRATEGY                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  PHASE 1: PREPARATION                                    │
│  ├── Deploy new 4.1.4 cluster (Green)                   │
│  ├── Configure Shovel for critical queues               │
│  └── Test with synthetic traffic                        │
│                                                          │
│  PHASE 2: QUEUE MIGRATION                               │
│  ├── Create quorum queues on Green cluster              │
│  ├── Enable Shovel to drain classic queues              │
│  ├── Switch publishers to Green (by application)        │
│  └── Validate message flow                              │
│                                                          │
│  PHASE 3: TRAFFIC CUTOVER                               │
│  ├── Redirect remaining publishers                       │
│  ├── Wait for Blue queue drain                          │
│  ├── Switch consumers to Green                          │
│  └── Monitor for issues                                 │
│                                                          │
│  PHASE 4: CLEANUP                                        │
│  ├── Remove Shovel configuration                        │
│  ├── Decommission Blue cluster                          │
│  └── Update documentation                               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Detailed Timeline

```
Week 1: Infrastructure Preparation
├── Day 1-2: Deploy Green cluster
├── Day 3-4: Configure networking, TLS, monitoring
└── Day 5: Initial testing

Week 2: Queue Migration Setup
├── Day 1-2: Create quorum queues on Green
├── Day 3-4: Configure Shovel for each queue
└── Day 5: Validate Shovel operation

Week 3: Application Migration
├── Day 1-2: Migrate non-critical applications
├── Day 3-4: Migrate critical applications
└── Day 5: Validation and monitoring

Week 4: Cutover and Cleanup
├── Day 1-2: Final traffic switch
├── Day 3-4: Monitor and stabilize
└── Day 5: Decommission Blue cluster
```

### 5.3 Application Migration Order

```
MIGRATION PRIORITY:

Priority 1 (First): Non-critical, low-volume
├── Logging queues
├── Analytics queues
└── Batch processing queues

Priority 2 (Second): Medium criticality
├── Notification queues
├── Email queues
└── Report generation

Priority 3 (Third): High criticality
├── Order processing
├── Payment queues
└── Real-time APIs

Priority 4 (Last): Mission-critical
├── Core transaction queues
├── Financial processing
└── Customer-facing real-time
```

### 5.4 Traffic Switching Methods

```
METHOD 1: DNS-Based Switch
┌─────────────────────────────────────────────────────────┐
│  rabbitmq.example.com → Blue cluster (before)          │
│  rabbitmq.example.com → Green cluster (after)          │
│                                                          │
│  Pros: Simple, no app changes                           │
│  Cons: TTL propagation delay, cached DNS                │
└─────────────────────────────────────────────────────────┘

METHOD 2: Load Balancer Switch
┌─────────────────────────────────────────────────────────┐
│  LB Backend Pool:                                        │
│  ├── Blue nodes (weight: 100 → 0)                       │
│  └── Green nodes (weight: 0 → 100)                      │
│                                                          │
│  Pros: Instant switch, gradual shift possible           │
│  Cons: Requires LB configuration access                 │
└─────────────────────────────────────────────────────────┘

METHOD 3: Application Configuration
┌─────────────────────────────────────────────────────────┐
│  Config change per application:                         │
│  RABBITMQ_HOST=blue-cluster → green-cluster             │
│                                                          │
│  Pros: Per-app control, staged rollout                  │
│  Cons: Requires app deployments, coordination           │
└─────────────────────────────────────────────────────────┘
```

---

## 6. Decision Framework

### 6.1 Strategy Selection Criteria

```
                    ┌─────────────────────────────────────┐
                    │     STRATEGY DECISION TREE          │
                    └─────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │  Can tolerate brief downtime? │
                    └───────────────┬───────────────┘
                           ┌────────┴────────┐
                          YES               NO
                           │                 │
                    ┌──────┴──────┐   ┌──────┴──────┐
                    │   Rolling   │   │  Have 2x    │
                    │   Upgrade   │   │  capacity?  │
                    └─────────────┘   └──────┬──────┘
                                      ┌──────┴──────┐
                                     YES           NO
                                      │             │
                               ┌──────┴──────┐ ┌────┴────┐
                               │ Blue-Green  │ │ Hybrid  │
                               │ or Hybrid   │ │ (Lean)  │
                               └─────────────┘ └─────────┘
```

### 6.2 Recommendation Matrix

| Scenario | Recommended Strategy |
|----------|---------------------|
| Small cluster, low traffic | Rolling Upgrade |
| Production, zero-downtime required | Blue-Green or Hybrid |
| Limited infrastructure budget | Hybrid (lean) |
| Many applications to migrate | Hybrid with staged rollout |
| Mission-critical financial | Blue-Green |
| Rapid timeline requirement | Rolling Upgrade |

---

## 7. Recommended Strategy for 3-Node Cluster

### 7.1 Our Recommendation: Hybrid Approach

For a production 3-node cluster migrating from 3.12 to 4.1.4 with classic to quorum queue conversion:

```
RECOMMENDED: HYBRID STRATEGY

Rationale:
├── Zero downtime for production traffic
├── Controlled rollback capability
├── Validates quorum queue behavior before cutover
├── Allows staged application migration
├── Manages risk with per-queue granularity
└── Reasonable infrastructure cost (1.5x for 2-3 weeks)
```

### 7.2 Implementation Summary

```
HYBRID IMPLEMENTATION STEPS:

1. Deploy Green Cluster (4.1.4)
   └── 3 nodes with quorum queue configuration

2. Configure Message Bridge
   └── Shovel from Blue classic queues to Green quorum queues

3. Migrate Applications in Phases
   └── Non-critical → Medium → Critical → Mission-critical

4. Cutover Traffic
   └── Load balancer switch to Green

5. Drain and Decommission
   └── Wait for Blue queues to empty, then remove
```

---

**Next Step**: [05-quorum-queue-migration.md](./05-quorum-queue-migration.md)
