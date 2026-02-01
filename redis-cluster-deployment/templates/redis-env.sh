#!/bin/bash
#
# redis-env.sh
# Redis environment configuration template
#
# Source this file in your shell:
#   source /opt/cached/current/scripts/redis-env.sh
#
# Or add to ~/.bashrc for permanent setup
#

# ============================================
# PATHS
# ============================================
export REDIS_HOME="/opt/cached/current"
export REDIS_BIN="${REDIS_HOME}/bin"
export REDIS_CONF="${REDIS_HOME}/conf"
export REDIS_DATA="${REDIS_HOME}/data"
export REDIS_LOGS="${REDIS_HOME}/logs"
export REDIS_RUN="${REDIS_HOME}/run"
export REDIS_SCRIPTS="${REDIS_HOME}/scripts"

# Add Redis binaries to PATH
export PATH="${REDIS_BIN}:${PATH}"

# ============================================
# CONNECTION SETTINGS
# ============================================
export REDIS_HOST="127.0.0.1"
export REDIS_PORT="6379"
export REDIS_SENTINEL_PORT="26379"
export REDIS_MASTER_NAME="mymaster"

# Password (DO NOT hardcode in production - use secrets manager)
# export REDIS_PASSWORD="your-password-here"

# ============================================
# ALIASES
# ============================================

# Redis CLI with password
alias rcli='redis-cli -a "$REDIS_PASSWORD"'
alias rping='redis-cli -a "$REDIS_PASSWORD" ping'
alias rinfo='redis-cli -a "$REDIS_PASSWORD" INFO'
alias rrepl='redis-cli -a "$REDIS_PASSWORD" INFO replication'
alias rmem='redis-cli -a "$REDIS_PASSWORD" INFO memory'
alias rclients='redis-cli -a "$REDIS_PASSWORD" CLIENT LIST'
alias rslow='redis-cli -a "$REDIS_PASSWORD" SLOWLOG GET 10'

# Sentinel CLI
alias scli='redis-cli -p $REDIS_SENTINEL_PORT'
alias smaster='redis-cli -p $REDIS_SENTINEL_PORT SENTINEL master $REDIS_MASTER_NAME'
alias sreplicas='redis-cli -p $REDIS_SENTINEL_PORT SENTINEL replicas $REDIS_MASTER_NAME'
alias ssentinels='redis-cli -p $REDIS_SENTINEL_PORT SENTINEL sentinels $REDIS_MASTER_NAME'
alias saddr='redis-cli -p $REDIS_SENTINEL_PORT SENTINEL get-master-addr-by-name $REDIS_MASTER_NAME'

# Service management
alias rstart='${REDIS_SCRIPTS}/04-start-services.sh'
alias rstop='${REDIS_SCRIPTS}/05-stop-services.sh'
alias rhealth='${REDIS_SCRIPTS}/health-check.sh'
alias rbackup='${REDIS_SCRIPTS}/backup.sh'
alias rfailover='${REDIS_SCRIPTS}/failover.sh'

# Logs
alias rlog='tail -f ${REDIS_LOGS}/redis.log'
alias slog='tail -f ${REDIS_LOGS}/sentinel.log'

# ============================================
# FUNCTIONS
# ============================================

# Get current master IP
redis_master_ip() {
    redis-cli -p $REDIS_SENTINEL_PORT SENTINEL get-master-addr-by-name $REDIS_MASTER_NAME 2>/dev/null | head -1
}

# Check if current node is master
is_redis_master() {
    local role=$(redis-cli -a "$REDIS_PASSWORD" INFO replication 2>/dev/null | grep role | cut -d: -f2 | tr -d '\r')
    [ "$role" = "master" ]
}

# Quick status
redis_status() {
    echo "=== Redis Status ==="
    echo -n "Process: "
    if [ -f "${REDIS_RUN}/redis.pid" ] && kill -0 $(cat "${REDIS_RUN}/redis.pid") 2>/dev/null; then
        echo "Running (PID: $(cat ${REDIS_RUN}/redis.pid))"
    else
        echo "Stopped"
    fi

    echo -n "Role: "
    redis-cli -a "$REDIS_PASSWORD" INFO replication 2>/dev/null | grep role | cut -d: -f2 | tr -d '\r' || echo "Unknown"

    echo -n "Memory: "
    redis-cli -a "$REDIS_PASSWORD" INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "Unknown"

    echo ""
    echo "=== Sentinel Status ==="
    echo -n "Process: "
    if [ -f "${REDIS_RUN}/sentinel.pid" ] && kill -0 $(cat "${REDIS_RUN}/sentinel.pid") 2>/dev/null; then
        echo "Running (PID: $(cat ${REDIS_RUN}/sentinel.pid))"
    else
        echo "Stopped"
    fi

    echo -n "Master: "
    redis_master_ip
}

# ============================================
# DISPLAY INFO
# ============================================

echo "Redis environment loaded"
echo "  REDIS_HOME: ${REDIS_HOME}"
echo "  Redis version: $(${REDIS_BIN}/redis-server --version 2>/dev/null | head -1 || echo 'Not installed')"
echo ""
echo "Quick commands:"
echo "  rstart    - Start services"
echo "  rstop     - Stop services"
echo "  rhealth   - Health check"
echo "  rinfo     - Redis INFO"
echo "  smaster   - Sentinel master info"
echo "  redis_status - Quick status"
