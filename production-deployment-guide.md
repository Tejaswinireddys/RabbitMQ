# RabbitMQ 4.1.x Production Deployment Guide

## Environment Strategy

### Environment Specifications
- **QA Environment**: 3 nodes (2 CPU, 8GB RAM, 100GB disk)
- **Production Environment**: 3 nodes (4+ CPU, 16GB+ RAM, 500GB+ disk)
- **Network**: Dedicated VLAN with load balancer

## Phase 1: QA Environment Setup

### 1.1 QA OS Configuration (All 3 QA Nodes)

```bash
# System limits for QA
sudo tee /etc/systemd/system/rabbitmq-server.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65536
LimitNPROC=32768
EOF

# Kernel parameters for QA
sudo tee /etc/sysctl.d/99-rabbitmq.conf << 'EOF'
net.core.somaxconn = 2048
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
vm.swappiness = 1
fs.file-max = 1048576
EOF

sudo sysctl -p /etc/sysctl.d/99-rabbitmq.conf
sudo systemctl daemon-reload
```

### 1.2 QA RabbitMQ Installation

```bash
# QA Node hostnames: qa-rmq-01, qa-rmq-02, qa-rmq-03
# QA IPs: 10.10.10.11, 10.10.10.12, 10.10.10.13

# Update /etc/hosts on all QA nodes
sudo tee -a /etc/hosts << 'EOF'
10.10.10.11    qa-rmq-01
10.10.10.12    qa-rmq-02
10.10.10.13    qa-rmq-03
EOF

# Install RabbitMQ (same steps as before)
sudo dnf install -y epel-release erlang
# ... (same installation steps)

# QA Configuration - rabbitmq.conf
sudo tee /etc/rabbitmq/rabbitmq.conf << 'EOF'
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@qa-rmq-01
cluster_formation.classic_config.nodes.2 = rabbit@qa-rmq-02
cluster_formation.classic_config.nodes.3 = rabbit@qa-rmq-03

cluster_partition_handling = pause_minority
default_queue_type = quorum
vm_memory_high_watermark.relative = 0.7
disk_free_limit.relative = 1.5
heartbeat = 60
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# QA specific settings
log.console.level = debug
collect_statistics_interval = 10000
EOF
```

### 1.3 QA Testing Procedures

```bash
#!/bin/bash
# qa_validation.sh

echo "=== QA Environment Validation ==="

# 1. Cluster formation test
echo "Testing cluster formation..."
sudo rabbitmqctl cluster_status

# 2. Queue creation and replication test
echo "Testing queue operations..."
sudo rabbitmqctl declare queue --name=qa_test_queue --type=quorum --durable=true

# 3. Message persistence test
echo "Testing message persistence..."
# Publish test messages
sudo rabbitmqctl publish exchange="" routing-key="qa_test_queue" payload="test message 1"
sudo rabbitmqctl publish exchange="" routing-key="qa_test_queue" payload="test message 2"

# 4. Node failure simulation
echo "Testing node failure..."
sudo systemctl stop rabbitmq-server  # Run on one node
sleep 30
sudo systemctl start rabbitmq-server

# 5. Network partition simulation
echo "Testing network partition..."
sudo iptables -A INPUT -s 10.10.10.12 -j DROP  # Block node2
sleep 60
sudo iptables -D INPUT -s 10.10.10.12 -j DROP  # Restore

# 6. Performance baseline
echo "Performance baseline test..."
# Install perf test tool and run
```

## Phase 2: Production Environment Setup

### 2.1 Production OS Configuration (All 3 Production Nodes)

```bash
# Production system limits
sudo tee /etc/systemd/system/rabbitmq-server.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=300000
LimitNPROC=300000
User=rabbitmq
Group=rabbitmq
EOF

# Production kernel parameters
sudo tee /etc/sysctl.d/99-rabbitmq.conf << 'EOF'
# Network optimization for production
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 10000
net.core.rmem_default = 262144
net.core.rmem_max = 33554432
net.core.wmem_default = 262144
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1

# Connection tracking for high load
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# Memory management for production
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 1

# File system limits
fs.file-max = 4194304
fs.nr_open = 4194304
EOF

sudo sysctl -p /etc/sysctl.d/99-rabbitmq.conf
```

