# RabbitMQ 4.1.x Dependency Packages and RPM Download Guide

## System Requirements
- **Operating System**: RHEL 8.6+ / CentOS Stream 8 / Rocky Linux 8 / AlmaLinux 8
- **Architecture**: x86_64 (AMD64)
- **Kernel**: 4.18.0+ 

## Core Dependencies

### 1. Erlang/OTP Requirements

#### Erlang Version Compatibility
- **RabbitMQ 4.1.x**: Requires Erlang 26.x (26.0 - 26.2)
- **Minimum**: Erlang 26.0
- **Recommended**: Erlang 26.2.x (latest stable)

#### Erlang Dependencies
```bash
# Core Erlang packages
erlang-26.2.1-1.el8.x86_64.rpm
erlang-asn1-26.2.1-1.el8.x86_64.rpm
erlang-compiler-26.2.1-1.el8.x86_64.rpm
erlang-crypto-26.2.1-1.el8.x86_64.rpm
erlang-diameter-26.2.1-1.el8.x86_64.rpm
erlang-eldap-26.2.1-1.el8.x86_64.rpm
erlang-erl_docgen-26.2.1-1.el8.x86_64.rpm
erlang-erl_interface-26.2.1-1.el8.x86_64.rpm
erlang-erts-26.2.1-1.el8.x86_64.rpm
erlang-et-26.2.1-1.el8.x86_64.rpm
erlang-eunit-26.2.1-1.el8.x86_64.rpm
erlang-inets-26.2.1-1.el8.x86_64.rpm
erlang-kernel-26.2.1-1.el8.x86_64.rpm
erlang-mnesia-26.2.1-1.el8.x86_64.rpm
erlang-os_mon-26.2.1-1.el8.x86_64.rpm
erlang-parsetools-26.2.1-1.el8.x86_64.rpm
erlang-public_key-26.2.1-1.el8.x86_64.rpm
erlang-runtime_tools-26.2.1-1.el8.x86_64.rpm
erlang-sasl-26.2.1-1.el8.x86_64.rpm
erlang-snmp-26.2.1-1.el8.x86_64.rpm
erlang-ssh-26.2.1-1.el8.x86_64.rpm
erlang-ssl-26.2.1-1.el8.x86_64.rpm
erlang-stdlib-26.2.1-1.el8.x86_64.rpm
erlang-syntax_tools-26.2.1-1.el8.x86_64.rpm
erlang-tools-26.2.1-1.el8.x86_64.rpm
erlang-xmerl-26.2.1-1.el8.x86_64.rpm
```

### 2. System Dependencies

#### Core System Packages
```bash
# Essential system packages
glibc-2.28-225.el8.x86_64.rpm
glibc-common-2.28-225.el8.x86_64.rpm
glibc-minimal-langpack-2.28-225.el8.x86_64.rpm
libgcc-8.5.0-18.el8.x86_64.rpm
libstdc++-8.5.0-18.el8.x86_64.rpm
zlib-1.2.11-25.el8.x86_64.rpm
openssl-1.1.1k-12.el8.x86_64.rpm
openssl-libs-1.1.1k-12.el8.x86_64.rpm
ncurses-libs-6.1-10.20180224.el8.x86_64.rpm
```

#### Network and Security
```bash
# Network utilities
socat-1.7.4.1-1.el8.x86_64.rpm
logrotate-3.14.0-6.el8.x86_64.rpm
curl-7.61.1-33.el8.x86_64.rpm
wget-1.19.5-11.el8.x86_64.rpm

# Security and certificates
ca-certificates-2023.2.60-1.el8.noarch.rpm
gnupg2-2.2.20-3.el8.x86_64.rpm
```

#### Process Management
```bash
# Systemd and process management
systemd-239-78.el8.x86_64.rpm
systemd-libs-239-78.el8.x86_64.rpm
dbus-1.12.8-26.el8.x86_64.rpm
```

### 3. RabbitMQ Server Package

#### Main RabbitMQ Package
```bash
# RabbitMQ 4.1.x server
rabbitmq-server-4.1.0-1.el8.noarch.rpm
```

## RPM Download Sources

### 1. Official RabbitMQ Repository
```bash
# Add RabbitMQ repository
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | sudo bash

# Repository configuration file
[rabbitmq-server]
name=rabbitmq-server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
```

