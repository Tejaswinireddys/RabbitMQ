#!/bin/bash
#
# health-check.sh
# Comprehensive health check for Redis cluster
#
# Usage: ./health-check.sh [--verbose] [--json]
#

set -e

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_BIN="${REDIS_HOME}/bin"
REDIS_CONF="${REDIS_HOME}/conf"
REDIS_RUN="${REDIS_HOME}/run"

# Get password from config
REDIS_PASSWORD=$(grep -E "^requirepass" ${REDIS_CONF}/redis.conf 2>/dev/null | awk '{print $2}' || echo "")
REDIS_CLI="${REDIS_BIN}/redis-cli"

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_CLI="${REDIS_CLI} -a ${REDIS_PASSWORD}"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERBOSE=false
JSON_OUTPUT=false
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARN=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --verbose|-v)
            VERBOSE=true
            ;;
        --json|-j)
            JSON_OUTPUT=true
            ;;
    esac
done

log_check() {
    local status=$1
    local name=$2
    local message=$3

    if [ "$JSON_OUTPUT" = true ]; then
        return
    fi

    case $status in
        pass)
            echo -e "${GREEN}[PASS]${NC} $name: $message"
            ((CHECKS_PASSED++))
            ;;
        fail)
            echo -e "${RED}[FAIL]${NC} $name: $message"
            ((CHECKS_FAILED++))
            ;;
        warn)
            echo -e "${YELLOW}[WARN]${NC} $name: $message"
            ((CHECKS_WARN++))
            ;;
    esac
}

if [ "$JSON_OUTPUT" = false ]; then
    echo "=============================================="
    echo "Redis Cluster Health Check"
    echo "Date: $(date)"
    echo "=============================================="
    echo ""
fi

# ===== Redis Server Checks =====

if [ "$JSON_OUTPUT" = false ]; then
    echo "=== Redis Server ==="
fi

# Check 1: Redis process running
if [ -f "${REDIS_RUN}/redis.pid" ] && kill -0 $(cat "${REDIS_RUN}/redis.pid") 2>/dev/null; then
    log_check pass "Process" "Redis is running (PID: $(cat ${REDIS_RUN}/redis.pid))"
else
    log_check fail "Process" "Redis is not running"
fi

# Check 2: Redis responding
PING_RESULT=$($REDIS_CLI ping 2>/dev/null || echo "FAIL")
if [ "$PING_RESULT" = "PONG" ]; then
    log_check pass "Response" "Redis responding to PING"
else
    log_check fail "Response" "Redis not responding to PING"
fi

# Check 3: Get role
ROLE=$($REDIS_CLI INFO replication 2>/dev/null | grep role | cut -d: -f2 | tr -d '\r' || echo "unknown")
log_check pass "Role" "$ROLE"

# Check 4: Connected replicas (if master)
if [ "$ROLE" = "master" ]; then
    REPLICAS=$($REDIS_CLI INFO replication 2>/dev/null | grep connected_slaves | cut -d: -f2 | tr -d '\r' || echo "0")
    if [ "$REPLICAS" -ge 2 ]; then
        log_check pass "Replicas" "$REPLICAS replicas connected"
    elif [ "$REPLICAS" -ge 1 ]; then
        log_check warn "Replicas" "Only $REPLICAS replica(s) connected (expected 2)"
    else
        log_check fail "Replicas" "No replicas connected"
    fi
fi

# Check 5: Replication lag (if replica)
if [ "$ROLE" = "slave" ]; then
    MASTER_LINK=$($REDIS_CLI INFO replication 2>/dev/null | grep master_link_status | cut -d: -f2 | tr -d '\r' || echo "unknown")
    if [ "$MASTER_LINK" = "up" ]; then
        log_check pass "Master Link" "Connected to master"
    else
        log_check fail "Master Link" "Master link status: $MASTER_LINK"
    fi

    LAG=$($REDIS_CLI INFO replication 2>/dev/null | grep master_repl_offset | cut -d: -f2 | tr -d '\r' || echo "0")
    log_check pass "Replication" "Offset: $LAG"
fi

# Check 6: Memory usage
MEMORY_USED=$($REDIS_CLI INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "0")
MEMORY_MAX=$($REDIS_CLI CONFIG GET maxmemory 2>/dev/null | tail -1 || echo "0")
if [ "$MEMORY_MAX" != "0" ]; then
    MEMORY_USED_BYTES=$($REDIS_CLI INFO memory 2>/dev/null | grep "used_memory:" | cut -d: -f2 | tr -d '\r' || echo "0")
    MEMORY_PCT=$((MEMORY_USED_BYTES * 100 / MEMORY_MAX))
    if [ "$MEMORY_PCT" -lt 80 ]; then
        log_check pass "Memory" "${MEMORY_USED} (${MEMORY_PCT}% of max)"
    elif [ "$MEMORY_PCT" -lt 95 ]; then
        log_check warn "Memory" "${MEMORY_USED} (${MEMORY_PCT}% of max)"
    else
        log_check fail "Memory" "${MEMORY_USED} (${MEMORY_PCT}% of max) - CRITICAL"
    fi
else
    log_check pass "Memory" "${MEMORY_USED} (no limit set)"
fi

# Check 7: Client connections
CLIENTS=$($REDIS_CLI INFO clients 2>/dev/null | grep connected_clients | cut -d: -f2 | tr -d '\r' || echo "0")
MAX_CLIENTS=$($REDIS_CLI CONFIG GET maxclients 2>/dev/null | tail -1 || echo "10000")
CLIENT_PCT=$((CLIENTS * 100 / MAX_CLIENTS))
if [ "$CLIENT_PCT" -lt 80 ]; then
    log_check pass "Clients" "$CLIENTS connected (${CLIENT_PCT}% of max)"
