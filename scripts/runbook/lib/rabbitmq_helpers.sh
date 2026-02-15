#!/bin/bash
# =============================================================================
# RabbitMQ Helper Functions
# =============================================================================
# Source after common.sh:
#   source "$(dirname "$0")/../lib/rabbitmq_helpers.sh"
# =============================================================================

# --- RabbitMQ API call ---
rmq_api() {
    local endpoint="$1"
    curl -s -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${RMQ_API}${endpoint}"
}

# --- Get cluster status ---
rmq_cluster_status() {
    for node in "${RMQ_NODES[@]}"; do
        local api="http://${node}:${RMQ_MGMT_PORT}/api"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/healthchecks/node" 2>/dev/null)
        if [[ "${status}" == "200" ]]; then
            echo -e "  ${GREEN}[UP]${NC}   ${node}"
        else
            echo -e "  ${RED}[DOWN]${NC} ${node}"
        fi
    done
}

# --- Get node health ---
rmq_node_health() {
    local node="$1"
    local api="http://${node}:${RMQ_MGMT_PORT}/api"
    curl -s -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/nodes" 2>/dev/null | \
        python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    for n in nodes:
        if '${node}' in n.get('name',''):
            print(f\"  Memory Used: {n.get('mem_used',0)/(1024**3):.2f} GB\")
            print(f\"  Memory Limit: {n.get('mem_limit',0)/(1024**3):.2f} GB\")
            print(f\"  Disk Free: {n.get('disk_free',0)/(1024**3):.2f} GB\")
            print(f\"  FD Used: {n.get('fd_used',0)}/{n.get('fd_total',0)}\")
            print(f\"  Proc Used: {n.get('proc_used',0)}/{n.get('proc_total',0)}\")
            print(f\"  Uptime: {n.get('uptime',0)//1000//3600}h\")
            print(f\"  Running: {n.get('running',False)}\")
            print(f\"  Memory Alarm: {n.get('mem_alarm',False)}\")
            print(f\"  Disk Alarm: {n.get('disk_free_alarm',False)}\")
except: print('  Unable to parse node info')
" 2>/dev/null
}

# --- Check memory alarm ---
rmq_check_memory_alarm() {
    local alarmed
    alarmed=$(rmq_api "/nodes" 2>/dev/null | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    print(','.join([n['name'] for n in nodes if n.get('mem_alarm', False)]))
except: pass
" 2>/dev/null)
    echo "${alarmed}"
}

# --- Check disk alarm ---
rmq_check_disk_alarm() {
    local alarmed
    alarmed=$(rmq_api "/nodes" 2>/dev/null | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    print(','.join([n['name'] for n in nodes if n.get('disk_free_alarm', False)]))
except: pass
" 2>/dev/null)
    echo "${alarmed}"
}

# --- List queues with depth ---
rmq_queue_depths() {
    local vhost="${1:-${RMQ_VHOST}}"
    rmq_api "/queues/${vhost}" 2>/dev/null | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    queues.sort(key=lambda q: q.get('messages', 0), reverse=True)
    print(f\"{'Queue':<50} {'Messages':>10} {'Ready':>10} {'Unacked':>10} {'Consumers':>10}\")
    print('-' * 92)
    for q in queues[:20]:
        print(f\"{q['name']:<50} {q.get('messages',0):>10} {q.get('messages_ready',0):>10} {q.get('messages_unacknowledged',0):>10} {q.get('consumers',0):>10}\")
except: print('Unable to parse queue data')
" 2>/dev/null
}

# --- List connections ---
rmq_connections() {
    rmq_api "/connections" 2>/dev/null | python3 -c "
import sys, json
try:
    conns = json.load(sys.stdin)
    print(f'Total connections: {len(conns)}')
    by_user = {}
    for c in conns:
        u = c.get('user','unknown')
        by_user[u] = by_user.get(u, 0) + 1
    for u, cnt in sorted(by_user.items(), key=lambda x: -x[1]):
        print(f'  {u}: {cnt}')
except: print('Unable to parse connection data')
" 2>/dev/null
}

# --- Restart RabbitMQ on a node (with confirmation) ---
rmq_restart_node() {
    local node="$1"
    confirm_action "About to restart RabbitMQ on ${node}. This will disconnect clients."
    log_step "Stopping RabbitMQ on ${node}..."
    remote_exec "${node}" "sudo systemctl stop ${RMQ_SERVICE}"
    sleep 5
    log_step "Starting RabbitMQ on ${node}..."
    remote_exec "${node}" "sudo systemctl start ${RMQ_SERVICE}"
    sleep 15
    log_step "Verifying ${node} rejoined cluster..."
    remote_exec "${node}" "sudo rabbitmqctl cluster_status"
}
