#!/bin/bash
#
# validate-migration.sh
# Comprehensive validation of RabbitMQ migration
#

set -e

# Configuration
BASELINE_DIR="${BASELINE_DIR:-/metrics/baseline}"
TOLERANCE_PERCENT="${TOLERANCE_PERCENT:-20}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
log_info() { echo -e "[INFO] $1"; }

echo "=============================================="
echo "RabbitMQ Migration Validation"
echo "Date: $(date)"
echo "=============================================="
echo ""

# 1. Cluster Health
echo "=== Cluster Health ==="

log_info "Checking cluster status..."
if rabbitmqctl cluster_status > /dev/null 2>&1; then
    log_pass "Cluster accessible"
else
    log_fail "Cluster not accessible"
fi

NODE_COUNT=$(rabbitmqctl cluster_status 2>/dev/null | grep "rabbit@" | wc -l)
if [ "$NODE_COUNT" -ge 3 ]; then
    log_pass "All $NODE_COUNT nodes running"
else
    log_fail "Expected 3 nodes, found $NODE_COUNT"
fi

ALARMS=$(rabbitmq-diagnostics check_local_alarms 2>&1 || true)
if [[ "$ALARMS" == *"ok"* ]]; then
    log_pass "No alarms active"
else
    log_fail "Alarms detected"
fi

# 2. Version Validation
echo ""
echo "=== Version Validation ==="

VERSION=$(rabbitmqctl version 2>/dev/null)
if [[ "$VERSION" == 4.1* ]]; then
    log_pass "RabbitMQ version: $VERSION"
else
    log_fail "Expected version 4.1.x, got $VERSION"
fi

ERLANG=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null)
if [[ "$ERLANG" == "26"* ]] || [[ "$ERLANG" == "27"* ]]; then
    log_pass "Erlang version: $ERLANG"
else
    log_warn "Erlang version: $ERLANG (expected 26.x or 27.x)"
fi

# 3. Queue Validation
echo ""
echo "=== Queue Validation ==="

TOTAL_QUEUES=$(rabbitmqctl list_queues name --quiet 2>/dev/null | wc -l)
QUORUM_QUEUES=$(rabbitmqctl list_queues type --quiet 2>/dev/null | grep -c "quorum" || echo "0")
CLASSIC_QUEUES=$(rabbitmqctl list_queues type --quiet 2>/dev/null | grep -c "classic" || echo "0")

log_info "Total queues: $TOTAL_QUEUES"
log_info "Quorum queues: $QUORUM_QUEUES"
log_info "Classic queues: $CLASSIC_QUEUES"

if [ "$QUORUM_QUEUES" -gt 0 ]; then
    log_pass "Quorum queues present"
else
    log_warn "No quorum queues found"
fi

# Check quorum queue replicas
log_info "Checking quorum queue replication..."
UNDER_REPLICATED=$(rabbitmqctl list_queues name type members --quiet 2>/dev/null | \
    grep "quorum" | while read -r name type members; do
        MEMBER_COUNT=$(echo "$members" | tr ',' '\n' | wc -l)
        if [ "$MEMBER_COUNT" -lt 3 ]; then
            echo "$name"
        fi
    done | wc -l)

if [ "$UNDER_REPLICATED" -eq 0 ]; then
    log_pass "All quorum queues properly replicated"
else
    log_warn "$UNDER_REPLICATED quorum queues under-replicated"
fi

# 4. Connection Validation
echo ""
echo "=== Connection Validation ==="

CONN_COUNT=$(rabbitmqctl list_connections --quiet 2>/dev/null | wc -l)
log_info "Active connections: $CONN_COUNT"

if [ -f "${BASELINE_DIR}/connections.txt" ]; then
    BASELINE_CONN=$(cat "${BASELINE_DIR}/connections.txt")
    DIFF=$((CONN_COUNT - BASELINE_CONN))
    PERCENT=$((DIFF * 100 / BASELINE_CONN))

    if [ "$PERCENT" -lt -"$TOLERANCE_PERCENT" ]; then
        log_warn "Connections ${PERCENT}% below baseline ($BASELINE_CONN)"
    else
        log_pass "Connection count within tolerance (baseline: $BASELINE_CONN)"
    fi
else
    log_info "No baseline available for comparison"
