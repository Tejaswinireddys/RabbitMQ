#!/bin/bash
# =============================================================================
# RB-REDIS-003: Redis Memory High / Evictions
# =============================================================================
# Severity: P1 - Critical
# Trigger:  Datadog monitor - redis.mem.used > threshold or evictions > 0
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../env/environment.conf"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/redis_helpers.sh"

AFFECTED_NODE="${1:-}"
[[ -z "${AFFECTED_NODE}" ]] && AFFECTED_NODE=$(redis_get_master)
[[ -z "${AFFECTED_NODE}" ]] && { log_error "Cannot determine master node. Usage: $0 <node>"; exit 1; }

REPORT_FILE=$(start_report "RB-REDIS-003_Memory_High")
log_info "=== RB-REDIS-003: Memory Investigation on ${AFFECTED_NODE} ==="

# Step 1: Memory summary
log_step "Step 1: Memory overview..."
report_line "${REPORT_FILE}" "Step 1: Memory Overview"
for node in "${REDIS_NODES[@]}"; do
    echo "--- ${node} ---" | tee -a "${REPORT_FILE}"
    redis_memory_summary "${node}" | tee -a "${REPORT_FILE}"
done

# Step 2: Maxmemory policy
log_step "Step 2: Eviction policy..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 2: Eviction Configuration"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" CONFIG GET maxmemory 2>/dev/null | tee -a "${REPORT_FILE}"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" CONFIG GET maxmemory-policy 2>/dev/null | tee -a "${REPORT_FILE}"

# Step 3: Key count and DB size
log_step "Step 3: Key distribution..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 3: Keyspace"
redis_info_section "${AFFECTED_NODE}" "keyspace" | tee -a "${REPORT_FILE}"

# Step 4: Memory fragmentation
log_step "Step 4: Fragmentation analysis..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 4: Memory Details"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" MEMORY STATS 2>/dev/null | head -40 | tee -a "${REPORT_FILE}"

# Step 5: Top big keys (sample)
log_step "Step 5: Big keys analysis..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 5: Big Keys (sampled)"
redis_cmd "${AFFECTED_NODE}" "${REDIS_PORT}" --bigkeys --no-auth-warning 2>/dev/null | grep -E "Biggest|Overall" | tee -a "${REPORT_FILE}"

# Step 6: Eviction stats
log_step "Step 6: Eviction stats..."
report_line "${REPORT_FILE}" ""
report_line "${REPORT_FILE}" "Step 6: Stats"
redis_info_section "${AFFECTED_NODE}" "stats" | grep -E "evicted_keys|expired_keys|keyspace_hits|keyspace_misses" | tee -a "${REPORT_FILE}"

# Step 7: Recommendations
log_step "Step 7: Recommendations..."
echo ""
echo "Remediation options:"
echo "  1. Increase maxmemory if host has available RAM"
echo "  2. Set TTL on keys that don't expire"
echo "  3. Change eviction policy (allkeys-lru recommended for cache)"
echo "  4. Remove unused/stale keys"
echo "  5. Enable MEMORY DOCTOR for fragmentation advice"
echo ""

FRAG=$(redis_info_section "${AFFECTED_NODE}" "memory" 2>/dev/null | grep "mem_fragmentation_ratio" | cut -d: -f2 | tr -d '\r')
if [[ -n "${FRAG}" ]] && (( $(echo "${FRAG} > 1.5" | bc -l 2>/dev/null || echo 0) )); then
    log_warn "High fragmentation ratio: ${FRAG} - consider MEMORY PURGE or restart"
    report_line "${REPORT_FILE}" "HIGH FRAGMENTATION: ${FRAG} - consider activedefrag or restart"
fi

log_info "Report saved to: ${REPORT_FILE}"
