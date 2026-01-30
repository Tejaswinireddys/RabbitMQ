#!/bin/bash
#
# pre-migration-health-check.sh
# Comprehensive health check before RabbitMQ migration
#

set -e

# Configuration
CLUSTER_NODES="${RABBITMQ_NODES:-rabbit-1 rabbit-2 rabbit-3}"
MIN_DISK_FREE_GB=10
MAX_MEMORY_PERCENT=80
EXPECTED_NODE_COUNT=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

log_info() {
    echo -e "[INFO] $1"
}

echo "=============================================="
echo "RabbitMQ Pre-Migration Health Check"
echo "Date: $(date)"
echo "=============================================="
echo ""

# 1. Check cluster status
log_info "Checking cluster status..."
if rabbitmqctl cluster_status > /dev/null 2>&1; then
    log_pass "Cluster is accessible"
else
    log_fail "Cannot access cluster"
    exit 1
fi

# 2. Check node count
log_info "Checking node count..."
NODE_COUNT=$(rabbitmqctl cluster_status 2>/dev/null | grep -c "running_nodes" || echo "0")
RUNNING_NODES=$(rabbitmqctl cluster_status 2>/dev/null | grep -A 100 "running_nodes" | grep "rabbit@" | wc -l)

if [ "$RUNNING_NODES" -ge "$EXPECTED_NODE_COUNT" ]; then
    log_pass "All $RUNNING_NODES nodes running"
else
    log_fail "Expected $EXPECTED_NODE_COUNT nodes, found $RUNNING_NODES"
fi

# 3. Check for alarms
log_info "Checking for alarms..."
ALARMS=$(rabbitmq-diagnostics check_local_alarms 2>&1)
if [[ "$ALARMS" == *"ok"* ]]; then
    log_pass "No local alarms"
else
    log_fail "Alarms detected: $ALARMS"
fi

# 4. Check disk space
log_info "Checking disk space..."
DISK_FREE_BYTES=$(rabbitmqctl status 2>/dev/null | grep -A 2 "disk_free" | tail -1 | tr -d ',' | awk '{print $1}')
if [ -n "$DISK_FREE_BYTES" ]; then
    DISK_FREE_GB=$((DISK_FREE_BYTES / 1024 / 1024 / 1024))
    if [ "$DISK_FREE_GB" -gt "$MIN_DISK_FREE_GB" ]; then
        log_pass "Disk free: ${DISK_FREE_GB}GB"
    else
        log_fail "Disk free: ${DISK_FREE_GB}GB (minimum: ${MIN_DISK_FREE_GB}GB)"
    fi
else
    log_warn "Could not determine disk space"
fi

# 5. Check memory
log_info "Checking memory usage..."
MEM_USED=$(rabbitmqctl status 2>/dev/null | grep -A 5 "memory" | head -5)
MEM_ALARM=$(rabbitmqctl status 2>/dev/null | grep -i "mem_alarm" | grep -c "true" || echo "0")
if [ "$MEM_ALARM" -eq 0 ]; then
    log_pass "Memory within limits"
else
    log_fail "Memory alarm active"
fi

# 6. Check feature flags
log_info "Checking feature flags..."
DISABLED_FLAGS=$(rabbitmqctl list_feature_flags 2>/dev/null | grep -c "disabled" || echo "0")
if [ "$DISABLED_FLAGS" -eq 0 ]; then
    log_pass "All feature flags enabled"
else
    log_warn "$DISABLED_FLAGS feature flags disabled"
    echo "      Run: rabbitmqctl enable_feature_flag all"
fi

# 7. Check for deprecated HA policies
log_info "Checking for deprecated HA policies..."
HA_POLICIES=$(rabbitmqctl list_policies 2>/dev/null | grep -c "ha-mode" || echo "0")
if [ "$HA_POLICIES" -eq 0 ]; then
    log_pass "No deprecated HA policies"
else
    log_warn "$HA_POLICIES HA policies found (will need migration)"
fi

# 8. Check RabbitMQ version
log_info "Checking RabbitMQ version..."
VERSION=$(rabbitmqctl version 2>/dev/null)
log_info "Current version: $VERSION"
if [[ "$VERSION" == 3.12* ]]; then
    log_pass "Version 3.12.x confirmed"
else
    log_warn "Version is $VERSION (expected 3.12.x)"
fi

# 9. Check Erlang version
log_info "Checking Erlang version..."
ERLANG_VERSION=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null)
log_info "Erlang version: $ERLANG_VERSION"

# 10. Check queue types
log_info "Checking queue distribution..."
CLASSIC_COUNT=$(rabbitmqctl list_queues type 2>/dev/null | grep -c "classic" || echo "0")
QUORUM_COUNT=$(rabbitmqctl list_queues type 2>/dev/null | grep -c "quorum" || echo "0")
STREAM_COUNT=$(rabbitmqctl list_queues type 2>/dev/null | grep -c "stream" || echo "0")
log_info "Classic queues: $CLASSIC_COUNT"
log_info "Quorum queues: $QUORUM_COUNT"
log_info "Stream queues: $STREAM_COUNT"

# 11. Check connections
log_info "Checking connections..."
CONN_COUNT=$(rabbitmqctl list_connections 2>/dev/null | wc -l)
log_info "Active connections: $CONN_COUNT"

# 12. Check for exclusive/auto-delete queues
log_info "Checking for non-migratable queues..."
EXCLUSIVE=$(rabbitmqctl list_queues exclusive 2>/dev/null | grep -c "true" || echo "0")
AUTO_DELETE=$(rabbitmqctl list_queues auto_delete 2>/dev/null | grep -c "true" || echo "0")
if [ "$EXCLUSIVE" -gt 0 ] || [ "$AUTO_DELETE" -gt 0 ]; then
    log_info "Found $EXCLUSIVE exclusive and $AUTO_DELETE auto-delete queues (will remain classic)"
fi

# Summary
echo ""
echo "=============================================="
echo "Health Check Summary"
echo "=============================================="
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo -e "Warnings: ${YELLOW}$WARN_COUNT${NC}"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}❌ PRE-MIGRATION CHECK FAILED${NC}"
    echo "Resolve all FAIL items before proceeding"
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PRE-MIGRATION CHECK PASSED WITH WARNINGS${NC}"
    echo "Review WARN items before proceeding"
    exit 0
else
    echo -e "${GREEN}✓ PRE-MIGRATION CHECK PASSED${NC}"
    echo "Ready to proceed with migration"
    exit 0
fi
