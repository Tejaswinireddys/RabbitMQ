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

# --- Default CLI timeout (seconds) to prevent hangs ---
RMQ_CLI_TIMEOUT="${RMQ_CLI_TIMEOUT:-60}"

# =============================================================================
# WHY rabbitmqctl list_queues HANGS:
# =============================================================================
# rabbitmqctl list_queues contacts EVERY queue leader across the cluster.
# It HANGS when:
#   1. A quorum queue leader is on a node that is down/unreachable
#   2. The Mnesia stats database is overloaded
#   3. A classic mirrored queue's master is on a paused node
#   4. Network partition exists (minority-side queues are unreachable)
#
# SOLUTION: Use the Management HTTP API instead (rmq_list_queues below).
#   - The API returns cached stats (doesn't block on each queue)
#   - If CLI is needed, ALWAYS use --timeout flag
#   - Use --local flag to only query queues on the local node (fast)
# =============================================================================

# --- RabbitMQ API call ---
rmq_api() {
    local endpoint="$1"
    shift
    curl -s --max-time 30 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${RMQ_API}${endpoint}" "$@"
}

# --- RabbitMQ API call against a specific node ---
rmq_api_node() {
    local node="$1"
    local endpoint="$2"
    shift 2
    curl -s --max-time 30 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "http://${node}:${RMQ_MGMT_PORT}/api${endpoint}" "$@"
}

# --- rabbitmqctl with timeout (prevents hanging) ---
rmq_ctl() {
    local node="${1}"
    shift
    remote_exec "${node}" "sudo timeout ${RMQ_CLI_TIMEOUT} ${RABBITMQCTL} $*" 2>/dev/null
}

# --- rabbitmq-diagnostics with timeout ---
rmq_diag() {
    local node="${1}"
    shift
    remote_exec "${node}" "sudo timeout ${RMQ_CLI_TIMEOUT} ${RABBITMQ_DIAGNOSTICS} $*" 2>/dev/null
}

# =============================================================================
# QUEUE LISTING — uses API (never hangs), with CLI fallback
# =============================================================================

