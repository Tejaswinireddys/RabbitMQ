# Node Upgrade Runbook

## Purpose
Step-by-step procedure for upgrading individual RabbitMQ nodes.

---

## Prerequisites

- [ ] Backup completed
- [ ] Upgrade packages available
- [ ] Maintenance window scheduled
- [ ] Team notified

---

## Procedure

### Step 1: Pre-Upgrade Checks

```bash
# Check cluster status
rabbitmqctl cluster_status

# Check node health
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_local_alarms

# Note current queue leaders on this node
rabbitmqctl list_queues name type leader | grep $(hostname)
```

### Step 2: Enable Maintenance Mode

```bash
# Enable maintenance mode (drains connections gracefully)
rabbitmqctl enable_maintenance_mode

# Wait for connections to drain
watch -n 5 'rabbitmqctl list_connections | wc -l'

# Verify no connections remain
rabbitmqctl list_connections
```

### Step 3: Stop RabbitMQ

```bash
# Stop the RabbitMQ service
sudo systemctl stop rabbitmq-server

# Verify stopped
sudo systemctl status rabbitmq-server
```

### Step 4: Upgrade Erlang (if needed)

```bash
# Check current version
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

# Upgrade Erlang (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y esl-erlang=1:26.2*

# Verify new version
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
```

### Step 5: Upgrade RabbitMQ

```bash
# Upgrade RabbitMQ (Debian/Ubuntu)
sudo apt-get install -y rabbitmq-server=4.1.4-1

# Verify package version
dpkg -l rabbitmq-server
```

### Step 6: Start RabbitMQ

```bash
# Start RabbitMQ
sudo systemctl start rabbitmq-server

# Wait for startup (may take 30-60 seconds)
sleep 30

# Check status
sudo systemctl status rabbitmq-server
rabbitmqctl status
```

### Step 7: Verify Cluster Membership

```bash
# Check cluster status
rabbitmqctl cluster_status

# Verify this node is listed
rabbitmqctl cluster_status | grep $(hostname)
```

### Step 8: Disable Maintenance Mode

```bash
# Disable maintenance mode
rabbitmqctl disable_maintenance_mode

# Verify connections returning
watch -n 5 'rabbitmqctl list_connections | wc -l'
```

### Step 9: Post-Upgrade Validation

```bash
# Check version
rabbitmqctl version

# Check health
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_local_alarms

# Check quorum queues rejoined
rabbitmqctl list_queues name type members online | head -20
```

---

## Rollback Procedure

If upgrade fails:

```bash
# 1. Stop RabbitMQ
sudo systemctl stop rabbitmq-server

# 2. Downgrade package
sudo apt-get install -y rabbitmq-server=3.12.x-1

# 3. Downgrade Erlang if needed
sudo apt-get install -y esl-erlang=1:25.x*

# 4. Start RabbitMQ
sudo systemctl start rabbitmq-server

# 5. Verify cluster
rabbitmqctl cluster_status
```

---

## Troubleshooting

### Node won't start
```bash
# Check logs
sudo tail -100 /var/log/rabbitmq/rabbit@$(hostname).log

# Check Erlang cookie
cat /var/lib/rabbitmq/.erlang.cookie
```

### Node won't join cluster
```bash
# Reset and rejoin
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl join_cluster rabbit@cluster-node-1
rabbitmqctl start_app
```

### Quorum queues not syncing
```bash
# Check queue members
rabbitmqctl list_queues name type members online

# Force sync (if needed)
rabbitmq-queues grow rabbit@$(hostname) all
```

---

## Completion Checklist

- [ ] Node running version 4.1.4
- [ ] Node in cluster
- [ ] No alarms
- [ ] Connections returning
- [ ] Quorum queues have this node as member
- [ ] Monitoring shows node healthy
