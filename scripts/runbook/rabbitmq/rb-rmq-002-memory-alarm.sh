#!/bin/bash
# =============================================================================
# RB-RMQ-002: Memory Alarm - Publishers Blocked
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - rabbitmq.node.mem_alarm = true
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

REPORT_FILE=$(start_report "RB-RMQ-002_Memory_Alarm")
log_info "=== RB-RMQ-002: Memory Alarm Investigation ==="

# Step 1: Identify alarmed nodes
log_step "Step 1: Identifying nodes with memory alarm..."
ALARMED=$(rmq_check_memory_alarm)
if [[ -z "${ALARMED}" ]]; then
    log_info "No memory alarms active"
    report_line "${REPORT_FILE}" "No memory alarms currently active"
    exit 0
fi
echo "Alarmed nodes: ${ALARMED}" | tee -a "${REPORT_FILE}"

# Step 2: Check memory details per node
log_step "Step 2: Memory details per node..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Node Memory Details"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    rmq_node_health "${node}" | tee -a "${REPORT_FILE}"
done

# Step 3: Identify top memory consumers (queues)
log_step "Step 3: Top queues by message depth..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Queue Depths"
rmq_queue_depths | tee -a "${REPORT_FILE}"

# Step 4: Check connections
log_step "Step 4: Connection analysis..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Connection Count"
rmq_connections | tee -a "${REPORT_FILE}"

# Step 5: Check Erlang process memory breakdown
log_step "Step 5: Erlang memory breakdown..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Erlang Memory Breakdown"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    remote_exec "${node}" "sudo rabbitmqctl eval 'rabbit_vm:memory().' 2>/dev/null" | tee -a "${REPORT_FILE}" || true
done

# Step 6: Remediation options
log_step "Step 6: Remediation..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Remediation Actions"

echo ""
echo "Recommended actions (in order):"
echo "  1. Purge stale/unused queues with high message counts"
echo "  2. Increase consumer throughput on backed-up queues"
echo "  3. Set per-queue message TTL policies"
echo "  4. Reduce prefetch count on consumers"
echo "  5. As last resort: restart affected node to release memory"
echo ""

confirm_action "Apply TTL policy (30min) on queues with >50k messages? (safe, reversible)"
log_step "Applying TTL policy..."

LARGE_QUEUES=$(rmq_api "/queues/${RMQ_VHOST}" 2>/dev/null | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    for q in queues:
        if q.get('messages', 0) > 50000:
            print(q['name'])
except: pass
" 2>/dev/null)

if [[ -n "${LARGE_QUEUES}" ]]; then
    while IFS= read -r queue; do
        log_step "Setting 30min TTL on queue: ${queue}"
        rmq_api "/policies/${RMQ_VHOST}/emergency-ttl-${queue}" \
            -X PUT -H "content-type:application/json" \
            -d "{\"pattern\":\"^${queue}$\",\"definition\":{\"message-ttl\":1800000},\"priority\":100,\"apply-to\":\"queues\"}" || true
        report_line "${REPORT_FILE}" "Applied emergency TTL on: ${queue}"
    done <<< "${LARGE_QUEUES}"
    notify_slack "RB-RMQ-002: Applied emergency TTL policy on large queues" "#ffaa00"
else
    log_info "No queues exceed 50k messages"
fi

log_info "Report saved to: ${REPORT_FILE}"
