#!/bin/bash
# =============================================================================
# RB-REDIS-008: Restart Decision — Which Node Can I Safely Restart?
# =============================================================================
# Purpose: Run BEFORE any restart/patching to determine which Redis node
#          is safe to take down without breaking the cluster.
#
# Usage:
#   ./rb-redis-008-restart-decision.sh                 # Analyze all nodes
#   ./rb-redis-008-restart-decision.sh redis-node1     # Check specific node
#
# Output:
#   - Per-node safety verdict: SAFE / UNSAFE / WARNING
#   - Current master/replica topology
#   - Sentinel quorum status
#   - Replication lag per replica
#   - Recommended restart order
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

TARGET_NODE="${1:-}"
REPORT_FILE=$(start_report "RB-REDIS-008_Restart_Decision")

log_info "============================================================"
log_info "  Redis + Sentinel Restart Decision Analysis"
log_info "  Environment: ${ENVIRONMENT}"
log_info "  Cluster: ${REDIS_NODES[*]}"
log_info "============================================================"
echo "" | tee -a "${REPORT_FILE}"

# =============================================================================
# STEP 1: Node Liveness & Roles
# =============================================================================
log_step "Step 1: Node Liveness & Roles"
report_line "${REPORT_FILE}" "=== STEP 1: NODE LIVENESS & ROLES ==="

RUNNING_COUNT=0
RUNNING_LIST=()
DOWN_LIST=()
MASTER_NODE=""
REPLICA_NODES=()

for node in "${REDIS_NODES[@]}"; do
    ping_result=$(redis_cmd "${node}" "${REDIS_PORT}" PING 2>/dev/null)
    role=$(redis_role "${node}" 2>/dev/null)

    if [[ "${ping_result}" == "PONG" ]]; then
        ((RUNNING_COUNT++))
        RUNNING_LIST+=("${node}")
        if [[ "${role}" == "master" ]]; then
            MASTER_NODE="${node}"
            echo -e "  ${GREEN}[UP]${NC}   ${node}  role=${RED}MASTER${NC}" | tee -a "${REPORT_FILE}"
        else
            REPLICA_NODES+=("${node}")
            echo -e "  ${GREEN}[UP]${NC}   ${node}  role=replica" | tee -a "${REPORT_FILE}"
        fi
    else
        DOWN_LIST+=("${node}")
        echo -e "  ${RED}[DOWN]${NC} ${node}" | tee -a "${REPORT_FILE}"
    fi
done

echo "" | tee -a "${REPORT_FILE}"
echo "  Running: ${RUNNING_COUNT} of ${#REDIS_NODES[@]}  |  Master: ${MASTER_NODE:-unknown}  |  Replicas: ${REPLICA_NODES[*]:-none}" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# =============================================================================
# STEP 2: Sentinel Quorum Check
# =============================================================================
log_step "Step 2: Sentinel Quorum Check"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 2: SENTINEL QUORUM ==="

SENTINEL_COUNT=0
SENTINEL_UP=()
SENTINEL_DOWN=()

for node in "${REDIS_NODES[@]}"; do
    sentinel_ping=$(sentinel_cmd "${node}" PING 2>/dev/null)
    if [[ "${sentinel_ping}" == "PONG" ]]; then
        ((SENTINEL_COUNT++))
        SENTINEL_UP+=("${node}")
        echo -e "  ${GREEN}[UP]${NC}   Sentinel on ${node}" | tee -a "${REPORT_FILE}"
    else
        SENTINEL_DOWN+=("${node}")
        echo -e "  ${RED}[DOWN]${NC} Sentinel on ${node}" | tee -a "${REPORT_FILE}"
    fi
done

echo "" | tee -a "${REPORT_FILE}"

# Quorum check via Sentinel
QUORUM_OK=false
if [[ ${SENTINEL_COUNT} -ge 1 ]]; then
    ckquorum_result=$(sentinel_cmd "${SENTINEL_UP[0]}" SENTINEL ckquorum "${SENTINEL_MASTER_NAME}" 2>/dev/null)
    if [[ "${ckquorum_result}" == *"OK"* ]]; then
        echo -e "  ${GREEN}Sentinel quorum: OK (${SENTINEL_COUNT}/3 sentinels up, quorum=2)${NC}" | tee -a "${REPORT_FILE}"
        QUORUM_OK=true
    else
        echo -e "  ${RED}Sentinel quorum: FAILED — automatic failover NOT possible${NC}" | tee -a "${REPORT_FILE}"
    fi
