# Emergency Rollback Runbook

## Purpose
Immediate rollback procedure when critical issues occur during migration.

---

## ⚠️ EMERGENCY ROLLBACK TRIGGERS

Initiate immediately if ANY of these occur:
- Complete cluster unavailability
- Confirmed data/message loss
- Critical application failures
- Performance degradation > 50%
- Message processing stopped

---

## Quick Reference

```bash
# IMMEDIATE ACTIONS (copy-paste ready)

# 1. Switch load balancer to blue cluster
#    [MANUAL: Update LB backend to blue cluster nodes]

# 2. Stop all Shovels
rabbitmqctl list_parameters shovel | awk '{print $2}' | \
    xargs -I {} rabbitmqctl clear_parameter shovel {}

# 3. Verify blue cluster
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status
```

---

## Detailed Rollback Procedure

### Step 1: Declare Emergency

```bash
# Record start time
echo "ROLLBACK INITIATED: $(date)" >> /var/log/rabbitmq/rollback.log

# Notify team immediately
# [Send alert to Slack/PagerDuty/etc.]
```

### Step 2: Switch Traffic to Blue Cluster

**Option A: Load Balancer (Fastest)**
```bash
# AWS ALB example
aws elbv2 modify-listener \
    --listener-arn $LISTENER_ARN \
    --default-actions Type=forward,TargetGroupArn=$BLUE_TARGET_GROUP

# HAProxy example - update config and reload
# sed -i 's/rabbit-green/rabbit-blue/g' /etc/haproxy/haproxy.cfg
# systemctl reload haproxy
```

**Option B: DNS (If no LB)**
```bash
# Update DNS to point to blue cluster
# [Manual DNS update required]
# Note: DNS TTL propagation delay expected
```

### Step 3: Verify Blue Cluster Operational

```bash
# Check blue cluster status
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    echo "=== $node ==="
    ssh $node "rabbitmqctl cluster_status" 2>&1 | head -5
done

# If blue cluster is down, start it
for node in rabbit-blue-1 rabbit-blue-2 rabbit-blue-3; do
    ssh $node "sudo systemctl start rabbitmq-server"
done

# Wait for cluster to form
sleep 30

# Verify cluster
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status
```

### Step 4: Stop All Shovels

```bash
# On blue cluster - remove migration Shovels
rabbitmqctl list_parameters shovel | while read vhost name value; do
    if [[ $name == migrate-* ]]; then
        echo "Removing Shovel: $name"
        rabbitmqctl clear_parameter shovel "$name"
    fi
done

# Verify no Shovels active
rabbitmqctl shovel_status
```

### Step 5: Recover Messages from Green (If Needed)

```bash
# Check if messages accumulated on green
GREEN_MESSAGES=$(rabbitmqctl -n rabbit@rabbit-green-1 list_queues messages --quiet | \
    awk '{sum+=$1} END {print sum}')

if [ "$GREEN_MESSAGES" -gt 0 ]; then
    echo "Messages on green cluster: $GREEN_MESSAGES"
    echo "Setting up reverse Shovels..."

    # Get list of queues with messages
    rabbitmqctl -n rabbit@rabbit-green-1 list_queues name messages --quiet | \
    while read queue count; do
        if [ "$count" -gt 0 ]; then
            echo "Reversing queue $queue ($count messages)"
            rabbitmqctl set_parameter shovel "reverse-$queue" "{
                \"src-uri\": \"amqp://rabbit-green-1\",
                \"src-queue\": \"$queue\",
                \"dest-uri\": \"amqp://rabbit-blue-1\",
                \"dest-queue\": \"$queue\",
                \"ack-mode\": \"on-confirm\"
            }"
        fi
    done
fi
```

### Step 6: Update Applications (If Needed)

```bash
# If applications were reconfigured for green, update them
# This is application-specific

# Kubernetes example
# kubectl set env deployment/app-name RABBITMQ_HOST=rabbit-blue.example.com
# kubectl rollout restart deployment/app-name
```

### Step 7: Verify Rollback Success

```bash
echo "=== ROLLBACK VERIFICATION ==="

# Check connections on blue
BLUE_CONN=$(rabbitmqctl -n rabbit@rabbit-blue-1 list_connections | wc -l)
echo "Blue cluster connections: $BLUE_CONN"

# Check message flow
rabbitmqctl -n rabbit@rabbit-blue-1 list_queues name messages consumers | head -20

# Check for errors
rabbitmqctl -n rabbit@rabbit-blue-1 status | grep -i error
```

### Step 8: Document and Notify

```bash
# Record rollback completion
echo "ROLLBACK COMPLETED: $(date)" >> /var/log/rabbitmq/rollback.log

# Capture state
rabbitmqctl -n rabbit@rabbit-blue-1 cluster_status >> /var/log/rabbitmq/rollback.log
rabbitmqctl -n rabbit@rabbit-blue-1 list_queues name messages >> /var/log/rabbitmq/rollback.log

# Notify stakeholders
echo "Send rollback complete notification to stakeholders"
```

---

## Post-Rollback Actions

### Immediate
- [ ] Confirm all applications connected to blue
- [ ] Confirm message flow normal
- [ ] Confirm no message loss
- [ ] Notify stakeholders of rollback

### Within 1 Hour
- [ ] Document rollback trigger and symptoms
- [ ] Preserve green cluster logs
- [ ] Capture green cluster state for analysis
- [ ] Schedule post-mortem

### Within 24 Hours
- [ ] Complete root cause analysis
- [ ] Document lessons learned
- [ ] Update migration plan
- [ ] Schedule retry (if applicable)

---

## Rollback Verification Checklist

- [ ] Blue cluster operational
- [ ] All 3 nodes healthy
- [ ] No alarms active
- [ ] Connections restored: ____ (expected: ____)
- [ ] Message publishing working
- [ ] Message consuming working
- [ ] Application health checks passing
- [ ] Error rates normal
- [ ] Stakeholders notified

---

## Escalation

If rollback fails or blue cluster unavailable:

| Level | Contact | When |
|-------|---------|------|
| L1 | On-call engineer | Immediately |
| L2 | Team lead | If L1 cannot resolve in 15 min |
| L3 | Engineering manager | If L2 cannot resolve in 30 min |
| L4 | VP Engineering | If business impact > 1 hour |

---

## Emergency Contacts

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| Migration Lead | | | |
| DBA On-Call | | | |
| Network Team | | | |
| Application Team | | | |
