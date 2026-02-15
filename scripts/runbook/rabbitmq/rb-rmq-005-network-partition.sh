#!/bin/bash
# =============================================================================
# RB-RMQ-005: Network Partition Detected (Split Brain)
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - rabbitmq.partitions > 0
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

REPORT_FILE=$(start_report "RB-RMQ-005_Network_Partition")
log_info "=== RB-RMQ-005: Network Partition Investigation ==="
notify_slack "RB-RMQ-005: Network partition detected in ${ENVIRONMENT} - investigating" "#ff0000"

# Step 1: Check partition status on all nodes
log_step "Step 1: Checking partition status..."
report_line "${REPORT_FILE}" "Step 1: Partition Status"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo ${RABBITMQCTL} cluster_status 2>/dev/null | grep -A5 'partitions\|alarms'" | tee -a "${REPORT_FILE}" || true
done

# Step 2: Network connectivity matrix
log_step "Step 2: Network connectivity matrix..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Network Connectivity Matrix"
for src in "${RMQ_NODES[@]}"; do
    for dst in "${RMQ_NODES[@]}"; do
        if [[ "${src}" != "${dst}" ]]; then
            result=$(remote_exec "${src}" "nc -z -w 3 ${dst} ${RMQ_DIST_PORT} && echo 'OK' || echo 'FAIL'" 2>/dev/null || echo "SSH_FAIL")
            echo "  ${src} -> ${dst}:${RMQ_DIST_PORT} = ${result}" | tee -a "${REPORT_FILE}"
        fi
    done
done

# Step 3: Check Erlang distribution
log_step "Step 3: Erlang distribution status..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Erlang Cookie & Distribution"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo ${RABBITMQCTL} eval 'net_adm:ping_list(nodes()).' 2>/dev/null" | tee -a "${REPORT_FILE}" || true
done

# Step 4: Check partition handling mode
log_step "Step 4: Partition handling mode..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Partition Handling Configuration"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo ${RABBITMQCTL} eval 'application:get_env(rabbit, cluster_partition_handling).' 2>/dev/null" | tee -a "${REPORT_FILE}" || true
done

# Step 5: Remediation
log_step "Step 5: Remediation options..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Remediation"

echo ""
echo "Partition resolution strategies:"
echo "  1. [PREFERRED] Restart minority-side nodes one at a time"
echo "  2. If 'pause_minority' mode: nodes auto-pause, just fix network"
echo "  3. If 'autoheal' mode: RabbitMQ will auto-heal (may lose messages)"
echo "  4. Manual: Stop all nodes, start one, join others to it"
echo ""
echo "WARNING: Data may be lost on the minority side"
echo ""

confirm_action "Restart minority-side nodes to resolve partition? (will disconnect clients)"

# Identify the node that sees itself in partition
MINORITY_NODES=$(rmq_api "/nodes" 2>/dev/null | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    for n in nodes:
        if n.get('partitions', []):
            print(n['name'].split('@')[1])
except: pass
" 2>/dev/null)

if [[ -n "${MINORITY_NODES}" ]]; then
    while IFS= read -r mnode; do
        log_step "Restarting ${mnode}..."
        remote_exec "${mnode}" "sudo systemctl restart ${RMQ_SERVICE}" || true
        sleep 30
    done <<< "${MINORITY_NODES}"
    report_line "${REPORT_FILE}" "Restarted: ${MINORITY_NODES}"
    notify_slack "RB-RMQ-005: Restarted partition-affected nodes" "#ffaa00"
fi

# Step 6: Verify resolution
log_step "Step 6: Verifying partition resolved..."
sleep 15
rmq_cluster_status | tee -a "${REPORT_FILE}"

log_info "Report saved to: ${REPORT_FILE}"
