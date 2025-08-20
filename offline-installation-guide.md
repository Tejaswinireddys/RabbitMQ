# Offline Installation Guide for RabbitMQ 4.1.x

## Overview
This guide provides step-by-step instructions for installing RabbitMQ 4.1.x in environments without internet access using pre-downloaded RPM packages.

## Prerequisites

### System Requirements
- RHEL 8.6+ / CentOS Stream 8 / Rocky Linux 8 / AlmaLinux 8
- Architecture: x86_64
- Storage: 200+ MB free space for packages
- User: root or sudo access

### Pre-Download Requirements
1. **Download all packages** using the provided download script
2. **Transfer packages** to target systems via:
   - USB drive
   - Network file share
   - SCP/SFTP transfer
   - DVD/CD media

## Package Download Process

### Step 1: Download Packages (Internet-Connected System)
```bash
# On a system with internet access
chmod +x download-rpms-script.sh
./download-rpms-script.sh

# This creates:
# - /tmp/rabbitmq-rpms/ directory with all packages
# - rabbitmq-4.1.x-rpms-rhel8-YYYYMMDD.tar.gz tarball
```

### Step 2: Transfer to Target Systems
```bash
# Option 1: Using tarball
scp rabbitmq-4.1.x-rpms-rhel8-*.tar.gz user@target-server:/tmp/

# Option 2: Using directory
rsync -av /tmp/rabbitmq-rpms/ user@target-server:/tmp/rabbitmq-rpms/

# Option 3: USB/External media
cp -r /tmp/rabbitmq-rpms /media/usb-drive/
```

## Offline Installation Process

### Step 1: Prepare Target System
```bash
# Extract packages on target system
cd /tmp
tar -xzf rabbitmq-4.1.x-rpms-rhel8-*.tar.gz
cd rabbitmq-rpms

# Verify all packages are present
ls -la *.rpm
./verify-packages.sh
```

### Step 2: Install System Dependencies
```bash
# Check if system dependencies are already installed
rpm -qa | grep -E "(socat|logrotate|curl|wget|gnupg2)"

# If missing, install from local packages or RHEL media
# Option 1: From downloaded system-deps (if available)
sudo rpm -ivh system-deps/*.rpm

# Option 2: From RHEL installation media
# Mount RHEL 8 ISO and install required packages
sudo mount /dev/cdrom /mnt
sudo dnf install /mnt/BaseOS/Packages/socat-*.rpm
sudo dnf install /mnt/BaseOS/Packages/logrotate-*.rpm
# ... other required packages
```

### Step 3: Install EPEL Repository
```bash
# Install EPEL for additional dependencies
sudo rpm -ivh epel-release-latest-8.noarch.rpm

# Verify EPEL installation
dnf repolist | grep epel
```

### Step 4: Install Erlang
```bash
# Install all Erlang packages together
echo "Installing Erlang $ERLANG_VERSION..."
sudo rpm -ivh erlang-*.rpm

# Verify Erlang installation
erl -version
which erl

# Check Erlang version compatibility
erl -eval 'erlang:system_info(otp_release), halt().' -noshell
```

### Step 5: Install RabbitMQ Server
```bash
# Install RabbitMQ server
echo "Installing RabbitMQ $RABBITMQ_VERSION..."
sudo rpm -ivh rabbitmq-server-*.rpm

# Verify installation
rpm -qa | grep rabbitmq
which rabbitmqctl

# Check RabbitMQ version
sudo rabbitmqctl version
```

### Step 6: Post-Installation Configuration
```bash
# Enable RabbitMQ service
sudo systemctl enable rabbitmq-server

# Start RabbitMQ service
sudo systemctl start rabbitmq-server

# Check service status
sudo systemctl status rabbitmq-server

# Verify RabbitMQ is running
sudo rabbitmqctl status
```

## Troubleshooting Offline Installation

### Common Issues and Solutions

#### 1. Missing Dependencies
**Problem**: RPM installation fails due to missing dependencies
```bash
# Error example:
error: Failed dependencies:
    libcrypto.so.1.1 is needed by erlang-crypto-26.2.1-1.el8.x86_64
```

