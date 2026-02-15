#!/bin/bash
# =============================================================================
# RB-RMQ-008: Restart Decision — Which Node Can I Safely Restart?
# =============================================================================
# Purpose: Run BEFORE any restart/patching to determine which node is safe
#          to take down without breaking the cluster.
#
# Usage:
#   ./rb-rmq-008-restart-decision.sh                  # Analyze all nodes
#   ./rb-rmq-008-restart-decision.sh rabbitmq-node1   # Check specific node
#
# Output:
#   - Per-node safety verdict: SAFE / UNSAFE / WARNING
#   - Recommended restart order
#   - Queue leader distribution (which node leads most queues)
#   - Quorum-critical status
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/rabbitmq_helpers.sh"

TARGET_NODE="${1:-}"
REPORT_FILE=$(start_report "RB-RMQ-008_Restart_Decision")

log_info "============================================================"
log_info "  RabbitMQ Restart Decision Analysis"
log_info "  Environment: ${ENVIRONMENT}"
log_info "  Cluster: ${RMQ_NODES[*]}"
log_info "============================================================"
echo "" | tee -a "${REPORT_FILE}"

# =============================================================================
# STEP 1: Cluster Liveness — How many nodes are up?
# =============================================================================
log_step "Step 1: Cluster Liveness Check"
report_line "${REPORT_FILE}" "=== STEP 1: CLUSTER LIVENESS ==="

RUNNING_COUNT=0
RUNNING_LIST=()
DOWN_LIST=()

for node in "${RMQ_NODES[@]}"; do
    local_api="http://${node}:${RMQ_MGMT_PORT}/api"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
        -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" "${local_api}/healthchecks/node" 2>/dev/null)
    if [[ "${http_code}" == "200" ]]; then
        echo -e "  ${GREEN}[UP]${NC}     ${node}" | tee -a "${REPORT_FILE}"
        ((RUNNING_COUNT++))
        RUNNING_LIST+=("${node}")
    else
        echo -e "  ${RED}[DOWN]${NC}   ${node}" | tee -a "${REPORT_FILE}"
        DOWN_LIST+=("${node}")
    fi
done

echo "" | tee -a "${REPORT_FILE}"
echo "  Running: ${RUNNING_COUNT} of ${#RMQ_NODES[@]}" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Immediate verdict based on running count
if [[ ${RUNNING_COUNT} -le 1 ]]; then
    echo -e "  ${RED}VERDICT: CLUSTER IS HALTED — only ${RUNNING_COUNT} node(s) running${NC}" | tee -a "${REPORT_FILE}"
    echo "  With pause_minority, a single node pauses itself." | tee -a "${REPORT_FILE}"
    echo "  ACTION: Bring DOWN nodes back up IMMEDIATELY. Do NOT restart the running node." | tee -a "${REPORT_FILE}"
    log_error "Cannot restart any node — cluster is already down/paused"
    notify_slack "RB-RMQ-008: Cluster has ${RUNNING_COUNT} node(s) — HALTED. Bring nodes up." "#ff0000"
    log_info "Report saved to: ${REPORT_FILE}"
    exit 1
fi