### 2.2 Production Security Configuration

```bash
# SSL Certificate setup (run on all production nodes)
sudo mkdir -p /etc/rabbitmq/ssl
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/ssl
sudo chmod 700 /etc/rabbitmq/ssl

# Generate or copy production SSL certificates
# sudo cp /path/to/ca.pem /etc/rabbitmq/ssl/
# sudo cp /path/to/server-cert.pem /etc/rabbitmq/ssl/
# sudo cp /path/to/server-key.pem /etc/rabbitmq/ssl/

# Firewall for production (restrict access)
sudo firewall-cmd --permanent --remove-service=ssh  # Remove if using key-based access
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.0/24" port port="5672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.0/24" port port="15672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.11-13" port port="25672" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### 2.3 Production RabbitMQ Configuration

```bash
# Production hostnames: prod-rmq-01, prod-rmq-02, prod-rmq-03
# Production IPs: 10.20.20.11, 10.20.20.12, 10.20.20.13
# Load Balancer VIP: 10.20.20.10

# Production /etc/hosts
sudo tee -a /etc/hosts << 'EOF'
10.20.20.11    prod-rmq-01
10.20.20.12    prod-rmq-02
10.20.20.13    prod-rmq-03
10.20.20.10    rabbitmq-cluster.example.com
EOF

# Production rabbitmq.conf
sudo tee /etc/rabbitmq/rabbitmq.conf << 'EOF'
# Production RabbitMQ 4.1.x Configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@prod-rmq-01
cluster_formation.classic_config.nodes.2 = rabbit@prod-rmq-02
cluster_formation.classic_config.nodes.3 = rabbit@prod-rmq-03

# Cluster stability settings
cluster_partition_handling = pause_minority
cluster_formation.randomized_startup_delay_range.min = 5
cluster_formation.randomized_startup_delay_range.max = 30

# Queue defaults for production
default_queue_type = quorum
default_user_tags.administrator = false

# Memory and performance settings
vm_memory_high_watermark.relative = 0.6
vm_memory_calculation_strategy = rss
disk_free_limit.relative = 2.0

# Network settings
heartbeat = 60
channel_max = 4096
connection_max = 4096
frame_max = 131072

# SSL/TLS Configuration
listeners.ssl.default = 5671
ssl_options.cacertfile = /etc/rabbitmq/ssl/ca.pem
ssl_options.certfile = /etc/rabbitmq/ssl/server-cert.pem
ssl_options.keyfile = /etc/rabbitmq/ssl/server-key.pem
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true
ssl_options.versions.1 = tlsv1.2
ssl_options.versions.2 = tlsv1.3

# Management interface
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0
management.ssl.port = 15671
management.ssl.cacertfile = /etc/rabbitmq/ssl/ca.pem
management.ssl.certfile = /etc/rabbitmq/ssl/server-cert.pem
management.ssl.keyfile = /etc/rabbitmq/ssl/server-key.pem

# Logging for production
log.console = false
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
log.file.rotation.date = $D0
log.file.rotation.size = 10485760

# Statistics collection
collect_statistics_interval = 10000
delegate_count = 32

# Production optimizations
queue_index_embed_msgs_below = 4096
lazy_queue_explicit_gc_run_operation_threshold = 1000
EOF

# Production advanced.config
sudo tee /etc/rabbitmq/advanced.config << 'EOF'
[
  {rabbit, [
    {cluster_nodes, {['rabbit@prod-rmq-01', 'rabbit@prod-rmq-02', 'rabbit@prod-rmq-03'], disc}},
    {cluster_partition_handling, pause_minority},
    {tcp_listeners, [5672]},
    {ssl_listeners, [5671]},
    {num_tcp_acceptors, 20},
    {num_ssl_acceptors, 10},
    {handshake_timeout, 10000},
    {vm_memory_high_watermark, 0.6},
    {vm_memory_calculation_strategy, rss},
    {disk_free_limit, {mem_relative, 2.0}},
    {heartbeat, 60},
    {channel_max, 4096},
    {connection_max, 4096},
    {collect_statistics_interval, 10000},
    {delegate_count, 32},
    {mnesia_table_loading_retry_timeout, 30000},
    {mnesia_table_loading_retry_limit, 10}
  ]},
  
  {rabbitmq_management, [
    {rates_mode, basic},
    {sample_retention_policies, [
      {global, [{605, 5}, {3660, 60}, {29400, 600}, {86400, 1800}]},
      {basic, [{605, 5}, {3660, 60}]},
      {detailed, [{605, 5}]}
    ]}
  ]},
  
  {kernel, [
    {inet_default_connect_options, [
      {nodelay, true},
      {keepalive, true},
      {send_timeout, 15000},
      {send_timeout_close, true}
    ]},
    {inet_dist_listen_min, 25672},
    {inet_dist_listen_max, 25672}
  ]}
].
EOF
```

## Phase 3: Deployment Procedures

### 3.1 Pre-Deployment Checklist

```bash
#!/bin/bash
# pre_deployment_check.sh

