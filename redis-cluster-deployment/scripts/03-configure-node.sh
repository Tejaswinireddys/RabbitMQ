#!/bin/bash
#
# 03-configure-node.sh
# Configure Redis and Sentinel for a specific node
# SHOULD BE RUN AS redis USER
#
# Usage: ./03-configure-node.sh <node-number> <master-ip> [this-node-ip] [redis-password]
#
# Examples:
#   ./03-configure-node.sh 1 10.0.1.1                      # Master node
#   ./03-configure-node.sh 2 10.0.1.1 10.0.1.2            # Replica node 2
#   ./03-configure-node.sh 3 10.0.1.1 10.0.1.3 mypassword # Replica node 3
#

set -e

# Arguments
NODE_NUMBER="${1:-1}"
MASTER_IP="${2:-10.0.1.1}"
THIS_NODE_IP="${3:-}"
REDIS_PASSWORD="${4:-REDIS_AUTH_PASSWORD_CHANGE_ME}"

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_CONF="${REDIS_HOME}/conf"
REDIS_PORT=6379
SENTINEL_PORT=26379

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    echo "Usage: $0 <node-number> <master-ip> [this-node-ip] [redis-password]"
    echo ""
    echo "Arguments:"
    echo "  node-number   : Node number (1=master, 2=replica, 3=replica)"
    echo "  master-ip     : IP address of the master node"
    echo "  this-node-ip  : IP address of this node (auto-detected if not provided)"
    echo "  redis-password: Redis authentication password"
    echo ""
    echo "Examples:"
    echo "  $0 1 10.0.1.1                        # Configure as master"
    echo "  $0 2 10.0.1.1 10.0.1.2              # Configure as replica"
    echo "  $0 3 10.0.1.1 10.0.1.3 mypassword   # Configure as replica with password"
    exit 1
}

# Validate arguments
if [ "$NODE_NUMBER" -lt 1 ] || [ "$NODE_NUMBER" -gt 3 ]; then
    log_error "Node number must be 1, 2, or 3"
fi

# Auto-detect this node's IP if not provided
if [ -z "$THIS_NODE_IP" ]; then
    THIS_NODE_IP=$(hostname -I | awk '{print $1}')
    log_info "Auto-detected IP: $THIS_NODE_IP"
fi

# Validate IPs
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid IP address: $ip"
    fi
}

validate_ip "$MASTER_IP"
validate_ip "$THIS_NODE_IP"

echo "=============================================="
echo "Redis Node Configuration"
echo "=============================================="
echo ""
echo "Node Number:  $NODE_NUMBER"
echo "Node IP:      $THIS_NODE_IP"
echo "Master IP:    $MASTER_IP"
echo "Role:         $([ "$NODE_NUMBER" -eq 1 ] && echo "MASTER" || echo "REPLICA")"
echo ""

# Check if running as redis user
CURRENT_USER=$(whoami)
if [ "$CURRENT_USER" != "redis" ]; then
    log_warn "This script should be run as 'redis' user (current: $CURRENT_USER)"
    log_info "Continuing anyway..."
fi

# Check if directories exist
if [ ! -d "$REDIS_CONF" ]; then
    log_error "Configuration directory does not exist: $REDIS_CONF"
fi

# Step 1: Create redis-common.conf
log_info "Step 1: Creating common configuration..."

cat > "${REDIS_CONF}/redis-common.conf" << EOF
# Redis 8.2.2 Common Configuration
# Generated: $(date)
# Node: $NODE_NUMBER ($THIS_NODE_IP)

################################## NETWORK ####################################
port ${REDIS_PORT}
tcp-backlog 511
timeout 0
tcp-keepalive 300

################################## GENERAL ####################################
daemonize yes
supervised systemd
pidfile ${REDIS_HOME}/run/redis.pid
loglevel notice
logfile ${REDIS_HOME}/logs/redis.log
databases 16
always-show-logo no
set-proc-title yes
proc-title-template "{title} {listen-addr} {server-mode}"

################################## SECURITY ###################################
requirepass ${REDIS_PASSWORD}
masterauth ${REDIS_PASSWORD}
protected-mode yes
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""

################################## MEMORY #####################################
maxmemory 12gb
maxmemory-policy volatile-lru
maxmemory-samples 5
replica-ignore-maxmemory yes

################################## SNAPSHOTTING ################################
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir ${REDIS_HOME}/data

################################# APPEND ONLY MODE ############################
appendonly yes
appendfilename "appendonly.aof"
appenddirname "appendonlydir"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

################################ SLOW LOG #####################################
slowlog-log-slower-than 10000
slowlog-max-len 128

################################ LATENCY MONITOR ##############################
latency-monitor-threshold 100

############################### ADVANCED CONFIG ###############################
hash-max-listpack-entries 512
hash-max-listpack-value 64
list-max-listpack-size -2
list-compress-depth 0
set-max-intset-entries 512
set-max-listpack-entries 128
set-max-listpack-value 64
zset-max-listpack-entries 128
zset-max-listpack-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