### 2. Erlang Solutions Repository
```bash
# Erlang Solutions repository for RHEL 8
[erlang-solutions]
name=CentOS 8 - Erlang Solutions
baseurl=https://packages.erlang-solutions.com/rpm/centos/8/$basearch
gpgcheck=1
gpgkey=https://packages.erlang-solutions.com/rpm/erlang_solutions.asc
enabled=1
```

### 3. EPEL Repository
```bash
# EPEL for additional packages
epel-release-8-19.el8.noarch.rpm
```

## Complete Dependency Download Script

### Download Script for Online Environment
```bash
#!/bin/bash
# File: download-rabbitmq-dependencies.sh

set -e

DOWNLOAD_DIR="/tmp/rabbitmq-packages"
ERLANG_VERSION="26.2.1"
RABBITMQ_VERSION="4.1.0"

echo "=== RabbitMQ 4.1.x Dependencies Download Script ==="

# Create download directory
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR

# Function to download RPM packages
download_package() {
    local package_name=$1
    local repo_url=$2
    
    echo "Downloading $package_name..."
    wget -q --no-check-certificate "$repo_url/$package_name" -O "$package_name"
    
    if [ $? -eq 0 ]; then
        echo "✓ Downloaded: $package_name"
    else
        echo "✗ Failed to download: $package_name"
    fi
}

# Download Erlang packages
echo "Downloading Erlang packages..."
ERLANG_BASE_URL="https://packages.erlang-solutions.com/rpm/centos/8/x86_64"

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

for package in "${erlang_packages[@]}"; do
    download_package "$package" "$ERLANG_BASE_URL"
done

# Download RabbitMQ server
echo "Downloading RabbitMQ server..."
RABBITMQ_URL="https://packagecloud.io/rabbitmq/rabbitmq-server/packages/el/8/rabbitmq-server-${RABBITMQ_VERSION}-1.el8.noarch.rpm/download.rpm"
download_package "rabbitmq-server-${RABBITMQ_VERSION}-1.el8.noarch.rpm" "$RABBITMQ_URL"

# Download system dependencies (these should be available from RHEL repos)
echo "Note: System dependencies should be downloaded from RHEL repositories:"
echo "- socat, logrotate, curl, wget, gnupg2, ca-certificates"
echo "- Use 'dnf download' command to get these from RHEL repos"

echo "Download completed! Packages saved in: $DOWNLOAD_DIR"
ls -la $DOWNLOAD_DIR
```

### Offline Installation Package List
```bash
#!/bin/bash
# File: create-offline-package-list.sh

# Create a comprehensive package list for offline installation
cat > rabbitmq-package-list.txt << 'EOF'
# Core system dependencies (download from RHEL repos)
socat
logrotate
curl
wget
gnupg2
ca-certificates
systemd
systemd-libs
dbus
openssl
openssl-libs
ncurses-libs
glibc
glibc-common
libgcc
libstdc++
zlib

# Erlang 26.2.x packages (download from Erlang Solutions)
erlang-26.2.1
erlang-asn1-26.2.1
erlang-compiler-26.2.1
erlang-crypto-26.2.1
erlang-diameter-26.2.1
erlang-eldap-26.2.1
erlang-erl_docgen-26.2.1
erlang-erl_interface-26.2.1
erlang-erts-26.2.1
erlang-et-26.2.1
erlang-eunit-26.2.1
erlang-inets-26.2.1
erlang-kernel-26.2.1
erlang-mnesia-26.2.1
erlang-os_mon-26.2.1
erlang-parsetools-26.2.1
erlang-public_key-26.2.1
erlang-runtime_tools-26.2.1
erlang-sasl-26.2.1
erlang-snmp-26.2.1
erlang-ssh-26.2.1
erlang-ssl-26.2.1
erlang-stdlib-26.2.1
erlang-syntax_tools-26.2.1
erlang-tools-26.2.1
erlang-xmerl-26.2.1

# RabbitMQ server
rabbitmq-server-4.1.0
EOF

echo "Package list created: rabbitmq-package-list.txt"
```

## Manual Download Commands

### Using DNF (Online)
```bash
# Download all dependencies to current directory
dnf download --resolve socat logrotate curl wget gnupg2 ca-certificates

# Download Erlang (after adding Erlang Solutions repo)
dnf download --resolve erlang

# Download RabbitMQ (after adding RabbitMQ repo)
dnf download --resolve rabbitmq-server
```

