#!/bin/bash
# =============================================================================
# RB-RMQ-001: RabbitMQ Node Down / Unresponsive
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - RabbitMQ node health check failed
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

AFFECTED_NODE="${1:-}"
[[ -z "${AFFECTED_NODE}" ]] && { log_error "Usage: $0 <node_hostname>"; exit 1; }

REPORT_FILE=$(start_report "RB-RMQ-001_Node_Down")
log_info "=== RB-RMQ-001: Node Down Investigation for ${AFFECTED_NODE} ==="

# Step 1: Verify node is actually down
log_step "Step 1: Verifying node status..."
report_line "${REPORT_FILE}" "Step 1: Node Status Verification"
rmq_cluster_status | tee -a "${REPORT_FILE}"

# Step 2: Check network connectivity
log_step "Step 2: Checking network connectivity..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Network Connectivity"
for port in "${RMQ_PORT}" "${RMQ_MGMT_PORT}" "${RMQ_DIST_PORT}"; do
    if nc -z -w 3 "${AFFECTED_NODE}" "${port}" 2>/dev/null; then
        echo "  Port ${port}: OPEN" | tee -a "${REPORT_FILE}"
    else
        echo "  Port ${port}: CLOSED/UNREACHABLE" | tee -a "${REPORT_FILE}"
    fi
done

# Step 3: Check OS-level health via SSH
log_step "Step 3: Checking OS-level health..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: OS-Level Health"
if remote_exec "${AFFECTED_NODE}" "uptime && free -h && df -h / ${RMQ_DATA_DIR}" 2>/dev/null | tee -a "${REPORT_FILE}"; then
    log_info "SSH access OK"
else
    log_error "Cannot SSH to ${AFFECTED_NODE} - may be a host-level issue"
    report_line "${REPORT_FILE}" "SSH FAILED - escalate to infrastructure team"
    notify_slack "RB-RMQ-001: Cannot reach ${AFFECTED_NODE} via SSH - host may be down" "#ff0000"
fi

# Step 4: Check RabbitMQ service status
log_step "Step 4: Checking RabbitMQ service..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Service Status"
remote_exec "${AFFECTED_NODE}" "sudo systemctl status ${RMQ_SERVICE} --no-pager -l" 2>/dev/null | tee -a "${REPORT_FILE}" || true

# Step 5: Check recent logs
log_step "Step 5: Checking recent logs..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Recent Logs (last 50 lines)"
remote_exec "${AFFECTED_NODE}" "sudo tail -50 ${RMQ_LOG_DIR}/rabbit@*.log" 2>/dev/null | tee -a "${REPORT_FILE}" || true

# Step 6: Attempt restart if service is stopped
log_step "Step 6: Remediation..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Remediation"

SERVICE_STATUS=$(remote_exec "${AFFECTED_NODE}" "sudo systemctl is-active ${RMQ_SERVICE}" 2>/dev/null || echo "unknown")
if [[ "${SERVICE_STATUS}" != "active" ]]; then
    confirm_action "RabbitMQ is ${SERVICE_STATUS} on ${AFFECTED_NODE}. Attempt restart?"
    log_step "Restarting RabbitMQ on ${AFFECTED_NODE}..."
    remote_exec "${AFFECTED_NODE}" "sudo systemctl start ${RMQ_SERVICE}"
    sleep 20

    # Verify
    NEW_STATUS=$(remote_exec "${AFFECTED_NODE}" "sudo systemctl is-active ${RMQ_SERVICE}" 2>/dev/null || echo "unknown")
    if [[ "${NEW_STATUS}" == "active" ]]; then
        log_info "RabbitMQ restarted successfully on ${AFFECTED_NODE}"
        report_line "${REPORT_FILE}" "RESOLVED: Service restarted successfully"
        notify_slack "RB-RMQ-001: RabbitMQ on ${AFFECTED_NODE} restarted successfully" "#36a64f"
    else
        log_error "Failed to restart RabbitMQ on ${AFFECTED_NODE}"
        report_line "${REPORT_FILE}" "FAILED: Could not restart service - ESCALATE"
        notify_slack "RB-RMQ-001: Failed to restart RabbitMQ on ${AFFECTED_NODE} - ESCALATE" "#ff0000"
        trigger_pagerduty "RabbitMQ node ${AFFECTED_NODE} down and cannot restart"
    fi
else
    log_info "Service is active - checking for cluster partition or other issues"
    report_line "${REPORT_FILE}" "Service active - investigate cluster-level issues"
fi

# Step 7: Verify cluster health post-remediation
log_step "Step 7: Post-remediation cluster check..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 7: Post-Remediation Status"
rmq_cluster_status | tee -a "${REPORT_FILE}"

log_info "Report saved to: ${REPORT_FILE}"
