# RabbitMQ 4.1.x OS Requirements and Settings Document

## Document Information
- **Version**: 1.0
- **Date**: August 2025
- **Environment**: RHEL 8.x Production Deployment
- **RabbitMQ Version**: 4.1.x
- **Cluster Size**: 3 Nodes

## 1. Hardware Requirements

### 1.1 QA Environment Specifications
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 vCPU | 4 vCPU |
| Memory | 8 GB RAM | 12 GB RAM |
| Storage | 100 GB | 200 GB |
| Network | 1 Gbps | 1 Gbps |
| IOPS | 1000 | 3000 |

### 1.2 Production Environment Specifications
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 vCPU | 8 vCPU |
| Memory | 16 GB RAM | 32 GB RAM |
| Storage | 500 GB | 1 TB |
| Network | 1 Gbps | 10 Gbps |
| IOPS | 3000 | 10000 |

### 1.3 Disk Configuration Requirements
```bash
# Recommended disk layout for production:
/                    50 GB    (Root filesystem)
/var/lib/rabbitmq   500 GB    (RabbitMQ data - dedicated partition)
/var/log/rabbitmq   50 GB     (RabbitMQ logs - dedicated partition)
/backup             200 GB    (Backup storage)
swap                16 GB     (Equal to RAM)

# File system recommendations:
Data partition: XFS with noatime,nodiratime options
Log partition:  XFS with noatime option
```

## 2. Operating System Requirements

### 2.1 Supported Operating Systems
- Red Hat Enterprise Linux (RHEL) 8.6+
- CentOS Stream 8
- Rocky Linux 8
- AlmaLinux 8

### 2.2 Kernel Version Requirements
- Minimum: 4.18.0-372.el8
- Recommended: Latest available for RHEL 8.x

### 2.3 Architecture Support
- x86_64 (Intel/AMD 64-bit)
- ARM64 (for cloud environments)

## 3. System Limits Configuration

### 3.1 File Descriptor Limits

#### QA Environment
```bash
# /etc/systemd/system/rabbitmq-server.service.d/limits.conf
[Service]
LimitNOFILE=65536
LimitNPROC=32768
User=rabbitmq
Group=rabbitmq
```

#### Production Environment
```bash
# /etc/systemd/system/rabbitmq-server.service.d/limits.conf
[Service]
LimitNOFILE=300000
LimitNPROC=300000
User=rabbitmq
Group=rabbitmq
```

### 3.2 System-wide Limits
```bash
# /etc/security/limits.d/99-rabbitmq.conf

# QA Environment
*               soft    nofile          65536
*               hard    nofile          65536
*               soft    nproc           32768
*               hard    nproc           32768
rabbitmq        soft    nofile          65536
rabbitmq        hard    nofile          65536

# Production Environment (uncomment for production)
# *               soft    nofile          300000
# *               hard    nofile          300000
# *               soft    nproc           300000
# *               hard    nproc           300000
# rabbitmq        soft    nofile          300000
# rabbitmq        hard    nofile          300000
```

## 4. Kernel Parameter Tuning

### 4.1 Network Parameters

#### QA Environment
```bash
# /etc/sysctl.d/99-rabbitmq-qa.conf
net.core.somaxconn = 2048
net.core.netdev_max_backlog = 2500
net.core.rmem_default = 262144
net.core.rmem_max = 8388608
net.core.wmem_default = 262144
net.core.wmem_max = 8388608
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608
net.ipv4.tcp_max_syn_backlog = 2048
```

#### Production Environment
```bash
# /etc/sysctl.d/99-rabbitmq-prod.conf
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
net.ipv4.tcp_fin_timeout = 30

# Connection tracking for high load
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
```

### 4.2 Memory Management Parameters

#### QA Environment
```bash
# Memory settings for QA
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 0
```

#### Production Environment
```bash
# Memory settings for Production
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.overcommit_memory = 1
vm.min_free_kbytes = 1048576
vm.zone_reclaim_mode = 0
```

### 4.3 File System Parameters
```bash
# File system limits
fs.file-max = 2097152          # QA
fs.file-max = 4194304          # Production
fs.nr_open = 2097152           # QA  
fs.nr_open = 4194304           # Production
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

## 5. Time Synchronization Requirements

### 5.1 NTP/Chrony Configuration
```bash
# Install chrony
sudo dnf install -y chrony