else
    echo -e "  ${RED}No Sentinels reachable — automatic failover IMPOSSIBLE${NC}" | tee -a "${REPORT_FILE}"
fi

# =============================================================================
# STEP 3: Replication Health & Lag
# =============================================================================
log_step "Step 3: Replication Health"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 3: REPLICATION HEALTH ==="

if [[ -n "${MASTER_NODE}" ]]; then
    CONNECTED_SLAVES=$(redis_info_section "${MASTER_NODE}" "replication" 2>/dev/null | grep "connected_slaves" | cut -d: -f2 | tr -d '\r')
    MASTER_OFFSET=$(redis_info_section "${MASTER_NODE}" "replication" 2>/dev/null | grep "master_repl_offset" | cut -d: -f2 | tr -d '\r')

    echo "  Master: ${MASTER_NODE}" | tee -a "${REPORT_FILE}"
    echo "  Connected replicas: ${CONNECTED_SLAVES:-0}" | tee -a "${REPORT_FILE}"
    echo "  Master repl offset: ${MASTER_OFFSET:-unknown}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    for replica in "${REPLICA_NODES[@]}"; do
        link_status=$(redis_info_section "${replica}" "replication" 2>/dev/null | grep "master_link_status" | cut -d: -f2 | tr -d '\r')
        slave_offset=$(redis_info_section "${replica}" "replication" 2>/dev/null | grep "slave_repl_offset" | cut -d: -f2 | tr -d '\r')

        if [[ -n "${MASTER_OFFSET}" && -n "${slave_offset}" ]]; then
            lag=$((MASTER_OFFSET - slave_offset))
        else
            lag="unknown"
        fi

        if [[ "${link_status}" == "up" ]]; then
            echo -e "  ${GREEN}${replica}:${NC} link=up, lag=${lag} bytes" | tee -a "${REPORT_FILE}"
        else
            echo -e "  ${RED}${replica}: link=${link_status:-down}, lag=${lag}${NC}" | tee -a "${REPORT_FILE}"
        fi
    done
else
    echo "  Cannot determine master — unable to check replication" | tee -a "${REPORT_FILE}"
fi

# =============================================================================
# STEP 4: min-replicas-to-write Impact
# =============================================================================
log_step "Step 4: min-replicas-to-write Impact Analysis"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 4: min-replicas-to-write IMPACT ==="

