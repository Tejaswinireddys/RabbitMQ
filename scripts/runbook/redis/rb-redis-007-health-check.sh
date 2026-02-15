#!/bin/bash
# =============================================================================
# RB-REDIS-007: Comprehensive Redis + Sentinel Health Check
# =============================================================================
# Use: Scheduled daily or on-demand verification of cluster health
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

REPORT_FILE=$(start_report "Redis_Health_Check")
ISSUES=0

log_info "=== Redis + Sentinel Comprehensive Health Check ==="
log_info "Environment: ${ENVIRONMENT} | Nodes: ${REDIS_NODES[*]}"
separator

# 1. Redis Connectivity
log_step "1. Redis Server Connectivity"
report_line "${REPORT_FILE}" "1. REDIS SERVER STATUS"
redis_cluster_status | tee -a "${REPORT_FILE}"
for node in "${REDIS_NODES[@]}"; do
    PING=$(redis_cmd "${node}" "${REDIS_PORT}" PING 2>/dev/null)
    [[ "${PING}" != "PONG" ]] && ((ISSUES++))
done
report_line "${REPORT_FILE}" ""

# 2. Sentinel Status
log_step "2. Sentinel Status"
report_line "${REPORT_FILE}" "2. SENTINEL STATUS"
redis_sentinel_status | tee -a "${REPORT_FILE}"
for node in "${REDIS_NODES[@]}"; do
    PING=$(sentinel_cmd "${node}" PING 2>/dev/null)
    [[ "${PING}" != "PONG" ]] && ((ISSUES++))
done
report_line "${REPORT_FILE}" ""

# 3. Memory
log_step "3. Memory Check"
report_line "${REPORT_FILE}" "3. MEMORY"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    redis_memory_summary "${node}" | tee -a "${REPORT_FILE}"
done
report_line "${REPORT_FILE}" ""

# 4. Replication
log_step "4. Replication Check"
report_line "${REPORT_FILE}" "4. REPLICATION"
MASTER=$(redis_get_master)
echo "Master: ${MASTER}" | tee -a "${REPORT_FILE}"
CONNECTED_SLAVES=$(redis_info_section "${MASTER}" "replication" | grep "connected_slaves" | cut -d: -f2 | tr -d '\r')
echo "Connected replicas: ${CONNECTED_SLAVES}" | tee -a "${REPORT_FILE}"
if [[ "${CONNECTED_SLAVES}" -lt 2 ]]; then
    log_warn "Expected 2 replicas, found ${CONNECTED_SLAVES}"
    ((ISSUES++))
fi
report_line "${REPORT_FILE}" ""

# 5. Persistence
log_step "5. Persistence Check"
report_line "${REPORT_FILE}" "5. PERSISTENCE"
for node in "${REDIS_NODES[@]}"; do
    RDB_STATUS=$(redis_info_section "${node}" "persistence" | grep "rdb_last_bgsave_status" | cut -d: -f2 | tr -d '\r')
    echo "  ${node}: rdb_last_bgsave_status = ${RDB_STATUS}" | tee -a "${REPORT_FILE}"
    if [[ "${RDB_STATUS}" != "ok" ]]; then
        log_warn "${node}: BGSAVE not OK"
        ((ISSUES++))
    fi
done
report_line "${REPORT_FILE}" ""

# 6. Key Stats
log_step "6. Keyspace"
report_line "${REPORT_FILE}" "6. KEYSPACE"
redis_info_section "${MASTER}" "keyspace" | tee -a "${REPORT_FILE}"
report_line "${REPORT_FILE}" ""

# 7. Hit Rate
log_step "7. Cache Hit Rate"
report_line "${REPORT_FILE}" "7. HIT RATE"
HITS=$(redis_info_section "${MASTER}" "stats" | grep "keyspace_hits" | cut -d: -f2 | tr -d '\r')
MISSES=$(redis_info_section "${MASTER}" "stats" | grep "keyspace_misses" | cut -d: -f2 | tr -d '\r')
if [[ -n "${HITS}" && -n "${MISSES}" ]]; then
    TOTAL=$((HITS + MISSES))
    if [[ ${TOTAL} -gt 0 ]]; then
        HIT_RATE=$(echo "scale=2; ${HITS} * 100 / ${TOTAL}" | bc 2>/dev/null || echo "N/A")
        echo "  Hit Rate: ${HIT_RATE}%" | tee -a "${REPORT_FILE}"
    fi
fi
report_line "${REPORT_FILE}" ""

# 8. Connections
log_step "8. Connection Count"
report_line "${REPORT_FILE}" "8. CONNECTIONS"
for node in "${REDIS_NODES[@]}"; do
    CONNS=$(redis_info_section "${node}" "clients" | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
    echo "  ${node}: ${CONNS} clients" | tee -a "${REPORT_FILE}"
done
report_line "${REPORT_FILE}" ""

# Summary
separator
if [[ ${ISSUES} -eq 0 ]]; then
    log_info "Health check PASSED - no issues found"
    report_line "${REPORT_FILE}" "RESULT: PASSED"
else
    log_warn "Health check found ${ISSUES} issue(s)"
    report_line "${REPORT_FILE}" "RESULT: ${ISSUES} ISSUE(S) FOUND"
fi

log_info "Report saved to: ${REPORT_FILE}"
