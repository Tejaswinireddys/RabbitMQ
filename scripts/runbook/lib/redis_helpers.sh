#!/bin/bash
# =============================================================================
# Redis Helper Functions
# =============================================================================
# Source after common.sh:
#   source "$(dirname "$0")/../lib/redis_helpers.sh"
#
# Requires variables from environment.conf:
#   REDIS_CLI, REDIS_SERVER_BIN, REDIS_SENTINEL_BIN
#   REDIS_NODES, REDIS_PORT, SENTINEL_PORT, REDIS_AUTH_PASS
#   REDIS_CONF_FILE, SENTINEL_CONF_FILE, SENTINEL_MASTER_NAME
#   REDIS_SERVICE, SENTINEL_SERVICE, REDIS_DATA_DIR, REDIS_LOG_DIR
#   REDIS_CMD_CONFIG, REDIS_CMD_SHUTDOWN, REDIS_CMD_BGSAVE
# =============================================================================

# --- Redis CLI command ---
redis_cmd() {
    local host="${1:-${REDIS_NODE1}}"
    local port="${2:-${REDIS_PORT}}"
    shift 2
    if [[ -n "${REDIS_AUTH_PASS}" ]]; then
        "${REDIS_CLI}" -h "${host}" -p "${port}" -a "${REDIS_AUTH_PASS}" --no-auth-warning "$@"
    else
        "${REDIS_CLI}" -h "${host}" -p "${port}" "$@"
    fi
}

# --- Sentinel CLI command ---
sentinel_cmd() {
    local host="${1:-${REDIS_NODE1}}"
    shift
    redis_cmd "${host}" "${SENTINEL_PORT}" "$@"
}

# --- Get current master ---
redis_get_master() {
    sentinel_cmd "${REDIS_NODE1}" SENTINEL get-master-addr-by-name "${SENTINEL_MASTER_NAME}" 2>/dev/null | head -1
}

# --- Get cluster role info ---
redis_role() {
    local host="$1"
    redis_cmd "${host}" "${REDIS_PORT}" ROLE 2>/dev/null | head -1
}

# --- Identify which node is master ---
redis_identify_master_node() {
    for node in "${REDIS_NODES[@]}"; do
        local role
        role=$(redis_role "${node}")
        if [[ "${role}" == "master" ]]; then
            echo "${node}"
            return 0
        fi
    done
    # Fallback to Sentinel
    redis_get_master
}

# --- Count running nodes ---
redis_running_node_count() {
    local count=0
    for node in "${REDIS_NODES[@]}"; do
        local ping
        ping=$(redis_cmd "${node}" "${REDIS_PORT}" PING 2>/dev/null)
        [[ "${ping}" == "PONG" ]] && ((count++))
    done
    echo "${count}"
}

# --- Count running sentinels ---
redis_running_sentinel_count() {
    local count=0
    for node in "${REDIS_NODES[@]}"; do
        local ping
        ping=$(sentinel_cmd "${node}" PING 2>/dev/null)
        [[ "${ping}" == "PONG" ]] && ((count++))
    done
    echo "${count}"
}

# --- CRITICAL: Check if safe to stop a node ---
redis_safe_to_stop() {
    local target_node="$1"
    local role
    role=$(redis_role "${target_node}")
    local running
    running=$(redis_running_node_count)
    local sentinels
    sentinels=$(redis_running_sentinel_count)

    # Check: min-replicas-to-write constraint
    if [[ "${role}" != "master" && ${running} -le 2 ]]; then
        log_warn "Only ${running} nodes running. Stopping this replica will leave master with <1 replica."
        log_warn "If min-replicas-to-write=1, master will STOP accepting writes."
    fi

    # Check: Never stop master without failover first
    if [[ "${role}" == "master" ]]; then
        log_error "STOP: ${target_node} is the MASTER. You must failover FIRST before stopping."
        log_error "Run: ${REDIS_CLI} -h ${target_node} -p ${SENTINEL_PORT} SENTINEL failover ${SENTINEL_MASTER_NAME}"
        return 1
    fi

    # Check: Sentinel quorum
    if [[ ${sentinels} -le 2 ]]; then
        log_warn "Only ${sentinels} Sentinels running. Stopping Sentinel on this node will break quorum (need 2/3)."
        log_warn "Without quorum, automatic failover is IMPOSSIBLE."
    fi

    log_info "Role: ${role}, Running nodes: ${running}, Sentinels: ${sentinels}"
    return 0
}

