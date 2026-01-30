# Migration Day Checklist

## Pre-Flight (T-2 Hours)

### Team Assembly
- [ ] Migration lead on standby
- [ ] DBA/Platform team on standby
- [ ] Application team contacts verified
- [ ] War room/communication channel established

### System Check
- [ ] Blue cluster healthy: `rabbitmqctl cluster_status`
- [ ] No active alarms: `rabbitmq-diagnostics check_local_alarms`
- [ ] Current connection count noted: ____
- [ ] Current message rates noted: ____

### Green Cluster Ready
- [ ] Green cluster healthy
- [ ] Definitions imported
- [ ] Quorum queues created
- [ ] Test message flow verified

---

## Phase 1: Shovel Configuration (T-0)

### Start Time: ___________

- [ ] Announce migration start to stakeholders
- [ ] Enable Shovels for each queue:
  ```bash
  ./scripts/setup-shovels.sh
  ```
- [ ] Verify Shovel status: `rabbitmqctl shovel_status`
- [ ] Monitor message flow to green cluster
- [ ] Document Shovel status:
  | Queue | Shovel Status | Messages/sec |
  |-------|---------------|--------------|
  | | | |

### Checkpoint 1
- [ ] All Shovels running
- [ ] Messages flowing to green
- [ ] No errors in logs
- [ ] **Proceed / Pause / Rollback**

---

## Phase 2: Non-Critical Applications (T+30min)

### Application Migrations
| Application | Status | Connections | Verified |
|-------------|--------|-------------|----------|
| logging-svc | | | [ ] |
| analytics-svc | | | [ ] |
| batch-processor | | | [ ] |

### Steps per Application
- [ ] Update configuration to green cluster
- [ ] Deploy/restart application
- [ ] Verify connections on green
- [ ] Verify message flow
- [ ] Check error rates

### Checkpoint 2
- [ ] Non-critical apps migrated
- [ ] No connection issues
- [ ] Message flow normal
- [ ] **Proceed / Pause / Rollback**

---

## Phase 3: Critical Applications (T+2h)

### Pre-Migration Checks
- [ ] Shovel queues drained or low
- [ ] Green cluster stable
- [ ] Performance acceptable

### Application Migrations
| Application | Status | Connections | Verified |
|-------------|--------|-------------|----------|
| order-svc | | | [ ] |
| payment-svc | | | [ ] |
| notification-svc | | | [ ] |

### Steps per Application
- [ ] Announce brief pause (if needed)
- [ ] Update configuration
- [ ] Deploy/restart
- [ ] Verify connections
- [ ] Verify message processing
- [ ] Monitor for 15 minutes

### Checkpoint 3
- [ ] Critical apps migrated
- [ ] All message flows working
- [ ] Performance acceptable
- [ ] **Proceed / Pause / Rollback**

---

## Phase 4: Traffic Cutover (T+4h)

### Pre-Cutover Checks
- [ ] All applications on green cluster
- [ ] Blue cluster queue depths near zero
- [ ] No pending Shovel messages

### Load Balancer Switch
- [ ] Record current LB configuration
- [ ] Switch AMQP endpoints to green
- [ ] Switch Management endpoints to green
- [ ] Verify health checks passing

### Post-Cutover Validation
- [ ] All connections on green: `rabbitmqctl list_connections`
- [ ] No connections on blue
- [ ] Message rates normal
- [ ] Queue depths normal

### Checkpoint 4
- [ ] Traffic fully on green
- [ ] No issues for 30 minutes
- [ ] **Complete / Monitor / Rollback**

---

## Phase 5: Stabilization (T+5h)

### Monitoring
- [ ] Connection count stable
- [ ] Message rates stable
- [ ] Queue depths stable
- [ ] No error rate increase
- [ ] CPU/Memory/Disk normal

### Validation Tests
- [ ] End-to-end test: orders
- [ ] End-to-end test: payments
- [ ] End-to-end test: notifications

### Final Checks
- [ ] All Shovels can be disabled
- [ ] Blue cluster can be stopped
- [ ] No rollback needed

---

## Completion

### Documentation
- [ ] Timeline recorded
- [ ] Issues documented
- [ ] Final metrics captured

### Communication
- [ ] Success announced to stakeholders
- [ ] Post-migration monitoring schedule set
- [ ] Decommission date set for blue cluster

### Sign-Off
| Milestone | Time | Verified By |
|-----------|------|-------------|
| Migration Start | | |
| Shovels Active | | |
| Non-Critical Complete | | |
| Critical Complete | | |
| Cutover Complete | | |
| Migration Complete | | |

---

## Rollback Triggers

**Initiate rollback if:**
- [ ] Data loss detected
- [ ] Cluster unresponsive > 5 minutes
- [ ] Performance degradation > 50%
- [ ] Multiple application failures
- [ ] Message processing stopped

**Rollback Command:**
```bash
./runbooks/emergency-rollback-runbook.md
```
