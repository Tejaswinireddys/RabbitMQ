#!/bin/bash

# RabbitMQ 4.1.x RPM Download Script for RHEL 8
# This script downloads all necessary RPM packages for offline installation

set -e

# Configuration
DOWNLOAD_DIR="/tmp/rabbitmq-rpms"
ERLANG_VERSION="26.2.1"
RABBITMQ_VERSION="4.1.0"
RHEL_VERSION="8"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== RabbitMQ 4.1.x RPM Download Script ===${NC}"
echo -e "${YELLOW}Target: RHEL 8 / CentOS Stream 8 / Rocky Linux 8${NC}"
echo -e "${YELLOW}Architecture: x86_64${NC}"
echo

# Create download directory
echo -e "${BLUE}Creating download directory: $DOWNLOAD_DIR${NC}"
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR

# Function to download with retry
download_with_retry() {
    local url=$1
    local filename=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "  ${YELLOW}Attempt $attempt/$max_attempts: $filename${NC}"
        
        if wget --timeout=30 --tries=1 -q "$url" -O "$filename"; then
            echo -e "  ${GREEN}✓ Downloaded: $filename${NC}"
            return 0
        else
            echo -e "  ${RED}✗ Failed attempt $attempt${NC}"
            rm -f "$filename" 2>/dev/null
            attempt=$((attempt + 1))
            sleep 2
        fi
    done
    
    echo -e "  ${RED}✗ Failed to download after $max_attempts attempts: $filename${NC}"
    return 1
}

# Download Erlang packages
echo -e "${BLUE}Downloading Erlang $ERLANG_VERSION packages...${NC}"

# Erlang base URL
ERLANG_BASE_URL="https://packages.erlang-solutions.com/rpm/centos/8/x86_64"

# Core Erlang packages
erlang_packages=(
    "erlang-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-asn1-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-compiler-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-crypto-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-diameter-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-eldap-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-erl_docgen-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-erl_interface-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-erts-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-et-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-eunit-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-inets-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-kernel-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-mnesia-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-os_mon-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-parsetools-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-public_key-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-runtime_tools-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-sasl-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-snmp-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-ssh-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-ssl-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-stdlib-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-syntax_tools-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-tools-${ERLANG_VERSION}-1.el8.x86_64.rpm"
    "erlang-xmerl-${ERLANG_VERSION}-1.el8.x86_64.rpm"
)

# Download Erlang packages
for package in "${erlang_packages[@]}"; do
    download_with_retry "$ERLANG_BASE_URL/$package" "$package"
done

# Download RabbitMQ server
echo -e "${BLUE}Downloading RabbitMQ $RABBITMQ_VERSION server...${NC}"
RABBITMQ_URL="https://github.com/rabbitmq/rabbitmq-server/releases/download/v${RABBITMQ_VERSION}/rabbitmq-server-${RABBITMQ_VERSION}-1.el8.noarch.rpm"
download_with_retry "$RABBITMQ_URL" "rabbitmq-server-${RABBITMQ_VERSION}-1.el8.noarch.rpm"

# Download additional dependencies (these may be available from RHEL repos)
echo -e "${BLUE}Downloading additional dependencies...${NC}"

# EPEL release
echo -e "  ${YELLOW}Downloading EPEL release...${NC}"
EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
download_with_retry "$EPEL_URL" "epel-release-latest-8.noarch.rpm"

# Create package verification script
echo -e "${BLUE}Creating package verification script...${NC}"
cat > verify-packages.sh << 'EOF'
#!/bin/bash

echo "=== RabbitMQ Package Verification ==="

PACKAGES_DIR="."
FAILED_PACKAGES=()

echo "Checking package integrity..."

for rpm_file in *.rpm; do
    if [ -f "$rpm_file" ]; then
        echo -n "Checking $rpm_file... "
        if rpm -K "$rpm_file" >/dev/null 2>&1; then
            echo "✓ OK"
        else
            echo "✗ FAILED"
            FAILED_PACKAGES+=("$rpm_file")
        fi
    fi
done

