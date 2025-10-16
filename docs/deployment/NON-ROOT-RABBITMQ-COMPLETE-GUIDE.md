# RabbitMQ 4.1.x Non-Root Complete Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [System Requirements](#system-requirements)
4. [Installation Process](#installation-process)
5. [Configuration](#configuration)
6. [Cluster Setup](#cluster-setup)
7. [Management Scripts](#management-scripts)
8. [Monitoring and Maintenance](#monitoring-and-maintenance)
9. [Troubleshooting](#troubleshooting)
10. [Security Considerations](#security-considerations)
11. [Backup and Recovery](#backup-and-recovery)

## Overview

This guide provides a comprehensive solution for installing and managing RabbitMQ 4.1.x cluster as a non-root user with minimal sudo privileges. The solution includes:

- **Minimal sudo privileges**: Only required commands are granted sudo access
- **Complete automation**: Scripts for installation, configuration, and management
- **Cluster support**: Full cluster setup and management capabilities
- **Monitoring**: Comprehensive monitoring and health checks
- **Security**: Secure configuration with proper user management

## Prerequisites

### User Account Setup
```bash
# Create dedicated user account
sudo useradd -m -s /bin/bash rabbitmq-admin
sudo usermod -aG wheel rabbitmq-admin

# Set password
sudo passwd rabbitmq-admin
```

### Required Sudo Privileges
The system administrator must configure the following sudoers file:

```bash
# Copy to /etc/sudoers.d/rabbitmq-deployment
sudo cp ~/rabbitmq-deployment/sudoers-rabbitmq.conf /etc/sudoers.d/rabbitmq-deployment
```

**Sudoers Configuration:**
```
# User alias for RabbitMQ admin
User_Alias RABBITMQ_ADMINS = rabbitmq-admin

# Command aliases for RabbitMQ operations
Cmnd_Alias RABBITMQ_INSTALL = /usr/bin/dnf install *, /usr/bin/rpm --import *, /usr/bin/tee /etc/yum.repos.d/*
Cmnd_Alias RABBITMQ_SERVICE = /usr/bin/systemctl * rabbitmq-server, /usr/sbin/rabbitmqctl *, /usr/sbin/rabbitmq-plugins *
Cmnd_Alias RABBITMQ_CONFIG = /usr/bin/tee /etc/rabbitmq/*, /usr/bin/mkdir -p /etc/rabbitmq/*, /usr/bin/chown *, /usr/bin/chmod *
Cmnd_Alias RABBITMQ_FIREWALL = /usr/bin/firewall-cmd *
Cmnd_Alias RABBITMQ_SYSCTL = /usr/sbin/sysctl *, /usr/bin/tee /etc/sysctl.d/*, /usr/bin/tee /etc/systemd/system/*
Cmnd_Alias RABBITMQ_LIMITS = /usr/bin/tee /etc/security/limits.d/*, /usr/bin/tee -a /etc/security/limits.conf
Cmnd_Alias RABBITMQ_HOSTS = /usr/bin/tee -a /etc/hosts, /usr/bin/hostnamectl set-hostname *
Cmnd_Alias RABBITMQ_PROCESS = /usr/bin/pkill -f rabbitmq, /usr/bin/ps aux | grep rabbitmq

# Grant permissions
RABBITMQ_ADMINS ALL=(ALL) NOPASSWD: RABBITMQ_INSTALL, RABBITMQ_SERVICE, RABBITMQ_CONFIG, RABBITMQ_FIREWALL, RABBITMQ_SYSCTL, RABBITMQ_LIMITS, RABBITMQ_HOSTS, RABBITMQ_PROCESS
```

## System Requirements

### Hardware Requirements
- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB+ recommended for production
- **Disk**: 20GB+ free space for data and logs
- **Network**: Stable network connectivity between cluster nodes

### Software Requirements
- **OS**: RHEL 8.x or CentOS 8.x
- **Erlang**: 26.x (automatically installed)
- **RabbitMQ**: 4.1.x
- **Firewall**: firewalld (for network security)

### Network Requirements
- **AMQP Port**: 5672 (application connections)
- **Management Port**: 15672 (web interface)
- **Clustering Port**: 25672 (inter-node communication)
- **EPMD Port**: 4369 (Erlang port mapper)
- **Node Communication**: 35672-35682 (dynamic range)

## Installation Process

### Step 1: Initial Setup
```bash
# Switch to rabbitmq-admin user
su - rabbitmq-admin

# Run the setup script
cd /path/to/rabbitmq/scripts/installation
chmod +x non-root-rabbitmq-setup.sh
./non-root-rabbitmq-setup.sh
```

### Step 2: System Preparation
```bash
cd ~/rabbitmq-deployment
./scripts/01-system-preparation.sh
```

This script will:
- Update system packages
- Install EPEL repository
- Install required packages (curl, wget, gnupg2, socat, logrotate, erlang)

### Step 3: Repository Configuration
```bash
./scripts/02-repo-setup.sh
```

This script will:
- Configure RabbitMQ repository
- Import GPG keys
- Set up package signing

### Step 4: RabbitMQ Installation
```bash
./scripts/03-rabbitmq-install.sh
```

This script will:
- Install RabbitMQ 4.1.x
- Create necessary directories
- Set proper ownership and permissions

### Step 5: System Limits Configuration
```bash
./scripts/04-system-limits.sh
```

This script will:
- Configure systemd service limits
- Set system-wide limits
- Reload systemd configuration

### Step 6: Kernel Parameters
```bash
./scripts/05-kernel-params.sh
```

This script will:
- Configure kernel parameters for production/QA
- Apply network and memory optimizations
- Set file system limits

### Step 7: Firewall Configuration
```bash
./scripts/06-firewall-config.sh
```

This script will:
- Configure firewall rules based on environment
- Set up network security
- Enable required ports

## Configuration

### RabbitMQ Configuration Files

#### Main Configuration (`rabbitmq.conf`)
```bash
# Network configuration
listeners.tcp.default = 5672
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Prometheus configuration
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0

# Memory configuration
vm_memory_high_watermark.relative = 0.6
vm_memory_high_watermark_paging_ratio = 0.5

# Disk configuration
disk_free_limit.relative = 2.0

# Logging configuration
log.console = true
log.console.level = info
log.file = true
log.file.level = info

# Cluster configuration
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@node1
cluster_formation.classic_config.nodes.2 = rabbit@node2
cluster_formation.classic_config.nodes.3 = rabbit@node3

# Network partition handling
cluster_partition_handling = pause_minority

# Default queue type for data safety
default_queue_type = quorum

# Heartbeat
heartbeat = 60

# Statistics collection
collect_statistics_interval = 10000
```

#### Advanced Configuration (`advanced.config`)
```erlang
[
  {rabbit, [
    {cluster_nodes, {['rabbit@node1', 'rabbit@node2', 'rabbit@node3'], disc}},
    {cluster_partition_handling, pause_minority},
    {tcp_listeners, [5672]},
    {num_tcp_acceptors, 10},
    {handshake_timeout, 10000},
    {vm_memory_high_watermark, 0.6},
    {heartbeat, 60},
    {channel_max, 2048},
    {connection_max, 2048},
    {collect_statistics_interval, 10000},
    {delegate_count, 16}
  ]},
  {rabbitmq_management, [
    {listener, [
      {port, 15672},
      {ip, "0.0.0.0"}
    ]}
  ]}
].
```

#### Enabled Plugins (`enabled_plugins`)
```
[rabbitmq_management,rabbitmq_management_agent,rabbitmq_prometheus,rabbitmq_federation,rabbitmq_shovel].
```

## Cluster Setup

### Step 1: Prepare All Nodes
Run the following on all three nodes:

```bash
# On each node
cd ~/rabbitmq-deployment
./scripts/07-cluster-setup.sh
```

### Step 2: Configure Primary Node (node1)
```bash
# Set hostname
sudo hostnamectl set-hostname node1

# Update /etc/hosts
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster Nodes
192.168.1.10    node1
192.168.1.11    node2
192.168.1.12    node3
EOF

# Start RabbitMQ
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server

# Create users
sudo rabbitmqctl add_user admin admin123
sudo rabbitmqctl set_user_tags admin administrator
sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

sudo rabbitmqctl add_user teja Teja@2024
sudo rabbitmqctl set_user_tags teja management
sudo rabbitmqctl set_permissions -p / teja ".*" ".*" ".*"

sudo rabbitmqctl add_user aswini Aswini@2024
sudo rabbitmqctl set_user_tags aswini management
sudo rabbitmqctl set_permissions -p / aswini ".*" ".*" ".*"

# Delete guest user
sudo rabbitmqctl delete_user guest
```

### Step 3: Configure Secondary Nodes (node2, node3)
```bash
# Set hostname
sudo hostnamectl set-hostname node2  # or node3

# Update /etc/hosts (same as node1)
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster Nodes
192.168.1.10    node1
192.168.1.11    node2
192.168.1.12    node3
EOF

# Start RabbitMQ
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server

# Join cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl start_app
```

### Step 4: Verify Cluster
```bash
# Check cluster status
sudo rabbitmqctl cluster_status

# Check node health
sudo rabbitmqctl node_health_check
```

## Management Scripts

### Service Management
```bash
# Start/stop/restart RabbitMQ
~/rabbitmq-deployment/scripts/manage-service.sh start
~/rabbitmq-deployment/scripts/manage-service.sh stop
~/rabbitmq-deployment/scripts/manage-service.sh restart
~/rabbitmq-deployment/scripts/manage-service.sh status
```

### Cluster Management
```bash
# Check cluster status
~/rabbitmq-deployment/scripts/manage-cluster.sh status

# Join cluster
~/rabbitmq-deployment/scripts/manage-cluster.sh join node1

# Leave cluster
~/rabbitmq-deployment/scripts/manage-cluster.sh leave

# List cluster nodes
~/rabbitmq-deployment/scripts/manage-cluster.sh nodes
```

### User Management
```bash
# List users
~/rabbitmq-deployment/scripts/manage-users.sh list

# Add user
~/rabbitmq-deployment/scripts/manage-users.sh add username password

# Delete user
~/rabbitmq-deployment/scripts/manage-users.sh delete username

# Change password
~/rabbitmq-deployment/scripts/manage-users.sh change-password username newpassword
```

### Advanced Management Scripts

#### Cluster Manager
```bash
# Comprehensive cluster management
~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh overview
~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh backup
~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh monitor
```

#### User Manager
```bash
# Comprehensive user management
~/rabbitmq-deployment/scripts/non-root-user-manager.sh list-users
~/rabbitmq-deployment/scripts/non-root-user-manager.sh create-default-users
~/rabbitmq-deployment/scripts/non-root-user-manager.sh export-definitions
```

## Monitoring and Maintenance

### Health Checks
```bash
# Basic health check
~/rabbitmq-deployment/scripts/validate-setup.sh

# Comprehensive health check
~/rabbitmq-deployment/scripts/non-root-monitoring.sh health-check

# Generate monitoring report
~/rabbitmq-deployment/scripts/non-root-monitoring.sh generate-report
```

### Real-time Monitoring
```bash
# Start real-time monitoring
~/rabbitmq-deployment/scripts/non-root-monitoring.sh real-time

# Check specific metrics
~/rabbitmq-deployment/scripts/non-root-monitoring.sh system-metrics
~/rabbitmq-deployment/scripts/non-root-monitoring.sh rabbitmq-metrics
```

### Performance Monitoring
```bash
# Performance metrics
~/rabbitmq-deployment/scripts/non-root-monitoring.sh performance-metrics

# Queue health
~/rabbitmq-deployment/scripts/non-root-monitoring.sh queue-health

# Memory usage
~/rabbitmq-deployment/scripts/non-root-monitoring.sh memory-usage
```

## Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check service status
sudo systemctl status rabbitmq-server

# Check logs
sudo journalctl -u rabbitmq-server -f

# Check RabbitMQ logs
sudo tail -f /var/log/rabbitmq/rabbit@$(hostname).log
```

#### Cluster Join Issues
```bash
# Reset and rejoin cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl start_app
```

#### Permission Issues
```bash
# Check sudo configuration
sudo -l

# Verify file ownership
ls -la /etc/rabbitmq/
ls -la /var/lib/rabbitmq/
ls -la /var/log/rabbitmq/

# Fix ownership if needed
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq/
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq/
```

#### Memory Issues
```bash
# Check memory usage
sudo rabbitmqctl status | grep -A 5 "Memory"

# Check for alarms
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'

# Check system memory
free -h
```

### Emergency Procedures
```bash
# Stop all RabbitMQ processes
sudo systemctl stop rabbitmq-server
sudo pkill -f rabbitmq

# Start in safe mode
sudo rabbitmq-server -detached

# Force cluster reset (CAUTION: Data loss possible)
sudo rabbitmqctl force_reset
```

## Security Considerations

### Network Security
- Configure firewall rules to restrict access
- Use VPN or private networks for cluster communication
- Enable SSL/TLS for production environments

### User Security
- Use strong passwords for all users
- Regularly rotate passwords
- Implement proper user roles and permissions
- Monitor user access and activities

### System Security
- Keep system and RabbitMQ updated
- Monitor system logs
- Implement proper backup procedures
- Use secure communication protocols

## Backup and Recovery

### Backup Procedures
```bash
# Create backup
~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh backup

# Export definitions
~/rabbitmq-deployment/scripts/non-root-user-manager.sh export-definitions backup.json
```

### Recovery Procedures
```bash
# Restore from backup
~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh restore /path/to/backup

# Import definitions
~/rabbitmq-deployment/scripts/non-root-user-manager.sh import-definitions backup.json
```

### Automated Backup
```bash
# Create cron job for automated backups
crontab -e

# Add the following line for daily backups at 2 AM
0 2 * * * ~/rabbitmq-deployment/scripts/non-root-cluster-manager.sh backup
```

## Quick Reference

### Essential Commands
```bash
# Service management
sudo systemctl start|stop|restart|status rabbitmq-server

# Cluster management
sudo rabbitmqctl cluster_status
sudo rabbitmqctl join_cluster rabbit@node1
sudo rabbitmqctl stop_app
sudo rabbitmqctl start_app

# User management
sudo rabbitmqctl list_users
sudo rabbitmqctl add_user username password
sudo rabbitmqctl delete_user username

# Monitoring
sudo rabbitmqctl status
sudo rabbitmqctl node_health_check
sudo rabbitmqctl list_queues
sudo rabbitmqctl list_connections
```

### Management Scripts
```bash
# Service management
~/rabbitmq-deployment/scripts/manage-service.sh {start|stop|restart|status}

# Cluster management
~/rabbitmq-deployment/scripts/manage-cluster.sh {status|join|leave|nodes}

# User management
~/rabbitmq-deployment/scripts/manage-users.sh {list|add|delete|change-password}

# Monitoring
~/rabbitmq-deployment/scripts/non-root-monitoring.sh {health-check|real-time|generate-report}
```

### Configuration Files
- `/etc/rabbitmq/rabbitmq.conf` - Main configuration
- `/etc/rabbitmq/advanced.config` - Advanced Erlang configuration
- `/etc/rabbitmq/enabled_plugins` - Enabled plugins
- `/var/lib/rabbitmq/.erlang.cookie` - Erlang cookie
- `/var/log/rabbitmq/` - Log files

## Support and Maintenance

### Regular Maintenance Tasks
1. **Daily**: Check service status and logs
2. **Weekly**: Review performance metrics and disk usage
3. **Monthly**: Update system and RabbitMQ packages
4. **Quarterly**: Review and update security configurations

### Monitoring Alerts
Set up monitoring alerts for:
- Service status
- Memory usage
- Disk space
- Connection limits
- Queue health
- Cluster status

### Documentation Updates
Keep this documentation updated with:
- Configuration changes
- New procedures
- Troubleshooting solutions
- Security updates

---

This comprehensive guide provides everything needed to deploy and manage RabbitMQ 4.1.x as a non-root user with minimal sudo privileges. The solution is production-ready and includes all necessary scripts, configurations, and procedures for successful deployment and ongoing management.
