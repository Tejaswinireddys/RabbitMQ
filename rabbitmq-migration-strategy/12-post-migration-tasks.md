# 12. Post-Migration Tasks

## Overview

This document outlines the tasks required after completing the RabbitMQ migration from 3.12 to 4.1.4.

---

## 1. Immediate Post-Migration (Day 1)

### 1.1 Verification Checklist

```bash
#!/bin/bash
# post-migration-verify.sh

echo "=== Post-Migration Verification ==="
echo "Date: $(date)"

# 1. Cluster health
echo "1. Checking cluster health..."
rabbitmqctl cluster_status

# 2. All nodes running
echo "2. Verifying all nodes..."
NODES=$(rabbitmqctl cluster_status | grep -c "running_nodes")
if [ "$NODES" -eq 3 ]; then
    echo "   ✓ All 3 nodes running"
else
    echo "   ✗ Expected 3 nodes, found $NODES"
fi

# 3. Quorum queue status
echo "3. Checking quorum queues..."
rabbitmqctl list_queues name type | grep quorum | head -10

# 4. Connection count
echo "4. Checking connections..."
CONNS=$(rabbitmqctl list_connections | wc -l)
echo "   Active connections: $CONNS"

# 5. Message rates
echo "5. Checking message rates..."
rabbitmqctl list_queues name \
    message_stats.publish_details.rate \
    message_stats.deliver_get_details.rate \
    2>/dev/null | head -10

# 6. No alarms
echo "6. Checking for alarms..."
rabbitmq-diagnostics check_local_alarms

# 7. Feature flags
echo "7. Checking feature flags..."
rabbitmqctl list_feature_flags name state | grep -v enabled || echo "   ✓ All feature flags enabled"

echo ""
echo "=== Verification Complete ==="
```

### 1.2 Performance Baseline Comparison

```bash
#!/bin/bash
# compare-performance.sh

echo "=== Performance Comparison ==="

# Load pre-migration baseline
BASELINE_DIR="/metrics/baseline_latest"

echo "Metric | Baseline | Current | Difference"
echo "-------|----------|---------|----------"

# Connections
BASELINE_CONN=$(cat $BASELINE_DIR/connections.txt)
CURRENT_CONN=$(rabbitmqctl list_connections | wc -l)
DIFF_CONN=$((CURRENT_CONN - BASELINE_CONN))
echo "Connections | $BASELINE_CONN | $CURRENT_CONN | $DIFF_CONN"

# Publish rate (from Prometheus)
BASELINE_PUB=$(curl -s "http://prometheus:9090/api/v1/query?query=rabbitmq:messages_published:rate5m{cluster='blue'}" | jq -r '.data.result[0].value[1]')
CURRENT_PUB=$(curl -s "http://prometheus:9090/api/v1/query?query=rabbitmq:messages_published:rate5m{cluster='green'}" | jq -r '.data.result[0].value[1]')
echo "Publish/s | $BASELINE_PUB | $CURRENT_PUB | -"

# Queue depths
rabbitmqctl list_queues name messages | head -20
```

### 1.3 Alert Validation

```bash
# Verify alerts are working
echo "Testing alert pipeline..."

# Trigger test alert (if configured)
curl -X POST http://alertmanager:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d '[{
        "labels": {"alertname": "TestAlert", "severity": "info"},
        "annotations": {"summary": "Post-migration test alert"}
    }]'

# Check Prometheus targets
curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("rabbitmq"))'
```

---

## 2. Stabilization Period (Days 2-7)

### 2.1 Daily Monitoring Checklist

```markdown
## Daily Post-Migration Checklist

### Cluster Health
- [ ] All nodes running
- [ ] No alarms active
- [ ] Disk space > 50%
- [ ] Memory < 80%

### Message Flow
- [ ] Publish rate within baseline
- [ ] Consume rate within baseline
- [ ] Queue depths stable
- [ ] No growing backlogs

### Application Health
- [ ] All applications connected
- [ ] No connection churn
- [ ] Error rates normal
- [ ] Latency acceptable

### Quorum Queues
- [ ] Leader distribution balanced
- [ ] No excessive elections
- [ ] Raft commit lag normal
- [ ] Snapshot frequency normal
```

