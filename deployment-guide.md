# RabbitMQ 4.1.x Cluster Deployment Guide for RHEL 8

## Prerequisites
- 3 RHEL 8 VMs with static IP addresses
- Root or sudo access on all VMs
- Network connectivity between all nodes
- Hostnames: node1, node2, node3

## Network Configuration

Update `/etc/hosts` on all nodes:
```
192.168.1.10    node1
192.168.1.11    node2
192.168.1.12    node3
```

## Deployment Steps

### 1. Install RabbitMQ on all nodes
```bash
# Copy install script to all nodes
scp install-rabbitmq-41.sh root@node1:/tmp/
scp install-rabbitmq-41.sh root@node2:/tmp/
scp install-rabbitmq-41.sh root@node3:/tmp/

# Run on each node
chmod +x /tmp/install-rabbitmq-41.sh
/tmp/install-rabbitmq-41.sh
```

### 2. Deploy configuration files
```bash
# Copy config files to all nodes
scp rabbitmq.conf advanced.config enabled_plugins definitions.json root@node1:/tmp/
scp rabbitmq.conf advanced.config enabled_plugins definitions.json root@node2:/tmp/
scp rabbitmq.conf advanced.config enabled_plugins definitions.json root@node3:/tmp/
```

### 3. Setup cluster
```bash
# Copy cluster setup script
scp cluster-setup.sh root@node1:/tmp/
scp cluster-setup.sh root@node2:/tmp/
scp cluster-setup.sh root@node3:/tmp/

# Run on node1 (primary)
chmod +x /tmp/cluster-setup.sh
/tmp/cluster-setup.sh -n node1 -i 192.168.1.10

# Run on node2
/tmp/cluster-setup.sh -n node2 -i 192.168.1.11

# Run on node3
/tmp/cluster-setup.sh -n node3 -i 192.168.1.12
```

## Data Safety Features

### Quorum Queues (Default)
- All queues are quorum queues by default
- Provides strong consistency and data safety
- Requires majority of nodes (2/3) for operations

### Network Partition Handling
- `pause_minority` strategy prevents split-brain
- Minority partition pauses until majority is available
- No data loss during network partitions

### Cluster Configuration
- 3-node cluster for optimal fault tolerance
- Can lose 1 node without data loss
- Automatic recovery when nodes rejoin

## Verification Commands

```bash
# Check cluster status
sudo rabbitmqctl cluster_status

# Check node health
sudo rabbitmqctl node_health_check

# List queues
sudo rabbitmqctl list_queues

# Check queue types
sudo rabbitmqctl list_queues name type

# Monitor cluster
sudo rabbitmqctl eval 'rabbit_mnesia:status().'
```

## Management Interface
- Access via: http://node1:15672, http://node2:15673, http://node3:15674
- Username: admin
- Password: admin123

## Monitoring and Alerts
- Prometheus metrics enabled on `/metrics` endpoint
- Monitor queue length, node status, memory usage
- Set alerts for node failures and network partitions

## Backup Strategy
```bash
# Export definitions
sudo rabbitmqctl export_definitions /backup/definitions.json

# Backup data directory
sudo tar -czf /backup/rabbitmq-data-$(date +%Y%m%d).tar.gz /var/lib/rabbitmq/
```

## Upgrade Process from 3.12
1. Stop applications using RabbitMQ
2. Backup current cluster
3. Upgrade one node at a time
4. Verify cluster health after each upgrade
5. Update configuration files
6. Restart applications

## Troubleshooting

### Node won't join cluster
```bash
# Reset and rejoin
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl start_app
```

### Check logs
```bash
sudo tail -f /var/log/rabbitmq/rabbit@nodeX.log
```

### Firewall issues
```bash
# Verify ports are open
sudo firewall-cmd --list-ports
```