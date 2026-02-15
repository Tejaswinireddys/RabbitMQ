#!/bin/bash
# =============================================================================
# RB-RMQ-006: Connection Storm / High Connection Count
# =============================================================================
# Severity: P2 - High
# Trigger:  Datadog monitor - connections exceeds threshold
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

REPORT_FILE=$(start_report "RB-RMQ-006_Connection_Storm")
log_info "=== RB-RMQ-006: Connection Storm Investigation ==="

# Step 1: Current connection count
log_step "Step 1: Connection overview..."
report_line "${REPORT_FILE}" "Step 1: Connection Count"
rmq_connections | tee -a "${REPORT_FILE}"

# Step 2: Connections by source IP
log_step "Step 2: Connections by source IP..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Top Source IPs"
rmq_api "/connections" 2>/dev/null | python3 -c "
import sys, json
try:
    conns = json.load(sys.stdin)
    by_ip = {}
    for c in conns:
        ip = c.get('peer_host', 'unknown')
        by_ip[ip] = by_ip.get(ip, 0) + 1
    for ip, cnt in sorted(by_ip.items(), key=lambda x: -x[1])[:20]:
        print(f'  {ip}: {cnt} connections')
except: print('Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 3: Connections by vhost
log_step "Step 3: Connections by vhost..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: By VHost"
rmq_api "/connections" 2>/dev/null | python3 -c "
import sys, json
try:
    conns = json.load(sys.stdin)
    by_vhost = {}
    for c in conns:
        v = c.get('vhost', '/')
        by_vhost[v] = by_vhost.get(v, 0) + 1
    for v, cnt in sorted(by_vhost.items(), key=lambda x: -x[1]):
        print(f'  {v}: {cnt}')
except: print('Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 4: Check for connection churn
log_step "Step 4: Connection churn rate..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Connection Churn"
rmq_api "/overview" 2>/dev/null | python3 -c "
import sys, json
try:
    o = json.load(sys.stdin)
    cr = o.get('churn_rates', {})
    print(f\"  Connection Created Rate: {cr.get('connection_created_details',{}).get('rate',0):.1f}/s\")
    print(f\"  Connection Closed Rate: {cr.get('connection_closed_details',{}).get('rate',0):.1f}/s\")
    print(f\"  Channel Created Rate: {cr.get('channel_created_details',{}).get('rate',0):.1f}/s\")
    print(f\"  Channel Closed Rate: {cr.get('channel_closed_details',{}).get('rate',0):.1f}/s\")
except: print('Unable to parse')
" 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 5: Check FD usage (connections consume FDs)
log_step "Step 5: File descriptor check..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: FD Usage"
for node in "${RMQ_NODES[@]}"; do
    rmq_node_health "${node}" 2>/dev/null | grep -i "fd" | tee -a "${REPORT_FILE}" || true
done

echo ""
log_info "Recommended actions:"
echo "  1. Identify the source IP/application causing excess connections"
echo "  2. Check if application is missing connection pooling"
echo "  3. Set connection limits per vhost/user via policies"
echo "  4. If emergency: close idle connections from specific IPs"
echo ""

log_info "Report saved to: ${REPORT_FILE}"
