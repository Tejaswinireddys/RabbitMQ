#!/bin/bash
# =============================================================================
# RB-REDIS-004: Replication Lag / Broken Replication
# =============================================================================
# Severity: P2 - High
# Trigger:  Datadog monitor - redis.replication.delay > threshold
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

REPORT_FILE=$(start_report "RB-REDIS-004_Replication_Lag")
log_info "=== RB-REDIS-004: Replication Lag Investigation ==="

# Step 1: Cluster roles
log_step "Step 1: Cluster roles..."
report_line "${REPORT_FILE}" "Step 1: Cluster Roles"
redis_cluster_status | tee -a "${REPORT_FILE}"

# Step 2: Replication info from master
log_step "Step 2: Replication info from master..."
MASTER=$(redis_get_master)
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Master Replication Info (${MASTER})"
redis_replication_summary "${MASTER}" | tee -a "${REPORT_FILE}"

# Step 3: Replication info from replicas
log_step "Step 3: Replica replication info..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Replica Replication"
for node in "${REDIS_NODES[@]}"; do
    ROLE=$(redis_role "${node}")
    if [[ "${ROLE}" == "slave" ]]; then
        echo "--- ${node} (replica) ---" | tee -a "${REPORT_FILE}"
        redis_replication_summary "${node}" | tee -a "${REPORT_FILE}"
        # Check master link
        LINK=$(redis_info_section "${node}" "replication" | grep "master_link_status" | cut -d: -f2 | tr -d '\r')
        if [[ "${LINK}" != "up" ]]; then
            log_warn "${node}: master_link_status = ${LINK}"
            report_line "${REPORT_FILE}" "WARNING: master_link_status = ${LINK}"
        fi
    fi
done

# Step 4: Calculate lag
log_step "Step 4: Offset-based lag calculation..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Replication Offset Lag"
MASTER_OFFSET=$(redis_info_section "${MASTER}" "replication" | grep "master_repl_offset" | cut -d: -f2 | tr -d '\r')
for node in "${REDIS_NODES[@]}"; do
    ROLE=$(redis_role "${node}")
    if [[ "${ROLE}" == "slave" ]]; then
        SLAVE_OFFSET=$(redis_info_section "${node}" "replication" | grep "slave_repl_offset" | cut -d: -f2 | tr -d '\r')
        if [[ -n "${MASTER_OFFSET}" && -n "${SLAVE_OFFSET}" ]]; then
            LAG=$((MASTER_OFFSET - SLAVE_OFFSET))
            echo "  ${node}: lag = ${LAG} bytes" | tee -a "${REPORT_FILE}"
            if [[ ${LAG} -gt 1000000 ]]; then
                log_warn "${node}: significant replication lag (${LAG} bytes)"
            fi
        fi
    fi
done

# Step 5: Check network between master and replicas
log_step "Step 5: Network latency to master..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Network Latency"
for node in "${REDIS_NODES[@]}"; do
    if [[ "${node}" != "${MASTER}" ]]; then
        LATENCY=$(remote_exec "${node}" "redis-cli -h ${MASTER} -p ${REDIS_PORT} ${REDIS_AUTH_PASS:+-a ${REDIS_AUTH_PASS}} --latency-history -i 1 2>/dev/null | head -3" 2>/dev/null || echo "unable to measure")
        echo "  ${node} -> ${MASTER}: ${LATENCY}" | tee -a "${REPORT_FILE}"
    fi
done

# Step 6: Check output buffer
log_step "Step 6: Client output buffer for replicas..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Replica Output Buffer"
redis_cmd "${MASTER}" "${REDIS_PORT}" CONFIG GET client-output-buffer-limit 2>/dev/null | tee -a "${REPORT_FILE}"

echo ""
log_info "Recommendations:"
echo "  1. If master_link_status=down: check network, restart replica"
echo "  2. If lag is high but link is up: check master write load"
echo "  3. Increase repl-backlog-size if full resync occurs frequently"
echo "  4. Check replica output buffer limits"
echo ""

log_info "Report saved to: ${REPORT_FILE}"