# --- List queues via HTTP API (PREFERRED — never hangs) ---
rmq_list_queues() {
    local vhost="${1:-${RMQ_VHOST}}"
    local node="${2:-}"
    local api_url

    # Try each node until one responds
    local nodes_to_try=()
    if [[ -n "${node}" ]]; then
        nodes_to_try=("${node}")
    else
        nodes_to_try=("${RMQ_NODES[@]}")
    fi

    for try_node in "${nodes_to_try[@]}"; do
        local result
        result=$(curl -s --max-time 15 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" \
            "http://${try_node}:${RMQ_MGMT_PORT}/api/queues/${vhost}?columns=name,messages,messages_ready,messages_unacknowledged,consumers,type,state,node,leader" 2>/dev/null)

        if [[ -n "${result}" && "${result}" != *"error"* && "${result}" != *"not_found"* ]]; then
            echo "${result}" | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    if not queues:
        print('  No queues found')
        sys.exit(0)
    queues.sort(key=lambda q: q.get('messages', 0), reverse=True)
    print(f\"{'Queue':<40} {'Type':<8} {'Messages':>10} {'Ready':>10} {'Unacked':>10} {'Consumers':>10} {'State':<10} {'Leader/Node':<20}\")
    print('-' * 130)
    for q in queues:
        leader = q.get('leader', q.get('node', 'N/A'))
        if leader: leader = leader.split('@')[-1] if '@' in str(leader) else str(leader)
        print(f\"{q['name']:<40} {q.get('type','classic'):<8} {q.get('messages',0):>10} {q.get('messages_ready',0):>10} {q.get('messages_unacknowledged',0):>10} {q.get('consumers',0):>10} {q.get('state','unknown'):<10} {leader:<20}\")
    print(f\"\nTotal queues: {len(queues)}\")
except Exception as e:
    print(f'Error parsing queue data: {e}')
" 2>/dev/null
            return 0
        fi
    done

    log_error "Could not reach any management API node for queue listing"
    log_warn "Falling back to CLI (may hang if a queue leader is on a down node)..."
    log_warn "Using --timeout ${RMQ_CLI_TIMEOUT}s and --local flag"

    # Fallback: CLI with timeout + --local (only local queues, won't hang on remote)
    for try_node in "${RMQ_NODES[@]}"; do
        rmq_ctl "${try_node}" "list_queues --local name messages consumers type --formatter=table --timeout ${RMQ_CLI_TIMEOUT}000" && return 0 || true
    done

    log_error "All queue listing methods failed"
    return 1
}

# --- List queues by depth (top N, API-based) ---
rmq_queue_depths() {
    local vhost="${1:-${RMQ_VHOST}}"
    rmq_list_queues "${vhost}"
}

# --- List queues LOCAL to a specific node only (CLI, fast) ---
rmq_list_queues_local() {
    local node="${1:-${RMQ_NODES[0]}}"
    log_info "Listing queues local to ${node} only (--local flag, will NOT hang)..."
    rmq_ctl "${node}" "list_queues --local name messages consumers type state --formatter=table --timeout ${RMQ_CLI_TIMEOUT}000"
}

# --- Count queues per node (which node leads how many queues) ---
rmq_queue_leader_distribution() {
    local vhost="${1:-${RMQ_VHOST}}"
    for try_node in "${RMQ_NODES[@]}"; do
        local result
        result=$(curl -s --max-time 15 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" \
            "http://${try_node}:${RMQ_MGMT_PORT}/api/queues/${vhost}?columns=name,type,node,leader" 2>/dev/null)
        if [[ -n "${result}" && "${result}" != *"error"* ]]; then
            echo "${result}" | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    leaders = {}
    types = {}
    for q in queues:
        leader = q.get('leader', q.get('node', 'unknown'))
        leaders[leader] = leaders.get(leader, 0) + 1
        qt = q.get('type', 'classic')
        types[qt] = types.get(qt, 0) + 1
    print('Queue Leader Distribution:')
    for node, cnt in sorted(leaders.items(), key=lambda x: -x[1]):
        short = node.split('@')[-1] if '@' in node else node
        print(f'  {short}: {cnt} queues')
    print(f'\nQueue Types:')
    for qt, cnt in sorted(types.items(), key=lambda x: -x[1]):
        print(f'  {qt}: {cnt}')
    print(f'\nTotal queues: {len(queues)}')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
            return 0
        fi
    done
    log_error "Could not reach management API"
    return 1
}

# =============================================================================
# CLUSTER STATUS & NODE HEALTH
# =============================================================================

# --- Get cluster status via CLI (with timeout) ---
rmq_cluster_status_cli() {
    local node="${1:-${RMQ_NODES[0]}}"
    rmq_ctl "${node}" "cluster_status"
}

# --- Get cluster status via API ---
rmq_cluster_status() {
    for node in "${RMQ_NODES[@]}"; do
        local api="http://${node}:${RMQ_MGMT_PORT}/api"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/healthchecks/node" 2>/dev/null)
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
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/healthchecks/node" 2>/dev/null)
        [[ "${status}" == "200" ]] && ((count++))
    done
    echo "${count}"
}

# --- Get running node names ---
rmq_running_nodes() {
    local running=()
    for node in "${RMQ_NODES[@]}"; do
        local api="http://${node}:${RMQ_MGMT_PORT}/api"
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/healthchecks/node" 2>/dev/null)
        [[ "${status}" == "200" ]] && running+=("${node}")
    done
    echo "${running[@]}"
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

# --- Check if a specific node is quorum-critical ---
rmq_is_quorum_critical() {
    local node="$1"
    local result
    result=$(rmq_ctl "${node}" "eval 'rabbit_maintenance:is_being_drained_consistent_read(node()).' --timeout ${RMQ_CLI_TIMEOUT}000" 2>/dev/null)
    # Use diagnostics check (more reliable)
    rmq_diag "${node}" "check_if_node_is_quorum_critical --timeout ${RMQ_CLI_TIMEOUT}000" 2>/dev/null
    return $?
}

# --- Drain node before maintenance (RabbitMQ 3.12+) ---
rmq_drain_node() {
    local node="$1"
    log_step "Draining ${node} (marking for maintenance)..."
    remote_exec "${node}" "sudo timeout ${RMQ_CLI_TIMEOUT} ${RABBITMQ_UPGRADE} drain" 2>/dev/null
    log_info "Node ${node} drained — no new clients will connect"
}

# --- Revive node after maintenance ---
rmq_revive_node() {
    local node="$1"
    log_step "Reviving ${node} (removing maintenance mode)..."
    remote_exec "${node}" "sudo timeout ${RMQ_CLI_TIMEOUT} ${RABBITMQ_UPGRADE} revive" 2>/dev/null
    log_info "Node ${node} revived — accepting connections"
}

# --- Get node health ---
rmq_node_health() {
    local node="$1"
    local api="http://${node}:${RMQ_MGMT_PORT}/api"
    curl -s --max-time 15 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${api}/nodes" 2>/dev/null | \
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
    rmq_ctl "${node}" "cluster_status"
}

# --- Check feature flags ---
rmq_feature_flags() {
    local node="${1:-${RMQ_NODES[0]}}"
    rmq_ctl "${node}" "list_feature_flags --timeout ${RMQ_CLI_TIMEOUT}000"
}

# --- Wait for quorum sync after restart ---
rmq_await_quorum_sync() {
    local node="$1"
    log_step "Waiting for quorum queues to sync on ${node} (may take minutes)..."
    rmq_ctl "${node}" "await_online_quorum_plus_one --timeout 300000"
    local rc=$?
    if [[ ${rc} -eq 0 ]]; then
        log_info "Quorum sync complete on ${node}"
    else
        log_warn "Quorum sync timed out or failed on ${node} — check manually"
    fi
    return ${rc}
}