# --- Manual failover (graceful) ---
redis_manual_failover() {
    local sentinel_host="${1:-${REDIS_NODE1}}"
    log_step "Triggering manual failover via Sentinel on ${sentinel_host}..."
    sentinel_cmd "${sentinel_host}" SENTINEL failover "${SENTINEL_MASTER_NAME}" 2>/dev/null
    log_info "Failover initiated. Waiting 15s for promotion..."
    sleep 15
    local new_master
    new_master=$(redis_get_master)
    log_info "New master: ${new_master}"
}

# --- Cluster status check ---
redis_cluster_status() {
    local master
    master=$(redis_get_master)
    echo "  Current Master: ${master:-unknown}"
    echo ""
    for node in "${REDIS_NODES[@]}"; do
        local role ping_result
        ping_result=$(redis_cmd "${node}" "${REDIS_PORT}" PING 2>/dev/null)
        role=$(redis_role "${node}")
        if [[ "${ping_result}" == "PONG" ]]; then
            echo -e "  ${GREEN}[UP]${NC}   ${node} (${role:-unknown})"
        else
            echo -e "  ${RED}[DOWN]${NC} ${node}"
        fi
    done
}

# --- Sentinel quorum status ---
redis_sentinel_status() {
    for node in "${REDIS_NODES[@]}"; do
        local ping_result
        ping_result=$(sentinel_cmd "${node}" PING 2>/dev/null)
        if [[ "${ping_result}" == "PONG" ]]; then
            echo -e "  ${GREEN}[UP]${NC}   Sentinel on ${node}"
        else
            echo -e "  ${RED}[DOWN]${NC} Sentinel on ${node}"
        fi
    done
    echo ""
    local sentinels_count
    sentinels_count=$(sentinel_cmd "${REDIS_NODE1}" SENTINEL master "${SENTINEL_MASTER_NAME}" 2>/dev/null | \
        grep -A1 "num-other-sentinels" | tail -1)
    echo "  Other Sentinels: ${sentinels_count:-unknown}"
    local quorum
    quorum=$(sentinel_cmd "${REDIS_NODE1}" SENTINEL master "${SENTINEL_MASTER_NAME}" 2>/dev/null | \
        grep -A1 "quorum" | tail -1)
    echo "  Quorum: ${quorum:-unknown}"
}

# --- Redis INFO section ---
redis_info_section() {
    local host="$1"
    local section="$2"
    redis_cmd "${host}" "${REDIS_PORT}" INFO "${section}" 2>/dev/null
}

# --- Memory summary ---
redis_memory_summary() {
    local host="$1"
    redis_info_section "${host}" "memory" | grep -E "used_memory_human|used_memory_peak_human|maxmemory_human|mem_fragmentation_ratio|used_memory_rss_human"
}

# --- Replication summary ---
redis_replication_summary() {
    local host="$1"
    redis_info_section "${host}" "replication" | grep -E "role|connected_slaves|master_link_status|master_last_io|master_repl_offset|slave_repl_offset"
}

# --- Slow log ---
redis_slowlog() {
    local host="$1"
    local count="${2:-10}"
    redis_cmd "${host}" "${REDIS_PORT}" SLOWLOG GET "${count}" 2>/dev/null
}

# --- Verify Sentinel config not corrupted ---
redis_verify_sentinel_conf() {
    local node="$1"
    log_step "Checking sentinel.conf on ${node}..."
    local has_monitor
    has_monitor=$(remote_exec "${node}" "grep -c 'sentinel monitor' ${SENTINEL_CONF_FILE} 2>/dev/null" || echo "0")
    if [[ "${has_monitor}" -lt 1 ]]; then
        log_error "${node}: sentinel.conf missing 'sentinel monitor' directive — Sentinel will not work"
        return 1
    fi
    log_info "${node}: sentinel.conf appears valid"
    return 0
}

# --- Restart Redis on a node (with safety checks) ---
redis_restart_node() {
    local node="$1"

    if ! redis_safe_to_stop "${node}"; then
        log_error "Aborting — use redis_manual_failover first if this is the master"
        return 1
    fi

    confirm_action "About to restart Redis on ${node} ($(redis_role "${node}"))."
    log_step "Stopping Redis on ${node}..."
    remote_exec "${node}" "sudo systemctl stop ${REDIS_SERVICE}"
    sleep 3
    log_step "Starting Redis on ${node}..."
    remote_exec "${node}" "sudo systemctl start ${REDIS_SERVICE}"
    sleep 5
    local ping_result
    ping_result=$(redis_cmd "${node}" "${REDIS_PORT}" PING 2>/dev/null)
    if [[ "${ping_result}" == "PONG" ]]; then
        log_info "Redis on ${node} is back up"
    else
        log_error "Redis on ${node} failed to come up"
    fi
}