if [[ -n "${MASTER_NODE}" ]]; then
    MIN_REPLICAS=$(redis_cmd "${MASTER_NODE}" "${REDIS_PORT}" ${REDIS_CMD_CONFIG} GET min-replicas-to-write 2>/dev/null | tail -1)
    echo "  min-replicas-to-write = ${MIN_REPLICAS:-unknown}" | tee -a "${REPORT_FILE}"
    echo "  Connected replicas    = ${CONNECTED_SLAVES:-0}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    if [[ "${MIN_REPLICAS}" -ge 1 ]] 2>/dev/null; then
        remaining_after_stop=$((${CONNECTED_SLAVES:-0} - 1))
        if [[ ${remaining_after_stop} -lt ${MIN_REPLICAS} && ${#REPLICA_NODES[@]} -le 1 ]]; then
            echo -e "  ${RED}WARNING: Stopping another replica will drop connected_slaves below min-replicas-to-write${NC}" | tee -a "${REPORT_FILE}"
            echo "  → Master will STOP ACCEPTING WRITES" | tee -a "${REPORT_FILE}"
        else
            echo -e "  ${GREEN}OK: After stopping 1 replica, ${remaining_after_stop} remain (>= ${MIN_REPLICAS} required)${NC}" | tee -a "${REPORT_FILE}"
        fi
    fi
fi

# =============================================================================
# STEP 5: Memory & Persistence Status
# =============================================================================
log_step "Step 5: Memory & Persistence"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "=== STEP 5: MEMORY & PERSISTENCE ==="

for node in "${RUNNING_LIST[@]}"; do
    echo "  --- ${node} ---" | tee -a "${REPORT_FILE}"
    redis_memory_summary "${node}" | sed 's/^/    /' | tee -a "${REPORT_FILE}"
    bgsave_status=$(redis_info_section "${node}" "persistence" 2>/dev/null | grep "rdb_last_bgsave_status" | cut -d: -f2 | tr -d '\r')
    bgsave_running=$(redis_info_section "${node}" "persistence" 2>/dev/null | grep "rdb_bgsave_in_progress" | cut -d: -f2 | tr -d '\r')
    echo "    rdb_last_bgsave_status: ${bgsave_status:-unknown}" | tee -a "${REPORT_FILE}"
    if [[ "${bgsave_running}" == "1" ]]; then
        echo -e "    ${YELLOW}BGSAVE in progress — wait for completion before restart${NC}" | tee -a "${REPORT_FILE}"
    fi
done

# =============================================================================
# STEP 6: FINAL VERDICT
# =============================================================================
echo "" | tee -a "${REPORT_FILE}"
log_step "Step 6: FINAL VERDICT"
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "============================================================"
report_line "${REPORT_FILE}" "  FINAL RESTART DECISION"
report_line "${REPORT_FILE}" "============================================================"

separator
echo ""

if [[ ${RUNNING_COUNT} -eq 3 ]]; then
    echo -e "  ${GREEN}Cluster is healthy (3/3 nodes).${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    # Per-node verdict
    for node in "${REDIS_NODES[@]}"; do
        role=$(redis_role "${node}" 2>/dev/null)

        if [[ "${role}" == "master" ]]; then
            echo -e "  ${YELLOW}[FAILOVER FIRST]${NC}  ${node} (MASTER)" | tee -a "${REPORT_FILE}"
            echo "      → This is the master. You MUST failover before stopping." | tee -a "${REPORT_FILE}"
            echo "      → ${REDIS_CLI} -p ${SENTINEL_PORT} SENTINEL failover ${SENTINEL_MASTER_NAME}" | tee -a "${REPORT_FILE}"
            echo "      → Wait 15s, verify new master, THEN stop this node." | tee -a "${REPORT_FILE}"
        else
            echo -e "  ${GREEN}[SAFE]${NC}            ${node} (replica)" | tee -a "${REPORT_FILE}"
            echo "      → Can be restarted directly. Procedure:" | tee -a "${REPORT_FILE}"
            echo "        1. sudo systemctl stop ${REDIS_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "        2. sudo systemctl stop ${SENTINEL_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "        3. Perform maintenance / OS patching" | tee -a "${REPORT_FILE}"
            echo "        4. sudo systemctl start ${REDIS_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "        5. sudo systemctl start ${SENTINEL_SERVICE}" | tee -a "${REPORT_FILE}"
            echo "        6. Verify: ${REDIS_CLI} -h ${node} -p ${REDIS_PORT} PING" | tee -a "${REPORT_FILE}"
            echo "        7. Verify replication: ${REDIS_CLI} -h ${node} INFO replication | grep master_link_status" | tee -a "${REPORT_FILE}"
            echo "        8. Wait for repl lag = 0 before restarting next node" | tee -a "${REPORT_FILE}"
        fi
        echo "" | tee -a "${REPORT_FILE}"
    done

    echo "  Recommended restart order:" | tee -a "${REPORT_FILE}"
    echo "    1. Replica with fewer keys/connections" | tee -a "${REPORT_FILE}"
    echo "    2. Other replica" | tee -a "${REPORT_FILE}"
    echo "    3. SENTINEL failover → then old master (now replica)" | tee -a "${REPORT_FILE}"

elif [[ ${RUNNING_COUNT} -eq 2 ]]; then
    echo -e "  ${YELLOW}WARNING: Only 2 of 3 nodes running.${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"

    for node in "${RUNNING_LIST[@]}"; do
        role=$(redis_role "${node}" 2>/dev/null)
        if [[ "${role}" == "master" ]]; then
            echo -e "  ${RED}[DO NOT RESTART]${NC}  ${node} (MASTER)" | tee -a "${REPORT_FILE}"
            echo "      → Only 1 replica connected. Stopping master = total write outage." | tee -a "${REPORT_FILE}"
        else
            echo -e "  ${RED}[RISKY]${NC}           ${node} (replica)" | tee -a "${REPORT_FILE}"
            echo "      → Stopping this replica: master has min-replicas-to-write=${MIN_REPLICAS:-1}" | tee -a "${REPORT_FILE}"
            echo "        If min-replicas-to-write >= 1, master will STOP writes." | tee -a "${REPORT_FILE}"
            echo "        AND Sentinel quorum drops to 1 → no automatic failover." | tee -a "${REPORT_FILE}"
        fi
    done

    echo "" | tee -a "${REPORT_FILE}"
    echo "  Required action: Bring the DOWN node back up first:" | tee -a "${REPORT_FILE}"
    for node in "${DOWN_LIST[@]}"; do
        echo "    ssh ${node} 'sudo systemctl start ${REDIS_SERVICE} && sudo systemctl start ${SENTINEL_SERVICE}'" | tee -a "${REPORT_FILE}"
    done
    echo "  After all 3 nodes are running, re-run this script." | tee -a "${REPORT_FILE}"

elif [[ ${RUNNING_COUNT} -le 1 ]]; then
    echo -e "  ${RED}CLUSTER IS DOWN — ${RUNNING_COUNT} node(s) running${NC}" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    echo "  Emergency recovery:" | tee -a "${REPORT_FILE}"
    echo "    1. Start Redis + Sentinel on ALL nodes" | tee -a "${REPORT_FILE}"
    echo "    2. Check which node has the latest data (ls -la ${REDIS_DATA_DIR}/dump.rdb)" | tee -a "${REPORT_FILE}"
    echo "    3. If Sentinel lost track of master:" | tee -a "${REPORT_FILE}"
    echo "       Restart all 3 Sentinels — they will re-elect" | tee -a "${REPORT_FILE}"
fi

echo "" | tee -a "${REPORT_FILE}"

# =============================================================================
# Specific node check
# =============================================================================
if [[ -n "${TARGET_NODE}" ]]; then
    echo "" | tee -a "${REPORT_FILE}"
    report_line "${REPORT_FILE}" ""
    report_line "${REPORT_FILE}" "=== SPECIFIC NODE CHECK: ${TARGET_NODE} ==="

    role=$(redis_role "${TARGET_NODE}" 2>/dev/null)
    ping=$(redis_cmd "${TARGET_NODE}" "${REDIS_PORT}" PING 2>/dev/null)

    if [[ "${ping}" != "PONG" ]]; then
        echo -e "  ${TARGET_NODE} is DOWN — it can be patched/restarted (it's already stopped)" | tee -a "${REPORT_FILE}"
    elif [[ "${role}" == "master" ]]; then
        echo -e "  ${TARGET_NODE} is the MASTER" | tee -a "${REPORT_FILE}"
        echo "" | tee -a "${REPORT_FILE}"
        echo "  Steps to safely restart this node:" | tee -a "${REPORT_FILE}"
        echo "    1. Trigger failover first:" | tee -a "${REPORT_FILE}"
        echo "       ${REDIS_CLI} -p ${SENTINEL_PORT} SENTINEL failover ${SENTINEL_MASTER_NAME}" | tee -a "${REPORT_FILE}"
        echo "    2. Wait 15 seconds" | tee -a "${REPORT_FILE}"
        echo "    3. Verify it is now a replica:" | tee -a "${REPORT_FILE}"
        echo "       ${REDIS_CLI} -h ${TARGET_NODE} ROLE" | tee -a "${REPORT_FILE}"
        echo "    4. Then stop and patch:" | tee -a "${REPORT_FILE}"
        echo "       sudo systemctl stop ${REDIS_SERVICE} && sudo systemctl stop ${SENTINEL_SERVICE}" | tee -a "${REPORT_FILE}"
    else
        echo -e "  ${TARGET_NODE} is a replica — ${GREEN}SAFE to restart directly${NC}" | tee -a "${REPORT_FILE}"
    fi
fi

separator
echo ""
log_info "Report saved to: ${REPORT_FILE}"