**Solution**:
```bash
# Option 1: Install missing packages from RHEL media
sudo dnf install /mnt/BaseOS/Packages/openssl-libs-*.rpm

# Option 2: Use --nodeps flag (use with caution)
sudo rpm -ivh --nodeps erlang-crypto-*.rpm

# Option 3: Download missing dependencies
# (requires temporary internet access)
dnf download --resolve openssl-libs
sudo rpm -ivh openssl-libs-*.rpm
```

#### 2. GPG Signature Verification Fails
**Problem**: Package signature verification fails
```bash
# Error example:
warning: erlang-26.2.1-1.el8.x86_64.rpm: Header V4 RSA/SHA1 Signature, key ID d208507ca14f4fca: NOKEY
```

**Solution**:
```bash
# Skip GPG verification (for offline installation)
sudo rpm -ivh --nogpgcheck package.rpm

# Or import GPG keys from packages
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-*
```

#### 3. Package Conflicts
**Problem**: Existing packages conflict with installation
```bash
# Error example:
file /usr/bin/erl from install of erlang-26.2.1 conflicts with file from package erlang-25.3.2
```

**Solution**:
```bash
# Remove conflicting packages first
sudo rpm -e erlang-25.3.2

# Or force installation
sudo rpm -ivh --force erlang-26.2.1-*.rpm
```

#### 4. Service Start Failures
**Problem**: RabbitMQ service fails to start
```bash
# Check detailed error logs
sudo journalctl -u rabbitmq-server -f

# Check RabbitMQ logs
sudo tail -f /var/log/rabbitmq/rabbit@hostname.log

# Common solutions:
# 1. Check disk space
df -h /var/lib/rabbitmq

# 2. Check file permissions
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq

# 3. Check hostname resolution
hostname
getent hosts $(hostname)
```

## Validation and Testing

### Installation Verification Script
```bash
#!/bin/bash
# File: validate-offline-installation.sh

echo "=== RabbitMQ Offline Installation Validation ==="

# Check Erlang installation
echo "1. Erlang verification:"
if command -v erl >/dev/null 2>&1; then
    echo "   ✓ Erlang installed"
    echo "   Version: $(erl -eval 'erlang:system_info(otp_release), halt().' -noshell 2>/dev/null)"
else
    echo "   ✗ Erlang not found"
fi

# Check RabbitMQ installation
echo "2. RabbitMQ verification:"
if command -v rabbitmqctl >/dev/null 2>&1; then
    echo "   ✓ RabbitMQ installed"
    echo "   Version: $(sudo rabbitmqctl version 2>/dev/null | head -1)"
else
    echo "   ✗ RabbitMQ not found"
fi

# Check service status
echo "3. Service status:"
if systemctl is-active rabbitmq-server >/dev/null 2>&1; then
    echo "   ✓ RabbitMQ service running"
else
    echo "   ✗ RabbitMQ service not running"
    echo "   Status: $(systemctl is-active rabbitmq-server)"
fi

# Check cluster status
echo "4. Cluster status:"
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "   ✓ RabbitMQ responding to commands"
    sudo rabbitmqctl cluster_status | grep "Cluster name"
else
    echo "   ✗ RabbitMQ not responding"
fi

# Check ports
echo "5. Network ports:"
if netstat -tlnp 2>/dev/null | grep :5672 >/dev/null; then
    echo "   ✓ AMQP port (5672) listening"
else
    echo "   ✗ AMQP port (5672) not listening"
fi

if netstat -tlnp 2>/dev/null | grep :15672 >/dev/null; then
    echo "   ✓ Management port (15672) listening"
else
    echo "   ✗ Management port (15672) not listening"
fi

echo "6. File permissions:"
if [ -r /var/lib/rabbitmq ]; then
    echo "   ✓ Data directory accessible"
else
    echo "   ✗ Data directory not accessible"
fi

echo ""
echo "Installation validation completed!"
```

