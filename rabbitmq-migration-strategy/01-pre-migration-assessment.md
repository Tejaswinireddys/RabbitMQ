# 01. Pre-Migration Assessment

## Overview

Before initiating the migration, a thorough assessment of the current environment is critical. This document outlines all areas requiring evaluation.

---

## 1. Current Cluster Inventory

### 1.1 Node Information

Collect the following for each node:

```bash
# On each node, gather system information
rabbitmqctl status
rabbitmqctl cluster_status
rabbitmq-diagnostics environment
rabbitmq-diagnostics erlang_version
```

| Node | Hostname | RabbitMQ Version | Erlang/OTP Version | RAM | Disk | Role |
|------|----------|------------------|-------------------|-----|------|------|
| Node 1 | rabbit1.example.com | 3.12.x | 25.x | GB | GB | Disc |
| Node 2 | rabbit2.example.com | 3.12.x | 25.x | GB | GB | Disc |
| Node 3 | rabbit3.example.com | 3.12.x | 25.x | GB | GB | Disc |

### 1.2 Cluster Configuration

```bash
# Collect cluster name
rabbitmqctl cluster_status | grep "Cluster name"

# Network partitioning strategy
rabbitmqctl environment | grep cluster_partition_handling

# Memory and disk thresholds
rabbitmqctl environment | grep -E "(vm_memory|disk_free)"
```

**Document:**
- Cluster name: ________________
- Partition handling strategy: ________________
- Memory high watermark: ________________
- Disk free limit: ________________

---

## 2. Queue Inventory Analysis

### 2.1 Queue Type Distribution

```bash
# List all queues with their types
rabbitmqctl list_queues name type durable auto_delete messages consumers \
    --formatter=json > queue_inventory.json

# Summary by type
rabbitmqctl list_queues type --quiet | sort | uniq -c
```

| Queue Type | Count | Total Messages | Notes |
|------------|-------|----------------|-------|
| Classic | | | Primary migration target |
| Classic (Mirrored) | | | HA policy applied |
| Quorum | | | Already migrated |
| Stream | | | No migration needed |

### 2.2 Queue Characteristics Assessment

For each classic queue, document:

```bash
# Detailed queue analysis
rabbitmqctl list_queues name type durable exclusive auto_delete \
    arguments messages_ready messages_unacknowledged consumers \
    memory policy state --formatter=json
```

**Classification Matrix:**

| Characteristic | Quorum Queue Compatible | Action Required |
|---------------|------------------------|-----------------|
| Durable: true | ✅ Yes | None |
| Durable: false | ❌ No | Mark as non-migratable |
| Exclusive: true | ❌ No | Cannot migrate |
| Auto-delete: true | ❌ No | Cannot migrate |
| TTL policies | ✅ Yes | Verify behavior |
| Max-length | ✅ Yes | Convert to policy |
| Dead-letter | ✅ Yes | Verify target queue |
| Priority queues | ❌ No | Keep as classic |

### 2.3 Queue Migration Eligibility

Create a categorized list:

**Category A - Direct Migration (Durable, Non-exclusive):**
- Queue names...

**Category B - Requires Application Changes:**
- Queue names (with reasons)...

**Category C - Cannot Migrate (Must remain Classic):**
- Queue names (with reasons)...

---

## 3. Application Dependency Mapping

### 3.1 Connected Applications

```bash
# List all connections with application names
rabbitmqctl list_connections name user client_properties peer_host peer_port \
    --formatter=json > connections.json

# List consumers
rabbitmqctl list_consumers queue_name channel_pid consumer_tag ack_required \
    --formatter=json > consumers.json
```

**Application Inventory:**

| Application | Connection Count | Queues Used | Protocol | Client Library | Version |
|-------------|-----------------|-------------|----------|----------------|---------|
| | | | AMQP 0-9-1 | | |
| | | | AMQP 1.0 | | |

### 3.2 Client Library Compatibility

| Client Library | Current Version | RabbitMQ 4.x Compatible Version | Upgrade Required |
|---------------|-----------------|--------------------------------|------------------|
| amqp-client (Java) | | 5.20+ | Yes/No |
| pika (Python) | | 1.3+ | Yes/No |
| amqplib (Node.js) | | 0.10+ | Yes/No |
| Bunny (Ruby) | | 2.22+ | Yes/No |
| php-amqplib | | 3.5+ | Yes/No |
| amqp (Go) | | 1.9+ | Yes/No |

---

## 4. Exchange and Binding Analysis

```bash
# List exchanges
rabbitmqctl list_exchanges name type durable auto_delete arguments \
    --formatter=json > exchanges.json

# List bindings
rabbitmqctl list_bindings source_name source_kind destination_name \
    destination_kind routing_key arguments --formatter=json > bindings.json
```

**Exchange Summary:**

| Exchange Type | Count | Notes |
|--------------|-------|-------|
| direct | | |
| fanout | | |
| topic | | |
| headers | | |
| x-consistent-hash | | Requires plugin |
| x-delayed-message | | Requires plugin |

