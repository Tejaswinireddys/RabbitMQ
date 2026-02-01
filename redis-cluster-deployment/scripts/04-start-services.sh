#!/bin/bash
#
# 04-start-services.sh
# Start Redis server and Sentinel services
# SHOULD BE RUN AS redis USER (or via sudo -u redis)
#
# Usage: ./04-start-services.sh [redis|sentinel|all]
#

set -e

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_BIN="${REDIS_HOME}/bin"
REDIS_CONF="${REDIS_HOME}/conf"
REDIS_RUN="${REDIS_HOME}/run"
REDIS_LOGS="${REDIS_HOME}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SERVICE="${1:-all}"

echo "=============================================="
echo "Starting Redis Services"
echo "=============================================="
echo ""

# Function to check if process is running
is_running() {
    local pidfile=$1
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to start Redis
start_redis() {
    log_info "Starting Redis server..."

    if is_running "${REDIS_RUN}/redis.pid"; then
        log_warn "Redis is already running (PID: $(cat ${REDIS_RUN}/redis.pid))"
        return 0
    fi

    # Check config exists
    if [ ! -f "${REDIS_CONF}/redis.conf" ]; then
        log_error "Redis configuration not found: ${REDIS_CONF}/redis.conf"
    fi

    # Start Redis
    ${REDIS_BIN}/redis-server ${REDIS_CONF}/redis.conf

    # Wait for startup
    sleep 2

    if is_running "${REDIS_RUN}/redis.pid"; then
        PID=$(cat "${REDIS_RUN}/redis.pid")
        log_success "Redis started (PID: $PID)"

        # Test connection
        if ${REDIS_BIN}/redis-cli -a "$(grep requirepass ${REDIS_CONF}/redis.conf | awk '{print $2}')" ping 2>/dev/null | grep -q PONG; then
            log_success "Redis responding to PING"
        else
            log_warn "Redis started but PING failed (may still be loading)"
        fi
    else
        log_error "Failed to start Redis"
    fi
}

# Function to start Sentinel
start_sentinel() {
    log_info "Starting Redis Sentinel..."

    if is_running "${REDIS_RUN}/sentinel.pid"; then
        log_warn "Sentinel is already running (PID: $(cat ${REDIS_RUN}/sentinel.pid))"
        return 0
    fi

    # Check config exists
    if [ ! -f "${REDIS_CONF}/sentinel.conf" ]; then
        log_error "Sentinel configuration not found: ${REDIS_CONF}/sentinel.conf"
    fi

    # Start Sentinel
    ${REDIS_BIN}/redis-sentinel ${REDIS_CONF}/sentinel.conf

    # Wait for startup
    sleep 2

    if is_running "${REDIS_RUN}/sentinel.pid"; then
        PID=$(cat "${REDIS_RUN}/sentinel.pid")
        log_success "Sentinel started (PID: $PID)"

        # Test connection
        if ${REDIS_BIN}/redis-cli -p 26379 ping 2>/dev/null | grep -q PONG; then
            log_success "Sentinel responding to PING"
        else
            log_warn "Sentinel started but PING failed"
        fi
    else
        log_error "Failed to start Sentinel"
    fi
}

# Function to show status
show_status() {
    echo ""
    echo "=============================================="
    echo "Service Status"
    echo "=============================================="

    # Redis status
    echo -n "Redis:    "
    if is_running "${REDIS_RUN}/redis.pid"; then
        PID=$(cat "${REDIS_RUN}/redis.pid")
        ROLE=$(${REDIS_BIN}/redis-cli -a "$(grep requirepass ${REDIS_CONF}/redis.conf 2>/dev/null | awk '{print $2}')" INFO replication 2>/dev/null | grep role | cut -d: -f2 | tr -d '\r' || echo "unknown")
        echo -e "${GREEN}Running${NC} (PID: $PID, Role: $ROLE)"
    else
        echo -e "${RED}Stopped${NC}"
    fi

    # Sentinel status
    echo -n "Sentinel: "
    if is_running "${REDIS_RUN}/sentinel.pid"; then
        PID=$(cat "${REDIS_RUN}/sentinel.pid")
        MASTER=$(${REDIS_BIN}/redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster 2>/dev/null | head -1 || echo "unknown")
        echo -e "${GREEN}Running${NC} (PID: $PID, Master: $MASTER)"
    else
        echo -e "${RED}Stopped${NC}"
    fi

    echo ""
}

# Main execution
case "$SERVICE" in
    redis)
        start_redis
        ;;
    sentinel)
        start_sentinel
        ;;
    all)
        start_redis
        echo ""
        # Wait a bit before starting Sentinel
        sleep 2
        start_sentinel
        ;;
    status)
        show_status
        exit 0
        ;;
    *)
        echo "Usage: $0 [redis|sentinel|all|status]"
        exit 1
        ;;
esac

show_status

echo "Log files:"
echo "  Redis:    ${REDIS_LOGS}/redis.log"
echo "  Sentinel: ${REDIS_LOGS}/sentinel.log"
echo ""
echo "To check logs:"
echo "  tail -f ${REDIS_LOGS}/redis.log"
echo "  tail -f ${REDIS_LOGS}/sentinel.log"