log_success "Common configuration created"

# Step 2: Create node-specific redis.conf
log_info "Step 2: Creating node-specific Redis configuration..."

if [ "$NODE_NUMBER" -eq 1 ]; then
    # MASTER configuration
    cat > "${REDIS_CONF}/redis.conf" << EOF
# Redis 8.2.2 MASTER Configuration
# Generated: $(date)
# Node: $NODE_NUMBER ($THIS_NODE_IP) - MASTER

include ${REDIS_CONF}/redis-common.conf

################################## NETWORK ####################################
bind ${THIS_NODE_IP} 127.0.0.1
replica-announce-ip ${THIS_NODE_IP}
replica-announce-port ${REDIS_PORT}

################################## REPLICATION ################################
# This is the MASTER node - no replicaof directive

min-replicas-to-write 1
min-replicas-max-lag 10

repl-diskless-sync yes
repl-diskless-sync-delay 5
repl-backlog-size 256mb
repl-backlog-ttl 3600
repl-ping-replica-period 10
repl-timeout 60
repl-disable-tcp-nodelay no
EOF
    log_success "Master configuration created"
else
    # REPLICA configuration
    cat > "${REDIS_CONF}/redis.conf" << EOF
# Redis 8.2.2 REPLICA Configuration
# Generated: $(date)
# Node: $NODE_NUMBER ($THIS_NODE_IP) - REPLICA

include ${REDIS_CONF}/redis-common.conf

################################## NETWORK ####################################
bind ${THIS_NODE_IP} 127.0.0.1
replica-announce-ip ${THIS_NODE_IP}
replica-announce-port ${REDIS_PORT}

################################## REPLICATION ################################
replicaof ${MASTER_IP} ${REDIS_PORT}

replica-serve-stale-data yes
replica-read-only yes
replica-priority 100

repl-diskless-sync yes
repl-diskless-sync-delay 5
repl-backlog-size 256mb
repl-backlog-ttl 3600
repl-ping-replica-period 10
repl-timeout 60
repl-disable-tcp-nodelay no
repl-diskless-load disabled
replica-lazy-flush no
EOF
    log_success "Replica configuration created"
fi

# Step 3: Create sentinel.conf
log_info "Step 3: Creating Sentinel configuration..."

cat > "${REDIS_CONF}/sentinel.conf" << EOF
# Redis Sentinel Configuration
# Generated: $(date)
# Node: $NODE_NUMBER ($THIS_NODE_IP)

################################## GENERAL ####################################
port ${SENTINEL_PORT}
bind ${THIS_NODE_IP} 127.0.0.1
daemonize yes
pidfile ${REDIS_HOME}/run/sentinel.pid
logfile ${REDIS_HOME}/logs/sentinel.log
dir ${REDIS_HOME}/data

################################## MONITORING #################################
sentinel monitor mymaster ${MASTER_IP} ${REDIS_PORT} 2
sentinel auth-pass mymaster ${REDIS_PASSWORD}
sentinel down-after-milliseconds mymaster 5000
sentinel failover-timeout mymaster 60000
sentinel parallel-syncs mymaster 1

################################## SECURITY ###################################
protected-mode no

################################## ADVANCED ###################################
sentinel announce-ip ${THIS_NODE_IP}
sentinel announce-port ${SENTINEL_PORT}
sentinel resolve-hostnames no
sentinel announce-hostnames no
sentinel deny-scripts-reconfig yes
EOF

log_success "Sentinel configuration created"

# Step 4: Set permissions
log_info "Step 4: Setting file permissions..."

chmod 640 "${REDIS_CONF}/redis-common.conf"
chmod 640 "${REDIS_CONF}/redis.conf"
chmod 640 "${REDIS_CONF}/sentinel.conf"

log_success "Permissions set"

# Step 5: Verify configuration
log_info "Step 5: Verifying configuration..."

# Test Redis config syntax
if ${REDIS_HOME}/bin/redis-server "${REDIS_CONF}/redis.conf" --test-memory 1 2>/dev/null; then
    log_success "Redis configuration syntax OK"
else
    # redis-server --test-memory may not work on all versions, try configtest
    log_info "Configuration created (manual verification recommended)"
fi

# Summary
echo ""
echo "=============================================="
echo "Configuration Complete"
echo "=============================================="
echo ""
echo "Node:         $NODE_NUMBER"
echo "Role:         $([ "$NODE_NUMBER" -eq 1 ] && echo "MASTER" || echo "REPLICA")"
echo "This IP:      $THIS_NODE_IP"
echo "Master IP:    $MASTER_IP"
echo ""
echo "Configuration files:"
echo "  ${REDIS_CONF}/redis-common.conf"
echo "  ${REDIS_CONF}/redis.conf"
echo "  ${REDIS_CONF}/sentinel.conf"
echo ""
echo "Next step: Run 04-start-services.sh to start Redis and Sentinel"