if [ ${#FAILED_PACKAGES[@]} -eq 0 ]; then
    echo -e "\n✅ All packages verified successfully!"
else
    echo -e "\n❌ Failed packages:"
    for pkg in "${FAILED_PACKAGES[@]}"; do
        echo "  - $pkg"
    done
fi

echo -e "\nPackage summary:"
echo "Total packages: $(ls *.rpm 2>/dev/null | wc -l)"
echo "Erlang packages: $(ls erlang-*.rpm 2>/dev/null | wc -l)"
echo "RabbitMQ packages: $(ls rabbitmq-*.rpm 2>/dev/null | wc -l)"
echo "Other packages: $(ls *.rpm 2>/dev/null | grep -v -E '^(erlang|rabbitmq)' | wc -l)"

echo -e "\nTotal size: $(du -sh . | cut -f1)"
EOF

chmod +x verify-packages.sh

# Create installation order script
echo -e "${BLUE}Creating installation order script...${NC}"
cat > install-order.sh << 'EOF'
#!/bin/bash

echo "=== RabbitMQ Installation Order Guide ==="
echo
echo "Install packages in the following order:"
echo

echo "1. System dependencies (if not already installed):"
echo "   sudo dnf install -y socat logrotate curl wget gnupg2"
echo

echo "2. EPEL repository:"
echo "   sudo rpm -ivh epel-release-latest-8.noarch.rpm"
echo

echo "3. Erlang packages (install all together):"
echo "   sudo rpm -ivh erlang-*.rpm"
echo

echo "4. RabbitMQ server:"
echo "   sudo rpm -ivh rabbitmq-server-*.rpm"
echo

echo "5. Verify installation:"
echo "   erl -version"
echo "   sudo systemctl status rabbitmq-server"
echo

echo "Note: If you encounter dependency issues, use:"
echo "      sudo dnf localinstall *.rpm"
EOF

chmod +x install-order.sh

# Create dependency download script for system packages
echo -e "${BLUE}Creating system dependency download script...${NC}"
cat > download-system-deps.sh << 'EOF'
#!/bin/bash

# Script to download system dependencies using dnf
# Run this on a RHEL 8 system with internet access

echo "=== Downloading System Dependencies ==="

# Create directory for system packages
mkdir -p system-deps
cd system-deps

# Download system dependencies
echo "Downloading system dependencies..."
dnf download --resolve \
    socat \
    logrotate \
    curl \
    wget \
    gnupg2 \
    ca-certificates \
    openssl \
    openssl-libs \
    ncurses-libs

echo "System dependencies downloaded to: $(pwd)"
ls -la

echo "Copy these packages along with Erlang and RabbitMQ packages for offline installation"
EOF

chmod +x download-system-deps.sh

# Generate package manifest
echo -e "${BLUE}Generating package manifest...${NC}"
cat > package-manifest.txt << EOF
# RabbitMQ 4.1.x Package Manifest
# Generated on: $(date)
# Target: RHEL 8 x86_64

## Package Versions
Erlang Version: $ERLANG_VERSION
RabbitMQ Version: $RABBITMQ_VERSION
RHEL Version: $RHEL_VERSION

## Package List
$(ls -la *.rpm 2>/dev/null | awk '{print $9, $5}' | sort)

## Package Count
Total RPM files: $(ls *.rpm 2>/dev/null | wc -l)
Total size: $(du -sh . | cut -f1)

## Checksums
$(sha256sum *.rpm 2>/dev/null | sort)
EOF

# Create tarball for easy transfer
echo -e "${BLUE}Creating distribution tarball...${NC}"
cd ..
TARBALL_NAME="rabbitmq-4.1.x-rpms-rhel8-$(date +%Y%m%d).tar.gz"
tar -czf "$TARBALL_NAME" -C "$DOWNLOAD_DIR" .

echo
echo -e "${GREEN}=== Download Complete! ===${NC}"
echo -e "${GREEN}Package directory: $DOWNLOAD_DIR${NC}"
echo -e "${GREEN}Distribution tarball: $(pwd)/$TARBALL_NAME${NC}"
echo
echo -e "${YELLOW}Package Summary:${NC}"
cd $DOWNLOAD_DIR
echo "  Erlang packages: $(ls erlang-*.rpm 2>/dev/null | wc -l)"
echo "  RabbitMQ packages: $(ls rabbitmq-*.rpm 2>/dev/null | wc -l)"
echo "  Other packages: $(ls *.rpm 2>/dev/null | grep -v -E '^(erlang|rabbitmq)' | wc -l)"
echo "  Total size: $(du -sh . | cut -f1)"
echo
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Run './verify-packages.sh' to verify package integrity"
echo "2. Use './download-system-deps.sh' to get system dependencies"
echo "3. Transfer all packages to target systems"
echo "4. Follow './install-order.sh' for installation sequence"
echo
echo -e "${BLUE}For offline installation, copy the entire directory or use the tarball.${NC}"