else
    log_check warn "Clients" "$CLIENTS connected (${CLIENT_PCT}% of max)"
fi

# Check 8: Persistence
RDB_STATUS=$($REDIS_CLI INFO persistence 2>/dev/null | grep rdb_last_bgsave_status | cut -d: -f2 | tr -d '\r' || echo "unknown")
AOF_STATUS=$($REDIS_CLI INFO persistence 2>/dev/null | grep aof_last_bgrewrite_status | cut -d: -f2 | tr -d '\r' || echo "unknown")
if [ "$RDB_STATUS" = "ok" ]; then
    log_check pass "RDB" "Last save successful"
else
    log_check warn "RDB" "Last save status: $RDB_STATUS"
fi

if [ "$AOF_STATUS" = "ok" ]; then
    log_check pass "AOF" "Last rewrite successful"
else
    log_check warn "AOF" "Last rewrite status: $AOF_STATUS"
fi

echo ""

# ===== Sentinel Checks =====

if [ "$JSON_OUTPUT" = false ]; then
    echo "=== Sentinel ==="
fi

SENTINEL_CLI="${REDIS_BIN}/redis-cli -p 26379"

# Check 9: Sentinel process running
if [ -f "${REDIS_RUN}/sentinel.pid" ] && kill -0 $(cat "${REDIS_RUN}/sentinel.pid") 2>/dev/null; then
    log_check pass "Process" "Sentinel is running (PID: $(cat ${REDIS_RUN}/sentinel.pid))"
else
    log_check fail "Process" "Sentinel is not running"
fi

# Check 10: Sentinel responding
SENTINEL_PING=$($SENTINEL_CLI ping 2>/dev/null || echo "FAIL")
if [ "$SENTINEL_PING" = "PONG" ]; then
    log_check pass "Response" "Sentinel responding to PING"
else
    log_check fail "Response" "Sentinel not responding"
fi

# Check 11: Master status
MASTER_INFO=$($SENTINEL_CLI SENTINEL master mymaster 2>/dev/null || echo "")
if [ -n "$MASTER_INFO" ]; then
    MASTER_IP=$(echo "$MASTER_INFO" | grep -A1 "^ip$" | tail -1)
    MASTER_STATUS=$(echo "$MASTER_INFO" | grep -A1 "^flags$" | tail -1)
    if [[ "$MASTER_STATUS" == *"master"* ]] && [[ "$MASTER_STATUS" != *"down"* ]]; then
        log_check pass "Master" "$MASTER_IP - $MASTER_STATUS"
    else
        log_check fail "Master" "$MASTER_IP - $MASTER_STATUS"
    fi
else
    log_check fail "Master" "Cannot get master info"
fi

# Check 12: Number of sentinels
SENTINEL_COUNT=$($SENTINEL_CLI SENTINEL master mymaster 2>/dev/null | grep -A1 "^num-other-sentinels$" | tail -1 || echo "0")
SENTINEL_TOTAL=$((SENTINEL_COUNT + 1))
if [ "$SENTINEL_TOTAL" -ge 3 ]; then
    log_check pass "Sentinels" "$SENTINEL_TOTAL sentinels in cluster"
elif [ "$SENTINEL_TOTAL" -ge 2 ]; then
    log_check warn "Sentinels" "Only $SENTINEL_TOTAL sentinels (expected 3)"
else
    log_check fail "Sentinels" "Only $SENTINEL_TOTAL sentinel(s) - quorum at risk"
fi

# Check 13: Number of replicas known to Sentinel
REPLICA_COUNT=$($SENTINEL_CLI SENTINEL master mymaster 2>/dev/null | grep -A1 "^num-slaves$" | tail -1 || echo "0")
if [ "$REPLICA_COUNT" -ge 2 ]; then
    log_check pass "Replicas" "Sentinel knows $REPLICA_COUNT replicas"
else
    log_check warn "Replicas" "Sentinel knows only $REPLICA_COUNT replica(s)"
fi

echo ""

# ===== Summary =====

if [ "$JSON_OUTPUT" = false ]; then
    echo "=============================================="
    echo "Summary"
    echo "=============================================="
    echo -e "Passed:   ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Warnings: ${YELLOW}$CHECKS_WARN${NC}"
    echo -e "Failed:   ${RED}$CHECKS_FAILED${NC}"
    echo ""

    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo -e "${RED}HEALTH CHECK FAILED${NC}"
        exit 1
    elif [ "$CHECKS_WARN" -gt 0 ]; then
        echo -e "${YELLOW}HEALTH CHECK PASSED WITH WARNINGS${NC}"
        exit 0
    else
        echo -e "${GREEN}HEALTH CHECK PASSED${NC}"
        exit 0
    fi
fi

# JSON output
if [ "$JSON_OUTPUT" = true ]; then
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"status\": \"$([ $CHECKS_FAILED -gt 0 ] && echo 'fail' || echo 'pass')\","
    echo "  \"checks_passed\": $CHECKS_PASSED,"
    echo "  \"checks_warned\": $CHECKS_WARN,"
    echo "  \"checks_failed\": $CHECKS_FAILED,"
    echo "  \"redis_role\": \"$ROLE\","
    echo "  \"memory_used\": \"$MEMORY_USED\","
    echo "  \"clients_connected\": $CLIENTS"
    echo "}"
fi
