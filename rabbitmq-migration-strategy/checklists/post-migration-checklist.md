# Post-Migration Checklist

## Immediate (Day 1)

### Cluster Validation
- [ ] All 3 nodes running: `rabbitmqctl cluster_status`
- [ ] RabbitMQ version confirmed: `rabbitmqctl version` = 4.1.4
- [ ] Erlang version confirmed: 26.x
- [ ] No alarms: `rabbitmq-diagnostics check_local_alarms`

### Queue Validation
- [ ] All expected queues present
- [ ] Quorum queues have 3 members each
- [ ] Queue depths within normal range
- [ ] No messages stuck in queues

### Connection Validation
- [ ] All applications connected
- [ ] Connection count matches baseline: ____ (baseline) vs ____ (current)
- [ ] No excessive connection churn
- [ ] TLS connections working (if applicable)

### Message Flow Validation
- [ ] Publish rate within baseline
- [ ] Consume rate within baseline
- [ ] No message delays
- [ ] Dead letter queues checked

---

## Day 2-3

### Performance Validation
- [ ] Latency within acceptable range
- [ ] Throughput matches or exceeds baseline
- [ ] Resource utilization stable:
  - CPU: ___% (target < 70%)
  - Memory: ___% (target < 80%)
  - Disk: ___% (target < 60%)

### Quorum Queue Health
- [ ] Leader distribution balanced across nodes
- [ ] Raft term changes minimal
- [ ] Commit latency acceptable (< 100ms)
- [ ] No excessive log growth

### Application Health
- [ ] All application health checks passing
- [ ] Error rates at baseline
- [ ] No customer-reported issues
- [ ] Retry rates normal

---

## Week 1

### Monitoring Validation
- [ ] All Prometheus metrics collecting
- [ ] Grafana dashboards accurate
- [ ] Alerts tested and working
- [ ] Log aggregation functional

### Cleanup Initiated
- [ ] Migration Shovels removed
- [ ] Temporary queues removed
- [ ] Test data cleaned up
- [ ] Blue cluster monitoring stopped

### Documentation
- [ ] Architecture docs updated
- [ ] Runbooks updated
- [ ] Connection strings documented
- [ ] Team notified of new procedures

---

## Week 2

### Blue Cluster Decommission
- [ ] Final backup of blue cluster created
- [ ] Blue cluster stopped
- [ ] DNS entries removed/updated
- [ ] Infrastructure resources released

### Final Validation
- [ ] 7 days without critical issues
- [ ] Performance baseline achieved
- [ ] All stakeholders satisfied
- [ ] No pending issues

### Documentation Complete
- [ ] Migration report finalized
- [ ] Lessons learned documented
- [ ] Training materials updated
- [ ] Change record closed

---

## Validation Metrics

| Metric | Baseline | Current | Status |
|--------|----------|---------|--------|
| Connections | | | ✓/✗ |
| Publish Rate | | | ✓/✗ |
| Consume Rate | | | ✓/✗ |
| Avg Latency | | | ✓/✗ |
| Error Rate | | | ✓/✗ |
| CPU Usage | | | ✓/✗ |
| Memory Usage | | | ✓/✗ |

---

## Sign-Off

### Day 1 Validation
| Role | Name | Date | Signature |
|------|------|------|-----------|
| Migration Lead | | | |
| Operations | | | |

### Week 1 Validation
| Role | Name | Date | Signature |
|------|------|------|-----------|
| Migration Lead | | | |
| Application Lead | | | |

### Final Sign-Off
| Role | Name | Date | Signature |
|------|------|------|-----------|
| Migration Lead | | | |
| Operations Lead | | | |
| Business Owner | | | |

**Migration Status:** [ ] Complete [ ] Issues Pending