if [[ ${RUNNING_COUNT} -eq 2 ]]; then
    echo -e "  ${RED}WARNING: Only 2 nodes running — DO NOT restart another node!${NC}" | tee -a "${REPORT_FILE}"
    echo "  Restarting any of the 2 running nodes will cause the remaining 1 to pause (pause_minority)." | tee -a "${REPORT_FILE}"
    echo "  This means TOTAL cluster outage." | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    if [[ ${#DOWN_LIST[@]} -gt 0 ]]; then
        echo "  The DOWN node(s) must be brought back up FIRST: ${DOWN_LIST[*]}" | tee -a "${REPORT_FILE}"
        echo "  After all 3 nodes are running, you can restart one at a time." | tee -a "${REPORT_FILE}"
    fi
fi

# =============================================================================
# STEP 2: Alarm Check — Are there active memory/disk alarms?
# =============================================================================
log_step "Step 2: Alarm Check"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 2: ALARM CHECK ==="

MEM_ALARMED=$(rmq_check_memory_alarm)
DISK_ALARMED=$(rmq_check_disk_alarm)
HAS_ALARM=false

if [[ -n "${MEM_ALARMED}" ]]; then
    echo -e "  ${RED}MEMORY ALARM on: ${MEM_ALARMED}${NC}" | tee -a "${REPORT_FILE}"
    echo "  Publishers are BLOCKED cluster-wide." | tee -a "${REPORT_FILE}"
    echo "  Resolve alarm before restarting nodes." | tee -a "${REPORT_FILE}"
    HAS_ALARM=true
else
    echo -e "  ${GREEN}No memory alarms${NC}" | tee -a "${REPORT_FILE}"
fi

if [[ -n "${DISK_ALARMED}" ]]; then
    echo -e "  ${RED}DISK ALARM on: ${DISK_ALARMED}${NC}" | tee -a "${REPORT_FILE}"
    echo "  Publishers are BLOCKED cluster-wide." | tee -a "${REPORT_FILE}"
    echo "  Resolve alarm before restarting nodes." | tee -a "${REPORT_FILE}"
    HAS_ALARM=true
else
    echo -e "  ${GREEN}No disk alarms${NC}" | tee -a "${REPORT_FILE}"
fi

# =============================================================================
# STEP 3: Partition Check
# =============================================================================
log_step "Step 3: Partition Check"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 3: PARTITION CHECK ==="

PARTITION_NODES=$(rmq_api "/nodes" 2>/dev/null | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    parts = [n['name'] for n in nodes if n.get('partitions', [])]
    if parts: print(','.join(parts))
except: pass
" 2>/dev/null)

if [[ -n "${PARTITION_NODES}" ]]; then
    echo -e "  ${RED}NETWORK PARTITION DETECTED: ${PARTITION_NODES}${NC}" | tee -a "${REPORT_FILE}"
    echo "  Resolve partition BEFORE any restarts." | tee -a "${REPORT_FILE}"
    echo "  See runbook: rb-rmq-005-network-partition.sh" | tee -a "${REPORT_FILE}"
else
    echo -e "  ${GREEN}No partitions detected${NC}" | tee -a "${REPORT_FILE}"
fi

# =============================================================================
# STEP 4: Queue Leader Distribution — Which node leads the most queues?
# =============================================================================
log_step "Step 4: Queue Leader Distribution (via API — will not hang)"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 4: QUEUE LEADER DISTRIBUTION ==="

# Get full queue data from API
QUEUE_DATA=""
for try_node in "${RUNNING_LIST[@]}"; do
    QUEUE_DATA=$(curl -s --max-time 15 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" \
        "http://${try_node}:${RMQ_MGMT_PORT}/api/queues/${RMQ_VHOST}?columns=name,type,node,leader,messages,messages_ready,consumers,state" 2>/dev/null)
    if [[ -n "${QUEUE_DATA}" && "${QUEUE_DATA}" != *"error"* ]]; then
        break
    fi
done

if [[ -n "${QUEUE_DATA}" && "${QUEUE_DATA}" != *"error"* ]]; then
    echo "${QUEUE_DATA}" | python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    if not queues:
        print('  No queues found')
        sys.exit(0)

    # Count leaders per node
    leaders = {}
    total_msgs = {}
    quorum_leaders = {}
    for q in queues:
        leader = q.get('leader', q.get('node', 'unknown'))
        short = leader.split('@')[-1] if '@' in leader else leader
        leaders[short] = leaders.get(short, 0) + 1
        total_msgs[short] = total_msgs.get(short, 0) + q.get('messages', 0)
        if q.get('type') == 'quorum':
            quorum_leaders[short] = quorum_leaders.get(short, 0) + 1

    print(f\"{'Node':<30} {'Total Queues':>15} {'Quorum Queues':>15} {'Messages Led':>15}\")
    print('-' * 77)
    for node in sorted(leaders.keys()):
        print(f\"{node:<30} {leaders[node]:>15} {quorum_leaders.get(node,0):>15} {total_msgs.get(node,0):>15}\")
    print(f\"\nTotal queues: {len(queues)}\")

    # Find safest node to restart (fewest queues/messages)
    if leaders:
        safest = min(leaders.keys(), key=lambda n: (quorum_leaders.get(n, 0), total_msgs.get(n, 0)))
        busiest = max(leaders.keys(), key=lambda n: (quorum_leaders.get(n, 0), total_msgs.get(n, 0)))
        print(f\"\n  Recommended restart order:\")
        ordered = sorted(leaders.keys(), key=lambda n: (quorum_leaders.get(n, 0), total_msgs.get(n, 0)))
        for i, n in enumerate(ordered, 1):
            print(f\"    {i}. {n} ({leaders[n]} queues, {quorum_leaders.get(n,0)} quorum, {total_msgs.get(n,0)} messages)\")
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null | tee -a "${REPORT_FILE}"
else
    echo "  Could not retrieve queue data from API" | tee -a "${REPORT_FILE}"
fi

# =============================================================================
# STEP 5: Quorum-Critical Check per Node
# =============================================================================
log_step "Step 5: Quorum-Critical Check"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 5: QUORUM-CRITICAL STATUS ==="
echo "" | tee -a "${REPORT_FILE}"
echo "  (A node is quorum-critical if it's the LAST online member of any quorum queue." | tee -a "${REPORT_FILE}"
echo "   Stopping a quorum-critical node makes those queues UNAVAILABLE.)" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

for node in "${RUNNING_LIST[@]}"; do
    echo -n "  ${node}: " | tee -a "${REPORT_FILE}"
    diag_result=$(rmq_diag "${node}" "check_if_node_is_quorum_critical --timeout ${RMQ_CLI_TIMEOUT}000" 2>&1)
    diag_rc=$?
    if [[ ${diag_rc} -eq 0 ]]; then
        echo -e "${GREEN}NOT quorum-critical — safe to restart${NC}" | tee -a "${REPORT_FILE}"
    else
        echo -e "${RED}QUORUM-CRITICAL — do NOT restart until other nodes sync${NC}" | tee -a "${REPORT_FILE}"
        echo "    ${diag_result}" | tee -a "${REPORT_FILE}"
    fi
done

# =============================================================================
# STEP 6: Connection Distribution — Impact of restarting each node
# =============================================================================
log_step "Step 6: Connection Distribution"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 6: CONNECTION DISTRIBUTION ==="

for try_node in "${RUNNING_LIST[@]}"; do
    CONN_DATA=$(curl -s --max-time 15 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" \
        "http://${try_node}:${RMQ_MGMT_PORT}/api/nodes" 2>/dev/null)
    if [[ -n "${CONN_DATA}" && "${CONN_DATA}" != *"error"* ]]; then
        echo "${CONN_DATA}" | python3 -c "
import sys, json
try:
    nodes = json.load(sys.stdin)
    print(f\"{'Node':<30} {'Connections':>15} {'Channels':>15} {'Memory (GB)':>15}\")
    print('-' * 77)
    for n in nodes:
        short = n['name'].split('@')[-1] if '@' in n['name'] else n['name']
        # Connection count per node requires separate API call, use fd_used as proxy
        mem_gb = n.get('mem_used', 0) / (1024**3)
        print(f\"{short:<30} {'(see below)':>15} {'(see below)':>15} {mem_gb:>15.2f}\")
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null | tee -a "${REPORT_FILE}"
        break
    fi
done

# Per-node connection count
for node in "${RUNNING_LIST[@]}"; do
    conn_count=$(curl -s --max-time 10 -u "${RMQ_ADMIN_USER}:${RMQ_ADMIN_PASS}" \
        "http://${node}:${RMQ_MGMT_PORT}/api/connections" 2>/dev/null | python3 -c "
import sys, json
try:
    conns = json.load(sys.stdin)
    by_node = {}
    for c in conns:
        n = c.get('node', 'unknown')
        short = n.split('@')[-1] if '@' in n else n
        by_node[short] = by_node.get(short, 0) + 1
    for n, cnt in sorted(by_node.items(), key=lambda x: -x[1]):
        print(f'  {n}: {cnt} connections')
except: pass
" 2>/dev/null)
    if [[ -n "${conn_count}" ]]; then
        echo "${conn_count}" | tee -a "${REPORT_FILE}"
        break
    fi
done

# =============================================================================
# STEP 7: FINAL VERDICT
# =============================================================================
echo "" | tee -a "${REPORT_FILE}"
log_step "Step 7: FINAL VERDICT"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "============================================================"
report_line "${REPORT_FILE}" "  FINAL RESTART DECISION"
report_line "${REPORT_FILE}" "============================================================"

separator
echo ""

# Build per-node verdict
if [[ ${RUNNING_COUNT} -eq 3 ]]; then
    echo -e "  ${GREEN}Cluster is healthy (3/3 nodes). ONE node can be restarted.${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    if [[ -n "${TARGET_NODE}" ]]; then
        # Check specific node
        echo "  Checking requested node: ${TARGET_NODE}" | tee -a "${REPORT_FILE}"
        is_running=false
        for r in "${RUNNING_LIST[@]}"; do
            [[ "${r}" == "${TARGET_NODE}" ]] && is_running=true
        done
        if [[ "${is_running}" == "true" ]]; then
            echo -e "  ${GREEN}[SAFE]${NC} ${TARGET_NODE} — can be restarted" | tee -a "${REPORT_FILE}"
            echo "" | tee -a "${REPORT_FILE}"
            echo "  Recommended procedure:" | tee -a "${REPORT_FILE}"
            echo "    1. sudo ${RABBITMQ_UPGRADE} drain                         # Stop accepting connections" | tee -a "${REPORT_FILE}"
            echo "    2. Wait 30s for connections to drain" | tee -a "${REPORT_FILE}"
            echo "    3. sudo systemctl stop ${RMQ_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "    4. Perform maintenance / patching" | tee -a "${REPORT_FILE}"
            echo "    5. sudo systemctl start ${RMQ_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "    6. sudo ${RABBITMQ_UPGRADE} revive" | tee -a "${REPORT_FILE}"
            echo "    7. sudo ${RABBITMQCTL} await_online_quorum_plus_one       # Wait for quorum sync" | tee -a "${REPORT_FILE}"
            echo "    8. Verify: sudo ${RABBITMQCTL} cluster_status" | tee -a "${REPORT_FILE}"
        else
            echo -e "  ${RED}${TARGET_NODE} is already DOWN${NC}" | tee -a "${REPORT_FILE}"
        fi
    else
        # Show all nodes verdict
        for node in "${RMQ_NODES[@]}"; do
            is_running=false
            for r in "${RUNNING_LIST[@]}"; do
                [[ "${r}" == "${node}" ]] && is_running=true
            done
            if [[ "${is_running}" == "false" ]]; then
                echo -e "  ${YELLOW}[DOWN]${NC}    ${node} — already down, bring UP first" | tee -a "${REPORT_FILE}"
            elif [[ "${HAS_ALARM}" == "true" ]]; then
                echo -e "  ${YELLOW}[WARN]${NC}    ${node} — resolve alarms before restarting" | tee -a "${REPORT_FILE}"
            elif [[ -n "${PARTITION_NODES}" ]]; then
                echo -e "  ${RED}[UNSAFE]${NC}  ${node} — resolve partition first" | tee -a "${REPORT_FILE}"
            else
                echo -e "  ${GREEN}[SAFE]${NC}    ${node} — can be restarted (one at a time)" | tee -a "${REPORT_FILE}"
            fi
        done

        echo "" | tee -a "${REPORT_FILE}"
        echo "  Restart procedure (for whichever node you choose):" | tee -a "${REPORT_FILE}"
        echo "    1. sudo ${RABBITMQ_UPGRADE} drain" | tee -a "${REPORT_FILE}"
        echo "    2. Wait 30s for connections to drain" | tee -a "${REPORT_FILE}"
        echo "    3. sudo systemctl stop ${RMQ_SERVICE}" | tee -a "${REPORT_FILE}"
        echo "    4. Perform maintenance" | tee -a "${REPORT_FILE}"
        echo "    5. sudo systemctl start ${RMQ_SERVICE}" | tee -a "${REPORT_FILE}"
        echo "    6. sudo ${RABBITMQ_UPGRADE} revive" | tee -a "${REPORT_FILE}"
        echo "    7. sudo ${RABBITMQCTL} await_online_quorum_plus_one" | tee -a "${REPORT_FILE}"
        echo "    8. Verify: sudo ${RABBITMQCTL} cluster_status" | tee -a "${REPORT_FILE}"
        echo "    9. WAIT for full sync before restarting the next node" | tee -a "${REPORT_FILE}"
    fi

elif [[ ${RUNNING_COUNT} -eq 2 ]]; then
    echo -e "  ${RED}CANNOT RESTART any running node!${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    echo "  Only 2 of 3 nodes are running." | tee -a "${REPORT_FILE}"
    echo "  With pause_minority: stopping 1 more → remaining node self-pauses → TOTAL OUTAGE" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    echo "  Required action:" | tee -a "${REPORT_FILE}"
    for node in "${DOWN_LIST[@]}"; do
        echo "    → Bring UP: ${node}" | tee -a "${REPORT_FILE}"
        echo "      ssh ${node} 'sudo systemctl start ${RMQ_SERVICE}'" | tee -a "${REPORT_FILE}"
    done
    echo "" | tee -a "${REPORT_FILE}"
    echo "  After all 3 nodes are running, re-run this script." | tee -a "${REPORT_FILE}"

else
    echo -e "  ${RED}CLUSTER IS DOWN — ${RUNNING_COUNT} node(s) running${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    echo "  Emergency recovery required:" | tee -a "${REPORT_FILE}"
    echo "    1. Start all nodes: sudo systemctl start ${RMQ_SERVICE}" | tee -a "${REPORT_FILE}"
    echo "    2. If nodes won't join cluster, check Erlang cookie consistency" | tee -a "${REPORT_FILE}"
    echo "    3. If Mnesia is corrupted, see rb-rmq runbook for full cluster recovery" | tee -a "${REPORT_FILE}"
fi

echo "" | tee -a "${REPORT_FILE}"
separator

# =============================================================================
# LIST ALL QUEUES (using API — will NOT hang)
# =============================================================================
if [[ ${RUNNING_COUNT} -ge 2 ]]; then
    echo "" | tee -a "${REPORT_FILE}"
    log_step "Appendix: Current Queue Listing (via Management API)"
    report_line "${REPORT_FILE}" ""
    report_line "${REPORT_FILE}" "=== APPENDIX: QUEUE LISTING (API-based, does NOT hang) ==="
    echo "" | tee -a "${REPORT_FILE}"
    echo "  NOTE: Using HTTP API instead of 'rabbitmqctl list_queues' because:" | tee -a "${REPORT_FILE}"
    echo "    - list_queues contacts every queue leader and HANGS if any leader is unreachable" | tee -a "${REPORT_FILE}"
    echo "    - API returns cached data instantly, never blocks" | tee -a "${REPORT_FILE}"
    echo "    - If you must use CLI: sudo ${RABBITMQCTL} list_queues --local --timeout 60000" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    rmq_list_queues "${RMQ_VHOST}" | tee -a "${REPORT_FILE}"
fi

echo ""
log_info "Report saved to: ${REPORT_FILE}"
