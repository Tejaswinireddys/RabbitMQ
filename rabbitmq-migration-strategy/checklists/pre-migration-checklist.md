# Pre-Migration Checklist

## Overview
Complete all items before initiating migration. All items marked with ⚠️ are blocking.

---

## 1. Environment Assessment

### Cluster Health
- [ ] ⚠️ All 3 nodes running and healthy
- [ ] ⚠️ No active alarms (memory, disk)
- [ ] ⚠️ Disk space > 50% available on all nodes
- [ ] ⚠️ Memory usage < 70% on all nodes
- [ ] Network connectivity between all nodes verified

### Current Version
- [ ] RabbitMQ version documented: `3.12.___`
- [ ] Erlang version documented: `___.___.___`
- [ ] All nodes on same version

### Feature Flags
- [ ] ⚠️ All feature flags enabled: `rabbitmqctl enable_feature_flag all`
- [ ] Verified with: `rabbitmqctl list_feature_flags`
- [ ] No deprecated features in use

---

## 2. Inventory Complete

### Queues
- [ ] Queue inventory exported: `rabbitmqctl list_queues > queues.txt`
- [ ] Queue types classified (classic, quorum, stream)
- [ ] Migration eligibility determined per queue
- [ ] Queues to remain classic documented

### Exchanges and Bindings
- [ ] Exchanges documented
- [ ] Bindings documented
- [ ] Custom exchange types identified

### Users and Permissions
- [ ] Users exported: `rabbitmqctl list_users > users.txt`
- [ ] Permissions documented
- [ ] Service accounts identified

### Policies
- [ ] All policies documented
- [ ] ⚠️ HA policies identified for removal/conversion
- [ ] Quorum queue policies prepared

### Plugins
- [ ] Enabled plugins listed
- [ ] Plugin compatibility with 4.x verified
- [ ] Community plugin updates obtained

---

## 3. Backup Verified

### Definition Backup
- [ ] ⚠️ Full definitions exported: `rabbitmqadmin export definitions.json`
- [ ] Backup file verified (valid JSON)
- [ ] Backup stored in secure location
- [ ] Backup tested with import (on test environment)

### Data Backup
- [ ] Mnesia directory backed up (if needed)
- [ ] Configuration files backed up
- [ ] Erlang cookie backed up

### Recovery Test
- [ ] Recovery procedure documented
- [ ] Recovery tested on non-production

---

## 4. Application Readiness

### Client Libraries
- [ ] All applications' client libraries identified
- [ ] ⚠️ Compatible versions confirmed for all clients
- [ ] Upgrade plan for each application documented

### Connection Configuration
- [ ] Applications can reach new cluster network
- [ ] DNS/service discovery updated (if applicable)
- [ ] Connection retry logic verified

### Code Changes
- [ ] Quorum queue declarations reviewed
- [ ] Publisher confirms enabled
- [ ] Consumer acknowledgment handling verified

---

## 5. Infrastructure Ready

### Green Cluster
- [ ] ⚠️ 3-node green cluster provisioned
- [ ] Network connectivity established
- [ ] Same network access as blue cluster
- [ ] Firewall rules configured

### Resources
- [ ] ⚠️ CPU: Minimum 4 cores per node
- [ ] ⚠️ RAM: Minimum 8 GB per node
- [ ] ⚠️ Disk: 3x current usage, SSD preferred
- [ ] Network: 1 Gbps minimum

### Software
- [ ] ⚠️ Erlang 26.2 installed on green nodes
- [ ] ⚠️ RabbitMQ 4.1.4 installed on green nodes
- [ ] Required plugins enabled
- [ ] Configuration files prepared

---

## 6. Monitoring Ready

### Metrics
- [ ] Prometheus configured to scrape green cluster
- [ ] Grafana dashboards updated/created
- [ ] Key metrics identified for migration

### Alerting
- [ ] ⚠️ Migration-specific alerts configured
- [ ] Escalation paths documented
- [ ] On-call team notified

### Logging
- [ ] Log aggregation configured
- [ ] Log retention adequate
- [ ] Key log patterns identified

---

## 7. Runbooks and Documentation

### Procedures
- [ ] ⚠️ Step-by-step migration procedure documented
- [ ] ⚠️ Rollback procedure documented and tested
- [ ] Emergency contacts documented

### Communication
- [ ] Stakeholders identified
- [ ] Communication plan prepared
- [ ] Maintenance window announced

---

## 8. Team Readiness

### Training
- [ ] Team trained on RabbitMQ 4.x changes
- [ ] Team trained on quorum queues
- [ ] Runbooks reviewed by team

### Availability
- [ ] ⚠️ Migration lead available for entire window
- [ ] DBA/Platform engineer available
- [ ] Application team contacts available
- [ ] Escalation chain available

---

## 9. Final Checks

### Go/No-Go Meeting
- [ ] All checklist items completed
- [ ] All blocking items (⚠️) resolved
- [ ] Stakeholder sign-off obtained
- [ ] Migration window confirmed

### Day-Before
- [ ] Cluster health rechecked
- [ ] Fresh backup taken
- [ ] Green cluster verified operational
- [ ] Team reminded of schedule

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Migration Lead | | | |
| DBA Lead | | | |
| Operations Lead | | | |
| Security Lead | | | |

**Migration Approved:** [ ] Yes [ ] No

**Scheduled Start Time:** _______________