### Basic Functionality Test
```bash
#!/bin/bash
# File: test-rabbitmq-basic.sh

echo "=== RabbitMQ Basic Functionality Test ==="

# Enable management plugin
echo "1. Enabling management plugin..."
sudo rabbitmq-plugins enable rabbitmq_management

# Create test queue
echo "2. Creating test queue..."
sudo rabbitmqctl declare queue --name=offline_test --type=quorum --durable=true

# Publish test message
echo "3. Publishing test message..."
sudo rabbitmqctl publish exchange="" routing-key="offline_test" payload="Offline installation test message"

# Check queue status
echo "4. Checking queue status:"
sudo rabbitmqctl list_queues name messages

# Create test user
echo "5. Creating test user..."
sudo rabbitmqctl add_user testuser testpass123
sudo rabbitmqctl set_user_tags testuser management
sudo rabbitmqctl set_permissions -p / testuser ".*" ".*" ".*"

echo "6. Testing management interface:"
echo "   URL: http://$(hostname):15672"
echo "   Login: testuser / testpass123"

echo ""
echo "Basic functionality test completed!"
echo "Access management interface to verify full functionality."
```

## Package Management

### Creating Local Repository
```bash
#!/bin/bash
# File: create-local-repository.sh

REPO_DIR="/opt/local-rabbitmq-repo"
PACKAGES_DIR="/tmp/rabbitmq-rpms"

echo "Creating local RabbitMQ repository..."

# Create repository directory
sudo mkdir -p $REPO_DIR

# Copy packages
sudo cp $PACKAGES_DIR/*.rpm $REPO_DIR/

# Install createrepo (if available)
if command -v createrepo >/dev/null 2>&1; then
    sudo createrepo $REPO_DIR
    
    # Create repository configuration
    sudo tee /etc/yum.repos.d/local-rabbitmq.repo << EOF
[local-rabbitmq]
name=Local RabbitMQ Repository
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
priority=1
EOF

    echo "Local repository created: $REPO_DIR"
    echo "Configuration: /etc/yum.repos.d/local-rabbitmq.repo"
    
    # Test repository
    dnf repolist | grep local-rabbitmq
else
    echo "createrepo not available, using direct RPM installation"
fi
```

### Package Update Process
```bash
#!/bin/bash
# File: update-offline-packages.sh

echo "=== Offline Package Update Process ==="

# Stop RabbitMQ service
sudo systemctl stop rabbitmq-server

# Backup current installation
sudo tar -czf /backup/rabbitmq-backup-$(date +%Y%m%d).tar.gz \
    /var/lib/rabbitmq \
    /etc/rabbitmq \
    /var/log/rabbitmq

# Update packages
sudo rpm -Uvh new-packages/*.rpm

# Start service
sudo systemctl start rabbitmq-server

# Verify update
sudo rabbitmqctl version
sudo rabbitmqctl cluster_status

echo "Package update completed!"
```

## Security Considerations

### Package Integrity
```bash
# Verify package checksums before installation
sha256sum -c package-manifest.txt

# Check package signatures (if GPG keys available)
rpm --checksig *.rpm
```

### System Hardening
```bash
# Remove installation packages after installation
rm -rf /tmp/rabbitmq-rpms

# Secure RabbitMQ directories
sudo chmod 750 /var/lib/rabbitmq
sudo chmod 750 /var/log/rabbitmq

# Remove default guest user
sudo rabbitmqctl delete_user guest
```

## Best Practices

### 1. Pre-Installation Checklist
- [ ] Verify system compatibility (RHEL 8.6+, x86_64)
- [ ] Check available disk space (500+ MB)
- [ ] Ensure proper user privileges (root/sudo)
- [ ] Backup existing system state
- [ ] Verify package integrity

### 2. Installation Process
- [ ] Install packages in correct order (system → Erlang → RabbitMQ)
- [ ] Verify each installation step
- [ ] Check service status after installation
- [ ] Test basic functionality
- [ ] Configure firewall rules

### 3. Post-Installation
- [ ] Enable required plugins
- [ ] Create application users
- [ ] Configure clustering (if multi-node)
- [ ] Set up monitoring
- [ ] Document configuration changes

### 4. Rollback Plan
- [ ] Keep original system packages
- [ ] Maintain configuration backups
- [ ] Document rollback procedures
- [ ] Test rollback process

This comprehensive offline installation guide ensures successful RabbitMQ 4.1.x deployment in air-gapped environments while maintaining security and reliability standards.