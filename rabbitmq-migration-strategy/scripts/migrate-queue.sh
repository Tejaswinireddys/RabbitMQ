#!/bin/bash
#
# migrate-queue.sh
# Migrate a single queue from classic to quorum using Shovel
#
# Usage: ./migrate-queue.sh <queue-name> [--target-cluster <host>]
#

set -e

# Parse arguments
QUEUE_NAME="${1}"
TARGET_CLUSTER="${3:-localhost}"
SOURCE_CLUSTER="${SOURCE_CLUSTER:-localhost}"
QUORUM_SIZE="${QUORUM_SIZE:-3}"
DELIVERY_LIMIT="${DELIVERY_LIMIT:-5}"

if [ -z "$QUEUE_NAME" ]; then
    echo "Usage: $0 <queue-name> [--target-cluster <host>]"
    echo ""
    echo "Options:"
    echo "  --target-cluster  Target cluster hostname (default: localhost)"
    echo ""
    echo "Environment variables:"
    echo "  SOURCE_CLUSTER    Source cluster hostname (default: localhost)"
    echo "  QUORUM_SIZE       Quorum queue replica count (default: 3)"
    echo "  DELIVERY_LIMIT    Max delivery attempts (default: 5)"
    echo ""
    echo "Examples:"
    echo "  $0 orders"
    echo "  $0 orders --target-cluster rabbit-green-1"
    exit 1
fi

echo "=============================================="
echo "Queue Migration: $QUEUE_NAME"
echo "Source: $SOURCE_CLUSTER"
echo "Target: $TARGET_CLUSTER"
echo "=============================================="

# Check if queue exists
echo ""
echo "[1/6] Checking source queue..."
QUEUE_INFO=$(rabbitmqctl list_queues name type durable messages --quiet 2>/dev/null | grep "^${QUEUE_NAME}[[:space:]]" || true)

if [ -z "$QUEUE_INFO" ]; then
    echo "Error: Queue '$QUEUE_NAME' not found"
    exit 1
fi

QUEUE_TYPE=$(echo "$QUEUE_INFO" | awk '{print $2}')
QUEUE_DURABLE=$(echo "$QUEUE_INFO" | awk '{print $3}')
QUEUE_MESSAGES=$(echo "$QUEUE_INFO" | awk '{print $4}')

echo "Found queue: $QUEUE_NAME"
echo "  Type: $QUEUE_TYPE"
echo "  Durable: $QUEUE_DURABLE"
echo "  Messages: $QUEUE_MESSAGES"

if [ "$QUEUE_TYPE" == "quorum" ]; then
    echo "Queue is already a quorum queue. Nothing to do."
    exit 0
fi

if [ "$QUEUE_DURABLE" != "true" ]; then
    echo "Error: Queue is not durable. Cannot migrate to quorum."
    exit 1
fi

# Get bindings
echo ""
echo "[2/6] Capturing bindings..."
BINDINGS=$(rabbitmqctl list_bindings source_name destination_name routing_key --quiet 2>/dev/null | \
    grep "[[:space:]]${QUEUE_NAME}[[:space:]]" || true)

if [ -n "$BINDINGS" ]; then
    echo "Found bindings:"
    echo "$BINDINGS" | while read -r line; do
        echo "  $line"
    done
else
    echo "No exchange bindings found (queue bound to default exchange only)"
fi

# Create quorum queue on target
QUORUM_QUEUE="${QUEUE_NAME}"
if [ "$SOURCE_CLUSTER" == "$TARGET_CLUSTER" ]; then
    QUORUM_QUEUE="${QUEUE_NAME}-quorum"
fi

echo ""
echo "[3/6] Creating quorum queue: $QUORUM_QUEUE"

if [ "$TARGET_CLUSTER" == "localhost" ]; then
    rabbitmqadmin declare queue \
        name="$QUORUM_QUEUE" \
        durable=true \
        arguments="{\"x-queue-type\":\"quorum\",\"x-quorum-initial-group-size\":$QUORUM_SIZE,\"x-delivery-limit\":$DELIVERY_LIMIT}"
