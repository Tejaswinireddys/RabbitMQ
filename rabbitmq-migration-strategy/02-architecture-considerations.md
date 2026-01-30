# 02. Architecture Considerations

## Overview

This document outlines the architectural decisions and trade-offs involved in migrating from RabbitMQ 3.12 to 4.1.4 with Classic to Quorum queue conversion.

---

## 1. RabbitMQ 4.x Architecture Changes

### 1.1 Major Changes in RabbitMQ 4.x

| Feature | RabbitMQ 3.12 | RabbitMQ 4.x | Impact |
|---------|---------------|--------------|--------|
| Metadata Store | Mnesia | Khepri (Raft-based) | Major |
| Classic Queue Mirroring | Supported | Deprecated/Removed | Breaking |
| Default Queue Type | classic | quorum (configurable) | Behavioral |
| Management UI | Classic | Modernized | Visual |
| Metrics | Prometheus compatible | Enhanced Prometheus | Monitoring |
| Stream Support | Full | Enhanced | Feature |

### 1.2 Khepri Database Migration

RabbitMQ 4.x introduces Khepri as the new metadata store:

```
┌─────────────────────────────────────────────────────────┐
│                    METADATA MIGRATION                    │
├─────────────────────────────────────────────────────────┤
│  Mnesia (3.12)              →        Khepri (4.x)       │
│  ├── Users                  →        ├── Users          │
│  ├── Vhosts                 →        ├── Vhosts         │
│  ├── Permissions            →        ├── Permissions    │
│  ├── Queues (metadata)      →        ├── Queues         │
│  ├── Exchanges              →        ├── Exchanges      │
│  ├── Bindings               →        ├── Bindings       │
│  └── Policies               →        └── Policies       │
└─────────────────────────────────────────────────────────┘
```

**Key Considerations:**
- Khepri uses Raft consensus (similar to quorum queues)
- More resilient to network partitions
- Requires minimum 3 nodes for optimal operation
- Migration is automatic but one-way

---

## 2. Classic vs Quorum Queue Architecture

### 2.1 Architectural Comparison

```
CLASSIC QUEUE (Mirrored)                QUORUM QUEUE
┌─────────────────────────┐             ┌─────────────────────────┐
│      Master Node        │             │      Leader Node        │
│  ┌─────────────────┐    │             │  ┌─────────────────┐    │
│  │   Queue Data    │    │             │  │   Queue Data    │    │
│  │   (Primary)     │────┼──Sync──►    │  │   (Raft Log)    │    │
│  └─────────────────┘    │             │  └─────────────────┘    │
└─────────────────────────┘             └───────────┬─────────────┘
         │                                          │
         │ Async Replication                        │ Raft Consensus
         ▼                                          ▼
┌─────────────────────────┐             ┌─────────────────────────┐
│      Mirror Node        │             │     Follower Node       │
│  ┌─────────────────┐    │             │  ┌─────────────────┐    │
│  │   Queue Data    │    │             │  │   Queue Data    │    │
│  │   (Mirror)      │    │             │  │   (Replica)     │    │
│  └─────────────────┘    │             │  └─────────────────┘    │
└─────────────────────────┘             └─────────────────────────┘
                                                    │
                                                    ▼
                                        ┌─────────────────────────┐
                                        │     Follower Node       │
                                        │  ┌─────────────────┐    │
                                        │  │   Queue Data    │    │
                                        │  │   (Replica)     │    │
                                        │  └─────────────────┘    │
                                        └─────────────────────────┘
```

### 2.2 Feature Comparison

| Feature | Classic Queue | Classic Mirrored | Quorum Queue |
|---------|--------------|------------------|--------------|
| Durability | Optional | Optional | Always durable |
| Replication | None | Async | Raft consensus |
| Data safety | Low | Medium | High |
| Performance | Highest | Medium | High |
| Memory usage | Lower | Medium | Higher |
| Disk usage | Lower | Medium | Higher |
| Leader election | N/A | Manual | Automatic |
| Poison message handling | None | None | Built-in |
| Delivery limit | None | None | Configurable |
| Priority support | Yes | Yes | No |
| TTL per-message | Yes | Yes | Yes |
| Lazy mode | Yes | Yes | No (inherent) |
| Max-length | Yes | Yes | Yes |

### 2.3 When NOT to Use Quorum Queues

**Keep as Classic Queue if:**

1. **Temporary/Transient queues**
   - Auto-delete queues
   - Exclusive queues
   - Reply-to queues (RPC patterns)

2. **Very high throughput, low durability needs**
   - Logging pipelines where loss is acceptable
   - Metrics collection with sampling

3. **Priority queues required**
   - Quorum queues don't support priorities
   - Consider separate queues per priority

