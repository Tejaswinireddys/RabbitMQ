# Redis Cluster Operations Guide

## Daily Operations

### Health Checks

```bash
# Quick health check
./scripts/health-check.sh

# JSON output for monitoring
./scripts/health-check.sh --json

# Manual checks
redis-cli -a $PASSWORD ping
redis-cli -p 26379 ping
```

### Monitoring Commands

```bash
# Redis info
redis-cli -a $PASSWORD INFO

# Specific sections
redis-cli -a $PASSWORD INFO replication
redis-cli -a $PASSWORD INFO memory
redis-cli -a $PASSWORD INFO stats
redis-cli -a $PASSWORD INFO clients

# Real-time monitoring
redis-cli -a $PASSWORD MONITOR  # WARNING: High overhead

# Slow log
redis-cli -a $PASSWORD SLOWLOG GET 10
redis-cli -a $PASSWORD SLOWLOG RESET

# Client list
redis-cli -a $PASSWORD CLIENT LIST

# Memory analysis
redis-cli -a $PASSWORD MEMORY STATS
redis-cli -a $PASSWORD MEMORY DOCTOR
```

### Sentinel Monitoring

```bash
# Master info
redis-cli -p 26379 SENTINEL master mymaster

# Replicas
redis-cli -p 26379 SENTINEL replicas mymaster

# Other Sentinels
redis-cli -p 26379 SENTINEL sentinels mymaster

# Current master address
redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
```

---

## Service Management

### Start/Stop Services

```bash
# Using scripts
./scripts/04-start-services.sh all
./scripts/05-stop-services.sh all

# Using systemd (if configured)
sudo systemctl start redis
sudo systemctl start redis-sentinel
sudo systemctl stop redis-sentinel
sudo systemctl stop redis

# Service status
./scripts/04-start-services.sh status
sudo systemctl status redis redis-sentinel
```

### Restart with Minimal Impact

```bash
# For single node restart (Sentinel will manage failover)
# 1. On the node to restart:

# Stop Sentinel first
./scripts/05-stop-services.sh sentinel

# Stop Redis
./scripts/05-stop-services.sh redis

# Perform maintenance...

# Start Redis
./scripts/04-start-services.sh redis

# Wait for sync
sleep 10

# Start Sentinel
./scripts/04-start-services.sh sentinel
```

---

## Failover Operations

### Manual Failover

```bash
# Interactive failover
./scripts/failover.sh

# Force failover (no confirmation)
./scripts/failover.sh --force

# Via Sentinel CLI
redis-cli -p 26379 SENTINEL failover mymaster
```

### Failover Monitoring

```bash
# Watch failover progress
watch -n 1 'redis-cli -p 26379 SENTINEL master mymaster | grep -E "ip|port|flags"'

# Check failover status
redis-cli -p 26379 SENTINEL FAILOVER-STATUS mymaster
```

---

## Backup and Recovery

### Manual Backup

```bash
# Trigger backup
./scripts/backup.sh

# Backup to specific location
./scripts/backup.sh --destination /mnt/backup

# Trigger BGSAVE only
redis-cli -a $PASSWORD BGSAVE

# Check BGSAVE status
redis-cli -a $PASSWORD LASTSAVE
redis-cli -a $PASSWORD INFO persistence
```

### Scheduled Backups

```bash
# Add to crontab (as redis user)
crontab -e

# Daily backup at 2 AM
0 2 * * * /opt/cached/current/scripts/backup.sh >> /opt/cached/current/logs/backup.log 2>&1
```

### Recovery

```bash
# 1. Stop Redis
./scripts/05-stop-services.sh redis

# 2. Restore RDB file
cp /backup/redis/dump.rdb /opt/cached/current/data/

# 3. Fix permissions
chown redis:redis /opt/cached/current/data/dump.rdb

# 4. Start Redis
./scripts/04-start-services.sh redis

# 5. Verify data
redis-cli -a $PASSWORD DBSIZE
```

---

## Configuration Changes

### Runtime Configuration

```bash
# View current config
redis-cli -a $PASSWORD CONFIG GET maxmemory
redis-cli -a $PASSWORD CONFIG GET "*"

# Change runtime config
redis-cli -a $PASSWORD CONFIG SET maxmemory 16gb
redis-cli -a $PASSWORD CONFIG SET maxmemory-policy allkeys-lru

# Persist changes (writes to config file)
redis-cli -a $PASSWORD CONFIG REWRITE
```

### Persistent Configuration

```bash
# Edit config file
vi /opt/cached/current/conf/redis.conf

# Validate syntax
redis-server /opt/cached/current/conf/redis.conf --test-memory 1

# Restart to apply
./scripts/05-stop-services.sh redis
./scripts/04-start-services.sh redis
```

