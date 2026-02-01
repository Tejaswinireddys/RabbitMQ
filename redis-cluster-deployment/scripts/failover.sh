#!/bin/bash
#
# failover.sh
# Manual failover script for Redis Sentinel cluster
#
# Usage: ./failover.sh [--force]
#

set -e

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_BIN="${REDIS_HOME}/bin"
SENTINEL_CLI="${REDIS_BIN}/redis-cli -p 26379"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FORCE=false
MASTER_NAME="mymaster"

# Parse arguments
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE=true
            ;;
        --help|-h)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  --force, -f  Skip confirmation prompt"
            exit 0
            ;;
    esac
done

echo "=============================================="
echo "Redis Manual Failover"
echo "=============================================="
echo ""

# Get current master info
echo "Current cluster status:"
MASTER_INFO=$($SENTINEL_CLI SENTINEL master $MASTER_NAME 2>/dev/null)

if [ -z "$MASTER_INFO" ]; then
    echo -e "${RED}ERROR: Cannot connect to Sentinel or master not configured${NC}"
    exit 1
fi

CURRENT_MASTER_IP=$(echo "$MASTER_INFO" | grep -A1 "^ip$" | tail -1)
CURRENT_MASTER_PORT=$(echo "$MASTER_INFO" | grep -A1 "^port$" | tail -1)
CURRENT_MASTER_STATUS=$(echo "$MASTER_INFO" | grep -A1 "^flags$" | tail -1)
NUM_REPLICAS=$(echo "$MASTER_INFO" | grep -A1 "^num-slaves$" | tail -1)
NUM_SENTINELS=$(echo "$MASTER_INFO" | grep -A1 "^num-other-sentinels$" | tail -1)

echo "  Master:     ${CURRENT_MASTER_IP}:${CURRENT_MASTER_PORT}"
echo "  Status:     ${CURRENT_MASTER_STATUS}"
echo "  Replicas:   ${NUM_REPLICAS}"
echo "  Sentinels:  $((NUM_SENTINELS + 1))"
echo ""

# Check if master is healthy
if [[ "$CURRENT_MASTER_STATUS" == *"down"* ]] || [[ "$CURRENT_MASTER_STATUS" == *"odown"* ]]; then
    echo -e "${YELLOW}WARNING: Master appears to be down${NC}"
    echo "Sentinel may already be performing automatic failover."
fi

# Check replica count
if [ "$NUM_REPLICAS" -lt 1 ]; then
    echo -e "${RED}ERROR: No replicas available for failover${NC}"
    exit 1
fi

# Show replicas
echo "Available replicas:"
$SENTINEL_CLI SENTINEL replicas $MASTER_NAME 2>/dev/null | while read line; do
    if [[ "$line" == *"ip"* ]] || [[ "$line" == *"port"* ]] || [[ "$line" == *"flags"* ]]; then
        echo "  $line"
    fi
done
echo ""

# Confirmation
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}This will trigger a manual failover.${NC}"
    echo "The current master will become a replica."
    echo ""
    read -p "Are you sure you want to proceed? (yes/NO): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Failover cancelled."
        exit 0
    fi
fi

echo ""
echo "Initiating failover..."

# Trigger failover
FAILOVER_RESULT=$($SENTINEL_CLI SENTINEL failover $MASTER_NAME 2>&1)

if [ "$FAILOVER_RESULT" = "OK" ]; then
    echo -e "${GREEN}Failover initiated successfully${NC}"
else
    echo -e "${RED}Failover command returned: $FAILOVER_RESULT${NC}"
    exit 1
fi

# Wait and monitor
echo ""
echo "Monitoring failover progress..."
echo ""

for i in {1..30}; do
    sleep 2

    NEW_MASTER_INFO=$($SENTINEL_CLI SENTINEL master $MASTER_NAME 2>/dev/null)
    NEW_MASTER_IP=$(echo "$NEW_MASTER_INFO" | grep -A1 "^ip$" | tail -1)
    NEW_MASTER_PORT=$(echo "$NEW_MASTER_INFO" | grep -A1 "^port$" | tail -1)
    NEW_MASTER_STATUS=$(echo "$NEW_MASTER_INFO" | grep -A1 "^flags$" | tail -1)

    echo "  [$i/30] Master: ${NEW_MASTER_IP}:${NEW_MASTER_PORT} - ${NEW_MASTER_STATUS}"

    if [ "$NEW_MASTER_IP" != "$CURRENT_MASTER_IP" ] && [[ "$NEW_MASTER_STATUS" == "master" ]]; then
        echo ""
        echo -e "${GREEN}Failover completed successfully!${NC}"
        echo ""
        echo "New master:  ${NEW_MASTER_IP}:${NEW_MASTER_PORT}"
        echo "Old master:  ${CURRENT_MASTER_IP}:${CURRENT_MASTER_PORT} (now replica)"
        exit 0
    fi
done

echo ""
echo -e "${YELLOW}Failover may still be in progress.${NC}"
echo "Check status with: $SENTINEL_CLI SENTINEL master $MASTER_NAME"
