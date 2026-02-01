#!/bin/bash
#
# 05-stop-services.sh
# Stop Redis server and Sentinel services
# SHOULD BE RUN AS redis USER (or via sudo -u redis)
#
# Usage: ./05-stop-services.sh [redis|sentinel|all]
#

set -e

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_BIN="${REDIS_HOME}/bin"
REDIS_CONF="${REDIS_HOME}/conf"
REDIS_RUN="${REDIS_HOME}/run"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SERVICE="${1:-all}"
GRACEFUL_TIMEOUT=30

echo "=============================================="
echo "Stopping Redis Services"
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

# Function to stop Redis
stop_redis() {
    log_info "Stopping Redis server..."

    if ! is_running "${REDIS_RUN}/redis.pid"; then
        log_warn "Redis is not running"
        # Clean up stale PID file
        rm -f "${REDIS_RUN}/redis.pid"
        return 0
    fi

    PID=$(cat "${REDIS_RUN}/redis.pid")

    # Try graceful shutdown first
    log_info "Sending SHUTDOWN command to Redis..."

    # Get password from config
    PASSWORD=$(grep -E "^requirepass" ${REDIS_CONF}/redis.conf 2>/dev/null | awk '{print $2}' || echo "")

    if [ -n "$PASSWORD" ]; then
        ${REDIS_BIN}/redis-cli -a "$PASSWORD" SHUTDOWN NOSAVE 2>/dev/null || true
    else
        ${REDIS_BIN}/redis-cli SHUTDOWN NOSAVE 2>/dev/null || true
    fi

    # Wait for graceful shutdown
    WAITED=0
    while is_running "${REDIS_RUN}/redis.pid" && [ $WAITED -lt $GRACEFUL_TIMEOUT ]; do
        sleep 1
        WAITED=$((WAITED + 1))
        echo -n "."
    done
    echo ""

    # Force kill if still running
    if is_running "${REDIS_RUN}/redis.pid"; then
        log_warn "Graceful shutdown failed, sending SIGKILL..."
        kill -9 $PID 2>/dev/null || true
        sleep 1
    fi

    # Verify stopped
    if is_running "${REDIS_RUN}/redis.pid"; then
        log_error "Failed to stop Redis (PID: $PID)"
        return 1
    else
        rm -f "${REDIS_RUN}/redis.pid"
        log_success "Redis stopped"
    fi
}

# Function to stop Sentinel
stop_sentinel() {
    log_info "Stopping Redis Sentinel..."

    if ! is_running "${REDIS_RUN}/sentinel.pid"; then
        log_warn "Sentinel is not running"
        # Clean up stale PID file
        rm -f "${REDIS_RUN}/sentinel.pid"
        return 0
    fi

    PID=$(cat "${REDIS_RUN}/sentinel.pid")

    # Try graceful shutdown
    log_info "Sending SHUTDOWN command to Sentinel..."
    ${REDIS_BIN}/redis-cli -p 26379 SHUTDOWN 2>/dev/null || true

    # Wait for graceful shutdown
    WAITED=0
    while is_running "${REDIS_RUN}/sentinel.pid" && [ $WAITED -lt $GRACEFUL_TIMEOUT ]; do
        sleep 1
        WAITED=$((WAITED + 1))
        echo -n "."
    done
    echo ""

    # Force kill if still running
    if is_running "${REDIS_RUN}/sentinel.pid"; then
        log_warn "Graceful shutdown failed, sending SIGKILL..."
        kill -9 $PID 2>/dev/null || true
        sleep 1
    fi

    # Verify stopped
    if is_running "${REDIS_RUN}/sentinel.pid"; then
        log_error "Failed to stop Sentinel (PID: $PID)"
        return 1
    else
        rm -f "${REDIS_RUN}/sentinel.pid"
        log_success "Sentinel stopped"
    fi
}

# Function to show status
show_status() {
    echo ""
    echo "=============================================="
    echo "Service Status"
    echo "=============================================="

    echo -n "Redis:    "
    if is_running "${REDIS_RUN}/redis.pid"; then
        echo -e "${GREEN}Running${NC} (PID: $(cat ${REDIS_RUN}/redis.pid))"
    else
        echo -e "${RED}Stopped${NC}"
    fi

    echo -n "Sentinel: "
    if is_running "${REDIS_RUN}/sentinel.pid"; then
        echo -e "${GREEN}Running${NC} (PID: $(cat ${REDIS_RUN}/sentinel.pid))"
    else
        echo -e "${RED}Stopped${NC}"
    fi

    echo ""
}

# Main execution
case "$SERVICE" in
    redis)
        stop_redis
        ;;
    sentinel)
        stop_sentinel
        ;;
    all)
        # Stop Sentinel first (to prevent failover during Redis stop)
        stop_sentinel
        echo ""
        stop_redis
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