### 2.2 Leader Rebalancing

```bash
# Check leader distribution
echo "Current leader distribution:"
rabbitmqctl list_queues name type leader | grep quorum | \
    awk '{print $3}' | sort | uniq -c

# Rebalance if needed
echo "Rebalancing queue leaders..."
rabbitmq-queues rebalance all

# Verify new distribution
echo "New leader distribution:"
rabbitmqctl list_queues name type leader | grep quorum | \
    awk '{print $3}' | sort | uniq -c
```

### 2.3 Performance Tuning

```bash
# Tune quorum queue settings based on observation
# /etc/rabbitmq/advanced.config

[
  {rabbit, [
    % Quorum queue settings
    {quorum_tick_interval, 5000},
    {quorum_commands_soft_limit, 256}
  ]},

  {ra, [
    % Raft settings
    {wal_max_size_bytes, 536870912},  % 512MB
    {wal_max_batch_size, 4096},
    {segment_max_entries, 32768}
  ]}
].
```

---

## 3. Cleanup Tasks (Week 2)

### 3.1 Remove Migration Infrastructure

```bash
#!/bin/bash
# cleanup-migration.sh

echo "=== Migration Cleanup ==="

# 1. Remove all Shovels
echo "1. Removing Shovels..."
rabbitmqctl list_parameters shovel | while read vhost name _; do
    if [[ $name == migrate-* ]] || [[ $name == reverse-* ]]; then
        echo "   Removing $name"
        rabbitmqctl clear_parameter shovel "$name"
    fi
done

# 2. Remove migration-specific policies
echo "2. Removing temporary policies..."
rabbitmqctl list_policies | while read vhost name _; do
    if [[ $name == *-migration* ]] || [[ $name == *-temp* ]]; then
        echo "   Removing policy $name"
        rabbitmqctl clear_policy -p "$vhost" "$name"
    fi
done

# 3. Clean up test queues
echo "3. Removing test queues..."
rabbitmqctl list_queues name | grep -E "^test-|^perf-|^migration-test" | \
while read queue; do
    echo "   Deleting $queue"
    rabbitmqadmin delete queue name="$queue"
done

echo "Cleanup complete"
```

### 3.2 Decommission Blue Cluster

```bash
#!/bin/bash
# decommission-blue.sh

# CAUTION: Only run after validation period complete!

echo "=== Blue Cluster Decommission ==="
echo "This will permanently shut down the blue cluster"
read -p "Are you sure? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted"
    exit 1
fi

# 1. Final backup
echo "1. Creating final backup..."
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "rabbitmqadmin export /backup/final-definitions-$node.json"
    ssh $node "tar -czvf /backup/final-mnesia-$node.tar.gz /var/lib/rabbitmq/mnesia"
done

# 2. Stop RabbitMQ
echo "2. Stopping RabbitMQ on blue nodes..."
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "systemctl stop rabbitmq-server"
    ssh $node "systemctl disable rabbitmq-server"
done

# 3. Update DNS (remove blue entries)
echo "3. DNS updates required (manual step)"
echo "   Remove: rabbit-blue-1, rabbit-blue-2, rabbit-blue-3"
echo "   Update: rabbitmq.example.com → green cluster only"

# 4. Update monitoring
echo "4. Remove blue cluster from monitoring..."
# (Update Prometheus config, Grafana dashboards)

# 5. Archive logs
echo "5. Archiving logs..."
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "tar -czvf /backup/final-logs-$node.tar.gz /var/log/rabbitmq"
done

echo "Blue cluster decommissioned"
echo "Keep backups for 90 days before deletion"
```

