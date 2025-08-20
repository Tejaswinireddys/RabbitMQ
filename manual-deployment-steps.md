# RabbitMQ 4.1.x Manual Deployment Steps

## 1. Prerequisites

### System Requirements
- **Operating System**: RHEL 8.x
- **Memory**: Minimum 4GB RAM per node
- **Disk**: 20GB+ free space per node
- **Network**: Static IP addresses for all nodes
- **User Access**: Root or sudo privileges

### Network Configuration
```bash
# Set static IP addresses (example IPs - adjust for your network)
Node1: 192.168.1.10
Node2: 192.168.1.11  
Node3: 192.168.1.12

# Update /etc/hosts on ALL nodes
sudo tee -a /etc/hosts << EOF
192.168.1.10    node1
192.168.1.11    node2
192.168.1.12    node3
EOF
```

### Firewall Configuration (Run on ALL nodes)
```bash
# Open required ports
sudo firewall-cmd --permanent --add-port=5672/tcp   # AMQP
sudo firewall-cmd --permanent --add-port=15672/tcp  # Management UI
sudo firewall-cmd --permanent --add-port=25672/tcp  # Inter-node communication
sudo firewall-cmd --permanent --add-port=4369/tcp   # EPMD port mapper
sudo firewall-cmd --permanent --add-port=35672-35682/tcp # Erlang distribution
sudo firewall-cmd --reload

# Verify firewall rules
sudo firewall-cmd --list-ports
```

### SELinux Configuration (Run on ALL nodes)
```bash
# Set SELinux to permissive (or configure properly)
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

## 2. Node Setup Steps

### Step 2.1: Install Erlang and RabbitMQ (Run on ALL nodes)

```bash
# Update system
sudo dnf update -y

# Install EPEL repository
sudo dnf install -y epel-release

# Install required packages
sudo dnf install -y curl wget gnupg2 socat logrotate

# Install Erlang 26.x (required for RabbitMQ 4.1.x)
sudo dnf install -y erlang

# Verify Erlang installation
erl -version

# Add RabbitMQ repository
sudo tee /etc/yum.repos.d/rabbitmq.repo << EOF
[rabbitmq-server]
name=rabbitmq-server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/\$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF

# Import GPG keys
sudo rpm --import https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key

# Install RabbitMQ 4.1.x
sudo dnf install -y rabbitmq-server

# Create necessary directories
sudo mkdir -p /etc/rabbitmq /var/log/rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq /var/lib/rabbitmq /etc/rabbitmq
```

### Step 2.2: Configure Node1 (Primary Node)

```bash
# Set hostname
sudo hostnamectl set-hostname node1

# Set Erlang cookie (SAME on all nodes)
echo "SWQOKODSQALRPCLNMEQG" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Create /etc/rabbitmq/rabbitmq.conf
sudo tee /etc/rabbitmq/rabbitmq.conf << 'EOF'
# RabbitMQ 4.1.x Configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@node1
cluster_formation.classic_config.nodes.2 = rabbit@node2
cluster_formation.classic_config.nodes.3 = rabbit@node3

# Network partition handling
cluster_partition_handling = pause_minority

# Default queue type for data safety
default_queue_type = quorum

# Memory and disk limits
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0

# Heartbeat
heartbeat = 60

# Management plugin
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Logging
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
EOF

# Create /etc/rabbitmq/enabled_plugins
sudo tee /etc/rabbitmq/enabled_plugins << 'EOF'
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
EOF

# Start RabbitMQ service
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 10

# Create admin user
sudo rabbitmqctl add_user admin admin123
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# Delete default guest user (security)
sudo rabbitmqctl delete_user guest

# Check status
sudo rabbitmqctl status
sudo rabbitmqctl cluster_status
```

### Step 2.3: Configure Node2

```bash
# Set hostname
sudo hostnamectl set-hostname node2