4. **Single-node deployments**
   - Quorum queues have overhead without benefit

---

## 3. Cluster Topology Decisions

### 3.1 Three-Node Cluster Considerations

```
RECOMMENDED: Odd number of nodes for quorum

Node Distribution:
┌─────────────────────────────────────────────────────────┐
│                    AVAILABILITY ZONE 1                   │
│  ┌─────────────────────────────────────────────────────┐│
│  │                     Node 1                          ││
│  │  • Quorum queue member                              ││
│  │  • Khepri voter                                     ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                    AVAILABILITY ZONE 2                   │
│  ┌─────────────────────────────────────────────────────┐│
│  │                     Node 2                          ││
│  │  • Quorum queue member                              ││
│  │  • Khepri voter                                     ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                    AVAILABILITY ZONE 3                   │
│  ┌─────────────────────────────────────────────────────┐│
│  │                     Node 3                          ││
│  │  • Quorum queue member                              ││
│  │  • Khepri voter                                     ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘

Quorum = 2 (majority of 3)
Tolerance = 1 node failure
```

### 3.2 Quorum Queue Replication Factor

**Recommendation for 3-node cluster:**

```erlang
%% rabbitmq.conf
quorum_queue.default_target_replica_count = 3

%% Or via policy
{
  "name": "quorum-policy",
  "pattern": ".*",
  "definition": {
    "x-quorum-target-group-size": 3
  }
}
```

| Cluster Size | Recommended Replication | Failure Tolerance |
|-------------|------------------------|-------------------|
| 3 nodes | 3 replicas | 1 node |
| 5 nodes | 5 replicas | 2 nodes |
| 7 nodes | 5-7 replicas | 2-3 nodes |

### 3.3 Memory and Disk Architecture

**Quorum Queue Memory Model:**

```
┌─────────────────────────────────────────────────────────┐
│                    PER-NODE MEMORY                       │
├─────────────────────────────────────────────────────────┤
│  Quorum Queue In-memory index: ~32 bytes/message        │
│  Segment files: Configurable (64KB-8MB segments)        │
│  WAL (Write-Ahead Log): Bounded by segment size         │
│                                                          │
│  Recommended: 2-4GB heap per 1M messages in-flight      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    DISK LAYOUT                           │
├─────────────────────────────────────────────────────────┤
│  /var/lib/rabbitmq/quorum/                              │
│  ├── <queue-id>/                                        │
│  │   ├── wal/           # Write-ahead log               │
│  │   ├── segments/      # Data segments                 │
│  │   └── snapshots/     # Raft snapshots                │
│  └── ...                                                │
│                                                          │
│  Recommended: SSD storage with 3x current disk usage    │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Network Architecture

### 4.1 Port Requirements

| Port | Protocol | Purpose | Change in 4.x |
|------|----------|---------|---------------|
| 4369 | epmd | Erlang Port Mapper | No change |
| 5672 | AMQP | Client connections | No change |
| 5671 | AMQPS | TLS client connections | No change |
| 15672 | HTTP | Management UI/API | No change |
| 15692 | HTTP | Prometheus metrics | No change |
| 25672 | Erlang | Inter-node communication | No change |
| 35672-35682 | Erlang | CLI tools | No change |

### 4.2 Load Balancer Configuration

```
┌─────────────────────────────────────────────────────────┐
│                   LOAD BALANCER CONFIG                   │
├─────────────────────────────────────────────────────────┤
│  AMQP (5672):                                           │
│  ├── Protocol: TCP                                      │
│  ├── Health check: TCP or HTTP /api/health/checks/alarms│
│  ├── Session affinity: Recommended for connection reuse │
│  └── Idle timeout: > 60 seconds (heartbeat)            │
│                                                          │
│  Management (15672):                                     │
│  ├── Protocol: HTTP/HTTPS                               │
│  ├── Health check: GET /api/healthchecks/node           │
│  └── Session affinity: Not required                     │
└─────────────────────────────────────────────────────────┘
```

### 4.3 Health Check Endpoints (4.x)

```bash
# Basic node health
GET /api/health/checks/local-alarms

# Cluster-wide health
GET /api/health/checks/cluster-wide-alarms

# Port listener check
GET /api/health/checks/port-listener/{port}

# Protocol check
GET /api/health/checks/protocol-listener/{protocol}

# Virtual host health
GET /api/health/checks/virtual-hosts