### 3.3 Remove Deprecated Configurations

```bash
# Remove HA policies (not needed for quorum queues)
rabbitmqctl list_policies | grep -E "ha-mode|ha-sync" | \
while read vhost name _; do
    echo "Removing deprecated HA policy: $name"
    rabbitmqctl clear_policy -p "$vhost" "$name"
done

# Clean up old configuration
grep -l "ha-mode\|ha-params" /etc/rabbitmq/*.conf && \
    echo "WARNING: Old HA configuration found, please remove"
```

---

## 4. Documentation Updates

### 4.1 Architecture Documentation

```markdown
# RabbitMQ Cluster Documentation

## Current Environment

### Cluster Information
- **Version**: RabbitMQ 4.1.4
- **Erlang/OTP**: 26.2
- **Last Updated**: [DATE]

### Nodes
| Node | Hostname | IP | Role |
|------|----------|-----|------|
| Node 1 | rabbit-green-1.example.com | 10.0.1.1 | Disc |
| Node 2 | rabbit-green-2.example.com | 10.0.1.2 | Disc |
| Node 3 | rabbit-green-3.example.com | 10.0.1.3 | Disc |

### Network Configuration
- AMQP: Port 5672
- AMQPS: Port 5671
- Management: Port 15672
- Prometheus: Port 15692

### Queue Types
| Type | Count | Usage |
|------|-------|-------|
| Quorum | X | Production queues |
| Classic | Y | RPC, temporary |
| Stream | Z | Event logs |

### Key Configurations
- Default queue type: quorum
- Quorum replication: 3 nodes
- Delivery limit: 5
- Dead letter exchange: dlx
```

### 4.2 Runbook Updates

```markdown
# Updated Runbooks for RabbitMQ 4.x

## Node Restart Procedure
1. Enable maintenance mode: `rabbitmqctl enable_maintenance_mode`
2. Wait for connections to drain
3. Stop node: `systemctl stop rabbitmq-server`
4. Start node: `systemctl start rabbitmq-server`
5. Verify join: `rabbitmqctl cluster_status`
6. Disable maintenance mode: `rabbitmqctl disable_maintenance_mode`

## Quorum Queue Leader Rebalance
1. Check current distribution: `rabbitmqctl list_queues name type leader`
2. Rebalance: `rabbitmq-queues rebalance all`
3. Verify: `rabbitmqctl list_queues name type leader`

## Adding a New Node
1. Install same RabbitMQ version
2. Copy Erlang cookie
3. Start RabbitMQ
4. Join cluster: `rabbitmqctl join_cluster rabbit@existing-node`
5. Verify: `rabbitmqctl cluster_status`
6. Grow quorum queues: `rabbitmq-queues grow rabbit@new-node all`
```

### 4.3 Training Materials

```markdown
# RabbitMQ 4.x Training Outline

## Module 1: What's New in 4.x
- Khepri metadata store
- Quorum queues as default
- Deprecated features (classic mirroring)
- New metrics and APIs

## Module 2: Quorum Queue Operations
- How quorum queues work (Raft)
- When to use quorum vs classic
- Monitoring quorum queue health
- Troubleshooting leader elections

## Module 3: New CLI Commands
- `rabbitmq-queues` commands
- `rabbitmq-streams` commands
- Feature flag management
- Health check endpoints

## Module 4: Monitoring Changes
- New Prometheus metrics
- Updated Grafana dashboards
- Alert tuning for quorum queues

## Module 5: Troubleshooting
- Common issues and resolutions
- Log analysis
- Performance tuning
```

---

## 5. Governance and Compliance

### 5.1 Change Record