# /etc/chrony.conf
pool 2.rhel.pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony

# Commands to execute
sudo systemctl enable chronyd
sudo systemctl start chronyd

# Verification
chrony sources -v
timedatectl status
```

### 5.2 Time Synchronization Validation
```bash
# Time drift tolerance: ±100ms maximum
# Check command:
chrony tracking

# Expected output should show:
# Stratum: 3 or less
# System time offset: < 100ms
```

## 6. Firewall Configuration

### 6.1 Required Ports

| Service | Port | Protocol | Source | Purpose |
|---------|------|----------|--------|---------|
| AMQP | 5672 | TCP | Application servers | Message queuing |
| AMQP SSL | 5671 | TCP | Application servers | Secure message queuing |
| Management | 15672 | TCP | Admin networks | Web management |
| Management SSL | 15671 | TCP | Admin networks | Secure web management |
| Inter-node | 25672 | TCP | Cluster nodes only | Node communication |
| EPMD | 4369 | TCP | Cluster nodes only | Port mapper |
| Erlang Distribution | 35672-35682 | TCP | Cluster nodes only | Erlang VM communication |
| Prometheus | 15692 | TCP | Monitoring servers | Metrics collection |

### 6.2 Firewall Rules Implementation

#### QA Environment
```bash
# QA firewall configuration
sudo firewall-cmd --permanent --add-port=5672/tcp
sudo firewall-cmd --permanent --add-port=15672/tcp
sudo firewall-cmd --permanent --add-port=25672/tcp
sudo firewall-cmd --permanent --add-port=4369/tcp
sudo firewall-cmd --permanent --add-port=35672-35682/tcp
sudo firewall-cmd --permanent --add-port=15692/tcp
sudo firewall-cmd --reload
```

#### Production Environment
```bash
# Production firewall (restrictive)
# AMQP from application subnets only
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.0/24" port port="5672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.0/24" port port="5671" protocol="tcp" accept'

# Management from admin subnets only  
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.40.0/24" port port="15672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.40.0/24" port port="15671" protocol="tcp" accept'

# Inter-node communication (specific IPs)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.11" port port="25672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.12" port port="25672" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.20.13" port port="25672" protocol="tcp" accept'

# Prometheus monitoring
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.50.0/24" port port="15692" protocol="tcp" accept'

sudo firewall-cmd --reload
```

## 7. SELinux Configuration

### 7.1 SELinux Settings for RabbitMQ

#### Option 1: Permissive Mode (Easier but less secure)
```bash
# Set SELinux to permissive
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Verify
sestatus
```

#### Option 2: Enforcing Mode with Custom Policy (Recommended for Production)
```bash
# Install policy tools
sudo dnf install -y policycoreutils-python-utils

# Set boolean values for RabbitMQ
sudo setsebool -P nis_enabled 1
sudo setsebool -P allow_execheap 1

# Configure ports for SELinux
sudo semanage port -a -t amqp_port_t -p tcp 25672
sudo semanage port -a -t http_port_t -p tcp 15672
sudo semanage port -a -t http_port_t -p tcp 15671

# Create custom SELinux module for RabbitMQ (if needed)
# This would require analysis of audit logs and custom policy creation
```

## 8. User and Permission Configuration

### 8.1 RabbitMQ User Setup
```bash
# Create rabbitmq user (usually done by package installation)
sudo useradd -r -s /bin/false -d /var/lib/rabbitmq rabbitmq

# Set directory ownership
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq

# Set permissions
sudo chmod 755 /var/lib/rabbitmq
sudo chmod 755 /var/log/rabbitmq
sudo chmod 755 /etc/rabbitmq
```

### 8.2 sudo Configuration for Administration
```bash
# /etc/sudoers.d/rabbitmq-admin
# Allow rabbitmq-admin group to manage RabbitMQ
%rabbitmq-admin ALL=(ALL) NOPASSWD: /usr/sbin/rabbitmqctl, /usr/sbin/rabbitmq-plugins, /bin/systemctl start rabbitmq-server, /bin/systemctl stop rabbitmq-server, /bin/systemctl restart rabbitmq-server, /bin/systemctl status rabbitmq-server
```

## 9. Storage Configuration

### 9.1 Disk Mount Options

#### Data Partition (/var/lib/rabbitmq)
```bash
# /etc/fstab entry for RabbitMQ data partition
/dev/mapper/vg_data-lv_rabbitmq /var/lib/rabbitmq xfs defaults,noatime,nodiratime,nobarrier 0 2

