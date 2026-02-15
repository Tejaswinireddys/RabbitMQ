#!/bin/bash
# =============================================================================
# RabbitMQ Helper Functions
# =============================================================================
# Source after common.sh:
#   source "$(dirname "$0")/../lib/rabbitmq_helpers.sh"
#
# Requires variables from environment.conf:
#   RABBITMQCTL, RABBITMQ_DIAGNOSTICS, RABBITMQ_PLUGINS, RABBITMQ_UPGRADE
#   RMQ_NODES, RMQ_MGMT_PORT, RMQ_ADMIN_USER, RMQ_ADMIN_PASS
#   RMQ_API, RMQ_VHOST, RMQ_SERVICE, RMQ_DATA_DIR, RMQ_LOG_DIR
#   RMQ_COOKIE_FILE, RMQ_MNESIA_DIR, RMQ_NODENAME_PREFIX
# =============================================================================

# --- RabbitMQ API call ---
rmq_api() {
    local endpoint="$1"
    shift
    curl -s -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${RMQ_API}${endpoint}" "$@"
}

# --- Get cluster status via CLI ---
rmq_cluster_status_cli() {
    local node="${1:-${RMQ_NODES[0]}}"
    remote_exec "${node}" "sudo ${RABBITMQCTL} cluster_status" 2>/dev/null
}

# --- Get cluster status via API ---
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

# --- Count running nodes ---
rmq_running_node_count() {
    local count=0
    for node in "${RMQ_NODES[@]}"; do
        local api="http://${node}:${RMQ_MGMT_PORT}/api"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/healthchecks/node" 2>/dev/null)
        [[ "${status}" == "200" ]] && ((count++))
    done
    echo "${count}"
}

# --- CRITICAL: Check if it's safe to take a node down ---
rmq_safe_to_stop() {
    local target_node="$1"
    local running
    running=$(rmq_running_node_count)
    if [[ ${running} -le 2 ]]; then
        log_error "UNSAFE: Only ${running} node(s) running. With pause_minority, stopping another node will HALT the cluster."
        log_error "At least 2 of 3 nodes must remain running for the cluster to function."
        return 1
    fi
    log_info "Safe to stop ${target_node}: ${running} nodes currently running"
    return 0
}

# --- Drain node before maintenance (RabbitMQ 3.12+) ---
rmq_drain_node() {
    local node="$1"
    log_step "Draining ${node} (marking for maintenance)..."
    remote_exec "${node}" "sudo ${RABBITMQ_UPGRADE} drain" 2>/dev/null
    log_info "Node ${node} drained — no new clients will connect"
}

# --- Revive node after maintenance ---
rmq_revive_node() {
    local node="$1"
    log_step "Reviving ${node} (removing maintenance mode)..."
    remote_exec "${node}" "sudo ${RABBITMQ_UPGRADE} revive" 2>/dev/null
    log_info "Node ${node} revived — accepting connections"
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

# --- Verify Erlang cookie consistency across nodes ---
rmq_verify_cookie() {
    log_step "Verifying Erlang cookie consistency..."
    local first_cookie=""
    for node in "${RMQ_NODES[@]}"; do
        local cookie
        cookie=$(remote_exec "${node}" "sudo cat ${RMQ_COOKIE_FILE} 2>/dev/null" || echo "UNREADABLE")
        if [[ -z "${first_cookie}" ]]; then
            first_cookie="${cookie}"
            echo "  ${node}: cookie=${cookie:0:8}... (reference)"
        elif [[ "${cookie}" != "${first_cookie}" ]]; then
            echo -e "  ${RED}${node}: MISMATCH — cookie differs from ${RMQ_NODES[0]}${NC}"
            log_error "Erlang cookie mismatch will prevent cluster formation"
        else
            echo -e "  ${GREEN}${node}: matches${NC}"
        fi
    done
}

# --- Check quorum queue health ---
rmq_quorum_queue_health() {
    rmq_api "/queues/${RMQ_VHOST}" 2>/dev/null | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    quorum_qs = [q for q in queues if q.get('type') == 'quorum']
    print(f'  Total quorum queues: {len(quorum_qs)}')
    for q in quorum_qs:
        members = len(q.get('members', []))
        online = len(q.get('online', []))
        if online < members:
            print(f\"  WARNING: {q['name']} — {online}/{members} members online\")
except: print('  Unable to parse')
" 2>/dev/null
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

# --- Restart RabbitMQ on a node (with safety check) ---
rmq_restart_node() {
    local node="$1"

    # Safety check: ensure quorum maintained
    if ! rmq_safe_to_stop "${node}"; then
        log_error "Aborting restart — would break cluster quorum"
        return 1
    fi

    confirm_action "About to restart RabbitMQ on ${node}. This will disconnect clients."
    log_step "Draining ${node} before restart..."
    rmq_drain_node "${node}" 2>/dev/null || true
    sleep 5

    log_step "Stopping RabbitMQ on ${node}..."
    remote_exec "${node}" "sudo systemctl stop ${RMQ_SERVICE}"
    sleep 5

    log_step "Starting RabbitMQ on ${node}..."
    remote_exec "${node}" "sudo systemctl start ${RMQ_SERVICE}"
    sleep 15

    log_step "Reviving ${node}..."
    rmq_revive_node "${node}" 2>/dev/null || true

    log_step "Verifying ${node} rejoined cluster..."
    remote_exec "${node}" "sudo ${RABBITMQCTL} cluster_status"
}

# --- Check feature flags ---
rmq_feature_flags() {
    local node="${1:-${RMQ_NODES[0]}}"
    remote_exec "${node}" "sudo ${RABBITMQCTL} list_feature_flags" 2>/dev/null
}