echo "=== Pre-Deployment Checklist ==="

# Infrastructure checks
echo "1. Verifying infrastructure..."
echo "   - DNS resolution: $(nslookup prod-rmq-01)"
echo "   - Network connectivity: $(ping -c 1 prod-rmq-01 && echo OK)"
echo "   - Load balancer health: $(curl -s http://10.20.20.10:15672 && echo OK)"

# Security checks
echo "2. Security verification..."
echo "   - SSL certificates: $(ls -la /etc/rabbitmq/ssl/)"
echo "   - Firewall rules: $(sudo firewall-cmd --list-all)"
echo "   - SELinux status: $(sestatus)"

# System resource checks
echo "3. System resources..."
echo "   - Memory: $(free -h | grep Mem)"
echo "   - Disk space: $(df -h /var/lib/rabbitmq)"
echo "   - File limits: $(ulimit -n)"

# Backup verification
echo "4. Backup systems..."
echo "   - Backup scripts: $(ls -la /opt/scripts/backup/)"
echo "   - Monitoring: $(systemctl status prometheus-node-exporter)"

echo "Pre-deployment check completed!"
```

### 3.2 Blue-Green Deployment Strategy

```bash
#!/bin/bash
# blue_green_deployment.sh

# Current production (Blue) - existing cluster
# New production (Green) - new 4.1.x cluster

echo "=== Blue-Green RabbitMQ Deployment ==="

# Step 1: Prepare Green environment
echo "1. Setting up Green environment..."
# Deploy new cluster with 4.1.x configuration

# Step 2: Sync data (if possible)
echo "2. Data synchronization..."
# Use federation or shovel to sync critical queues

# Step 3: Application testing on Green
echo "3. Testing applications on Green..."
# Point test applications to Green cluster

# Step 4: DNS/Load Balancer switch
echo "4. Traffic switching..."
# Update load balancer to point to Green cluster

# Step 5: Monitor and rollback if needed
echo "5. Monitoring phase..."
# Monitor for 30 minutes, rollback if issues detected
```

### 3.3 Rolling Upgrade Strategy (Alternative)

```bash
#!/bin/bash
# rolling_upgrade.sh

echo "=== Rolling Upgrade Strategy ==="

# Step 1: Upgrade node 3 first
echo "1. Upgrading prod-rmq-03..."
sudo systemctl stop rabbitmq-server
# Install RabbitMQ 4.1.x
sudo systemctl start rabbitmq-server
# Wait for cluster to stabilize

# Step 2: Upgrade node 2
echo "2. Upgrading prod-rmq-02..."
# Repeat process

# Step 3: Upgrade node 1 (primary)
echo "3. Upgrading prod-rmq-01..."
# Final upgrade

echo "Rolling upgrade completed!"
```

## Phase 4: Production Monitoring and Maintenance

### 4.1 Production Monitoring Setup

```bash
# Install monitoring tools
sudo dnf install -y prometheus-node-exporter

# RabbitMQ Prometheus metrics
sudo tee /etc/rabbitmq/conf.d/20-prometheus.conf << 'EOF'
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
EOF

# Monitoring script
sudo tee /opt/scripts/monitor_production.sh << 'EOF'
#!/bin/bash
# Production monitoring script

ALERT_EMAIL="admin@company.com"
CLUSTER_VIP="10.20.20.10"

# Check cluster health
if ! curl -s http://admin:password@$CLUSTER_VIP:15672/api/cluster-name; then
    echo "ALERT: RabbitMQ cluster is down!" | mail -s "RabbitMQ Alert" $ALERT_EMAIL