# Mount options explanation:
# noatime: Don't update access times
# nodiratime: Don't update directory access times  
# nobarrier: Disable write barriers for performance (use with battery-backed RAID)
```

#### Log Partition (/var/log/rabbitmq)
```bash
# /etc/fstab entry for RabbitMQ log partition
/dev/mapper/vg_data-lv_rabbitmq_logs /var/log/rabbitmq xfs defaults,noatime 0 2
```

### 9.2 Disk I/O Scheduler
```bash
# Set I/O scheduler for better performance
# For SSD storage:
echo noop > /sys/block/sda/queue/scheduler

# For traditional spinning disks:
echo deadline > /sys/block/sda/queue/scheduler

# Make permanent by adding to /etc/default/grub:
# GRUB_CMDLINE_LINUX="elevator=deadline"
```

## 10. Memory Configuration

### 10.1 Swap Configuration

#### QA Environment
```bash
# Swap size: Equal to RAM (8GB for QA)
# /etc/fstab
/dev/mapper/vg_system-lv_swap swap swap defaults 0 0

# Swappiness setting
echo 'vm.swappiness = 10' >> /etc/sysctl.d/99-rabbitmq-qa.conf
```

#### Production Environment
```bash
# Swap size: Equal to RAM (16GB+ for production)
# Minimal swap usage
echo 'vm.swappiness = 1' >> /etc/sysctl.d/99-rabbitmq-prod.conf

# Consider disabling swap for high-performance environments
# swapoff -a
# Comment out swap in /etc/fstab
```

### 10.2 Transparent Huge Pages
```bash
# Disable transparent huge pages for better performance
echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent
sudo tee -a /etc/rc.local << 'EOF'
#!/bin/bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF

sudo chmod +x /etc/rc.local
```

## 11. Network Configuration Requirements

### 11.1 Hostname Configuration
```bash
# Set static hostnames
# QA Environment:
sudo hostnamectl set-hostname qa-rmq-01.company.local   # Node 1
sudo hostnamectl set-hostname qa-rmq-02.company.local   # Node 2
sudo hostnamectl set-hostname qa-rmq-03.company.local   # Node 3

# Production Environment:
sudo hostnamectl set-hostname prod-rmq-01.company.local # Node 1
sudo hostnamectl set-hostname prod-rmq-02.company.local # Node 2
sudo hostnamectl set-hostname prod-rmq-03.company.local # Node 3

# Verify hostname resolution
getent hosts $(hostname)
```

### 11.2 DNS Configuration
```bash
# /etc/hosts entries for cluster nodes
# QA Environment
10.10.10.11    qa-rmq-01.company.local qa-rmq-01
10.10.10.12    qa-rmq-02.company.local qa-rmq-02
10.10.10.13    qa-rmq-03.company.local qa-rmq-03

# Production Environment
10.20.20.11    prod-rmq-01.company.local prod-rmq-01
10.20.20.12    prod-rmq-02.company.local prod-rmq-02
10.20.20.13    prod-rmq-03.company.local prod-rmq-03
10.20.20.10    rabbitmq-cluster.company.local
```

### 11.3 Network Interface Configuration
```bash
# Static IP configuration example for RHEL 8
# /etc/sysconfig/network-scripts/ifcfg-eth0

TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
IPV6INIT=no
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=10.20.20.11     # Adjust for each node
PREFIX=24
GATEWAY=10.20.20.1
DNS1=8.8.8.8
DNS2=8.8.4.4
```

## 12. Monitoring and Logging Requirements

### 12.1 System Monitoring Tools
```bash
# Install required monitoring packages
sudo dnf install -y sysstat iotop htop nethogs tcpdump

# Enable system statistics collection
sudo systemctl enable sysstat
sudo systemctl start sysstat

# Configure sysstat collection interval
# /etc/sysconfig/sysstat
HISTORY=30
COMPRESSAFTER=7
SADC_OPTIONS="-S DISK"
```

### 12.2 Log Rotation Configuration
```bash
# /etc/logrotate.d/rabbitmq
/var/log/rabbitmq/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 rabbitmq rabbitmq
    postrotate
        systemctl reload rabbitmq-server > /dev/null 2>&1 || true
    endscript
}

