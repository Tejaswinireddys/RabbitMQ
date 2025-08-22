# RabbitMQ 4.x Single Node Deployment on RHEL8 VM

## 🎯 Overview

Complete deployment guide for RabbitMQ 4.x single-node cluster on RHEL8 VM with static cluster name configuration.

## 📋 Prerequisites

- RHEL8 VM with root/sudo access
- Minimum 4GB RAM, 2 CPU cores
- 20GB available disk space
- Network access for package downloads

---

## 🚀 Step 1: System Preparation

### 1.1 Update System
```bash
sudo dnf update -y
sudo dnf install -y wget curl gnupg2
```

### 1.2 Install Required Dependencies
```bash
# Install EPEL repository
sudo dnf install -y epel-release

# Install necessary tools
sudo dnf install -y socat logrotate
```

### 1.3 Configure SELinux (if enabled)
```bash
# Check SELinux status
getenforce

# If SELinux is enforcing, configure for RabbitMQ
sudo setsebool -P nis_enabled 1
sudo semanage port -a -t amqp_port_t -p tcp 5672
sudo semanage port -a -t amqp_port_t -p tcp 15672
sudo semanage port -a -t amqp_port_t -p tcp 25672
```

---

## 🔧 Step 2: Install Erlang/OTP

### 2.1 Add Erlang Repository
```bash
# Create Erlang repository file
sudo tee /etc/yum.repos.d/rabbitmq_erlang.repo <<EOF
[rabbitmq_erlang]
name=rabbitmq_erlang
baseurl=https://packagecloud.io/rabbitmq/erlang/el/8/x86_64
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/rabbitmq/erlang/gpgkey
       https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md
EOF
```

### 2.2 Install Erlang 26.x (Required for RabbitMQ 4.x)
```bash
# Install Erlang
sudo dnf install -y erlang
```

### 2.3 Verify Erlang Installation
```bash
erl -version
# Should show: Erlang (SMP,ASYNC_THREADS,HIPE) (BEAM) emulator version 14.0 or higher
```

---

## 📦 Step 3: Install RabbitMQ 4.x

### 3.1 Add RabbitMQ Repository
```bash
# Create RabbitMQ repository file
sudo tee /etc/yum.repos.d/rabbitmq.repo <<EOF
[rabbitmq_server]
name=rabbitmq_server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/x86_64
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey
       https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md
EOF
```

### 3.2 Install RabbitMQ Server
```bash
# Update repository cache
sudo dnf makecache -y

# Install RabbitMQ 4.x
sudo dnf install -y rabbitmq-server
```

### 3.3 Verify Installation
```bash
sudo rabbitmq-server -version
# Should show: RabbitMQ version: 4.x.x
```

---

## ⚙️ Step 4: Configure RabbitMQ

### 4.1 Create Configuration Directory
```bash
sudo mkdir -p /etc/rabbitmq
sudo chown rabbitmq:rabbitmq /etc/rabbitmq
```

### 4.2 Create Main Configuration File
```bash
sudo tee /etc/rabbitmq/rabbitmq.conf <<EOF
# Cluster Configuration
cluster_name = myapp-rabbitmq-cluster
cluster_formation.peer_discovery_backend = classic_config

# Node Configuration  
node_name = rabbit@$(hostname -s)

# Network Configuration
listeners.tcp.default = 5672
listeners.ssl.default = 5671
management.listener.port = 15672
management.listener.ssl = false

# Memory and Disk Configuration
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 2GB

# Performance Tuning for RHEL8
channel_max = 2000
heartbeat = 60
frame_max = 8192
collect_statistics_interval = 10000

# Logging Configuration
log.console = false
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
log.file.rotation.size = 100MB
log.file.rotation.count = 5

# Management Plugin Configuration
management.rates_mode = basic
management.sample_retention_policies.global.minute = 5
management.sample_retention_policies.global.hour = 60
management.sample_retention_policies.global.day = 1200

# Default User Configuration
default_user = admin
default_pass = RabbitMQ_Admin_2024!
default_user_tags.administrator = true
default_permissions.configure = .*
default_permissions.read = .*
default_permissions.write = .*

# Security Configuration
auth_mechanisms.1 = PLAIN
auth_mechanisms.2 = AMQPLAIN

# Queue Configuration
queue_master_locator = min-masters

# RHEL8 Specific Optimizations
tcp_listen_options.backlog = 128
tcp_listen_options.nodelay = true
tcp_listen_options.keepalive = true
EOF
```

