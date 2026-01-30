#!/bin/bash
#
# backup-definitions.sh
# Comprehensive backup of RabbitMQ definitions and configuration
#

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/rabbitmq}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

echo "=============================================="
echo "RabbitMQ Backup Script"
echo "Date: $(date)"
echo "Backup Location: $BACKUP_PATH"
echo "=============================================="

# Create backup directory
mkdir -p "$BACKUP_PATH"

# 1. Export definitions (users, vhosts, permissions, exchanges, queues, bindings, policies)
echo ""
echo "[1/6] Exporting definitions..."
if command -v rabbitmqadmin &> /dev/null; then
    rabbitmqadmin export "${BACKUP_PATH}/definitions.json"
else
    # Fallback to management API
    curl -s -u guest:guest http://localhost:15672/api/definitions > "${BACKUP_PATH}/definitions.json"
fi
echo "      Saved: ${BACKUP_PATH}/definitions.json"

# 2. Export cluster status
echo "[2/6] Capturing cluster status..."
rabbitmqctl cluster_status > "${BACKUP_PATH}/cluster_status.txt" 2>&1
echo "      Saved: ${BACKUP_PATH}/cluster_status.txt"

# 3. Export queue details
echo "[3/6] Exporting queue inventory..."
rabbitmqctl list_queues \
    name type durable exclusive auto_delete arguments \
    messages consumers memory policy \
    --formatter=json > "${BACKUP_PATH}/queues.json" 2>/dev/null
echo "      Saved: ${BACKUP_PATH}/queues.json"

# 4. Export bindings
echo "[4/6] Exporting bindings..."
rabbitmqctl list_bindings \
    source_name source_kind destination_name destination_kind \
    routing_key arguments \
    --formatter=json > "${BACKUP_PATH}/bindings.json" 2>/dev/null
echo "      Saved: ${BACKUP_PATH}/bindings.json"

# 5. Backup configuration files
echo "[5/6] Backing up configuration files..."
CONFIG_BACKUP="${BACKUP_PATH}/config"
mkdir -p "$CONFIG_BACKUP"

# Copy config files if they exist
[ -f /etc/rabbitmq/rabbitmq.conf ] && cp /etc/rabbitmq/rabbitmq.conf "$CONFIG_BACKUP/"
[ -f /etc/rabbitmq/advanced.config ] && cp /etc/rabbitmq/advanced.config "$CONFIG_BACKUP/"
[ -f /etc/rabbitmq/enabled_plugins ] && cp /etc/rabbitmq/enabled_plugins "$CONFIG_BACKUP/"
[ -f /etc/rabbitmq/rabbitmq-env.conf ] && cp /etc/rabbitmq/rabbitmq-env.conf "$CONFIG_BACKUP/"

# Copy Erlang cookie (for cluster recovery)
if [ -f /var/lib/rabbitmq/.erlang.cookie ]; then
    cp /var/lib/rabbitmq/.erlang.cookie "$CONFIG_BACKUP/"
    chmod 600 "$CONFIG_BACKUP/.erlang.cookie"
fi

echo "      Saved: ${CONFIG_BACKUP}/"

# 6. Create manifest
echo "[6/6] Creating backup manifest..."
cat << EOF > "${BACKUP_PATH}/manifest.txt"
RabbitMQ Backup Manifest
========================
Timestamp: $(date)
Hostname: $(hostname)
RabbitMQ Version: $(rabbitmqctl version 2>/dev/null || echo "Unknown")
Erlang Version: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo "Unknown")

Files:
EOF

ls -la "$BACKUP_PATH" >> "${BACKUP_PATH}/manifest.txt"

# Create checksums
echo "" >> "${BACKUP_PATH}/manifest.txt"
echo "Checksums (SHA256):" >> "${BACKUP_PATH}/manifest.txt"
find "$BACKUP_PATH" -type f ! -name "checksums.txt" -exec sha256sum {} \; >> "${BACKUP_PATH}/manifest.txt"

echo "      Saved: ${BACKUP_PATH}/manifest.txt"

# Create tarball
echo ""
echo "Creating compressed archive..."
TARBALL="${BACKUP_DIR}/rabbitmq_backup_${TIMESTAMP}.tar.gz"
tar -czvf "$TARBALL" -C "$BACKUP_DIR" "$TIMESTAMP" > /dev/null
echo "Archive created: $TARBALL"

# Cleanup old backups
echo ""
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "rabbitmq_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +${RETENTION_DAYS} -exec rm -rf {} \; 2>/dev/null || true

# Summary
echo ""
echo "=============================================="
echo "Backup Complete"
echo "=============================================="
echo "Location: $BACKUP_PATH"
echo "Archive: $TARBALL"
echo "Size: $(du -h "$TARBALL" | awk '{print $1}')"
echo ""
echo "To restore from this backup:"
echo "  1. Extract: tar -xzvf $TARBALL"
echo "  2. Import: rabbitmqadmin import ${BACKUP_PATH}/definitions.json"
echo ""

# Verify backup
echo "Verifying backup..."
if [ -f "${BACKUP_PATH}/definitions.json" ] && [ -s "${BACKUP_PATH}/definitions.json" ]; then
    # Check JSON is valid
    if python3 -c "import json; json.load(open('${BACKUP_PATH}/definitions.json'))" 2>/dev/null; then
        echo "✓ Backup verified successfully"
        exit 0
    else
        echo "✗ Warning: definitions.json may be invalid"
        exit 1
    fi
else
    echo "✗ Backup verification failed"
    exit 1
fi