# For production, use smaller rotation intervals
/var/log/rabbitmq/*.log {
    size 100M
    missingok
    rotate 50
    compress
    delaycompress
    notifempty
    create 0644 rabbitmq rabbitmq
    postrotate
        systemctl reload rabbitmq-server > /dev/null 2>&1 || true
    endscript
}
```

## 13. Security Requirements

### 13.1 SSL/TLS Certificate Requirements
```bash
# Certificate directory structure
/etc/rabbitmq/ssl/
├── ca.pem              # Certificate Authority
├── server-cert.pem     # Server certificate
├── server-key.pem      # Server private key
└── client-cert.pem     # Client certificate (optional)

# Set proper permissions
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq/ssl/
sudo chmod 700 /etc/rabbitmq/ssl/
sudo chmod 600 /etc/rabbitmq/ssl/*.pem
```

### 13.2 Security Hardening
```bash
# Disable unnecessary services
sudo systemctl disable cups
sudo systemctl disable avahi-daemon
sudo systemctl disable bluetooth

# Configure SSH hardening
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
Protocol 2
ClientAliveInterval 300
ClientAliveCountMax 2
```

## 14. System Validation Scripts

### 14.1 Pre-Installation Validation
```bash
#!/bin/bash
# pre_install_validation.sh

echo "=== RabbitMQ Pre-Installation System Validation ==="

# Check OS version
echo "OS Version: $(cat /etc/redhat-release)"

# Check kernel version
echo "Kernel: $(uname -r)"

# Check memory
total_mem=$(free -g | awk '/^Mem:/{print $2}')
echo "Total Memory: ${total_mem}GB"
if [ $total_mem -lt 8 ]; then
    echo "WARNING: Memory less than 8GB"
fi

# Check disk space
disk_space=$(df -h /var | tail -1 | awk '{print $4}')
echo "Available disk space on /var: $disk_space"

# Check network connectivity
for node in node1 node2 node3; do
    ping -c 1 $node >/dev/null 2>&1 && echo "$node: Reachable" || echo "$node: NOT reachable"
done

# Check time synchronization
if systemctl is-active chronyd >/dev/null; then
    echo "Time synchronization: Active"
else
    echo "WARNING: Time synchronization not active"
fi

# Check firewall status
echo "Firewall status: $(systemctl is-active firewalld)"

# Check SELinux
echo "SELinux: $(sestatus | grep 'Current mode' | awk '{print $3}')"

echo "Validation completed!"
```

### 14.2 Post-Installation Validation
```bash
#!/bin/bash
# post_install_validation.sh

echo "=== RabbitMQ Post-Installation System Validation ==="

# Check system limits
echo "Current file descriptor limit: $(ulimit -n)"
echo "Required: 65536+ for QA, 300000+ for Production"

# Check kernel parameters
echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "vm.swappiness: $(cat /proc/sys/vm/swappiness)"

# Check RabbitMQ service
echo "RabbitMQ service: $(systemctl is-active rabbitmq-server)"

# Check RabbitMQ logs
if [ -f /var/log/rabbitmq/rabbit@$(hostname).log ]; then
    echo "RabbitMQ log file exists"
    tail -5 /var/log/rabbitmq/rabbit@$(hostname).log
else
    echo "WARNING: RabbitMQ log file not found"
fi

# Check cluster status
sudo rabbitmqctl cluster_status 2>/dev/null && echo "Cluster: OK" || echo "Cluster: Not configured"

echo "Post-installation validation completed!"
```

## 15. Compliance and Documentation

### 15.1 Change Control Requirements
- All OS configuration changes must be documented
- Changes must be tested in QA before production
- Configuration files must be version controlled
- Rollback procedures must be documented and tested

### 15.2 Documentation Requirements
- System configuration documentation
- Network diagram with IP addresses and ports
- Security policy documentation
- Monitoring and alerting configuration
- Backup and recovery procedures

### 15.3 Audit Requirements
- System configuration audit trail
- Security configuration compliance
- Performance baseline documentation
- Disaster recovery testing documentation

---

**Document Control:**
- **Created by**: System Administrator
- **Approved by**: Infrastructure Manager
- **Review Date**: Quarterly
- **Next Review**: November 2025