fi

# Check queue lengths
QUEUE_COUNT=$(curl -s http://admin:password@$CLUSTER_VIP:15672/api/queues | jq '.[].messages' | awk '{sum+=$1} END {print sum}')
if [ "$QUEUE_COUNT" -gt 100000 ]; then
    echo "ALERT: High queue depth: $QUEUE_COUNT messages" | mail -s "RabbitMQ Alert" $ALERT_EMAIL
fi

# Check memory usage
MEMORY_USAGE=$(curl -s http://admin:password@$CLUSTER_VIP:15672/api/nodes | jq '.[0].mem_used_details.rate')
if [ "$MEMORY_USAGE" -gt 80 ]; then
    echo "ALERT: High memory usage: $MEMORY_USAGE%" | mail -s "RabbitMQ Alert" $ALERT_EMAIL
fi
EOF

# Setup cron job for monitoring
echo "*/5 * * * * /opt/scripts/monitor_production.sh" | sudo crontab -
```

### 4.2 Backup and Recovery Procedures

```bash
#!/bin/bash
# backup_production.sh

BACKUP_DIR="/backup/rabbitmq/$(date +%Y%m%d)"
RETENTION_DAYS=30

echo "=== Production Backup Procedure ==="

# Create backup directory
sudo mkdir -p $BACKUP_DIR

# Export definitions
sudo rabbitmqctl export_definitions $BACKUP_DIR/definitions.json

# Backup data directories (on each node)
for node in prod-rmq-01 prod-rmq-02 prod-rmq-03; do
    echo "Backing up $node..."
    sudo ssh $node "tar -czf /tmp/rabbitmq-data-$(date +%Y%m%d).tar.gz /var/lib/rabbitmq/"
    sudo scp $node:/tmp/rabbitmq-data-$(date +%Y%m%d).tar.gz $BACKUP_DIR/
done

# Cleanup old backups
find /backup/rabbitmq/ -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Backup completed: $BACKUP_DIR"
```

### 4.3 Disaster Recovery Procedures

```bash
#!/bin/bash
# disaster_recovery.sh

echo "=== Disaster Recovery Procedure ==="

# Step 1: Assess damage
echo "1. Assessing cluster status..."
sudo rabbitmqctl cluster_status

# Step 2: Restore from backup if needed
echo "2. Restoring from backup..."
LATEST_BACKUP=$(ls -t /backup/rabbitmq/ | head -1)
sudo rabbitmqctl import_definitions /backup/rabbitmq/$LATEST_BACKUP/definitions.json

# Step 3: Verify recovery
echo "3. Verifying recovery..."
sudo rabbitmqctl list_queues
sudo rabbitmqctl cluster_status

echo "Recovery completed!"
```

## Phase 5: Operational Procedures

### 5.1 Change Management Process

1. **Change Request**: All changes must go through formal change request
2. **QA Testing**: Test all changes in QA environment first
3. **Maintenance Window**: Schedule changes during approved maintenance windows
4. **Rollback Plan**: Always have a tested rollback procedure
5. **Documentation**: Update all documentation after changes

### 5.2 Health Check Scripts

```bash
#!/bin/bash
# daily_health_check.sh

echo "=== Daily RabbitMQ Health Check ==="
echo "Date: $(date)"

echo "1. Cluster Status:"
sudo rabbitmqctl cluster_status

echo "2. Queue Overview:"
sudo rabbitmqctl list_queues name messages consumers

echo "3. Memory Usage:"
sudo rabbitmqctl status | grep -A 5 "Memory"

echo "4. Disk Usage:"
df -h /var/lib/rabbitmq

echo "5. Connection Count:"
sudo rabbitmqctl list_connections | wc -l

echo "6. Node Health:"
for node in prod-rmq-01 prod-rmq-02 prod-rmq-03; do
    ssh $node "sudo rabbitmqctl node_health_check" && echo "$node: OK" || echo "$node: FAILED"
done

echo "Health check completed!"
```

This production deployment guide ensures:
- **Zero downtime** deployment options
- **Data safety** throughout the process
- **Comprehensive monitoring** and alerting
- **Disaster recovery** procedures
- **Operational excellence** practices