### 4.3 Create Environment Configuration
```bash
sudo tee /etc/rabbitmq/rabbitmq-env.conf <<EOF
# Node and Cluster Configuration
RABBITMQ_CLUSTER_NAME=myapp-rabbitmq-cluster
RABBITMQ_NODE_NAME=rabbit@$(hostname -s)
RABBITMQ_NODENAME=rabbit@$(hostname -s)

# Erlang Cookie for cluster authentication
RABBITMQ_ERLANG_COOKIE=my-secret-cookie-change-this-in-production

# Paths
RABBITMQ_MNESIA_BASE=/var/lib/rabbitmq/mnesia
RABBITMQ_LOG_BASE=/var/log/rabbitmq

# System Limits
RABBITMQ_IO_THREAD_POOL_SIZE=128
ERL_EPMD_PORT=4369
EOF
```

### 4.4 Enable Required Plugins
```bash
sudo tee /etc/rabbitmq/enabled_plugins <<EOF
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel,rabbitmq_shovel_management,rabbitmq_federation,rabbitmq_federation_management].
EOF
```

---

## 🔥 Step 5: Firewall Configuration

### 5.1 Configure firewalld
```bash
# Start and enable firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld

# Add RabbitMQ ports
sudo firewall-cmd --permanent --add-port=5672/tcp   # AMQP
sudo firewall-cmd --permanent --add-port=5671/tcp   # AMQPS
sudo firewall-cmd --permanent --add-port=15672/tcp  # Management UI
sudo firewall-cmd --permanent --add-port=25672/tcp  # Inter-node communication
sudo firewall-cmd --permanent --add-port=4369/tcp   # EPMD

# Create RabbitMQ service definition (optional)
sudo tee /etc/firewalld/services/rabbitmq.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>RabbitMQ</short>
  <description>RabbitMQ Message Broker</description>
  <port protocol="tcp" port="5672"/>
  <port protocol="tcp" port="5671"/>
  <port protocol="tcp" port="15672"/>
  <port protocol="tcp" port="25672"/>
  <port protocol="tcp" port="4369"/>
</service>
EOF

# Reload firewall
sudo firewall-cmd --reload
```

---

## 🏃 Step 6: Start and Enable RabbitMQ

### 6.1 Set Proper Permissions
```bash
# Set ownership for RabbitMQ directories
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq

# Set proper permissions
sudo chmod 640 /etc/rabbitmq/rabbitmq.conf
sudo chmod 640 /etc/rabbitmq/rabbitmq-env.conf
```

### 6.2 Start RabbitMQ Service
```bash
# Enable and start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Check service status
sudo systemctl status rabbitmq-server
```

### 6.3 Verify Service is Running
```bash
# Check if RabbitMQ is running
sudo rabbitmqctl status

# Check cluster status
sudo rabbitmqctl cluster_status

# Check enabled plugins
sudo rabbitmqctl list_enabled_plugins
```

---

## 🔒 Step 7: Security Configuration

### 7.1 Change Default Admin Password
```bash
# Add a new admin user with strong password
sudo rabbitmqctl add_user myapp_admin 'Strong_Password_2024!'
sudo rabbitmqctl set_user_tags myapp_admin administrator
sudo rabbitmqctl set_permissions -p / myapp_admin ".*" ".*" ".*"

# Delete default admin user (optional)
sudo rabbitmqctl delete_user admin
```

### 7.2 Create Application User
```bash
# Create application-specific user
sudo rabbitmqctl add_user myapp_user 'App_User_Password_2024!'
sudo rabbitmqctl set_permissions -p / myapp_user ".*" ".*" ".*"
```

### 7.3 Configure TLS (Optional but Recommended)
```bash
# Create certificate directory
sudo mkdir -p /etc/rabbitmq/certs
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/certs
sudo chmod 750 /etc/rabbitmq/certs

# Generate self-signed certificates (for testing)
sudo openssl req -new -x509 -days 365 -nodes -out /etc/rabbitmq/certs/server.pem \
  -keyout /etc/rabbitmq/certs/server.key \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$(hostname -f)"

sudo chown rabbitmq:rabbitmq /etc/rabbitmq/certs/*
sudo chmod 640 /etc/rabbitmq/certs/*
```

---

## 🌐 Step 8: Verification and Testing

### 8.1 Access Management UI
```bash
# Get server IP
ip addr show | grep inet | grep -v 127.0.0.1

# Access Management UI at: http://YOUR_VM_IP:15672
# Username: myapp_admin
# Password: Strong_Password_2024!
```

### 8.2 Test AMQP Connection
```bash
# Install telnet for connection testing
sudo dnf install -y telnet

# Test AMQP port
telnet localhost 5672
```

### 8.3 Test Management API
```bash
# Test API endpoint
curl -u myapp_admin:Strong_Password_2024! http://localhost:15672/api/overview | jq '.'
```

