# Redis Troubleshooting Guide

## Common Issues

### 1. Redis Won't Start

#### Symptoms
- Service fails to start
- PID file not created
- Port not listening

#### Diagnosis
```bash
# Check logs
tail -100 /opt/cached/current/logs/redis.log

# Check port conflict
netstat -tlnp | grep 6379
ss -tlnp | grep 6379

# Check permissions
ls -la /opt/cached/current/
ls -la /opt/cached/current/data/
ls -la /opt/cached/current/run/

# Check config syntax
/opt/cached/current/bin/redis-server /opt/cached/current/conf/redis.conf --test-memory 1
```

#### Solutions

**Port already in use:**
```bash
# Find process using port
lsof -i :6379
# Kill if needed
kill -9 <pid>
```

**Permission denied:**
```bash
sudo chown -R redis:redis /opt/cached/current/
sudo chmod 750 /opt/cached/current/data
```

**Memory allocation error:**
```bash
# Check available memory
free -h
# Reduce maxmemory in config
vi /opt/cached/current/conf/redis.conf
# Set: maxmemory 1gb
```

**Configuration error:**
```bash
# Common issues:
# - Missing include file
# - Invalid IP in bind
# - Wrong password format
# Check config file carefully
```

---

### 2. Replica Not Connecting to Master

#### Symptoms
- `master_link_status: down`
- Replication not starting
- Connection refused errors

#### Diagnosis
```bash
# On Replica - check status
redis-cli -a $PASSWORD INFO replication

# Test connectivity to master
redis-cli -h MASTER_IP -p 6379 -a $PASSWORD ping

# Check master is accepting connections
redis-cli -a $PASSWORD CLIENT LIST | grep slave

# Check firewall
sudo iptables -L -n | grep 6379
```

#### Solutions

**Network connectivity:**
```bash
# Test port
nc -zv MASTER_IP 6379

# Open firewall
sudo iptables -A INPUT -p tcp --dport 6379 -j ACCEPT
```

**Authentication mismatch:**
```bash
# Verify masterauth on replica matches requirepass on master
grep masterauth /opt/cached/current/conf/redis.conf
grep requirepass /opt/cached/current/conf/redis.conf  # on master
```

**Master not listening on correct interface:**
```bash
# On master, check bind address
grep bind /opt/cached/current/conf/redis.conf
# Should include the network IP, not just 127.0.0.1
```

---

### 3. Sentinel Not Detecting Nodes

#### Symptoms
- `num-other-sentinels: 0`
- `num-slaves: 0`
- Sentinels not communicating

#### Diagnosis
```bash
# Check Sentinel logs
tail -100 /opt/cached/current/logs/sentinel.log

# Check Sentinel config
cat /opt/cached/current/conf/sentinel.conf

# Check master detection
redis-cli -p 26379 SENTINEL master mymaster

# Check other Sentinels
redis-cli -p 26379 SENTINEL sentinels mymaster
```

#### Solutions

**Wrong master IP in Sentinel config:**
```bash
# Update sentinel.conf with correct master IP
vi /opt/cached/current/conf/sentinel.conf
# Change: sentinel monitor mymaster CORRECT_IP 6379 2
# Restart Sentinel
./scripts/05-stop-services.sh sentinel
./scripts/04-start-services.sh sentinel
```

**Sentinel port blocked:**
```bash
sudo iptables -A INPUT -p tcp --dport 26379 -j ACCEPT
```

**Announce IP not set:**
```bash
# Add to sentinel.conf
sentinel announce-ip THIS_NODE_IP
sentinel announce-port 26379
```

---

### 4. High Memory Usage

#### Symptoms
- Memory alarm
- OOM killer terminated Redis
- Slow performance

#### Diagnosis
```bash
# Check memory usage
redis-cli -a $PASSWORD INFO memory

# Check maxmemory setting
redis-cli -a $PASSWORD CONFIG GET maxmemory

# Find big keys
redis-cli -a $PASSWORD --bigkeys

# Memory doctor
redis-cli -a $PASSWORD MEMORY DOCTOR
```

#### Solutions

**Increase maxmemory:**
```bash
redis-cli -a $PASSWORD CONFIG SET maxmemory 16gb
redis-cli -a $PASSWORD CONFIG REWRITE
```

**Enable eviction:**
```bash
redis-cli -a $PASSWORD CONFIG SET maxmemory-policy volatile-lru
```

**Clean up unused keys:**
```bash
# Scan and delete pattern
redis-cli -a $PASSWORD --scan --pattern "temp:*" | xargs redis-cli -a $PASSWORD DEL
```

**Enable defragmentation:**
```bash
redis-cli -a $PASSWORD CONFIG SET activedefrag yes
```

---

### 5. High Latency

#### Symptoms
- Slow response times
- Timeout errors in applications
- Slow log entries