---

## Client Management

### Connection Management

```bash
# List all clients
redis-cli -a $PASSWORD CLIENT LIST

# Kill specific client
redis-cli -a $PASSWORD CLIENT KILL ID <client-id>

# Kill by pattern
redis-cli -a $PASSWORD CLIENT KILL TYPE normal

# Set client name
redis-cli -a $PASSWORD CLIENT SETNAME myapp
```

### Connection Limits

```bash
# Check current connections
redis-cli -a $PASSWORD INFO clients

# Set max clients
redis-cli -a $PASSWORD CONFIG SET maxclients 10000
```

---

## Memory Management

### Memory Analysis

```bash
# Memory usage
redis-cli -a $PASSWORD INFO memory

# Memory doctor (recommendations)
redis-cli -a $PASSWORD MEMORY DOCTOR

# Key memory usage
redis-cli -a $PASSWORD MEMORY USAGE mykey

# Sample big keys
redis-cli -a $PASSWORD --bigkeys

# Defragmentation
redis-cli -a $PASSWORD CONFIG SET activedefrag yes
redis-cli -a $PASSWORD MEMORY PURGE
```

### Eviction Management

```bash
# Current policy
redis-cli -a $PASSWORD CONFIG GET maxmemory-policy

# Change policy
redis-cli -a $PASSWORD CONFIG SET maxmemory-policy volatile-lru

# Available policies:
# noeviction, allkeys-lru, volatile-lru, allkeys-lfu, volatile-lfu,
# allkeys-random, volatile-random, volatile-ttl
```

---

## Replication Operations

### Check Replication Status

```bash
# On Master
redis-cli -a $PASSWORD INFO replication

# Key metrics:
# - connected_slaves: Number of replicas
# - slave0: Replica info (state, offset, lag)
# - repl_backlog_size: Backlog buffer size

# On Replica
redis-cli -a $PASSWORD INFO replication
# - master_link_status: up/down
# - master_sync_in_progress: 0/1
# - master_repl_offset: Current offset
```

### Add New Replica

```bash
# On new replica node
redis-cli -a $PASSWORD REPLICAOF <master-ip> 6379

# Verify sync started
redis-cli -a $PASSWORD INFO replication
```

### Remove Replica

```bash
# Promote to standalone
redis-cli -a $PASSWORD REPLICAOF NO ONE

# Then reconfigure as needed
```

### Force Full Resync

```bash
# On replica, trigger full resync
redis-cli -a $PASSWORD DEBUG SLEEP 0
# or restart the replica
./scripts/05-stop-services.sh redis
./scripts/04-start-services.sh redis
```

---

## Maintenance Tasks

### Log Rotation

```bash
# Redis log rotation (add to logrotate)
cat > /etc/logrotate.d/redis << 'EOF'
/opt/cached/current/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF
```

### Cleanup Expired Keys

```bash
# Redis handles TTL automatically
# To force cleanup:
redis-cli -a $PASSWORD DEBUG SLEEP 0

# Check expired keys stats
redis-cli -a $PASSWORD INFO stats | grep expired
```

### Performance Tuning

```bash
# Check latency
redis-cli -a $PASSWORD --latency
redis-cli -a $PASSWORD --latency-history

# Intrinsic latency
redis-cli -a $PASSWORD --intrinsic-latency 10

# Memory efficiency
redis-cli -a $PASSWORD DEBUG STRUCTSIZE
```

---

## Emergency Procedures

### Redis Not Responding

```bash
# 1. Check process
ps aux | grep redis

# 2. Check logs
tail -100 /opt/cached/current/logs/redis.log

# 3. Check system resources
free -h
df -h
top -p $(cat /opt/cached/current/run/redis.pid)

# 4. Force restart if needed
kill -9 $(cat /opt/cached/current/run/redis.pid)
./scripts/04-start-services.sh redis
```

### Sentinel Split Brain

```bash
# Check all Sentinels agree on master
for node in 10.0.1.1 10.0.1.2 10.0.1.3; do
    echo "=== $node ==="
    redis-cli -h $node -p 26379 SENTINEL get-master-addr-by-name mymaster
done

# If disagreement, restart Sentinels one by one
```

### Data Corruption

```bash
# 1. Stop Redis
./scripts/05-stop-services.sh redis

# 2. Backup current data
cp -r /opt/cached/current/data /opt/cached/current/data.corrupt

# 3. Check RDB
redis-check-rdb /opt/cached/current/data/dump.rdb

# 4. Check AOF
redis-check-aof /opt/cached/current/data/appendonlydir/*.aof

# 5. Repair AOF if needed
redis-check-aof --fix /opt/cached/current/data/appendonlydir/*.aof

# 6. Restore from backup or replica
```
