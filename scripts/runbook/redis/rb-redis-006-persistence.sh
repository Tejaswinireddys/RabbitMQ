#!/bin/bash
# =============================================================================
# RB-REDIS-006: Persistence Failure (RDB/AOF)
# =============================================================================
# Severity: P2 - High
# Trigger:  Datadog monitor - rdb_last_bgsave_status != ok or aof issues
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

REPORT_FILE=$(start_report "RB-REDIS-006_Persistence")
log_info "=== RB-REDIS-006: Persistence Investigation ==="

# Step 1: Persistence status on all nodes
log_step "Step 1: Persistence status..."
report_line "${REPORT_FILE}" "Step 1: Persistence Status"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    redis_info_section "${node}" "persistence" | tee -a "${REPORT_FILE}"
done

# Step 2: Check disk space
log_step "Step 2: Disk space on data directories..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Disk Space"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "df -h ${REDIS_DATA_DIR}" 2>/dev/null | tee -a "${REPORT_FILE}" || true
    remote_exec "${node}" "ls -lh ${REDIS_DATA_DIR}/*.rdb ${REDIS_DATA_DIR}/*.aof 2>/dev/null" | tee -a "${REPORT_FILE}" || true
done

# Step 3: Check for background save errors
log_step "Step 3: Recent errors in logs..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Persistence Errors in Logs"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo grep -i 'BGSAVE\|bgsave\|RDB\|rdb\|AOF\|aof\|fork\|Background saving' ${REDIS_LOG_DIR}/redis.log 2>/dev/null | tail -20" | tee -a "${REPORT_FILE}" || true
done

# Step 4: Memory vs disk check (fork needs 2x memory)
log_step "Step 4: Memory availability for fork..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Memory for Fork"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "free -h" 2>/dev/null | tee -a "${REPORT_FILE}" || true
    REDIS_MEM=$(redis_info_section "${node}" "memory" | grep "used_memory_rss_human" | cut -d: -f2 | tr -d '\r')
    echo "  Redis RSS: ${REDIS_MEM}" | tee -a "${REPORT_FILE}"
done

# Step 5: Check overcommit setting
log_step "Step 5: vm.overcommit_memory setting..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Overcommit Setting"
for node in "${REDIS_NODES[@]}"; do
    OC=$(remote_exec "${node}" "sysctl vm.overcommit_memory 2>/dev/null" || echo "unknown")
    echo "  ${node}: ${OC}" | tee -a "${REPORT_FILE}"
    if [[ "${OC}" == *"= 0"* ]]; then
        log_warn "${node}: overcommit=0 can cause BGSAVE to fail. Recommend setting to 1"
    fi
done

# Step 6: Manual BGSAVE test
echo ""
confirm_action "Trigger a manual BGSAVE on master to test persistence?"
MASTER=$(redis_get_master)
log_step "Triggering BGSAVE on ${MASTER}..."
redis_cmd "${MASTER}" "${REDIS_PORT}" BGSAVE 2>/dev/null
sleep 5
SAVE_STATUS=$(redis_info_section "${MASTER}" "persistence" | grep "rdb_last_bgsave_status" | cut -d: -f2 | tr -d '\r')
echo "BGSAVE status: ${SAVE_STATUS}" | tee -a "${REPORT_FILE}"

log_info "Report saved to: ${REPORT_FILE}"
