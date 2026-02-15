#!/bin/bash
# =============================================================================
# Redis Helper Functions
# =============================================================================
# Source after common.sh:
#   source "$(dirname "$0")/../lib/redis_helpers.sh"
# =============================================================================

# --- Redis CLI command ---
redis_cmd() {
    local host="${1:-${REDIS_NODE1}}"
    local port="${2:-${REDIS_PORT}}"
    shift 2
    if [[ -n "${REDIS_AUTH_PASS}" ]]; then
        "${REDIS_BIN}/redis-cli" -h "${host}" -p "${port}" -a "${REDIS_AUTH_PASS}" --no-auth-warning "$@"
    else
        "${REDIS_BIN}/redis-cli" -h "${host}" -p "${port}" "$@"
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

# --- Restart Redis on a node ---
redis_restart_node() {
    local node="$1"
    local role
    role=$(redis_role "${node}")
    if [[ "${role}" == "master" ]]; then
        confirm_action "WARNING: ${node} is the MASTER. Restarting will trigger failover. Proceed?"
    else
        confirm_action "About to restart Redis on ${node} (${role})."
    fi
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