### 8.4 Verify Cluster Configuration
```bash
# Check cluster name
sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().'

# Should output: <<"myapp-rabbitmq-cluster">>
```

---

## 📊 Step 9: Monitoring Setup

### 9.1 Configure Log Rotation
```bash
sudo tee /etc/logrotate.d/rabbitmq <<EOF
/var/log/rabbitmq/*.log {
    daily
    missingok
    rotate 10
    compress
    notifempty
    create 0644 rabbitmq rabbitmq
    postrotate
        /bin/kill -USR1 \$(cat /var/lib/rabbitmq/mnesia/rabbit@$(hostname -s).pid 2> /dev/null) 2> /dev/null || true
    endscript
}
EOF
```

### 9.2 Setup Prometheus Monitoring
```bash
# Prometheus metrics available at:
curl http://localhost:15672/metrics
```

### 9.3 Create Health Check Script
```bash
sudo tee /usr/local/bin/rabbitmq-health-check.sh <<'EOF'
#!/bin/bash
# RabbitMQ Health Check Script

echo "=== RabbitMQ Health Check ==="
echo "Timestamp: $(date)"

# Check service status
echo "Service Status:"
systemctl is-active rabbitmq-server

# Check node status
echo -e "\nNode Status:"
rabbitmqctl status --quiet

# Check cluster status
echo -e "\nCluster Status:"
rabbitmqctl cluster_status --quiet

# Check management plugin
echo -e "\nManagement API:"
curl -s -u myapp_admin:Strong_Password_2024! http://localhost:15672/api/healthchecks/node | jq '.status' 2>/dev/null || echo "Management API not accessible"

echo "=== Health Check Complete ==="
EOF

sudo chmod +x /usr/local/bin/rabbitmq-health-check.sh
```

---

## 🚀 Step 10: Application Integration

### 10.1 Connection Examples

**Java/Spring Boot (application.yml):**
```yaml
spring:
  rabbitmq:
    host: YOUR_VM_IP
    port: 5672
    username: myapp_user
    password: App_User_Password_2024!
    virtual-host: /
```

**Python (pika):**
```python
import pika

credentials = pika.PlainCredentials('myapp_user', 'App_User_Password_2024!')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('YOUR_VM_IP', 5672, '/', credentials)
)
```

**Node.js (amqplib):**
```javascript
const amqp = require('amqplib');

const connection = await amqp.connect({
  hostname: 'YOUR_VM_IP',
  port: 5672,
  username: 'myapp_user',
  password: 'App_User_Password_2024!',
  vhost: '/'
});
```

---

## 🔧 Step 11: Maintenance Commands

### 11.1 Service Management
```bash
# Start/Stop/Restart service
sudo systemctl start rabbitmq-server
sudo systemctl stop rabbitmq-server
sudo systemctl restart rabbitmq-server

# View logs
sudo journalctl -u rabbitmq-server -f
sudo tail -f /var/log/rabbitmq/rabbit.log
```

### 11.2 User Management
```bash
# List users
sudo rabbitmqctl list_users

# Add user
sudo rabbitmqctl add_user username password

# Delete user
sudo rabbitmqctl delete_user username

# Change password
sudo rabbitmqctl change_password username newpassword
```

### 11.3 Queue Management
```bash
# List queues
sudo rabbitmqctl list_queues

# List exchanges
sudo rabbitmqctl list_exchanges

# Purge queue
sudo rabbitmqctl purge_queue queue_name
```

### 11.4 Backup and Restore
```bash
# Backup definitions
curl -u myapp_admin:Strong_Password_2024! \
  http://localhost:15672/api/definitions > rabbitmq-backup-$(date +%Y%m%d).json

# Restore definitions
curl -u myapp_admin:Strong_Password_2024! \
  -X POST -H "content-type:application/json" \
  -d @rabbitmq-backup-$(date +%Y%m%d).json \
  http://localhost:15672/api/definitions
```

---

## 🏁 Quick Verification Checklist

- [ ] RabbitMQ service is running: `sudo systemctl status rabbitmq-server`
- [ ] Management UI accessible: http://YOUR_VM_IP:15672
- [ ] Cluster name correct: `sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().'`
- [ ] Firewall ports open: `sudo firewall-cmd --list-ports`
- [ ] Users created and working
- [ ] Application can connect successfully
- [ ] Monitoring metrics available: http://YOUR_VM_IP:15672/metrics

---

## 📝 Production Notes

1. **Change default passwords** in production
2. **Enable TLS** for secure communication
3. **Configure backup strategy** for data persistence
4. **Set up monitoring alerts** for critical metrics
5. **Document connection strings** for applications
6. **Plan for capacity scaling** as usage grows

Your RabbitMQ 4.x single-node cluster is now deployed and ready on RHEL8!