#!/bin/bash
# =============================================================================
# RB-RMQ-007: Comprehensive RabbitMQ Health Check
# =============================================================================
# Use: Scheduled daily or on-demand verification of cluster health
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

REPORT_FILE=$(start_report "RabbitMQ_Health_Check")
ISSUES=0

log_info "=== RabbitMQ Comprehensive Health Check ==="
log_info "Environment: ${ENVIRONMENT} | Nodes: ${RMQ_NODES[*]}"
separator

# 1. Cluster Membership
log_step "1. Cluster Status"
report_line "${REPORT_FILE}" "1. CLUSTER STATUS"
rmq_cluster_status | tee -a "${REPORT_FILE}"
report_line "${REPORT_FILE}" ""

# 2. Node Health
log_step "2. Node Health"
report_line "${REPORT_FILE}" "2. NODE HEALTH"
for node in "${RMQ_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    rmq_node_health "${node}" | tee -a "${REPORT_FILE}"
done
report_line "${REPORT_FILE}" ""

# 3. Memory Alarms
log_step "3. Memory Alarm Check"
report_line "${REPORT_FILE}" "3. MEMORY ALARMS"
ALARMED=$(rmq_check_memory_alarm)
if [[ -n "${ALARMED}" ]]; then
    echo -e "  ${RED}ALARM: ${ALARMED}${NC}" | tee -a "${REPORT_FILE}"
    ((ISSUES++))
else
    echo -e "  ${GREEN}No memory alarms${NC}" | tee -a "${REPORT_FILE}"
fi
report_line "${REPORT_FILE}" ""

# 4. Disk Alarms
log_step "4. Disk Alarm Check"
report_line "${REPORT_FILE}" "4. DISK ALARMS"
DISK_ALARMED=$(rmq_check_disk_alarm)
if [[ -n "${DISK_ALARMED}" ]]; then
    echo -e "  ${RED}ALARM: ${DISK_ALARMED}${NC}" | tee -a "${REPORT_FILE}"
    ((ISSUES++))
else
    echo -e "  ${GREEN}No disk alarms${NC}" | tee -a "${REPORT_FILE}"
fi
report_line "${REPORT_FILE}" ""

# 5. Partitions
log_step "5. Partition Check"
report_line "${REPORT_FILE}" "5. NETWORK PARTITIONS"
PARTITIONS=$(rmq_api "/nodes" 2>/dev/null | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    parts = [n['name'] for n in nodes if n.get('partitions', [])]
    if parts: print(','.join(parts))
except: pass
" 2>/dev/null)
if [[ -n "${PARTITIONS}" ]]; then
    echo -e "  ${RED}PARTITIONS DETECTED: ${PARTITIONS}${NC}" | tee -a "${REPORT_FILE}"
    ((ISSUES++))
else
    echo -e "  ${GREEN}No partitions${NC}" | tee -a "${REPORT_FILE}"
fi
report_line "${REPORT_FILE}" ""

# 6. Queue Health
log_step "6. Queue Depth Check"
report_line "${REPORT_FILE}" "6. QUEUE DEPTH"
DEEP_QUEUES=$(rmq_api "/queues/${RMQ_VHOST}" 2>/dev/null | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    deep = [q for q in queues if q.get('messages', 0) > ${RMQ_QUEUE_DEPTH_WARN}]
    for q in sorted(deep, key=lambda x: -x.get('messages', 0)):
        print(f\"  WARNING: {q['name']} = {q.get('messages',0)} messages\")
    if not deep: print('  All queues within threshold')
except: print('  Unable to check')
" 2>/dev/null)
echo "${DEEP_QUEUES}" | tee -a "${REPORT_FILE}"
report_line "${REPORT_FILE}" ""

# 7. Connection Count
log_step "7. Connection Count"
report_line "${REPORT_FILE}" "7. CONNECTIONS"
rmq_connections | tee -a "${REPORT_FILE}"
report_line "${REPORT_FILE}" ""

# 8. Overview Stats
log_step "8. Message Rates"
report_line "${REPORT_FILE}" "8. MESSAGE RATES"
rmq_api "/overview" 2>/dev/null | python3 -c "
import sys, json
try:
    o = json.load(sys.stdin)
    ms = o.get('message_stats', {})
    print(f\"  Publish Rate: {ms.get('publish_details',{}).get('rate',0):.1f}/s\")
    print(f\"  Deliver Rate: {ms.get('deliver_get_details',{}).get('rate',0):.1f}/s\")
    print(f\"  Ack Rate: {ms.get('ack_details',{}).get('rate',0):.1f}/s\")
    q = o.get('queue_totals', {})
    print(f\"  Total Messages: {q.get('messages',0)}\")
    print(f\"  Total Queues: {o.get('object_totals',{}).get('queues',0)}\")
except: print('  Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

separator
if [[ ${ISSUES} -eq 0 ]]; then
    log_info "Health check PASSED - no critical issues found"
    report_line "${REPORT_FILE}" ""
    report_line "${REPORT_FILE}" "RESULT: PASSED - No critical issues"
else
    log_warn "Health check found ${ISSUES} issue(s) - review report"
    report_line "${REPORT_FILE}" ""
    report_line "${REPORT_FILE}" "RESULT: ${ISSUES} ISSUE(S) FOUND - Review above"
fi

log_info "Report saved to: ${REPORT_FILE}"
