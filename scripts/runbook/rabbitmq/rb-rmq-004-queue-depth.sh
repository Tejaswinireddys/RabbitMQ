#!/bin/bash
# =============================================================================
# RB-RMQ-004: Queue Depth Threshold Exceeded
# =============================================================================
# Severity: P2 - High
# Trigger:  Datadog monitor - queue messages > threshold
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

QUEUE_NAME="${1:-}"
REPORT_FILE=$(start_report "RB-RMQ-004_Queue_Depth")
log_info "=== RB-RMQ-004: Queue Depth Investigation ==="

# Step 1: Current queue depths
log_step "Step 1: Queue depth overview..."
report_line "${REPORT_FILE}" "Step 1: Queue Depths (Top 20)"
rmq_queue_depths | tee -a "${REPORT_FILE}"

# Step 2: If specific queue provided, deep-dive
if [[ -n "${QUEUE_NAME}" ]]; then
    log_step "Step 2: Deep-dive on queue: ${QUEUE_NAME}"
    report_line "${REPORT_FILE}" ""
    report_line "${REPORT_FILE}" "Step 2: Queue Detail - ${QUEUE_NAME}"
    rmq_api "/queues/${RMQ_VHOST}/${QUEUE_NAME}" 2>/dev/null | python3 -c "
import sys, json
try:
    q = json.load(sys.stdin)
    print(f\"  Name: {q['name']}\")
    print(f\"  Type: {q.get('type', 'classic')}\")
    print(f\"  Durable: {q.get('durable', False)}\")
    print(f\"  Messages: {q.get('messages', 0)}\")
    print(f\"  Ready: {q.get('messages_ready', 0)}\")
    print(f\"  Unacked: {q.get('messages_unacknowledged', 0)}\")
    print(f\"  Consumers: {q.get('consumers', 0)}\")
    print(f\"  Memory: {q.get('memory', 0) / (1024*1024):.2f} MB\")
    rates = q.get('messages_details', {})
    print(f\"  Message Rate: {rates.get('rate', 0):.1f}/s\")
    pub_rates = q.get('message_stats', {}).get('publish_details', {})
    print(f\"  Publish Rate: {pub_rates.get('rate', 0):.1f}/s\")
    del_rates = q.get('message_stats', {}).get('deliver_get_details', {})
    print(f\"  Consume Rate: {del_rates.get('rate', 0):.1f}/s\")
except Exception as e: print(f'Error: {e}')
" 2>/dev/null | tee -a "${REPORT_FILE}"
fi

# Step 3: Check consumer health
log_step "Step 3: Consumer health..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Queues with zero consumers"
rmq_api "/queues/${RMQ_VHOST}" 2>/dev/null | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    orphaned = [q for q in queues if q.get('consumers', 0) == 0 and q.get('messages', 0) > 0]
    if orphaned:
        for q in sorted(orphaned, key=lambda x: -x.get('messages', 0)):
            print(f\"  {q['name']}: {q.get('messages', 0)} messages, 0 consumers\")
    else:
        print('  All queues with messages have consumers')
except: print('Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 4: Rate analysis
log_step "Step 4: Publish vs consume rate analysis..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Rate Imbalance"
rmq_api "/overview" 2>/dev/null | python3 -c "
import sys, json
try:
    o = json.load(sys.stdin)
    pub = o.get('message_stats', {}).get('publish_details', {}).get('rate', 0)
    deliver = o.get('message_stats', {}).get('deliver_get_details', {}).get('rate', 0)
    print(f\"  Global Publish Rate: {pub:.1f}/s\")
    print(f\"  Global Consume Rate: {deliver:.1f}/s\")
    if pub > 0 and deliver > 0:
        ratio = deliver / pub
        print(f\"  Consume/Publish Ratio: {ratio:.2f}\")
        if ratio < 0.8:
            print(f\"  WARNING: Consumers falling behind!\")
except: print('Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

echo ""
log_info "Recommended actions:"
echo "  1. Scale up consumers for affected queues"
echo "  2. Check consumer application logs for errors"
echo "  3. Verify consumer prefetch settings (lower = more balanced)"
echo "  4. If queue is unused, consider purging or deleting"
echo ""

log_info "Report saved to: ${REPORT_FILE}"