#### Diagnosis
```bash
# Check latency
redis-cli -a $PASSWORD --latency

# Check slow log
redis-cli -a $PASSWORD SLOWLOG GET 10

# Check client output buffers
redis-cli -a $PASSWORD INFO clients

# Check if BGSAVE/BGREWRITEAOF running
redis-cli -a $PASSWORD INFO persistence
```

#### Solutions

**Slow commands:**
```bash
# Identify slow commands from SLOWLOG
# Optimize or avoid O(N) commands on large datasets
# Use SCAN instead of KEYS
# Use MGET instead of multiple GET
```

**Background save causing latency:**
```bash
# Adjust save frequency
redis-cli -a $PASSWORD CONFIG SET save ""
# Or use less frequent saves
redis-cli -a $PASSWORD CONFIG SET save "900 1 300 10"
```

**Large client buffers:**
```bash
# Increase limits
redis-cli -a $PASSWORD CONFIG SET client-output-buffer-limit "normal 256mb 128mb 60"
```

---

### 6. Failover Not Working

#### Symptoms
- Master down but no failover
- Failover takes too long
- Wrong replica promoted

#### Diagnosis
```bash
# Check Sentinel quorum
redis-cli -p 26379 SENTINEL ckquorum mymaster

# Check Sentinel master info
redis-cli -p 26379 SENTINEL master mymaster

# Check if enough Sentinels are up
redis-cli -p 26379 SENTINEL sentinels mymaster | grep -c "^name"
```

#### Solutions

**Quorum not reached:**
```bash
# Need at least 2 Sentinels for quorum of 2
# Ensure at least 2 Sentinels are running and connected
```

**Adjust failover timing:**
```bash
# If failover takes too long
redis-cli -p 26379 SENTINEL SET mymaster down-after-milliseconds 3000
```

**Force failover:**
```bash
redis-cli -p 26379 SENTINEL failover mymaster
```

---

### 7. Disk Space Issues

#### Symptoms
- Write errors
- BGSAVE fails
- AOF rewrite fails

#### Diagnosis
```bash
# Check disk space
df -h /opt/cached/current/data

# Check RDB/AOF sizes
ls -lah /opt/cached/current/data/
ls -lah /opt/cached/current/data/appendonlydir/

# Check persistence status
redis-cli -a $PASSWORD INFO persistence
```

#### Solutions

**Clean up old files:**
```bash
# Remove old RDB files
find /opt/cached/current/data -name "temp-*.rdb" -delete

# Compact AOF
redis-cli -a $PASSWORD BGREWRITEAOF
```

**Move data directory:**
```bash
# Stop Redis
./scripts/05-stop-services.sh redis

# Move data
mv /opt/cached/current/data /larger/disk/redis-data
ln -s /larger/disk/redis-data /opt/cached/current/data

# Start Redis
./scripts/04-start-services.sh redis
```

---

## Log Analysis

### Key Log Patterns

```bash
# Connection issues
grep -i "connection\|refused\|timeout" /opt/cached/current/logs/redis.log

# Memory issues
grep -i "memory\|oom\|maxmemory" /opt/cached/current/logs/redis.log

# Replication issues
grep -i "sync\|replica\|slave\|master" /opt/cached/current/logs/redis.log

# Sentinel events
grep -i "failover\|switch\|odown\|sdown" /opt/cached/current/logs/sentinel.log
```

### Log Levels

```bash
# Increase log verbosity temporarily
redis-cli -a $PASSWORD CONFIG SET loglevel debug

# Reset after debugging
redis-cli -a $PASSWORD CONFIG SET loglevel notice
```

---

## Emergency Recovery

### Redis Process Hung

```bash
# Get thread dump
kill -USR1 $(cat /opt/cached/current/run/redis.pid)
# Check /opt/cached/current/logs/redis.log for output

# Force kill if needed
kill -9 $(cat /opt/cached/current/run/redis.pid)
rm /opt/cached/current/run/redis.pid
./scripts/04-start-services.sh redis
```

### Restore from Replica

```bash
# If master data is corrupted, promote replica:
# 1. On replica
redis-cli -a $PASSWORD REPLICAOF NO ONE

# 2. Update Sentinel to point to new master
redis-cli -p 26379 SENTINEL failover mymaster

# 3. Reconfigure old master as replica (when recovered)
redis-cli -a $PASSWORD REPLICAOF NEW_MASTER_IP 6379
```

### Full Cluster Recovery

```bash
# If all nodes are down:
# 1. Start master first without Sentinel
./scripts/04-start-services.sh redis

# 2. Verify master data
redis-cli -a $PASSWORD DBSIZE

# 3. Start replicas
# On each replica node:
./scripts/04-start-services.sh redis

# 4. Verify replication
redis-cli -a $PASSWORD INFO replication

# 5. Start Sentinels (master first)
./scripts/04-start-services.sh sentinel
```