else
    rabbitmqadmin -H "$TARGET_CLUSTER" declare queue \
        name="$QUORUM_QUEUE" \
        durable=true \
        arguments="{\"x-queue-type\":\"quorum\",\"x-quorum-initial-group-size\":$QUORUM_SIZE,\"x-delivery-limit\":$DELIVERY_LIMIT}"
fi

echo "Created quorum queue: $QUORUM_QUEUE"

# Recreate bindings on target
echo ""
echo "[4/6] Recreating bindings..."
if [ -n "$BINDINGS" ]; then
    echo "$BINDINGS" | while read -r source dest routing; do
        if [ -n "$source" ] && [ "$source" != "" ]; then
            echo "  Binding: $source -> $QUORUM_QUEUE ($routing)"
            if [ "$TARGET_CLUSTER" == "localhost" ]; then
                rabbitmqadmin declare binding \
                    source="$source" \
                    destination="$QUORUM_QUEUE" \
                    routing_key="$routing" 2>/dev/null || true
            else
                rabbitmqadmin -H "$TARGET_CLUSTER" declare binding \
                    source="$source" \
                    destination="$QUORUM_QUEUE" \
                    routing_key="$routing" 2>/dev/null || true
            fi
        fi
    done
fi

# Setup Shovel
echo ""
echo "[5/6] Configuring Shovel..."

SHOVEL_NAME="migrate-${QUEUE_NAME}"
SHOVEL_CONFIG="{
    \"src-protocol\": \"amqp091\",
    \"src-uri\": \"amqp://${SOURCE_CLUSTER}\",
    \"src-queue\": \"${QUEUE_NAME}\",
    \"dest-protocol\": \"amqp091\",
    \"dest-uri\": \"amqp://${TARGET_CLUSTER}\",
    \"dest-queue\": \"${QUORUM_QUEUE}\",
    \"ack-mode\": \"on-confirm\",
    \"reconnect-delay\": 5
}"

rabbitmqctl set_parameter shovel "$SHOVEL_NAME" "$SHOVEL_CONFIG"

echo "Shovel configured: $SHOVEL_NAME"

# Monitor migration
echo ""
echo "[6/6] Migration in progress..."
echo "Monitoring message transfer (Ctrl+C to stop monitoring):"
echo ""

while true; do
    SOURCE_MSGS=$(rabbitmqctl list_queues name messages --quiet 2>/dev/null | \
        grep "^${QUEUE_NAME}[[:space:]]" | awk '{print $2}')

    if [ "$TARGET_CLUSTER" == "localhost" ]; then
        TARGET_MSGS=$(rabbitmqctl list_queues name messages --quiet 2>/dev/null | \
            grep "^${QUORUM_QUEUE}[[:space:]]" | awk '{print $2}')
    else
        TARGET_MSGS=$(rabbitmqctl -n "rabbit@${TARGET_CLUSTER}" list_queues name messages --quiet 2>/dev/null | \
            grep "^${QUORUM_QUEUE}[[:space:]]" | awk '{print $2}' 2>/dev/null || echo "?")
    fi

    SHOVEL_STATUS=$(rabbitmqctl shovel_status 2>/dev/null | grep "$SHOVEL_NAME" | awk '{print $3}' || echo "unknown")

    printf "\r  Source (%s): %s msgs | Target (%s): %s msgs | Shovel: %s     " \
        "$QUEUE_NAME" "${SOURCE_MSGS:-0}" "$QUORUM_QUEUE" "${TARGET_MSGS:-0}" "$SHOVEL_STATUS"

    if [ "${SOURCE_MSGS:-0}" -eq 0 ] && [ "${SHOVEL_STATUS}" == "running" ]; then
        echo ""
        echo ""
        echo "Source queue drained!"
        break
    fi

    sleep 2
done

echo ""
echo "=============================================="
echo "Migration Summary"
echo "=============================================="
echo "Source Queue: $QUEUE_NAME (classic)"
echo "Target Queue: $QUORUM_QUEUE (quorum)"
echo "Messages Migrated: Yes"
echo ""
echo "Next steps:"
echo "1. Update applications to use queue: $QUORUM_QUEUE"
echo "2. Remove Shovel: rabbitmqctl clear_parameter shovel $SHOVEL_NAME"
echo "3. Delete source queue: rabbitmqadmin delete queue name=$QUEUE_NAME"
echo ""
