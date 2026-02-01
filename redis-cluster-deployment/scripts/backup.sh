#!/bin/bash
#
# backup.sh
# Backup Redis data (RDB snapshot)
#
# Usage: ./backup.sh [--destination /path/to/backup]
#

set -e

# Configuration
REDIS_HOME="/opt/cached/current"
REDIS_BIN="${REDIS_HOME}/bin"
REDIS_CONF="${REDIS_HOME}/conf"
REDIS_DATA="${REDIS_HOME}/data"
BACKUP_DIR="${BACKUP_DIR:-/backup/redis}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Get password from config
REDIS_PASSWORD=$(grep -E "^requirepass" ${REDIS_CONF}/redis.conf 2>/dev/null | awk '{print $2}' || echo "")
REDIS_CLI="${REDIS_BIN}/redis-cli"

if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_CLI="${REDIS_CLI} -a ${REDIS_PASSWORD}"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --destination|-d)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --retention|-r)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--destination /path] [--retention days]"
            exit 1
            ;;
    esac
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)
BACKUP_PATH="${BACKUP_DIR}/${HOSTNAME}"
BACKUP_FILE="${BACKUP_PATH}/redis_backup_${TIMESTAMP}"

echo "=============================================="
echo "Redis Backup"
echo "Date: $(date)"
echo "=============================================="
echo ""

# Create backup directory
log_info "Creating backup directory: ${BACKUP_PATH}"
mkdir -p "${BACKUP_PATH}"

# Check Redis is running
log_info "Checking Redis status..."
ROLE=$($REDIS_CLI INFO replication 2>/dev/null | grep role | cut -d: -f2 | tr -d '\r' || echo "unknown")

if [ "$ROLE" = "unknown" ]; then
    log_error "Cannot connect to Redis"
fi

log_info "Redis role: $ROLE"

# Trigger BGSAVE
log_info "Triggering background save..."
BGSAVE_RESULT=$($REDIS_CLI BGSAVE 2>&1)
log_info "BGSAVE response: $BGSAVE_RESULT"

# Wait for BGSAVE to complete
log_info "Waiting for background save to complete..."
TIMEOUT=300
WAITED=0

while [ $WAITED -lt $TIMEOUT ]; do
    BGSAVE_IN_PROGRESS=$($REDIS_CLI INFO persistence 2>/dev/null | grep rdb_bgsave_in_progress | cut -d: -f2 | tr -d '\r')

    if [ "$BGSAVE_IN_PROGRESS" = "0" ]; then
        log_success "Background save completed"
        break
    fi

    echo -n "."
    sleep 2
    WAITED=$((WAITED + 2))
done
echo ""

if [ $WAITED -ge $TIMEOUT ]; then
    log_error "BGSAVE timeout after ${TIMEOUT} seconds"
fi

# Get RDB file info
RDB_FILE="${REDIS_DATA}/dump.rdb"
if [ ! -f "$RDB_FILE" ]; then
    log_error "RDB file not found: $RDB_FILE"
fi

RDB_SIZE=$(du -h "$RDB_FILE" | awk '{print $1}')
RDB_MTIME=$(stat -c %y "$RDB_FILE" 2>/dev/null || stat -f %Sm "$RDB_FILE" 2>/dev/null)

log_info "RDB file: $RDB_FILE"
log_info "RDB size: $RDB_SIZE"
log_info "RDB modified: $RDB_MTIME"

# Copy RDB file
log_info "Copying RDB file to backup location..."
cp "$RDB_FILE" "${BACKUP_FILE}.rdb"
log_success "Created: ${BACKUP_FILE}.rdb"

# Copy AOF if exists
AOF_DIR="${REDIS_DATA}/appendonlydir"
if [ -d "$AOF_DIR" ]; then
    log_info "Copying AOF directory..."
    cp -r "$AOF_DIR" "${BACKUP_FILE}_aof"
    log_success "Created: ${BACKUP_FILE}_aof/"
fi

# Backup configuration
log_info "Backing up configuration..."
mkdir -p "${BACKUP_FILE}_conf"
cp "${REDIS_CONF}/redis.conf" "${BACKUP_FILE}_conf/" 2>/dev/null || true
cp "${REDIS_CONF}/redis-common.conf" "${BACKUP_FILE}_conf/" 2>/dev/null || true
cp "${REDIS_CONF}/sentinel.conf" "${BACKUP_FILE}_conf/" 2>/dev/null || true
log_success "Created: ${BACKUP_FILE}_conf/"

# Create manifest
log_info "Creating manifest..."
cat > "${BACKUP_FILE}_manifest.txt" << EOF
Redis Backup Manifest
=====================
Timestamp: $(date)
Hostname: $HOSTNAME
Redis Role: $ROLE

Files:
$(ls -la ${BACKUP_FILE}* 2>/dev/null)

Redis Info:
$($REDIS_CLI INFO server 2>/dev/null | head -20)

Checksum (RDB):
$(sha256sum "${BACKUP_FILE}.rdb" 2>/dev/null || shasum -a 256 "${BACKUP_FILE}.rdb" 2>/dev/null)
EOF
log_success "Created: ${BACKUP_FILE}_manifest.txt"

# Compress backup
log_info "Compressing backup..."
cd "${BACKUP_PATH}"
tar -czvf "redis_backup_${TIMESTAMP}.tar.gz" \
    "redis_backup_${TIMESTAMP}.rdb" \
    "redis_backup_${TIMESTAMP}_conf" \
    "redis_backup_${TIMESTAMP}_manifest.txt" \
    $([ -d "redis_backup_${TIMESTAMP}_aof" ] && echo "redis_backup_${TIMESTAMP}_aof") \
    2>/dev/null

# Remove uncompressed files
rm -f "${BACKUP_FILE}.rdb"
rm -rf "${BACKUP_FILE}_conf"
rm -rf "${BACKUP_FILE}_aof"
rm -f "${BACKUP_FILE}_manifest.txt"

COMPRESSED_SIZE=$(du -h "${BACKUP_PATH}/redis_backup_${TIMESTAMP}.tar.gz" | awk '{print $1}')
log_success "Compressed backup: redis_backup_${TIMESTAMP}.tar.gz (${COMPRESSED_SIZE})"

# Clean old backups
log_info "Cleaning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_PATH}" -name "redis_backup_*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

# Summary
echo ""
echo "=============================================="
echo "Backup Complete"
echo "=============================================="
echo ""
echo "Backup file: ${BACKUP_PATH}/redis_backup_${TIMESTAMP}.tar.gz"
echo "Size:        ${COMPRESSED_SIZE}"
echo ""
echo "To restore:"
echo "  1. Extract: tar -xzvf redis_backup_${TIMESTAMP}.tar.gz"
echo "  2. Stop Redis: ./05-stop-services.sh redis"
echo "  3. Copy RDB: cp redis_backup_${TIMESTAMP}.rdb ${REDIS_DATA}/dump.rdb"
echo "  4. Start Redis: ./04-start-services.sh redis"
