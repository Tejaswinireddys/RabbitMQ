# RabbitMQ 4.x Single Node Deployment Guide

## 🎯 Overview

This guide provides a complete setup for deploying RabbitMQ 4.x as a single-node cluster with static configuration, ready for application integration.

## 📋 Deployment Options

Choose your preferred deployment method:
- [Docker Deployment](#docker-deployment) (Recommended)
- [Native Installation](#native-installation)
- [Docker Compose](#docker-compose-deployment)

---

## 🐳 Docker Deployment

### 1. Create Configuration Directory
```bash
mkdir -p rabbitmq-config/{config,data,logs}
cd rabbitmq-config
```

### 2. RabbitMQ Configuration File
Create `config/rabbitmq.conf`:
```ini
# Cluster Configuration
cluster_name = myapp-rabbitmq-cluster
cluster_formation.peer_discovery_backend = classic_config

# Node Configuration
node_name = rabbit@rabbitmq-node1

# Network Configuration
listeners.tcp.default = 5672
listeners.ssl.default = 5671
management.listener.port = 15672
management.listener.ssl = false

# Memory and Disk Configuration
vm_memory_high_watermark.relative = 0.6
disk_free_limit.absolute = 2GB

# Performance Tuning
channel_max = 2000
heartbeat = 60
frame_max = 8192

# Logging Configuration
log.console = true
log.console.level = info
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info

# Management Plugin
management.rates_mode = basic
management.sample_retention_policies.global.minute = 5
management.sample_retention_policies.global.hour = 60
management.sample_retention_policies.global.day = 1200

# Security Configuration
auth_mechanisms.1 = PLAIN
auth_mechanisms.2 = AMQPLAIN
default_user = admin
default_pass = secure_password_change_me
default_user_tags.administrator = true
default_permissions.configure = .*
default_permissions.read = .*
default_permissions.write = .*

# Queue Configuration
queue_master_locator = min-masters
```

### 3. Enabled Plugins Configuration
Create `config/enabled_plugins`:
```erlang
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel,rabbitmq_shovel_management].
```

### 4. Environment Variables File
Create `.env`:
```env
RABBITMQ_CLUSTER_NAME=myapp-rabbitmq-cluster
RABBITMQ_NODE_NAME=rabbit@rabbitmq-node1
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=secure_password_change_me
RABBITMQ_ERLANG_COOKIE=my-secret-cookie-change-this
```

### 5. Docker Run Command
```bash
docker run -d \
  --name rabbitmq-single \
  --hostname rabbitmq-node1 \
  -p 5672:5672 \
  -p 15672:15672 \
  -p 5671:5671 \
  -p 15671:15671 \
  -p 25672:25672 \
  -e RABBITMQ_CLUSTER_NAME=myapp-rabbitmq-cluster \
  -e RABBITMQ_NODE_NAME=rabbit@rabbitmq-node1 \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=secure_password_change_me \
  -e RABBITMQ_ERLANG_COOKIE=my-secret-cookie-change-this \
  -v $(pwd)/config/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro \
  -v $(pwd)/config/enabled_plugins:/etc/rabbitmq/enabled_plugins:ro \
  -v $(pwd)/data:/var/lib/rabbitmq:Z \
  -v $(pwd)/logs:/var/log/rabbitmq:Z \
  --restart unless-stopped \
  rabbitmq:4-management
```

---

## 🐋 Docker Compose Deployment

### 1. Docker Compose File
Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  rabbitmq:
    image: rabbitmq:4-management
    container_name: rabbitmq-single
    hostname: rabbitmq-node1
    
    ports:
      - "5672:5672"      # AMQP port
      - "15672:15672"    # Management UI
      - "5671:5671"      # AMQPS port (SSL)
      - "15671:15671"    # Management UI (SSL)
      - "25672:25672"    # Inter-node communication
    
    environment:
      - RABBITMQ_CLUSTER_NAME=myapp-rabbitmq-cluster
      - RABBITMQ_NODE_NAME=rabbit@rabbitmq-node1
      - RABBITMQ_DEFAULT_USER=admin
      - RABBITMQ_DEFAULT_PASS=secure_password_change_me
      - RABBITMQ_ERLANG_COOKIE=my-secret-cookie-change-this
    
    volumes:
      - ./config/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro
      - ./config/enabled_plugins:/etc/rabbitmq/enabled_plugins:ro
      - ./data:/var/lib/rabbitmq:Z
      - ./logs:/var/log/rabbitmq:Z
    
    restart: unless-stopped
    
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

networks:
  default:
    name: rabbitmq-network
```

### 2. Deploy with Docker Compose
```bash
# Start the service
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f rabbitmq
```

---

## 💻 Native Installation

### 1. Installation (Ubuntu/Debian)
```bash
# Install Erlang 26+ (required for RabbitMQ 4.x)
sudo apt-get update
sudo apt-get install -y erlang-base erlang-asn1 erlang-crypto erlang-eldap \
                        erlang-ftp erlang-inets erlang-mnesia erlang-os-mon \
                        erlang-parsetools erlang-public-key erlang-runtime-tools \
                        erlang-snmp erlang-ssl erlang-syntax-tools erlang-tftp \
                        erlang-tools erlang-xmerl

# Add RabbitMQ repository
curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/ubuntu/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/rabbitmq.list

# Install RabbitMQ 4.x
sudo apt-get update
sudo apt-get install -y rabbitmq-server=4.*
```

### 2. Configuration Files
Create `/etc/rabbitmq/rabbitmq.conf`:
```ini
# Use the same configuration as shown in Docker section above
```

Create `/etc/rabbitmq/enabled_plugins`:
```erlang
[rabbitmq_management,rabbitmq_prometheus,rabbitmq_shovel,rabbitmq_shovel_management].
```

### 3. Environment Configuration
Create `/etc/rabbitmq/rabbitmq-env.conf`:
```bash
RABBITMQ_CLUSTER_NAME=myapp-rabbitmq-cluster
RABBITMQ_NODE_NAME=rabbit@$(hostname)
RABBITMQ_ERLANG_COOKIE=my-secret-cookie-change-this
```

### 4. Service Management
```bash
# Start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Check status
sudo systemctl status rabbitmq-server

# View logs
sudo journalctl -u rabbitmq-server -f
```

---

## 🔧 Management and Verification

### 1. Access Management UI
- URL: http://localhost:15672
- Username: admin
- Password: secure_password_change_me

### 2. Command Line Management
```bash
# Check cluster status
sudo rabbitmqctl cluster_status

# Check node status
sudo rabbitmqctl status

# List queues
sudo rabbitmqctl list_queues

# List exchanges
sudo rabbitmqctl list_exchanges

# List users
sudo rabbitmqctl list_users
```

### 3. Application Connection Testing
```bash
# Test AMQP connection
telnet localhost 5672

# Test Management API
curl -u admin:secure_password_change_me http://localhost:15672/api/overview
```

---

## 🚀 Application Integration

### 1. Connection String Examples

**Spring Boot (application.yml):**
```yaml
spring:
  rabbitmq:
    host: localhost
    port: 5672
    username: admin
    password: secure_password_change_me
    virtual-host: /
```

**Node.js (amqplib):**
```javascript
const amqp = require('amqplib');

const connection = await amqp.connect({
  hostname: 'localhost',
  port: 5672,
  username: 'admin',
  password: 'secure_password_change_me',
  vhost: '/'
});
```

**Python (pika):**
```python
import pika

credentials = pika.PlainCredentials('admin', 'secure_password_change_me')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', 5672, '/', credentials)
)
```

### 2. Health Check Endpoint
```bash
# Application health check
curl http://localhost:15672/api/healthchecks/node
```

---

## 🔒 Security Considerations

### 1. Change Default Credentials
```bash
# Add new admin user
sudo rabbitmqctl add_user myapp_user strong_password
sudo rabbitmqctl set_user_tags myapp_user administrator
sudo rabbitmqctl set_permissions -p / myapp_user ".*" ".*" ".*"

# Delete default user (optional)
sudo rabbitmqctl delete_user admin
```

### 2. Enable TLS (Optional)
Create TLS certificates and update configuration:
```ini
# Add to rabbitmq.conf
listeners.ssl.default = 5671
ssl_options.cacertfile = /etc/rabbitmq/certs/ca_certificate.pem
ssl_options.certfile   = /etc/rabbitmq/certs/server_certificate.pem
ssl_options.keyfile    = /etc/rabbitmq/certs/server_key.pem
ssl_options.verify     = verify_peer
ssl_options.fail_if_no_peer_cert = false
```

---

## 📊 Monitoring and Maintenance

### 1. Prometheus Metrics
Access metrics at: http://localhost:15672/metrics

### 2. Log Locations
- Docker: `./logs/` directory
- Native: `/var/log/rabbitmq/`

### 3. Backup Strategy
```bash
# Backup definitions
curl -u admin:password http://localhost:15672/api/definitions > backup.json

# Restore definitions
curl -u admin:password -X POST -H "content-type:application/json" \
     -d @backup.json http://localhost:15672/api/definitions
```

---

## 🏁 Quick Start Commands

### Docker (Recommended)
```bash
mkdir rabbitmq-single && cd rabbitmq-single
# Copy configuration files from above
docker-compose up -d
```

### Verification
```bash
# Check if running
docker ps | grep rabbitmq

# Access Management UI
open http://localhost:15672
```

Your single-node RabbitMQ 4.x cluster is now ready for application integration!