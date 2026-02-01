# Redis 8.2.2 Installation Guide

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 16+ GB |
| Disk | 20 GB SSD | 100+ GB NVMe SSD |
| Network | 1 Gbps | 10 Gbps |

### Software Requirements

- Operating System: RHEL 8/9, Ubuntu 20.04/22.04, Debian 11/12
- GCC 8+ (for compilation)
- OpenSSL development libraries
- systemd (for service management)

### Network Requirements

| Port | Protocol | Purpose |
|------|----------|---------|
| 6379 | TCP | Redis server |
| 26379 | TCP | Sentinel |

---

## Installation Steps

### Step 1: Prepare All Nodes

Run on ALL THREE nodes:

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y  # Debian/Ubuntu
# or
sudo yum update -y  # RHEL/CentOS

# Install dependencies
sudo apt-get install -y build-essential tcl pkg-config libssl-dev libsystemd-dev
# or
sudo yum groupinstall -y "Development Tools"
sudo yum install -y tcl openssl-devel systemd-devel

# Download installation scripts
git clone <repository-url>
cd redis-cluster-deployment/scripts
```

### Step 2: Create Redis User (All Nodes)

```bash
# Run as root
sudo ./01-setup-user.sh
```

This creates:
- User: `redis` (UID: 6379)
- Group: `redis` (GID: 6379)
- Directory: `/opt/cached/current`
- System limits and kernel parameters

### Step 3: Install Redis (All Nodes)

```bash
# Run as root
sudo ./02-install-redis.sh
```

This downloads and compiles Redis 8.2.2 with:
- TLS support
- systemd integration
- Installation to `/opt/cached/redis-8.2.2/`

### Step 4: Configure Master (Node 1)

```bash
# On Node 1 (Master)
# Replace IPs with your actual IPs

sudo -u redis ./03-configure-node.sh 1 10.0.1.1 10.0.1.1 YourSecurePassword
```

### Step 5: Configure Replicas (Nodes 2 and 3)

```bash
# On Node 2
sudo -u redis ./03-configure-node.sh 2 10.0.1.1 10.0.1.2 YourSecurePassword

# On Node 3
sudo -u redis ./03-configure-node.sh 3 10.0.1.1 10.0.1.3 YourSecurePassword
```

### Step 6: Start Services

Start in order: Master first, then Replicas.

```bash
# On Master (Node 1) first
sudo -u redis ./04-start-services.sh

# Wait 10 seconds, then on Node 2
sudo -u redis ./04-start-services.sh

# Wait 10 seconds, then on Node 3
sudo -u redis ./04-start-services.sh
```

### Step 7: Verify Cluster

```bash
# Check Redis
/opt/cached/current/bin/redis-cli -a YourSecurePassword INFO replication

# Check Sentinel
/opt/cached/current/bin/redis-cli -p 26379 SENTINEL master mymaster

# Run health check
./health-check.sh
```

---

## Installing systemd Services (Optional)

For automatic startup on boot:

```bash
# Copy service files
sudo cp systemd/redis.service /etc/systemd/system/
sudo cp systemd/redis-sentinel.service /etc/systemd/system/

# Update password in service file
sudo sed -i 's/REDIS_AUTH_PASSWORD_CHANGE_ME/YourSecurePassword/g' /etc/systemd/system/redis.service

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable redis
sudo systemctl enable redis-sentinel

# Start services
sudo systemctl start redis
sudo systemctl start redis-sentinel

# Check status
sudo systemctl status redis
sudo systemctl status redis-sentinel
```

---

## Post-Installation Verification

### Check Cluster Status

```bash
# On Master
redis-cli -a YourSecurePassword INFO replication
# Should show: role:master, connected_slaves:2

# On Replicas
redis-cli -a YourSecurePassword INFO replication
# Should show: role:slave, master_link_status:up

# Sentinel status (any node)
redis-cli -p 26379 SENTINEL master mymaster
# Should show master IP and status
```

### Test Replication

```bash
# On Master
redis-cli -a YourSecurePassword SET test:key "hello"

# On Replica
redis-cli -a YourSecurePassword GET test:key
# Should return: "hello"
```

### Test Failover

```bash
# Trigger manual failover
./failover.sh

# Or via Sentinel
redis-cli -p 26379 SENTINEL failover mymaster
```

---

## Troubleshooting

### Redis won't start

```bash
# Check logs
tail -100 /opt/cached/current/logs/redis.log

# Check configuration
/opt/cached/current/bin/redis-server /opt/cached/current/conf/redis.conf --test-memory 1

# Check permissions
ls -la /opt/cached/current/
```

### Replica won't connect to Master

```bash
# Check master is reachable
redis-cli -h MASTER_IP -p 6379 -a PASSWORD ping

# Check firewall
sudo iptables -L -n | grep 6379

# Check master password matches
grep masterauth /opt/cached/current/conf/redis.conf
grep requirepass /opt/cached/current/conf/redis.conf
```

### Sentinel not detecting nodes

```bash
# Check Sentinel logs
tail -100 /opt/cached/current/logs/sentinel.log

# Check Sentinel config
cat /opt/cached/current/conf/sentinel.conf

# Manual info
redis-cli -p 26379 SENTINEL master mymaster
redis-cli -p 26379 SENTINEL replicas mymaster
redis-cli -p 26379 SENTINEL sentinels mymaster
```
