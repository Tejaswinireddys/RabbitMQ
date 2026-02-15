#!/bin/bash
# =============================================================================
# RB-REDIS-001: Redis Node Down / Unresponsive
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - redis.ping failed / redis.net.connected = 0
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

AFFECTED_NODE="${1:-}"
[[ -z "${AFFECTED_NODE}" ]] && { log_error "Usage: $0 <node_hostname>"; exit 1; }

REPORT_FILE=$(start_report "RB-REDIS-001_Node_Down")
log_info "=== RB-REDIS-001: Redis Node Down Investigation for ${AFFECTED_NODE} ==="

# Step 1: Verify node status
log_step "Step 1: Verifying Redis cluster status..."
report_line "${REPORT_FILE}" "Step 1: Cluster Status"
redis_cluster_status | tee -a "${REPORT_FILE}"

# Step 2: Check Sentinel view
log_step "Step 2: Sentinel perspective..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Sentinel Status"
redis_sentinel_status | tee -a "${REPORT_FILE}"

# Step 3: Network connectivity
log_step "Step 3: Network connectivity..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Network Connectivity"
for port in "${REDIS_PORT}" "${SENTINEL_PORT}"; do
    if nc -z -w 3 "${AFFECTED_NODE}" "${port}" 2>/dev/null; then
        echo "  ${AFFECTED_NODE}:${port} OPEN" | tee -a "${REPORT_FILE}"
    else
        echo "  ${AFFECTED_NODE}:${port} CLOSED/UNREACHABLE" | tee -a "${REPORT_FILE}"
    fi
done

# Step 4: OS-level check
log_step "Step 4: OS-level health..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: OS Health"
if remote_exec "${AFFECTED_NODE}" "uptime && free -h && df -h / ${REDIS_DATA_DIR}" 2>/dev/null | tee -a "${REPORT_FILE}"; then
    log_info "SSH access OK"
else
    log_error "Cannot SSH to ${AFFECTED_NODE}"
    notify_slack "RB-REDIS-001: Cannot reach ${AFFECTED_NODE} - host may be down" "#ff0000"
fi

# Step 5: Service status
log_step "Step 5: Redis service status..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Service Status"
remote_exec "${AFFECTED_NODE}" "sudo systemctl status ${REDIS_SERVICE} --no-pager -l" 2>/dev/null | tee -a "${REPORT_FILE}" || true
remote_exec "${AFFECTED_NODE}" "sudo systemctl status ${SENTINEL_SERVICE} --no-pager -l" 2>/dev/null | tee -a "${REPORT_FILE}" || true

# Step 6: Recent logs
log_step "Step 6: Recent Redis logs..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Recent Logs"
remote_exec "${AFFECTED_NODE}" "sudo tail -30 ${REDIS_LOG_DIR}/redis.log" 2>/dev/null | tee -a "${REPORT_FILE}" || true

# Step 7: Remediation
log_step "Step 7: Remediation..."
SERVICE_STATUS=$(remote_exec "${AFFECTED_NODE}" "sudo systemctl is-active ${REDIS_SERVICE}" 2>/dev/null || echo "unknown")
if [[ "${SERVICE_STATUS}" != "active" ]]; then
    ROLE=$(redis_role "${AFFECTED_NODE}" 2>/dev/null || echo "unknown")
    confirm_action "Redis is ${SERVICE_STATUS} on ${AFFECTED_NODE} (was: ${ROLE}). Attempt restart?"

    remote_exec "${AFFECTED_NODE}" "sudo systemctl start ${REDIS_SERVICE}"
    sleep 5

    PING=$(redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" PING 2>/dev/null)
    if [[ "${PING}" == "PONG" ]]; then
        log_info "Redis restarted successfully on ${AFFECTED_NODE}"
        report_line "${REPORT_FILE}" "RESOLVED: Redis restarted"
        notify_slack "RB-REDIS-001: Redis on ${AFFECTED_NODE} recovered" "#36a64f"
    else
        log_error "Redis failed to start on ${AFFECTED_NODE}"
        report_line "${REPORT_FILE}" "FAILED: Redis did not start - ESCALATE"
        notify_slack "RB-REDIS-001: Redis restart failed on ${AFFECTED_NODE} - ESCALATE" "#ff0000"
        trigger_pagerduty "Redis node ${AFFECTED_NODE} down and cannot restart"
    fi

    # Ensure Sentinel is also running
    remote_exec "${AFFECTED_NODE}" "sudo systemctl start ${SENTINEL_SERVICE}" 2>/dev/null || true
fi

# Step 8: Post-check
log_step "Step 8: Post-remediation check..."
redis_cluster_status | tee -a "${REPORT_FILE}"

log_info "Report saved to: ${REPORT_FILE}"
