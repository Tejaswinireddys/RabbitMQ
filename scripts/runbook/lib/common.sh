#!/bin/bash
# =============================================================================
# Common Functions Library
# =============================================================================
# Shared functions for all runbook automation scripts
# Source after environment.conf:
#   source "$(dirname "$0")/../env/environment.conf"
#   source "$(dirname "$0")/../lib/common.sh"
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging ---
log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $(date '+%H:%M:%S') $*"; }

# --- Ensure directories ---
ensure_dirs() {
    mkdir -p "${LOG_DIR}" "${REPORT_DIR}" 2>/dev/null || true
}

# --- Remote execution ---
remote_exec() {
    local host="$1"
    shift
    ssh ${SSH_OPTS} -i "${SSH_KEY}" "${SSH_USER}@${host}" "$@"
}

# --- Slack notification ---
notify_slack() {
    local message="$1"
    local color="${2:-#36a64f}"
    if [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H 'Content-type: application/json' \
            -d "{
                \"channel\": \"${SLACK_CHANNEL}\",
                \"attachments\": [{
                    \"color\": \"${color}\",
                    \"title\": \"Runbook Execution - ${ENVIRONMENT}\",
                    \"text\": \"${message}\",
                    \"footer\": \"Executed by ${SSH_USER} at $(date '+%Y-%m-%d %H:%M:%S')\"
                }]
            }" >/dev/null 2>&1 || true
    fi
}

# --- PagerDuty trigger ---
trigger_pagerduty() {
    local description="$1"
    local severity="${2:-critical}"
    if [[ -n "${PAGERDUTY_SERVICE_KEY}" ]]; then
        curl -s -X POST "https://events.pagerduty.com/v2/enqueue" \
            -H 'Content-type: application/json' \
            -d "{
                \"routing_key\": \"${PAGERDUTY_SERVICE_KEY}\",
                \"event_action\": \"trigger\",
                \"payload\": {
                    \"summary\": \"${description}\",
                    \"severity\": \"${severity}\",
                    \"source\": \"runbook-automation\",
                    \"component\": \"${ENVIRONMENT}\"
                }
            }" >/dev/null 2>&1 || true
    fi
}

# --- Confirmation prompt ---
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}${message}${NC}"
    read -rp "Type 'yes' to proceed: " response
    if [[ "${response}" != "yes" ]]; then
        log_warn "Action cancelled by user"
        exit 1
    fi
}

# --- Report header ---
start_report() {
    local title="$1"
    local report_file="${REPORT_DIR}/${title// /_}_${TIMESTAMP}.txt"
    ensure_dirs
    {
        echo "================================================================"
        echo "  ${title}"
        echo "  Environment: ${ENVIRONMENT} | DC: ${DATACENTER}"
        echo "  Executed by: ${SSH_USER} at $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================================"
        echo ""
    } > "${report_file}"
    echo "${report_file}"
}

# --- Append to report ---
report_line() {
    local report_file="$1"
    shift
    echo "$*" >> "${report_file}"
}

# --- Print separator ---
separator() {
    echo "----------------------------------------------------------------"
}