```markdown
# Change Record: RabbitMQ Migration

## Change Details
- **Change ID**: CHG-2024-XXXX
- **Date**: [DATE]
- **Type**: Major Version Upgrade
- **Systems Affected**: RabbitMQ Message Broker

## Change Summary
Migration of 3-node RabbitMQ cluster from version 3.12.x to 4.1.4,
including conversion of classic queues to quorum queues.

## Technical Details
- Previous version: 3.12.x
- New version: 4.1.4
- Erlang upgraded: 25.x → 26.2
- Queue types migrated: Classic → Quorum

## Impact Assessment
- Downtime: Zero (blue-green deployment)
- Data loss: None
- Performance change: +/- 10%

## Rollback Executed: No

## Post-Implementation Review
- [ ] All success criteria met
- [ ] No unplanned incidents
- [ ] Documentation updated
- [ ] Training completed
```

### 5.2 Audit Trail

```bash
# Generate audit report
#!/bin/bash
echo "=== Migration Audit Report ===" > /audit/migration-audit.txt
echo "Generated: $(date)" >> /audit/migration-audit.txt
echo "" >> /audit/migration-audit.txt

echo "## Cluster Status" >> /audit/migration-audit.txt
rabbitmqctl cluster_status >> /audit/migration-audit.txt

echo "## Feature Flags" >> /audit/migration-audit.txt
rabbitmqctl list_feature_flags >> /audit/migration-audit.txt

echo "## Users and Permissions" >> /audit/migration-audit.txt
rabbitmqctl list_users >> /audit/migration-audit.txt
rabbitmqctl list_permissions >> /audit/migration-audit.txt

echo "## Queues" >> /audit/migration-audit.txt
rabbitmqctl list_queues name type durable >> /audit/migration-audit.txt

echo "## Policies" >> /audit/migration-audit.txt
rabbitmqctl list_policies >> /audit/migration-audit.txt
```

---

## 6. Long-Term Maintenance

### 6.1 Regular Maintenance Tasks

| Task | Frequency | Procedure |
|------|-----------|-----------|
| Health check | Daily | Automated monitoring |
| Log rotation | Daily | Logrotate configured |
| Backup definitions | Daily | Automated export |
| Disk usage review | Weekly | Monitor and clean |
| Performance review | Weekly | Dashboard review |
| Security patches | Monthly | Planned maintenance |
| Certificate renewal | Before expiry | 30-day advance |
| Capacity planning | Quarterly | Usage trend analysis |

### 6.2 Upgrade Path Planning

```markdown
# Future Upgrade Considerations

## RabbitMQ 4.x Patch Updates
- Monitor release notes
- Test in staging before production
- Rolling upgrade procedure

## Erlang Updates
- 27.x available as upgrade path
- Test compatibility before upgrade
- Same rolling upgrade procedure

## Next Major Version (5.x when available)
- Follow similar migration strategy
- Expect 6-12 month planning cycle
- Document lessons from 4.x migration
```

---

## 7. Success Metrics and Reporting

### 7.1 Migration Success Criteria

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Downtime | 0 minutes | | |
| Message loss | 0 messages | | |
| Rollback needed | No | | |
| All apps migrated | 100% | | |
| Performance impact | < 20% | | |
| Timeline adherence | On schedule | | |

### 7.2 Final Migration Report

```markdown
# RabbitMQ Migration Final Report

## Executive Summary
[Summary of migration outcome]

## Timeline
| Phase | Planned | Actual |
|-------|---------|--------|
| Assessment | Week 1 | |
| Preparation | Week 2 | |
| Migration | Week 3 | |
| Validation | Week 4 | |

## Key Achievements
1. Zero-downtime migration completed
2. All queues converted to quorum type
3. Performance maintained/improved
4. No message loss

## Challenges and Resolutions
[Document any issues encountered]

## Lessons Learned
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

## Recommendations
1. [Recommendation 1]
2. [Recommendation 2]

## Sign-off
| Role | Name | Signature | Date |
|------|------|-----------|------|
| Migration Lead | | | |
| Operations Lead | | | |
| Application Lead | | | |
| Business Owner | | | |
```

---

**Migration Strategy Documentation Complete**

Return to [README.md](./README.md) for navigation.