# Set SAME Erlang cookie
echo "SWQOKODSQALRPCLNMEQG" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Copy same configuration files from node1
sudo tee /etc/rabbitmq/rabbitmq.conf << 'EOF'
# RabbitMQ 4.1.x Configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@node1
cluster_formation.classic_config.nodes.2 = rabbit@node2
cluster_formation.classic_config.nodes.3 = rabbit@node3

cluster_partition_handling = pause_minority
default_queue_type = quorum
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
heartbeat = 60
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
EOF

sudo tee /etc/rabbitmq/enabled_plugins << 'EOF'
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
EOF

# Start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 10

# Join cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl start_app

# Verify cluster status
sudo rabbitmqctl cluster_status
```

### Step 2.4: Configure Node3

```bash
# Set hostname
sudo hostnamectl set-hostname node3

# Set SAME Erlang cookie
echo "SWQOKODSQALRPCLNMEQG" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Copy same configuration files
sudo tee /etc/rabbitmq/rabbitmq.conf << 'EOF'
# RabbitMQ 4.1.x Configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@node1
cluster_formation.classic_config.nodes.2 = rabbit@node2
cluster_formation.classic_config.nodes.3 = rabbit@node3

cluster_partition_handling = pause_minority
default_queue_type = quorum
vm_memory_high_watermark.relative = 0.6
disk_free_limit.relative = 2.0
heartbeat = 60
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
EOF

sudo tee /etc/rabbitmq/enabled_plugins << 'EOF'
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
EOF

# Start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 10

# Join cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl start_app

# Verify cluster status
sudo rabbitmqctl cluster_status
```

## 3. Cluster Validation

### 3.1: Basic Cluster Health Checks

```bash
# Run on any node to check cluster status
sudo rabbitmqctl cluster_status

# Expected output should show all 3 nodes:
# Cluster status of node rabbit@nodeX ...
# Basics
# Cluster name: rabbit@node1
# Disk Nodes: [rabbit@node1, rabbit@node2, rabbit@node3]
# Running Nodes: [rabbit@node1, rabbit@node2, rabbit@node3]

# Check node health
sudo rabbitmqctl node_health_check

# Check if all nodes are running
sudo rabbitmqctl eval 'rabbit_mnesia:cluster_nodes(all).'

# List all nodes
sudo rabbitmqctl list_nodes

# Check queue types
sudo rabbitmqctl environment | grep default_queue_type
```

### 3.2: Management Interface Validation

```bash
# Access management interface from browser:
http://192.168.1.10:15672  # Node1
http://192.168.1.11:15672  # Node2  
http://192.168.1.12:15672  # Node3

# Login credentials:
Username: admin
Password: admin123

# Verify in Overview tab:
# - All 3 nodes should be visible
# - Cluster name should be displayed
# - No alarms should be present
```

### 3.3: Network Partition Test

```bash
# Test network partition handling
# Block communication between nodes temporarily
sudo iptables -A INPUT -s 192.168.1.11 -j DROP  # Run on node1 to block node2

# Check cluster status - minority should pause
sudo rabbitmqctl cluster_status

# Restore communication
sudo iptables -D INPUT -s 192.168.1.11 -j DROP

# Verify cluster recovers
sudo rabbitmqctl cluster_status
```

### 3.4: Node Failover Test

```bash
# Stop one node
sudo systemctl stop rabbitmq-server  # Run on node3

# Check cluster from remaining nodes
sudo rabbitmqctl cluster_status  # Run on node1 or node2

# Start the stopped node
sudo systemctl start rabbitmq-server  # On node3

# Verify it rejoins automatically
sudo rabbitmqctl cluster_status
```

## 4. Sample Queue Creation Scripts

### 4.1: Basic Queue Creation Script

```bash
#!/bin/bash
# save as create_queues.sh

# Create quorum queues (recommended for data safety)
sudo rabbitmqctl declare queue --vhost=/ --name=orders --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name=payments --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name=notifications --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name=audit_logs --type=quorum --durable=true

# Create classic queue (if needed)
sudo rabbitmqctl declare queue --vhost=/ --name=temp_queue --type=classic --durable=false