fi

# 5. Message Flow Validation
echo ""
echo "=== Message Flow Validation ==="

# Check for stuck messages
TOTAL_MSGS=$(rabbitmqctl list_queues messages --quiet 2>/dev/null | awk '{sum+=$1} END {print sum}')
UNACKED=$(rabbitmqctl list_queues messages_unacknowledged --quiet 2>/dev/null | awk '{sum+=$1} END {print sum}')

log_info "Total messages in queues: $TOTAL_MSGS"
log_info "Unacknowledged messages: $UNACKED"

# Check for consumers
QUEUES_NO_CONSUMERS=$(rabbitmqctl list_queues name messages consumers --quiet 2>/dev/null | \
    awk '$2 > 100 && $3 == 0 {print $1}' | wc -l)

if [ "$QUEUES_NO_CONSUMERS" -eq 0 ]; then
    log_pass "No queues with high message count and zero consumers"
else
    log_warn "$QUEUES_NO_CONSUMERS queues have messages but no consumers"
fi

# 6. Feature Flags
echo ""
echo "=== Feature Flags ==="

DISABLED_FLAGS=$(rabbitmqctl list_feature_flags --quiet 2>/dev/null | grep -c "disabled" || echo "0")
if [ "$DISABLED_FLAGS" -eq 0 ]; then
    log_pass "All feature flags enabled"
else
    log_warn "$DISABLED_FLAGS feature flags disabled"
fi

# 7. Shovel Status
echo ""
echo "=== Shovel Status ==="

SHOVEL_COUNT=$(rabbitmqctl list_parameters shovel --quiet 2>/dev/null | wc -l)
if [ "$SHOVEL_COUNT" -eq 0 ]; then
    log_pass "No active Shovels (migration complete)"
else
    log_info "$SHOVEL_COUNT Shovels still configured"

    # Check Shovel status
    rabbitmqctl shovel_status 2>/dev/null | while read -r line; do
        if [[ "$line" == *"running"* ]]; then
            echo "  Running: $line"
        elif [[ "$line" == *"terminated"* ]]; then
            echo "  Terminated: $line"
        fi
    done
fi

# 8. Monitoring Check
echo ""
echo "=== Monitoring Check ==="

# Check Prometheus endpoint
if curl -s http://localhost:15692/metrics > /dev/null 2>&1; then
    log_pass "Prometheus metrics endpoint accessible"
else
    log_warn "Prometheus metrics endpoint not accessible"
fi

# Check management API
if curl -s -u guest:guest http://localhost:15672/api/overview > /dev/null 2>&1; then
    log_pass "Management API accessible"
else
    log_fail "Management API not accessible"
fi

# 9. Performance Check
echo ""
echo "=== Performance Check ==="

# Check disk I/O
DISK_ALARM=$(rabbitmqctl status 2>/dev/null | grep -c "disk.*alarm" || echo "0")
if [ "$DISK_ALARM" -eq 0 ]; then
    log_pass "No disk alarms"
else
    log_fail "Disk alarm active"
fi

# Check file descriptors
FD_USED=$(rabbitmqctl status 2>/dev/null | grep -A 2 "file_descriptors" | grep "used" | awk '{print $2}' | tr -d ',')
FD_LIMIT=$(rabbitmqctl status 2>/dev/null | grep -A 2 "file_descriptors" | grep "limit" | awk '{print $2}' | tr -d ',')

if [ -n "$FD_USED" ] && [ -n "$FD_LIMIT" ]; then
    FD_PERCENT=$((FD_USED * 100 / FD_LIMIT))
    if [ "$FD_PERCENT" -lt 80 ]; then
        log_pass "File descriptors: ${FD_PERCENT}% used"
    else
        log_warn "File descriptors: ${FD_PERCENT}% used (high)"
    fi
fi

# Summary
echo ""
echo "=============================================="
echo "Validation Summary"
echo "=============================================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Warnings: ${YELLOW}$WARN${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "Address all FAIL items before considering migration complete"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  VALIDATION PASSED WITH WARNINGS${NC}"
    echo "Review WARN items but migration can proceed"
    exit 0
else
    echo -e "${GREEN}✓ VALIDATION PASSED${NC}"
    echo "Migration validated successfully"
    exit 0
fi
