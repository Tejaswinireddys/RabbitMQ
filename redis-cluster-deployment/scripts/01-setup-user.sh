#!/bin/bash
#
# 01-setup-user.sh
# Create redis user and directory structure
# MUST BE RUN AS ROOT
#
# Usage: sudo ./01-setup-user.sh
#

set -e

# Configuration
REDIS_USER="redis"
REDIS_GROUP="redis"
REDIS_UID=6379
REDIS_GID=6379
REDIS_HOME="/opt/cached"
REDIS_CURRENT="${REDIS_HOME}/current"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo "=============================================="
echo "Redis User and Directory Setup"
echo "=============================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "Operating System: $NAME $VERSION_ID"
else
    log_warn "Cannot detect OS version"
fi

# Step 1: Create redis group
log_info "Step 1: Creating redis group..."
if getent group "$REDIS_GROUP" > /dev/null 2>&1; then
    log_warn "Group '$REDIS_GROUP' already exists"
else
    groupadd -g $REDIS_GID $REDIS_GROUP
    log_success "Group '$REDIS_GROUP' created with GID $REDIS_GID"
fi

# Step 2: Create redis user
log_info "Step 2: Creating redis user..."
if id "$REDIS_USER" > /dev/null 2>&1; then
    log_warn "User '$REDIS_USER' already exists"
else
    useradd -r -u $REDIS_UID -g $REDIS_GROUP -d $REDIS_HOME -s /bin/bash -c "Redis Server" $REDIS_USER
    log_success "User '$REDIS_USER' created with UID $REDIS_UID"
fi

# Step 3: Create directory structure
log_info "Step 3: Creating directory structure..."

DIRS=(
    "${REDIS_HOME}"
    "${REDIS_HOME}/redis-8.2.2"
    "${REDIS_HOME}/redis-8.2.2/bin"
    "${REDIS_HOME}/redis-8.2.2/conf"
    "${REDIS_HOME}/redis-8.2.2/data"
    "${REDIS_HOME}/redis-8.2.2/logs"
    "${REDIS_HOME}/redis-8.2.2/run"
    "${REDIS_HOME}/redis-8.2.2/scripts"
    "${REDIS_HOME}/redis-8.2.2/certs"
)

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_info "  Created: $dir"
    else
        log_info "  Exists: $dir"
    fi
done

# Step 4: Create symlink
log_info "Step 4: Creating 'current' symlink..."
if [ -L "${REDIS_CURRENT}" ]; then
    rm "${REDIS_CURRENT}"
fi
ln -s "${REDIS_HOME}/redis-8.2.2" "${REDIS_CURRENT}"
log_success "Symlink created: ${REDIS_CURRENT} -> ${REDIS_HOME}/redis-8.2.2"

# Step 5: Set permissions
log_info "Step 5: Setting permissions..."
chown -R ${REDIS_USER}:${REDIS_GROUP} ${REDIS_HOME}
chmod 755 ${REDIS_HOME}
chmod 750 ${REDIS_HOME}/redis-8.2.2
chmod 750 ${REDIS_HOME}/redis-8.2.2/conf
chmod 750 ${REDIS_HOME}/redis-8.2.2/data
chmod 750 ${REDIS_HOME}/redis-8.2.2/logs
chmod 750 ${REDIS_HOME}/redis-8.2.2/run
chmod 750 ${REDIS_HOME}/redis-8.2.2/scripts
chmod 700 ${REDIS_HOME}/redis-8.2.2/certs
log_success "Permissions set"

# Step 6: Configure system limits
log_info "Step 6: Configuring system limits..."

# Add limits.conf entry
LIMITS_FILE="/etc/security/limits.d/redis.conf"
cat > $LIMITS_FILE << EOF
# Redis limits
${REDIS_USER} soft nofile 65536
${REDIS_USER} hard nofile 65536
${REDIS_USER} soft nproc 65536
${REDIS_USER} hard nproc 65536
EOF
log_success "Created $LIMITS_FILE"

# Step 7: Configure sysctl for Redis
log_info "Step 7: Configuring kernel parameters..."

SYSCTL_FILE="/etc/sysctl.d/99-redis.conf"
cat > $SYSCTL_FILE << EOF
# Redis kernel parameters

# Memory overcommit
vm.overcommit_memory = 1

# Disable Transparent Huge Pages (THP) warning
# Note: THP should be disabled at boot via systemd or rc.local

# TCP backlog
net.core.somaxconn = 65535

# TCP keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5

# Network buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

sysctl -p $SYSCTL_FILE > /dev/null 2>&1 || true
log_success "Kernel parameters configured"

# Step 8: Create THP disable service
log_info "Step 8: Creating THP disable service..."

THP_SERVICE="/etc/systemd/system/disable-thp.service"
cat > $THP_SERVICE << EOF
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=redis.service redis-sentinel.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF

systemctl daemon-reload
systemctl enable disable-thp.service
systemctl start disable-thp.service || true
log_success "THP disable service created and enabled"

# Summary
echo ""
echo "=============================================="
echo "Setup Complete"
echo "=============================================="
echo ""
echo "User:        ${REDIS_USER} (UID: ${REDIS_UID})"
echo "Group:       ${REDIS_GROUP} (GID: ${REDIS_GID})"
echo "Home:        ${REDIS_HOME}"
echo "Current:     ${REDIS_CURRENT}"
echo ""
echo "Directory Structure:"
find ${REDIS_HOME} -maxdepth 3 -type d | head -20
echo ""
echo "Next step: Run 02-install-redis.sh to install Redis binaries"