---

## 5. Plugin Inventory

```bash
# List enabled plugins
rabbitmq-plugins list --enabled
```

**Plugin Compatibility Matrix:**

| Plugin | Enabled | RabbitMQ 4.x Status | Action Required |
|--------|---------|--------------------|--------------------|
| rabbitmq_management | ✅ | ✅ Included | None |
| rabbitmq_shovel | | ✅ Compatible | Verify config |
| rabbitmq_federation | | ✅ Compatible | Verify config |
| rabbitmq_prometheus | | ✅ Compatible | Update dashboards |
| rabbitmq_delayed_message_exchange | | ⚠️ Check version | Upgrade plugin |
| rabbitmq_consistent_hash_exchange | | ✅ Compatible | None |
| rabbitmq_mqtt | | ✅ Compatible | None |
| rabbitmq_stomp | | ✅ Compatible | None |
| rabbitmq_stream | | ✅ Compatible | None |

---

## 6. Feature Flags Status

```bash
# List all feature flags with status
rabbitmqctl list_feature_flags --formatter=json
```

**Critical Feature Flags for 4.x:**

| Feature Flag | Current Status | Required for 4.x | Action |
|-------------|----------------|------------------|--------|
| quorum_queue | | Required | Enable before upgrade |
| implicit_default_bindings | | Required | Enable before upgrade |
| virtual_host_metadata | | Required | Enable before upgrade |
| maintenance_mode_status | | Required | Enable before upgrade |
| user_limits | | Required | Enable before upgrade |
| stream_queue | | Required | Enable before upgrade |
| classic_queue_type_delivery_support | | Required | Enable before upgrade |
| restart_streams | | Required | Enable before upgrade |
| message_containers | | New in 3.13+ | Will be enabled |
| khepri_db | | New in 4.x | Post-upgrade |

**Pre-upgrade Feature Flag Enablement:**
```bash
# Enable all stable feature flags before upgrade
rabbitmqctl enable_feature_flag all
```

---

## 7. Performance Baseline

### 7.1 Current Metrics

Capture baseline metrics for comparison post-migration:

```bash
# Message rates
rabbitmqctl list_queues name messages_ready messages_unacknowledged \
    message_stats.publish_details.rate message_stats.deliver_get_details.rate
```

| Metric | Current Value | Acceptable Range |
|--------|--------------|------------------|
| Publish rate (msg/s) | | |
| Consume rate (msg/s) | | |
| Queue depth (avg) | | |
| Memory usage (%) | | |
| Disk usage (%) | | |
| Connection count | | |
| Channel count | | |

### 7.2 Load Patterns

Document peak usage times and patterns:
- Peak hours: ________________
- Peak message rate: ________________
- Peak connection count: ________________

---

## 8. Network and Infrastructure

### 8.1 Network Topology

```
┌─────────────────────────────────────────────────────────┐
│                    Load Balancer                         │
│                   (Port 5672, 15672)                     │
└─────────────────────────────────────────────────────────┘
            │               │               │
    ┌───────┴───────┐ ┌─────┴─────┐ ┌───────┴───────┐
    │   Node 1      │ │  Node 2   │ │    Node 3     │
    │  (Primary)    │ │ (Member)  │ │   (Member)    │
    └───────────────┘ └───────────┘ └───────────────┘
    Inter-node: 25672 (Erlang distribution)
    Inter-node: 4369 (epmd)
```

### 8.2 DNS/Service Discovery

- DNS entries: ________________
- Service discovery mechanism: ________________
- Cluster formation method: ________________

### 8.3 TLS/SSL Configuration

```bash
# Check TLS status
rabbitmqctl environment | grep -A 20 ssl
```

- TLS enabled: Yes/No
- Certificate expiry: ________________
- Protocol versions: ________________

---

## 9. Backup Assessment

### 9.1 Current Backup Strategy

| Backup Type | Frequency | Retention | Location |
|-------------|-----------|-----------|----------|
| Definition export | | | |
| Message backup | | | |
| Configuration files | | | |
| Mnesia directory | | | |

### 9.2 Recovery Testing

- Last recovery test date: ________________
- Recovery time: ________________
- Data integrity verified: Yes/No

---

## 10. Assessment Summary

### Readiness Score

| Category | Score (1-5) | Notes |
|----------|-------------|-------|
| Cluster Health | | |
| Queue Compatibility | | |
| Application Readiness | | |
| Backup Strategy | | |
| Team Preparedness | | |
| **Overall Readiness** | | |

### Identified Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| | High/Medium/Low | |

### Go/No-Go Decision

- [ ] Assessment complete
- [ ] All blocking issues resolved
- [ ] Stakeholder sign-off obtained
- [ ] Migration window scheduled

---

**Next Step**: [02-architecture-considerations.md](./02-architecture-considerations.md)
