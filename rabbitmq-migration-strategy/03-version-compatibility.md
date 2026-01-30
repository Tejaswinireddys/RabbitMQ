# 03. Version Compatibility Matrix

## Overview

This document details version compatibility requirements for migrating from RabbitMQ 3.12 to 4.1.4.

---

## 1. RabbitMQ Version Upgrade Path

### 1.1 Supported Upgrade Path

```
┌─────────────────────────────────────────────────────────┐
│                    UPGRADE PATH                          │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  3.12.x ──► 3.13.x ──► 4.0.x ──► 4.1.4                  │
│     │                                                    │
│     └──────► DIRECT UPGRADE NOT SUPPORTED ──────►       │
│                                                          │
│  RECOMMENDED PATH:                                       │
│  3.12.x → 3.13.x (enable feature flags) → 4.1.4        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Version Compatibility Rules

| From Version | To Version | Direct Upgrade | Notes |
|-------------|------------|----------------|-------|
| 3.12.x | 3.12.y | ✅ Yes | Minor version upgrade |
| 3.12.x | 3.13.x | ✅ Yes | Enable feature flags first |
| 3.12.x | 4.0.x | ⚠️ Via 3.13 | Need intermediate step |
| 3.13.x | 4.0.x | ✅ Yes | Enable all feature flags |
| 3.13.x | 4.1.x | ✅ Yes | Enable all feature flags |
| 4.0.x | 4.1.x | ✅ Yes | Minor version upgrade |

### 1.3 Critical Upgrade Requirements

```bash
# BEFORE upgrading to 4.x, you MUST:

# 1. Ensure all feature flags from 3.12 are enabled
rabbitmqctl enable_feature_flag all

# 2. Verify feature flag status
rabbitmqctl list_feature_flags

# 3. Check that no deprecated features are in use
rabbitmq-diagnostics check_if_node_is_quorum_critical

# 4. Remove classic mirrored queue policies (deprecated in 4.x)
rabbitmqctl list_policies
```

---

## 2. Erlang/OTP Compatibility

### 2.1 Erlang Version Requirements

| RabbitMQ Version | Minimum Erlang | Maximum Erlang | Recommended |
|-----------------|----------------|----------------|-------------|
| 3.12.x | 25.0 | 26.x | 26.2 |
| 3.13.x | 26.0 | 26.x | 26.2 |
| 4.0.x | 26.2 | 27.x | 26.2 or 27.1 |
| 4.1.x | 26.2 | 27.x | 27.1 |

### 2.2 Erlang Upgrade Considerations

```
ERLANG UPGRADE PATH:

Current: Erlang 25.x (with RabbitMQ 3.12)
    │
    ▼
Step 1: Upgrade to Erlang 26.2 (compatible with 3.12, 3.13, 4.x)
    │
    ▼
Step 2: Upgrade RabbitMQ 3.12 → 3.13 (if needed)
    │
    ▼
Step 3: Upgrade RabbitMQ 3.13 → 4.1.4
    │
    ▼
Optional: Upgrade to Erlang 27.x (post-migration)
```

### 2.3 Erlang Feature Compatibility

| Erlang Feature | 25.x | 26.x | 27.x | RabbitMQ Usage |
|---------------|------|------|------|----------------|
| JIT Compiler | ✅ | ✅ | ✅ | Performance |
| Socket API | v1 | v1 | v2 | Network I/O |
| Process Flags | Legacy | Enhanced | Enhanced | Quorum queues |
| ETS Tables | Standard | Optimized | Optimized | Metadata |

---

## 3. Operating System Compatibility

### 3.1 Supported Operating Systems

| OS | Version | RabbitMQ 3.12 | RabbitMQ 4.1.4 |
|----|---------|---------------|----------------|
| Ubuntu | 20.04 LTS | ✅ | ✅ |
| Ubuntu | 22.04 LTS | ✅ | ✅ |
| Ubuntu | 24.04 LTS | ⚠️ | ✅ |
| Debian | 11 (Bullseye) | ✅ | ✅ |
| Debian | 12 (Bookworm) | ✅ | ✅ |
| RHEL/CentOS | 8.x | ✅ | ✅ |
| RHEL/Rocky | 9.x | ✅ | ✅ |
| Amazon Linux | 2023 | ✅ | ✅ |
| Windows Server | 2019/2022 | ✅ | ✅ |

### 3.2 Container Compatibility

| Platform | RabbitMQ 3.12 | RabbitMQ 4.1.4 | Image Tag |
|----------|---------------|----------------|-----------|
| Docker | ✅ | ✅ | `rabbitmq:4.1.4-management` |
| Kubernetes | ✅ | ✅ | Operator 2.x+ |
| OpenShift | ✅ | ✅ | Certified operator |
| ECS/Fargate | ✅ | ✅ | Custom task definition |

---

## 4. Client Library Compatibility

### 4.1 Official Client Libraries

| Language | Library | Min Version for 4.x | Current Stable | Notes |
|----------|---------|---------------------|----------------|-------|
| Java | amqp-client | 5.18.0 | 5.22.0 | |
| Java | Spring AMQP | 3.0.0 | 3.2.0 | |
| Python | pika | 1.3.0 | 1.3.2 | |
| Python | aio-pika | 9.0.0 | 9.5.0 | Async support |
| Python | kombu | 5.3.0 | 5.4.0 | Celery compatible |
| Node.js | amqplib | 0.10.0 | 0.10.4 | |
| .NET | RabbitMQ.Client | 6.5.0 | 7.0.0 | Major version bump |
| Go | amqp091-go | 1.9.0 | 1.10.0 | |
| Ruby | bunny | 2.22.0 | 2.23.0 | |
| PHP | php-amqplib | 3.5.0 | 3.7.0 | |
| Rust | lapin | 2.3.0 | 2.5.0 | |

### 4.2 Client Connection Changes in 4.x

```
CLIENT COMPATIBILITY NOTES:

1. AMQP 0-9-1 Protocol
   └── Fully compatible, no changes required

2. AMQP 1.0 Protocol
   └── Enhanced support in 4.x
   └── Check client library AMQP 1.0 support

3. Connection Properties
   └── New capabilities in 4.x
   └── Older clients work but miss new features

4. Heartbeat
   └── Default changed from 60s to 60s (no change)
   └── Verify client heartbeat settings

5. Channel Max
   └── Default: 2047 (unchanged)
   └── Verify client doesn't exceed
```

### 4.3 Breaking Changes for Clients

| Change | Impact | Mitigation |
|--------|--------|------------|
| Classic mirrored queues deprecated | High | Migrate to quorum queues |
| Default queue type change | Medium | Explicitly declare queue type |
| New error codes | Low | Update error handling |
| Management API changes | Low | Update API clients |

---

## 5. Plugin Compatibility

### 5.1 Core Plugins

| Plugin | RabbitMQ 3.12 | RabbitMQ 4.1.4 | Action |
|--------|---------------|----------------|--------|
| rabbitmq_management | ✅ Built-in | ✅ Built-in | None |
| rabbitmq_management_agent | ✅ Built-in | ✅ Built-in | None |
| rabbitmq_prometheus | ✅ Built-in | ✅ Built-in | Update dashboards |
| rabbitmq_shovel | ✅ | ✅ | Verify config |
| rabbitmq_shovel_management | ✅ | ✅ | None |
| rabbitmq_federation | ✅ | ✅ | Verify config |
| rabbitmq_federation_management | ✅ | ✅ | None |

### 5.2 Protocol Plugins

| Plugin | RabbitMQ 3.12 | RabbitMQ 4.1.4 | Notes |
|--------|---------------|----------------|-------|
| rabbitmq_mqtt | ✅ | ✅ | Enhanced in 4.x |
| rabbitmq_stomp | ✅ | ✅ | Compatible |
| rabbitmq_web_mqtt | ✅ | ✅ | Compatible |
| rabbitmq_web_stomp | ✅ | ✅ | Compatible |
| rabbitmq_stream | ✅ | ✅ | Enhanced in 4.x |
| rabbitmq_amqp1_0 | ✅ | ✅ (Native) | Now core feature |

### 5.3 Community/Third-Party Plugins

| Plugin | Compatibility | Action Required |
|--------|--------------|-----------------|
| rabbitmq_delayed_message_exchange | ⚠️ Check version | Upgrade to 4.x compatible |
| rabbitmq_message_timestamp | ⚠️ Check version | May need update |
| rabbitmq_consistent_hash_exchange | ✅ | Built into core |
| rabbitmq_sharding | ⚠️ Deprecated | Migrate to streams |

---

## 6. Feature Flag Compatibility

### 6.1 Feature Flags from 3.12

```bash
# Feature flags that MUST be enabled before 4.x upgrade:

# Required for 4.x
quorum_queue                          # REQUIRED
implicit_default_bindings             # REQUIRED
virtual_host_metadata                 # REQUIRED
maintenance_mode_status               # REQUIRED
user_limits                           # REQUIRED
feature_flags_v2                      # REQUIRED
stream_queue                          # REQUIRED
stream_sac_coordinator_unblock_group  # REQUIRED
stream_filtering                      # REQUIRED
direct_exchange_routing_v2            # REQUIRED
message_containers                    # New in 3.13
```

### 6.2 New Feature Flags in 4.x

| Feature Flag | Description | Default |
|-------------|-------------|---------|
| khepri_db | New metadata store | Disabled initially |
| message_containers_deaths_v2 | Enhanced dead lettering | Enabled |
| quorum_queue_non_voters | Non-voting replicas | Available |
| stream_update_config | Stream config updates | Enabled |

### 6.3 Feature Flag Migration Script

```bash
#!/bin/bash
# enable-feature-flags.sh

echo "Enabling all required feature flags for 4.x upgrade..."

# Enable all stable feature flags
rabbitmqctl enable_feature_flag all

# Verify all flags enabled
echo "Verifying feature flags..."
rabbitmqctl list_feature_flags name state | grep -v enabled

if [ $? -eq 0 ]; then
    echo "WARNING: Some feature flags are not enabled!"
    exit 1
fi

echo "All feature flags enabled successfully"
```

---

## 7. Protocol Compatibility

### 7.1 AMQP Protocol Versions

| Protocol | RabbitMQ 3.12 | RabbitMQ 4.1.4 |
|----------|---------------|----------------|
| AMQP 0-9-1 | ✅ Primary | ✅ Primary |
| AMQP 1.0 | ✅ Plugin | ✅ Native |
| MQTT 3.1.1 | ✅ Plugin | ✅ Plugin |
| MQTT 5.0 | ✅ Plugin | ✅ Enhanced |
| STOMP 1.2 | ✅ Plugin | ✅ Plugin |

### 7.2 Wire Protocol Changes

```
AMQP 0-9-1 CHANGES IN 4.x:

1. Queue Declare
   └── New argument: x-queue-type (default may change)

2. Basic.Publish
   └── Quorum queue behavior for confirms

3. Basic.Consume
   └── Single active consumer improvements

4. Connection.Open
   └── New capabilities field values
```

---

## 8. Configuration Compatibility

### 8.1 Deprecated Configuration

| Configuration | Status in 4.x | Migration |
|--------------|---------------|-----------|
| `ha-mode` | Removed | Use quorum queues |
| `ha-params` | Removed | Use quorum queues |
| `ha-sync-mode` | Removed | Use quorum queues |
| `ha-promote-on-shutdown` | Removed | Automatic in quorum |
| `classic_queue.default_version` | Changed | Now 2 (CQv2) |

### 8.2 New Configuration Options

```erlang
%% New in RabbitMQ 4.x

# Default queue type
default_queue_type = quorum

# Quorum queue settings
quorum_queue.default_target_replica_count = 3
quorum_queue.compute_checksums = true

# Khepri settings (metadata store)
khepri.default_timeout = 30000

# Stream settings
stream.replication_factor = 3
```

### 8.3 Configuration Migration

```bash
# Export current config
rabbitmqctl environment > current_config.txt

# Key configs to review:
grep -E "(ha-mode|ha-params|ha-sync)" /etc/rabbitmq/rabbitmq.conf

# Remove deprecated HA settings
# Add quorum queue defaults
```

---

## 9. API Compatibility

### 9.1 Management API Changes

| Endpoint | Change in 4.x | Action |
|----------|---------------|--------|
| `/api/queues` | New fields for quorum | Update parsers |
| `/api/health` | New endpoints | Update health checks |
| `/api/definitions` | Compatible | None |
| `/api/nodes` | New metrics | Update dashboards |
| `/api/cluster-name` | Compatible | None |

### 9.2 CLI Command Changes

| Command | Status | Replacement |
|---------|--------|-------------|
| `rabbitmqctl sync_queue` | Deprecated | Not needed for quorum |
| `rabbitmqctl cancel_sync_queue` | Deprecated | Not needed |
| `rabbitmqctl set_policy ha-*` | Deprecated | Use quorum policies |
| `rabbitmqctl list_feature_flags` | Enhanced | New flag fields |

---

## 10. Compatibility Verification Checklist

```
PRE-UPGRADE COMPATIBILITY CHECK:

[ ] Erlang version compatible (26.2+)
[ ] OS version supported
[ ] All feature flags enabled
[ ] Client libraries updated
[ ] Plugins compatible
[ ] No deprecated HA policies
[ ] Configuration reviewed
[ ] API consumers updated
[ ] Monitoring dashboards updated
[ ] Backup strategy verified
```

---

**Next Step**: [04-migration-strategies.md](./04-migration-strategies.md)
