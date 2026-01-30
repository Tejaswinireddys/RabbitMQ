# RabbitMQ 4.1.4 Three-Node Cluster Deployment Guide

## Prerequisites

- 3 servers with RabbitMQ 4.1.4 installed
- Minimum 8GB RAM per node (16GB+ recommended)
- SSD storage with at least 50GB free space
- Network connectivity between all nodes on ports: 4369, 5672, 15672, 25672, 15692

## File Overview

| File | Purpose |
|------|---------|
| `rabbitmq.conf` | Main configuration file |
| `advanced.config` | Erlang-specific advanced settings |
| `enabled_plugins` | List of enabled plugins |

## Deployment Steps

### 1. Set Hostnames

Ensure each node has a resolvable hostname. Update `/etc/hosts` on all nodes:

```bash
192.168.1.10  rabbitmq-node-1
192.168.1.11  rabbitmq-node-2
192.168.1.12  rabbitmq-node-3
```

### 2. Erlang Cookie (CRITICAL)

All nodes MUST share the same Erlang cookie for cluster communication.

Generate a secure cookie:
```bash
openssl rand -hex 32
```

Place in `/var/lib/rabbitmq/.erlang.cookie` on ALL nodes:
```bash
echo "YOUR_GENERATED_COOKIE_HERE" > /var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
```

### 3. Copy Configuration Files

```bash
# Copy to each node
scp rabbitmq.conf enabled_plugins advanced.config root@rabbitmq-node-1:/etc/rabbitmq/
scp rabbitmq.conf enabled_plugins advanced.config root@rabbitmq-node-2:/etc/rabbitmq/
scp rabbitmq.conf enabled_plugins advanced.config root@rabbitmq-node-3:/etc/rabbitmq/

# Set permissions
ssh root@rabbitmq-node-X "chown rabbitmq:rabbitmq /etc/rabbitmq/*"
```

### 4. Update Node-Specific Settings

Edit `rabbitmq.conf` on each node to update:
- `default_pass` - Set a strong unique password
- Node hostnames if different from template

### 5. Start Cluster

Start RabbitMQ on each node (start node-1 first):
```bash
# On each node
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
```

### 6. Verify Cluster Status

```bash
rabbitmqctl cluster_status
```

Expected output shows all 3 nodes as running.

### 7. Create Production Users

```bash
# Delete default admin user after creating proper users
rabbitmqctl add_user production_admin "STRONG_PASSWORD_HERE"
rabbitmqctl set_user_tags production_admin administrator
rabbitmqctl set_permissions -p / production_admin ".*" ".*" ".*"

# Create application user with limited permissions
rabbitmqctl add_user app_user "APP_PASSWORD_HERE"
rabbitmqctl set_permissions -p / app_user "^app\." "^app\." "^app\."

# Delete the default admin
rabbitmqctl delete_user admin
```

## TLS/SSL Configuration

For production, enable TLS:

1. Generate certificates (use your CA):
```bash
mkdir -p /etc/rabbitmq/ssl
# Place ca_certificate.pem, server_certificate.pem, server_key.pem
chmod 600 /etc/rabbitmq/ssl/*
chown rabbitmq:rabbitmq /etc/rabbitmq/ssl/*
```

2. Uncomment TLS sections in `rabbitmq.conf`

3. Restart RabbitMQ

## Firewall Rules

```bash
# AMQP
firewall-cmd --permanent --add-port=5672/tcp
# AMQPS (TLS)
firewall-cmd --permanent --add-port=5671/tcp
# Management UI
firewall-cmd --permanent --add-port=15672/tcp
# Erlang distribution
firewall-cmd --permanent --add-port=25672/tcp
# EPMD
firewall-cmd --permanent --add-port=4369/tcp
# Prometheus metrics
firewall-cmd --permanent --add-port=15692/tcp
firewall-cmd --reload
```

## Monitoring

### Prometheus Scrape Config

```yaml
- job_name: 'rabbitmq'
  static_configs:
    - targets:
      - 'rabbitmq-node-1:15692'
      - 'rabbitmq-node-2:15692'
      - 'rabbitmq-node-3:15692'
  metrics_path: /metrics
```

### Key Metrics to Monitor

- `rabbitmq_queue_messages` - Queue depth
- `rabbitmq_queue_consumers` - Consumer count
- `rabbitmq_connections` - Connection count
- `rabbitmq_process_resident_memory_bytes` - Memory usage
- `rabbitmq_disk_space_available_bytes` - Available disk
- `rabbitmq_cluster_members` - Cluster health

## Maintenance Operations

### Rolling Restart
```bash
# On each node, one at a time:
rabbitmqctl stop_app
rabbitmqctl start_app
# Wait for sync before proceeding to next node
rabbitmqctl await_online_nodes 3
```

### Drain Node for Maintenance
```bash
rabbitmqctl drain
# Perform maintenance
rabbitmqctl revive
```

### Check Queue Sync Status
```bash
rabbitmqctl list_queues name type leader online
```

## Troubleshooting

### Node Won't Join Cluster
```bash
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app
```

### Check Logs
```bash
tail -f /var/log/rabbitmq/rabbit*.log
```

### Memory Issues
```bash
rabbitmqctl status | grep -A 20 memory
```

## Backup Strategy

```bash
# Export definitions (users, vhosts, queues, exchanges, bindings)
rabbitmqctl export_definitions /backup/definitions-$(date +%Y%m%d).json

# Backup Mnesia database (stop node first for consistency)
tar -czf /backup/mnesia-$(date +%Y%m%d).tar.gz /var/lib/rabbitmq/mnesia/
```