### Using YUM (Alternative)
```bash
# Download packages with dependencies
yumdownloader --resolve socat logrotate curl wget gnupg2
yumdownloader --resolve erlang
yumdownloader --resolve rabbitmq-server
```

### Direct Wget Downloads
```bash
# Erlang Solutions packages
wget https://packages.erlang-solutions.com/rpm/centos/8/x86_64/erlang-26.2.1-1.el8.x86_64.rpm

# RabbitMQ server
wget https://github.com/rabbitmq/rabbitmq-server/releases/download/v4.1.0/rabbitmq-server-4.1.0-1.el8.noarch.rpm
```

## Offline Installation Preparation

### Create Local Repository
```bash
#!/bin/bash
# File: create-local-repo.sh

REPO_DIR="/opt/local-repo"
PACKAGES_DIR="/tmp/rabbitmq-packages"

echo "Creating local repository for offline installation..."

# Create repository directory
sudo mkdir -p $REPO_DIR
sudo cp $PACKAGES_DIR/*.rpm $REPO_DIR/

# Install createrepo if not available
sudo dnf install -y createrepo

# Create repository metadata
sudo createrepo $REPO_DIR

# Create repository configuration
sudo tee /etc/yum.repos.d/local-rabbitmq.repo << EOF
[local-rabbitmq]
name=Local RabbitMQ Repository
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
EOF

echo "Local repository created at: $REPO_DIR"
echo "Repository configuration: /etc/yum.repos.d/local-rabbitmq.repo"
```

### Offline Installation Script
```bash
#!/bin/bash
# File: offline-install.sh

PACKAGES_DIR="/tmp/rabbitmq-packages"

echo "=== Offline RabbitMQ Installation ==="

# Install packages in correct order
echo "Installing system dependencies..."
sudo rpm -ivh $PACKAGES_DIR/socat-*.rpm
sudo rpm -ivh $PACKAGES_DIR/logrotate-*.rpm
sudo rpm -ivh $PACKAGES_DIR/curl-*.rpm
sudo rpm -ivh $PACKAGES_DIR/wget-*.rpm
sudo rpm -ivh $PACKAGES_DIR/gnupg2-*.rpm

echo "Installing Erlang..."
sudo rpm -ivh $PACKAGES_DIR/erlang-*.rpm

echo "Installing RabbitMQ server..."
sudo rpm -ivh $PACKAGES_DIR/rabbitmq-server-*.rpm

echo "Offline installation completed!"
```

## Verification Commands

### Check Installed Packages
```bash
# Verify Erlang installation
erl -version
rpm -qa | grep erlang

# Verify RabbitMQ installation
rpm -qa | grep rabbitmq
sudo systemctl status rabbitmq-server

# Check dependencies
rpm -qR rabbitmq-server
ldd /usr/lib64/erlang/erts-*/bin/beam.smp
```

### Package Information
```bash
# Get package information
rpm -qi rabbitmq-server
rpm -qi erlang

# List package files
rpm -ql rabbitmq-server
rpm -ql erlang

# Check package dependencies
rpm -qR rabbitmq-server
```

## Package Sizes (Approximate)

| Package Category | Size | Count |
|------------------|------|--------|
| **Erlang packages** | ~85 MB | 22 packages |
| **RabbitMQ server** | ~15 MB | 1 package |
| **System dependencies** | ~25 MB | 8-10 packages |
| **Total** | **~125 MB** | **31+ packages** |

## Repository GPG Keys

### RabbitMQ Signing Key
```bash
# Import RabbitMQ signing key
sudo rpm --import https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
```

### Erlang Solutions Key
```bash
# Import Erlang Solutions key
sudo rpm --import https://packages.erlang-solutions.com/rpm/erlang_solutions.asc
```

## Troubleshooting

### Common Issues
1. **Missing dependencies**: Use `--force` or `--nodeps` with caution
2. **GPG verification fails**: Import correct signing keys
3. **Version conflicts**: Ensure compatible Erlang version
4. **Network issues**: Use offline installation method

### Dependency Resolution
```bash
# Check missing dependencies
rpm -qpR package.rpm

# Install with dependency resolution
sudo dnf localinstall package.rpm

# Force installation (use with caution)
sudo rpm -ivh --force --nodeps package.rpm
```

This comprehensive guide provides all necessary information for downloading and installing RabbitMQ 4.1.x dependencies in both online and offline environments.