# Node memory check
GET /api/health/checks/node-is-quorum-critical
```

---

## 5. High Availability Architecture

### 5.1 HA Strategy with Quorum Queues

```
┌─────────────────────────────────────────────────────────┐
│               HIGH AVAILABILITY MODEL                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Publisher ──► Load Balancer ──► Any Node               │
│                     │                                    │
│                     │    Raft replication               │
│                     ▼    ◄─────────────►                │
│              ┌─────────────┐                            │
│              │   Leader    │◄──► Follower 1             │
│              └─────────────┘◄──► Follower 2             │
│                     │                                    │
│                     ▼                                    │
│  Consumer ◄── Load Balancer ◄── Any Node                │
│                                                          │
│  Automatic leader election on failure (< 30 seconds)    │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Partition Handling Strategy

**Recommended for 4.x with Quorum Queues:**

```erlang
%% rabbitmq.conf
cluster_partition_handling = pause_minority
```

| Strategy | Behavior | Recommendation |
|----------|----------|----------------|
| `pause_minority` | Minority nodes pause | **Recommended** for quorum |
| `autoheal` | Automatic healing | Not for quorum queues |
| `ignore` | Manual intervention | Not recommended |

### 5.3 Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| 1 node failure | Quorum maintained | Automatic leader election |
| 2 node failure | Quorum lost | Queues become unavailable |
| Network partition (1 vs 2) | Minority pauses | Auto-resume when healed |
| Leader node failure | Brief unavailability | New leader elected (<30s) |

---

## 6. Security Architecture

### 6.1 TLS Configuration for 4.x

```erlang
%% rabbitmq.conf
listeners.ssl.default = 5671

ssl_options.cacertfile = /path/to/ca_certificate.pem
ssl_options.certfile   = /path/to/server_certificate.pem
ssl_options.keyfile    = /path/to/server_key.pem

# TLS 1.3 recommended for 4.x
ssl_options.versions.1 = tlsv1.3
ssl_options.versions.2 = tlsv1.2
```

### 6.2 Inter-node TLS

```erlang
%% Enable TLS for inter-node communication
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_classic_config
distribution.listener.interface = 0.0.0.0
distribution.listener.port_range.min = 25672
distribution.listener.port_range.max = 25672

ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true
```

---

## 7. Monitoring Architecture

### 7.1 Metrics Architecture (4.x Enhanced)

```
┌─────────────────────────────────────────────────────────┐
│                 MONITORING STACK                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  RabbitMQ ──► Prometheus ──► Grafana                    │
│  (15692)      (scrape)       (visualize)                │
│                    │                                     │
│                    ▼                                     │
│              Alertmanager                                │
│              (alerting)                                  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Key Metrics for Quorum Queues

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `rabbitmq_raft_term_total` | Raft term (leader elections) | Rapid increase |
| `rabbitmq_raft_log_entries` | Uncommitted entries | > 10000 |
| `rabbitmq_raft_entry_commit_latency` | Commit latency | > 500ms |
| `rabbitmq_quorum_queue_messages` | Queue depth | Application-specific |
| `rabbitmq_quorum_queue_memory` | Memory per queue | > 1GB per queue |

---

## 8. Capacity Planning

### 8.1 Resource Requirements Change

| Resource | Classic Queue | Quorum Queue | Change |
|----------|--------------|--------------|--------|
| Memory | Baseline | +20-40% | Increase |
| Disk IOPS | Baseline | +50-100% | Increase |
| Disk Space | Baseline | +200-300% | Increase |
| Network | Baseline | +100-200% | Increase |
| CPU | Baseline | +10-30% | Increase |

### 8.2 Sizing Recommendations

```
FOR 3-NODE CLUSTER (Production):

Minimum per node:
├── CPU: 4 cores
├── RAM: 8 GB
├── Disk: 100 GB SSD (3x message volume)
└── Network: 1 Gbps

Recommended per node:
├── CPU: 8 cores
├── RAM: 16 GB
├── Disk: 500 GB NVMe SSD
└── Network: 10 Gbps

High-throughput per node:
├── CPU: 16 cores
├── RAM: 32 GB
├── Disk: 1 TB NVMe SSD
└── Network: 25 Gbps
```

---

## 9. Trade-off Analysis

### 9.1 Migration Strategy Trade-offs

| Approach | Downtime | Risk | Complexity | Rollback |
|----------|----------|------|------------|----------|
| Rolling upgrade | Minimal | Medium | Low | Medium |
| Blue-green | None | Low | High | Easy |
| Federation bridge | None | Low | Medium | Easy |
| Shovel-based | None | Low | Medium | Easy |

### 9.2 Recommended Approach

**For 3-node production cluster:**

```
RECOMMENDATION: Blue-Green with Federation Bridge

Rationale:
├── Zero downtime requirement satisfied
├── Easy rollback to old cluster
├── Thorough testing before cutover
├── Queue migration can be gradual
└── Lower risk than in-place upgrade
```

---

**Next Step**: [03-version-compatibility.md](./03-version-compatibility.md)
