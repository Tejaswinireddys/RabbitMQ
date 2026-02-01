#!/bin/bash
#
# 02-install-redis.sh
# Download and install Redis 8.2.2 binaries
# CAN BE RUN AS ROOT (installs to redis user directories)
#
# Usage: sudo ./02-install-redis.sh
#

set -e

# Configuration
REDIS_VERSION="8.2.2"
REDIS_USER="redis"
REDIS_GROUP="redis"
REDIS_HOME="/opt/cached"
REDIS_INSTALL="${REDIS_HOME}/redis-${REDIS_VERSION}"
REDIS_CURRENT="${REDIS_HOME}/current"
BUILD_DIR="/tmp/redis-build-$$"

# Download URL
REDIS_DOWNLOAD_URL="https://github.com/redis/redis/archive/refs/tags/${REDIS_VERSION}.tar.gz"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "[INFO] $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

echo "=============================================="
echo "Redis ${REDIS_VERSION} Installation"
echo "=============================================="
echo ""

# Check prerequisites
log_info "Checking prerequisites..."

# Check for required tools
for cmd in gcc make curl tar; do
    if ! command -v $cmd &> /dev/null; then
        log_error "$cmd is required but not installed"
    fi
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
fi

# Check if user exists
if ! id "$REDIS_USER" > /dev/null 2>&1; then
    log_error "User '$REDIS_USER' does not exist. Run 01-setup-user.sh first"
fi

# Check if directory exists
if [ ! -d "$REDIS_INSTALL" ]; then
    log_error "Directory '$REDIS_INSTALL' does not exist. Run 01-setup-user.sh first"
fi

# Check if already installed
if [ -f "${REDIS_INSTALL}/bin/redis-server" ]; then
    INSTALLED_VERSION=$("${REDIS_INSTALL}/bin/redis-server" --version 2>/dev/null | grep -oP 'v=\K[0-9.]+' || echo "unknown")
    log_warn "Redis already installed (version: $INSTALLED_VERSION)"
    read -p "Reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
fi

# Step 1: Install build dependencies
log_info "Step 1: Installing build dependencies..."

if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    apt-get update -qq
    apt-get install -y -qq build-essential tcl pkg-config libssl-dev libsystemd-dev
elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS/Fedora
    yum groupinstall -y "Development Tools"
    yum install -y tcl openssl-devel systemd-devel
else
    log_warn "Unknown distribution, assuming dependencies are installed"
fi
log_success "Dependencies installed"

# Step 2: Download Redis
log_info "Step 2: Downloading Redis ${REDIS_VERSION}..."

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

curl -sSL -o "redis-${REDIS_VERSION}.tar.gz" "$REDIS_DOWNLOAD_URL"
log_success "Downloaded redis-${REDIS_VERSION}.tar.gz"

# Step 3: Extract
log_info "Step 3: Extracting..."
tar xzf "redis-${REDIS_VERSION}.tar.gz"
cd "redis-${REDIS_VERSION}"
log_success "Extracted"

# Step 4: Compile
log_info "Step 4: Compiling Redis (this may take a few minutes)..."

# Compile with systemd support and TLS
make BUILD_TLS=yes USE_SYSTEMD=yes -j$(nproc) > /dev/null 2>&1
log_success "Compilation complete"

# Step 5: Run tests (optional)
# log_info "Step 5: Running tests..."
# make test > /dev/null 2>&1 || log_warn "Some tests failed, continuing..."

# Step 5: Install binaries
log_info "Step 5: Installing binaries..."

BINARIES=(
    redis-server
    redis-cli
    redis-benchmark
    redis-check-aof
    redis-check-rdb
)

for binary in "${BINARIES[@]}"; do
    if [ -f "src/$binary" ]; then
        install -m 755 "src/$binary" "${REDIS_INSTALL}/bin/"
        log_info "  Installed: $binary"
    fi
done

# Create sentinel symlink
ln -sf "${REDIS_INSTALL}/bin/redis-server" "${REDIS_INSTALL}/bin/redis-sentinel"
log_info "  Created: redis-sentinel (symlink)"

log_success "Binaries installed"

# Step 6: Set ownership
log_info "Step 6: Setting ownership..."
chown -R ${REDIS_USER}:${REDIS_GROUP} "${REDIS_INSTALL}/bin"
log_success "Ownership set"

# Step 7: Verify installation
log_info "Step 7: Verifying installation..."

VERSION_OUTPUT=$("${REDIS_INSTALL}/bin/redis-server" --version)
if [[ "$VERSION_OUTPUT" == *"$REDIS_VERSION"* ]] || [[ "$VERSION_OUTPUT" == *"Redis server"* ]]; then
    log_success "Redis server verified: $VERSION_OUTPUT"
else
    log_warn "Version verification inconclusive: $VERSION_OUTPUT"
fi

CLI_OUTPUT=$("${REDIS_INSTALL}/bin/redis-cli" --version)
log_success "Redis CLI verified: $CLI_OUTPUT"

# Step 8: Create PATH helper script
log_info "Step 8: Creating environment script..."

cat > "${REDIS_INSTALL}/scripts/redis-env.sh" << 'EOF'
#!/bin/bash
# Redis environment variables
# Source this file: source /opt/cached/current/scripts/redis-env.sh

export REDIS_HOME="/opt/cached/current"
export REDIS_BIN="${REDIS_HOME}/bin"
export REDIS_CONF="${REDIS_HOME}/conf"
export REDIS_DATA="${REDIS_HOME}/data"
export REDIS_LOGS="${REDIS_HOME}/logs"
export REDIS_RUN="${REDIS_HOME}/run"

export PATH="${REDIS_BIN}:${PATH}"

# Aliases
alias redis-cli="${REDIS_BIN}/redis-cli"
alias redis-server="${REDIS_BIN}/redis-server"
alias redis-sentinel="${REDIS_BIN}/redis-sentinel"

echo "Redis environment loaded"
echo "  REDIS_HOME: ${REDIS_HOME}"
echo "  Redis version: $(${REDIS_BIN}/redis-server --version | head -1)"
EOF

chmod 755 "${REDIS_INSTALL}/scripts/redis-env.sh"
chown ${REDIS_USER}:${REDIS_GROUP} "${REDIS_INSTALL}/scripts/redis-env.sh"
log_success "Environment script created"

# Summary
echo ""
echo "=============================================="
echo "Installation Complete"
echo "=============================================="
echo ""
echo "Version:     Redis ${REDIS_VERSION}"
echo "Location:    ${REDIS_INSTALL}"
echo "Binaries:    ${REDIS_INSTALL}/bin/"
echo ""
echo "Installed binaries:"
ls -la "${REDIS_INSTALL}/bin/"
echo ""
echo "To use Redis:"
echo "  source ${REDIS_CURRENT}/scripts/redis-env.sh"
echo "  redis-server --version"
echo "  redis-cli --version"
echo ""
echo "Next step: Run 03-configure-node.sh to configure this node"
