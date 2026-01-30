#!/bin/bash
#
# queue-inventory.sh
# Generate comprehensive queue inventory for migration planning
#

set -e

OUTPUT_DIR="${1:-.}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/queue_inventory_${TIMESTAMP}.md"
JSON_FILE="${OUTPUT_DIR}/queue_inventory_${TIMESTAMP}.json"

echo "Generating queue inventory report..."
echo "Output: $REPORT_FILE"

# Generate JSON export
rabbitmqctl list_queues \
    name type durable exclusive auto_delete arguments \
    messages messages_ready messages_unacknowledged \
    consumers memory policy state \
    --formatter=json > "$JSON_FILE"

# Start report
cat << EOF > "$REPORT_FILE"
# RabbitMQ Queue Inventory Report

**Generated:** $(date)
**Cluster:** $(rabbitmqctl cluster_status 2>/dev/null | grep "Cluster name" | awk '{print $NF}' || echo "Unknown")
**RabbitMQ Version:** $(rabbitmqctl version 2>/dev/null)

---

## Summary Statistics

EOF

# Count queues by type
TOTAL_QUEUES=$(rabbitmqctl list_queues name --quiet 2>/dev/null | wc -l)
CLASSIC_QUEUES=$(rabbitmqctl list_queues type --quiet 2>/dev/null | grep -c "classic" || echo "0")
QUORUM_QUEUES=$(rabbitmqctl list_queues type --quiet 2>/dev/null | grep -c "quorum" || echo "0")
STREAM_QUEUES=$(rabbitmqctl list_queues type --quiet 2>/dev/null | grep -c "stream" || echo "0")

cat << EOF >> "$REPORT_FILE"
| Metric | Count |
|--------|-------|
| Total Queues | $TOTAL_QUEUES |
| Classic Queues | $CLASSIC_QUEUES |
| Quorum Queues | $QUORUM_QUEUES |
| Stream Queues | $STREAM_QUEUES |

---

## Migration Eligibility Analysis

EOF

# Analyze each queue for migration eligibility
echo "### Queues Eligible for Quorum Migration" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Queue Name | Messages | Consumers | Memory | Reason |" >> "$REPORT_FILE"
echo "|------------|----------|-----------|--------|--------|" >> "$REPORT_FILE"

MIGRATE_COUNT=0
rabbitmqctl list_queues name type durable exclusive auto_delete arguments messages consumers memory --quiet 2>/dev/null | \
while IFS=$'\t' read -r name type durable exclusive auto_delete arguments messages consumers memory; do
    if [ "$type" == "classic" ] && [ "$durable" == "true" ] && [ "$exclusive" == "false" ] && [ "$auto_delete" == "false" ]; then
        # Check for priority queue
        if [[ "$arguments" == *"x-max-priority"* ]]; then
            continue
        fi
        echo "| $name | $messages | $consumers | $memory | Eligible |" >> "$REPORT_FILE"
        ((MIGRATE_COUNT++))
    fi
done

cat << EOF >> "$REPORT_FILE"

**Total eligible for migration:** Queues that are durable, non-exclusive, non-auto-delete, and non-priority

---

### Queues to Remain Classic

| Queue Name | Type | Reason |
|------------|------|--------|
EOF

rabbitmqctl list_queues name type durable exclusive auto_delete arguments --quiet 2>/dev/null | \
while IFS=$'\t' read -r name type durable exclusive auto_delete arguments; do
    if [ "$type" == "quorum" ] || [ "$type" == "stream" ]; then
        echo "| $name | $type | Already quorum/stream |" >> "$REPORT_FILE"
    elif [ "$exclusive" == "true" ]; then
        echo "| $name | classic | Exclusive queue |" >> "$REPORT_FILE"
    elif [ "$auto_delete" == "true" ]; then
        echo "| $name | classic | Auto-delete queue |" >> "$REPORT_FILE"
    elif [ "$durable" == "false" ]; then
        echo "| $name | classic | Non-durable queue |" >> "$REPORT_FILE"
    elif [[ "$arguments" == *"x-max-priority"* ]]; then
        echo "| $name | classic | Priority queue |" >> "$REPORT_FILE"
    fi
done

cat << EOF >> "$REPORT_FILE"

---

## Queue Details

### All Queues (Sorted by Message Count)

| Queue Name | Type | Messages | Consumers | Memory (bytes) | Policy |
|------------|------|----------|-----------|----------------|--------|
EOF

rabbitmqctl list_queues name type messages consumers memory policy --quiet 2>/dev/null | \
    sort -t$'\t' -k3 -rn | head -50 | \
while IFS=$'\t' read -r name type messages consumers memory policy; do
    echo "| $name | $type | $messages | $consumers | $memory | ${policy:-none} |" >> "$REPORT_FILE"
done

cat << EOF >> "$REPORT_FILE"

---

## Bindings Summary

EOF

echo "| Exchange | Queue | Routing Key |" >> "$REPORT_FILE"
echo "|----------|-------|-------------|" >> "$REPORT_FILE"

rabbitmqctl list_bindings source_name destination_name routing_key --quiet 2>/dev/null | head -50 | \
while IFS=$'\t' read -r source dest routing; do
    if [ -n "$source" ]; then
        echo "| $source | $dest | $routing |" >> "$REPORT_FILE"
    fi
done

cat << EOF >> "$REPORT_FILE"

---

## Policies

| Name | Pattern | Definition | Apply To |
|------|---------|------------|----------|
EOF

rabbitmqctl list_policies --quiet 2>/dev/null | \
while IFS=$'\t' read -r vhost name pattern apply_to definition priority; do
    echo "| $name | $pattern | $definition | $apply_to |" >> "$REPORT_FILE"
done

cat << EOF >> "$REPORT_FILE"

---

## Recommendations

1. **Migrate to Quorum:** All eligible classic queues should be migrated to quorum queues for improved durability and automatic leader election.

2. **Keep as Classic:** Exclusive queues, auto-delete queues, and priority queues must remain classic.

3. **HA Policies:** Remove any ha-mode policies after converting to quorum queues.

4. **Large Queues:** Queues with high message counts should be drained before migration if possible.

---

**Full JSON export:** ${JSON_FILE}
EOF

echo ""
echo "Report generated: $REPORT_FILE"
echo "JSON export: $JSON_FILE"
echo ""
echo "Quick stats:"
echo "  Total queues: $TOTAL_QUEUES"
echo "  Classic: $CLASSIC_QUEUES"
echo "  Quorum: $QUORUM_QUEUES"
echo "  Stream: $STREAM_QUEUES"