# List all queues
sudo rabbitmqctl list_queues name type durable auto_delete
```

### 4.2: Advanced Queue Configuration Script

```bash
#!/bin/bash
# save as advanced_queues.sh

# Quorum queue with specific arguments
sudo rabbitmqctl declare queue --vhost=/ --name=high_priority_orders \
  --type=quorum \
  --durable=true \
  --arguments='{"x-quorum-initial-group-size":3,"x-max-length":10000}'

# Dead letter queue setup
sudo rabbitmqctl declare queue --vhost=/ --name=failed_orders --type=quorum --durable=true

sudo rabbitmqctl declare queue --vhost=/ --name=orders_with_dlx \
  --type=quorum \
  --durable=true \
  --arguments='{"x-dead-letter-exchange":"dlx","x-dead-letter-routing-key":"failed"}'

# Create exchanges
sudo rabbitmqctl declare exchange --vhost=/ --name=order_exchange --type=direct --durable=true
sudo rabbitmqctl declare exchange --vhost=/ --name=dlx --type=direct --durable=true

# Create bindings
sudo rabbitmqctl declare binding --vhost=/ --source=order_exchange --destination=orders_with_dlx --routing-key=new
sudo rabbitmqctl declare binding --vhost=/ --source=dlx --destination=failed_orders --routing-key=failed

# List all queues with details
sudo rabbitmqctl list_queues name type durable auto_delete arguments
```

### 4.3: Queue Validation Script

```bash
#!/bin/bash
# save as validate_queues.sh

echo "=== Queue Validation ==="

# List all queues
echo "All Queues:"
sudo rabbitmqctl list_queues name type messages consumers

echo -e "\n=== Quorum Queue Details ==="
# Check quorum queue members
sudo rabbitmqctl list_queues name type online_members members

echo -e "\n=== Exchange and Binding Information ==="
sudo rabbitmqctl list_exchanges name type
sudo rabbitmqctl list_bindings

echo -e "\n=== Cluster Queue Distribution ==="
# Show which node is leader for each queue
sudo rabbitmqctl eval 'rabbit_amqqueue:info_all([name, type, leader]).'
```

### 4.4: Performance Test Script

```bash
#!/bin/bash
# save as queue_performance_test.sh

# Create test queue
sudo rabbitmqctl declare queue --vhost=/ --name=perf_test --type=quorum --durable=true

# Install perf test tool (if not already installed)
# wget https://github.com/rabbitmq/rabbitmq-perf-test/releases/latest/download/perf-test-2.18.1.jar

# Run performance test (requires Java)
# java -jar perf-test-2.18.1.jar \
#   --uri amqp://admin:admin123@192.168.1.10:5672 \
#   --queue perf_test \
#   --producers 5 \
#   --consumers 5 \
#   --rate 1000 \
#   --time 60

echo "Performance test setup completed"
echo "Install perf-test tool and uncomment lines above to run actual test"
```

### 4.5: Monitoring Script

```bash
#!/bin/bash
# save as monitor_cluster.sh

echo "=== RabbitMQ Cluster Monitoring ==="
echo "Timestamp: $(date)"
echo

echo "=== Cluster Status ==="
sudo rabbitmqctl cluster_status

echo -e "\n=== Node Memory Usage ==="
sudo rabbitmqctl status | grep -A 5 "Memory"

echo -e "\n=== Queue Overview ==="
sudo rabbitmqctl list_queues name messages consumers memory

echo -e "\n=== Connection Count ==="
sudo rabbitmqctl list_connections | wc -l

echo -e "\n=== Exchange List ==="
sudo rabbitmqctl list_exchanges name type

echo -e "\n=== Alarms (should be empty) ==="
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'
```

### Make Scripts Executable

```bash
chmod +x create_queues.sh
chmod +x advanced_queues.sh  
chmod +x validate_queues.sh
chmod +x queue_performance_test.sh
chmod +x monitor_cluster.sh
```