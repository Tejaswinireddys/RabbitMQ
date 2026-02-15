#!/bin/bash
# =============================================================================
# RB-RMQ-003: Disk Space Alarm - Publishers Blocked
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - rabbitmq.node.disk_free_alarm = true
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

REPORT_FILE=$(start_report "RB-RMQ-003_Disk_Alarm")
log_info "=== RB-RMQ-003: Disk Alarm Investigation ==="

# Step 1: Check disk alarm status
log_step "Step 1: Checking disk alarms..."
ALARMED=$(rmq_check_disk_alarm)
echo "Disk alarmed nodes: ${ALARMED:-none}" | tee -a "${REPORT_FILE}"

# Step 2: Check disk usage on all nodes
log_step "Step 2: Disk usage on all nodes..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Disk Usage"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "df -h / ${RMQ_DATA_DIR} 2>/dev/null" | tee -a "${REPORT_FILE}" || true
    remote_exec "${node}" "du -sh ${RMQ_DATA_DIR}/* 2>/dev/null | sort -rh | head -10" | tee -a "${REPORT_FILE}" || true
done

# Step 3: Check what's consuming disk
log_step "Step 3: Large files in RabbitMQ data directory..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Largest Files"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo find ${RMQ_DATA_DIR} -type f -size +100M -exec ls -lh {} \;" 2>/dev/null | tee -a "${REPORT_FILE}" || true
done

# Step 4: Check log sizes
log_step "Step 4: Log file sizes..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Log Sizes"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "du -sh ${RMQ_LOG_DIR}/* 2>/dev/null | sort -rh" | tee -a "${REPORT_FILE}" || true
done

# Step 5: Remediation
log_step "Step 5: Remediation..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Remediation Actions"

echo ""
echo "Automated cleanup options:"
echo "  1. Truncate old RabbitMQ logs"
echo "  2. Purge empty/idle queues with messages"
echo "  3. Clear Mnesia staging files"
echo ""

confirm_action "Truncate RabbitMQ log files older than 7 days on alarmed nodes?"

if [[ -n "${ALARMED}" ]]; then
    for node_name in $(echo "${ALARMED}" | tr ',' '\n'); do
        # Extract hostname from RabbitMQ node name (rabbit@hostname)
        hostname="${node_name#*@}"
        log_step "Cleaning logs on ${hostname}..."
        remote_exec "${hostname}" "sudo find ${RMQ_LOG_DIR} -name '*.log.*' -mtime +7 -delete" 2>/dev/null || true
        remote_exec "${hostname}" "sudo truncate -s 0 ${RMQ_LOG_DIR}/rabbit@*.log.1 2>/dev/null" || true
        report_line "${REPORT_FILE}" "Cleaned old logs on ${hostname}"
    done
    notify_slack "RB-RMQ-003: Cleaned old logs on alarmed nodes" "#ffaa00"
fi

# Step 6: Verify
log_step "Step 6: Post-cleanup verification..."
for node in "${RMQ_NODES[@]}"; do
    remote_exec "${node}" "df -h ${RMQ_DATA_DIR}" 2>/dev/null | tee -a "${REPORT_FILE}" || true
done

log_info "Report saved to: ${REPORT_FILE}"
