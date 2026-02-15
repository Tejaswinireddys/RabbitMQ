#!/bin/bash
# =============================================================================
# RB-REDIS-005: High Latency / Slow Commands
# =============================================================================
# Severity: P2 - High
# Trigger:  Datadog monitor - redis.info.latency_ms > threshold
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

AFFECTED_NODE="${1:-}"
[[ -z "${AFFECTED_NODE}" ]] && AFFECTED_NODE=$(redis_get_master)
[[ -z "${AFFECTED_NODE}" ]] && { log_error "Usage: $0 <node>"; exit 1; }

REPORT_FILE=$(start_report "RB-REDIS-005_Latency")
log_info "=== RB-REDIS-005: Latency Investigation on ${AFFECTED_NODE} ==="

# Step 1: Current latency
log_step "Step 1: Measuring current latency..."
report_line "${REPORT_FILE}" "Step 1: Latency Measurement"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" --latency -c 10 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 2: Slowlog
log_step "Step 2: Slow log entries..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Slow Log (last 20)"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" SLOWLOG GET 20 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 3: Slowlog config
log_step "Step 3: Slowlog configuration..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Slowlog Config"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" CONFIG GET slowlog-log-slower-than 2>/dev/null | tee -a "${REPORT_FILE}"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" CONFIG GET slowlog-max-len 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 4: Check for blocking commands
log_step "Step 4: Connected clients & blocked..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Client Info"
redis_info_section "${AFFECTED_NODE}" "clients" | tee -a "${REPORT_FILE}"

# Step 5: CPU usage
log_step "Step 5: Redis CPU usage..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: CPU Stats"
redis_info_section "${AFFECTED_NODE}" "cpu" | tee -a "${REPORT_FILE}"

# Step 6: Check persistence impact
log_step "Step 6: Persistence (fork) impact..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Persistence Impact"
redis_info_section "${AFFECTED_NODE}" "persistence" | grep -E "rdb_last_bgsave|aof_last_rewrite|rdb_bgsave_in_progress|aof_rewrite_in_progress" | tee -a "${REPORT_FILE}"

# Step 7: OS-level check
log_step "Step 7: OS metrics..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 7: OS Metrics"
remote_exec "${AFFECTED_NODE}" "top -bn1 | head -15" 2>/dev/null | tee -a "${REPORT_FILE}" || true
remote_exec "${AFFECTED_NODE}" "vmstat 1 3" 2>/dev/null | tee -a "${REPORT_FILE}" || true

echo ""
log_info "Recommendations:"
echo "  1. Review slow log for KEYS, SMEMBERS, LRANGE on large collections"
echo "  2. Replace O(N) commands with SCAN-based alternatives"
echo "  3. If fork latency: schedule RDB saves during low traffic"
echo "  4. Check if swap is active (huge latency impact)"
echo "  5. Consider enabling lazyfree for async deletion"
echo ""

log_info "Report saved to: ${REPORT_FILE}"
