#!/bin/bash
# =============================================================================
# RB-REDIS-002: Sentinel Quorum Lost
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - sentinel quorum < 2 or sentinel down
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

REPORT_FILE=$(start_report "RB-REDIS-002_Sentinel_Quorum")
log_info "=== RB-REDIS-002: Sentinel Quorum Investigation ==="

# Step 1: Sentinel status on all nodes
log_step "Step 1: Sentinel health check..."
report_line "${REPORT_FILE}" "Step 1: Sentinel Status"
redis_sentinel_status | tee -a "${REPORT_FILE}"

# Step 2: Sentinel master info
log_step "Step 2: Sentinel master view..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Master Info from Sentinels"
for node in "${REDIS_NODES[@]}"; do
    echo "--- Sentinel on ${node} ---" | tee -a "${REPORT_FILE}"
    sentinel_cmd "${node}" SENTINEL master "${SENTINEL_MASTER_NAME}" 2>/dev/null | \
        grep -A1 -E "^(name|ip|port|flags|num-slaves|num-other-sentinels|quorum)" | tee -a "${REPORT_FILE}" || echo "  UNREACHABLE" | tee -a "${REPORT_FILE}"
done

# Step 3: Check Sentinel logs for events
log_step "Step 3: Recent Sentinel events..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Sentinel Logs"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo tail -30 ${REDIS_LOG_DIR}/sentinel.log 2>/dev/null || sudo tail -30 /var/log/redis/redis-sentinel.log" 2>/dev/null | \
        grep -E "sdown|odown|switch-master|failover|quorum" | tee -a "${REPORT_FILE}" || true
done

# Step 4: Network connectivity between Sentinels
log_step "Step 4: Sentinel network connectivity..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Sentinel Connectivity"
for src in "${REDIS_NODES[@]}"; do
    for dst in "${REDIS_NODES[@]}"; do
        if [[ "${src}" != "${dst}" ]]; then
            result=$(remote_exec "${src}" "nc -z -w 3 ${dst} ${SENTINEL_PORT} && echo 'OK' || echo 'FAIL'" 2>/dev/null || echo "SSH_FAIL")
            echo "  ${src} -> ${dst}:${SENTINEL_PORT} = ${result}" | tee -a "${REPORT_FILE}"
        fi
    done
done

# Step 5: Remediation
log_step "Step 5: Remediation..."
DOWN_SENTINELS=()
for node in "${REDIS_NODES[@]}"; do
    PING=$(sentinel_cmd "${node}" PING 2>/dev/null)
    if [[ "${PING}" != "PONG" ]]; then
        DOWN_SENTINELS+=("${node}")
    fi
done

if [[ ${#DOWN_SENTINELS[@]} -gt 0 ]]; then
    confirm_action "Restart Sentinel on: ${DOWN_SENTINELS[*]}?"
    for node in "${DOWN_SENTINELS[@]}"; do
        log_step "Restarting Sentinel on ${node}..."
        remote_exec "${node}" "sudo systemctl restart ${SENTINEL_SERVICE}" || true
        sleep 5
    done
    report_line "${REPORT_FILE}" "Restarted Sentinel on: ${DOWN_SENTINELS[*]}"
    notify_slack "RB-REDIS-002: Restarted Sentinels on ${DOWN_SENTINELS[*]}" "#ffaa00"
fi

# Step 6: Verify quorum restored
log_step "Step 6: Verifying quorum..."
sleep 10
redis_sentinel_status | tee -a "${REPORT_FILE}"

log_info "Report saved to: ${REPORT_FILE}"
