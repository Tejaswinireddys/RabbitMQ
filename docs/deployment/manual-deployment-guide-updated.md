# RabbitMQ 4.1.x Environment-Based Manual Deployment Guide

## Overview

This updated manual deployment guide uses environment-based configuration management for easier deployment across multiple environments (QA, Staging, Production). The environment configuration system provides:

- **Static cluster names** per environment
- **Environment-specific hostnames and IPs**
- **Centralized configuration management**
- **Easy environment switching**
- **Consistent deployment process**

## 1. Prerequisites

### System Requirements
- **Operating System**: RHEL 8.x
- **Memory**: Minimum 4GB RAM per node (8GB+ for production)
- **Disk**: 20GB+ free space per node (50GB+ for production)
- **Network**: Static IP addresses for all nodes
- **User Access**: Root or sudo privileges

### Pre-Deployment Setup

#### 1.1: Download and Setup Environment Configuration
```bash
# Download deployment files (assuming they're in current directory)
cd /opt/rabbitmq-deployment

# Make scripts executable
chmod +x load-environment.sh
chmod +x environment-manager.sh
chmod +x generate-configs.sh

# List available environments
./load-environment.sh list
```

#### 1.2: Configure Your Environment
```bash
# For new environments, create from template
./environment-manager.sh create your-env-name

# Or clone existing environment
./environment-manager.sh clone qa your-env-name

# Edit the environment file with your specific settings
vi environments/your-env-name.env
```

### Sample Environment Configuration
Update `environments/your-env-name.env` with your environment-specific details:

```bash
# === Environment Info ===
ENVIRONMENT_NAME="your-env"
ENVIRONMENT_TYPE="production"  # or qa, staging, development

# === Cluster Name (Environment Specific) ===
RABBITMQ_CLUSTER_NAME="rabbitmq-your-env-cluster"

# === Node Configuration ===
RABBITMQ_NODE_1_HOSTNAME="prod-rmq-node1"
RABBITMQ_NODE_2_HOSTNAME="prod-rmq-node2"
RABBITMQ_NODE_3_HOSTNAME="prod-rmq-node3"

# === IP Addresses ===
RABBITMQ_NODE_1_IP="10.20.20.10"
RABBITMQ_NODE_2_IP="10.20.20.11"
RABBITMQ_NODE_3_IP="10.20.20.12"

# === Load Balancer Configuration ===
RABBITMQ_VIP="10.20.20.100"
```

#### 1.3: Validate Environment Configuration
```bash
# Validate your environment configuration
./load-environment.sh validate your-env-name

# Show environment details
./load-environment.sh show your-env-name
```

#### 1.4: Generate Configuration Files
```bash
# Generate environment-specific configuration files
./generate-configs.sh your-env-name

# Review generated files
ls -la *.conf *.config *.json
```

#### 1.5: Update Network Configuration
```bash
# Automatically update /etc/hosts with environment hostnames
./environment-manager.sh update-hosts your-env-name

# Or manually update /etc/hosts on ALL nodes
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster - your-env Environment
10.20.20.10 prod-rmq-node1
10.20.20.11 prod-rmq-node2
10.20.20.12 prod-rmq-node3
EOF
```

### 1.6: Firewall Configuration (Run on ALL nodes)
```bash
# Load environment to get port configurations
source ./load-environment.sh your-env-name

# Open required ports
sudo firewall-cmd --permanent --add-port=$RABBITMQ_NODE_PORT/tcp      # AMQP
sudo firewall-cmd --permanent --add-port=$RABBITMQ_MANAGEMENT_PORT/tcp # Management UI
sudo firewall-cmd --permanent --add-port=$RABBITMQ_DIST_PORT/tcp       # Inter-node communication
sudo firewall-cmd --permanent --add-port=4369/tcp                      # EPMD port mapper
sudo firewall-cmd --permanent --add-port=35672-35682/tcp               # Erlang distribution

# SSL ports if SSL is enabled
if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
    sudo firewall-cmd --permanent --add-port=5671/tcp   # AMQP SSL
    sudo firewall-cmd --permanent --add-port=15671/tcp  # Management SSL
fi

sudo firewall-cmd --reload

# Verify firewall rules
sudo firewall-cmd --list-ports
```

### 1.7: SELinux Configuration (Run on ALL nodes)
```bash
# Set SELinux to permissive (or configure properly)
sudo setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

## 2. Installation Steps (Run on ALL nodes)

### 2.1: Install Dependencies and RabbitMQ
```bash
# Update system
sudo dnf update -y

# Install EPEL repository
sudo dnf install -y epel-release

# Install required packages
sudo dnf install -y curl wget gnupg2 socat logrotate

# Install Erlang 26.x (required for RabbitMQ 4.1.x)
sudo dnf install -y erlang

# Verify Erlang installation
erl -version

# Add RabbitMQ repository
sudo tee /etc/yum.repos.d/rabbitmq.repo << EOF
[rabbitmq-server]
name=rabbitmq-server
baseurl=https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/\$basearch
repo_gpgcheck=1
gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF

# Import GPG keys
sudo rpm --import https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key

# Install RabbitMQ 4.1.x
sudo dnf install -y rabbitmq-server

# Create necessary directories
sudo mkdir -p /etc/rabbitmq /var/log/rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq /var/lib/rabbitmq /etc/rabbitmq
```

## 3. Environment-Based Node Configuration

### 3.1: Setup Environment on Each Node
```bash
# Copy deployment files to each node
scp -r /opt/rabbitmq-deployment/ root@$RABBITMQ_NODE_1_HOSTNAME:/opt/
scp -r /opt/rabbitmq-deployment/ root@$RABBITMQ_NODE_2_HOSTNAME:/opt/
scp -r /opt/rabbitmq-deployment/ root@$RABBITMQ_NODE_3_HOSTNAME:/opt/

# On each node, load the environment
cd /opt/rabbitmq-deployment
source ./load-environment.sh your-env-name
```

### 3.2: Generate Erlang Cookie (Same on ALL nodes)
```bash
# Generate secure Erlang cookie
ERLANG_COOKIE=$(openssl rand -hex 20)
echo "Generated Erlang Cookie: $ERLANG_COOKIE"

# Set cookie on all nodes (use the SAME cookie!)
echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
```

### 3.3: Deploy Configuration Files to ALL nodes
```bash
# Method 1: Automated deployment
./environment-manager.sh deploy your-env-name

# Method 2: Manual deployment per node
# On each node:
cd /opt/rabbitmq-deployment
source ./load-environment.sh your-env-name
./generate-configs.sh your-env-name --output-dir /etc/rabbitmq

# Set proper ownership
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*.conf /etc/rabbitmq/*.config /etc/rabbitmq/*.json
```

### 3.4: Configure Node-Specific Settings

#### Node 1 (Primary Node)
```bash
# Set hostname to match environment configuration
sudo hostnamectl set-hostname $RABBITMQ_NODE_1_HOSTNAME

# Enable and start RabbitMQ service
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 15

# Import user definitions (includes environment-specific users)
sudo rabbitmqctl import_definitions /etc/rabbitmq/definitions.json

# Delete default guest user for security
sudo rabbitmqctl delete_user guest

# Check status
sudo rabbitmqctl status
sudo rabbitmqctl cluster_status
```

#### Node 2 (Secondary)
```bash
# Set hostname to match environment configuration
sudo hostnamectl set-hostname $RABBITMQ_NODE_2_HOSTNAME

# Start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 15

# Join cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster $RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME
sudo rabbitmqctl start_app

# Verify cluster status
sudo rabbitmqctl cluster_status
```

#### Node 3 (Secondary)
```bash
# Set hostname to match environment configuration
sudo hostnamectl set-hostname $RABBITMQ_NODE_3_HOSTNAME

# Start RabbitMQ
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
sleep 15

# Join cluster
sudo rabbitmqctl stop_app
sudo rabbitmqctl reset
sudo rabbitmqctl join_cluster $RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME
sudo rabbitmqctl start_app

# Verify cluster status
sudo rabbitmqctl cluster_status
```

## 4. Cluster Validation

### 4.1: Environment-Aware Validation
```bash
# Load environment for validation
source ./load-environment.sh your-env-name

# Comprehensive cluster validation
echo "=== Cluster Validation for Environment: $ENVIRONMENT_NAME ==="
echo "Cluster Name: $RABBITMQ_CLUSTER_NAME"
echo "Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"
echo ""

# Check cluster status
sudo rabbitmqctl cluster_status

# Verify cluster name
ACTUAL_CLUSTER_NAME=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' | sed 's/<<"\(.*\)">>/\1/')
echo "Expected Cluster Name: $RABBITMQ_CLUSTER_NAME"
echo "Actual Cluster Name: $ACTUAL_CLUSTER_NAME"

if [ "$ACTUAL_CLUSTER_NAME" = "$RABBITMQ_CLUSTER_NAME" ]; then
    echo "✅ Cluster name matches environment configuration"
else
    echo "❌ Cluster name mismatch!"
fi
```

### 4.2: Environment-Specific Health Checks
```bash
# Check all environment nodes
for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
    echo "Checking node: $hostname"
    
    if [ "$hostname" = "$(hostname)" ]; then
        # Local node
        sudo rabbitmqctl node_health_check
    else
        # Remote node
        ssh "root@$hostname" "rabbitmqctl node_health_check"
    fi
done

# Check environment-specific users
echo "Checking environment users:"
sudo rabbitmqctl list_users | grep -E "($RABBITMQ_CUSTOM_USER_1|$RABBITMQ_CUSTOM_USER_2)"
```

### 4.3: Management Interface Access
```bash
# Display management interface URLs for environment
echo "Management Interface Access:"
echo "Node 1: http://$RABBITMQ_NODE_1_IP:$RABBITMQ_MANAGEMENT_PORT"
echo "Node 2: http://$RABBITMQ_NODE_2_IP:$RABBITMQ_MANAGEMENT_PORT"
echo "Node 3: http://$RABBITMQ_NODE_3_IP:$RABBITMQ_MANAGEMENT_PORT"

if [ -n "$RABBITMQ_VIP" ]; then
    echo "VIP: http://$RABBITMQ_VIP:$RABBITMQ_MANAGEMENT_PORT"
fi

echo ""
echo "Login credentials:"
echo "  User: $RABBITMQ_CUSTOM_USER_1"
echo "  User: $RABBITMQ_CUSTOM_USER_2"
echo "  Admin: $RABBITMQ_DEFAULT_USER"
```

## 5. Environment-Aware Queue Management

### 5.1: Environment-Aware Queue Creation Script
```bash
#!/bin/bash
# File: create-environment-queues.sh

# Load environment
source ./load-environment.sh ${1:-qa}

echo "Creating queues for environment: $ENVIRONMENT_NAME"
echo "Cluster: $RABBITMQ_CLUSTER_NAME"

# Create environment-specific queues
sudo rabbitmqctl declare queue --vhost=/ --name="$ENVIRONMENT_NAME-orders" --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name="$ENVIRONMENT_NAME-payments" --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name="$ENVIRONMENT_NAME-notifications" --type=quorum --durable=true
sudo rabbitmqctl declare queue --vhost=/ --name="$ENVIRONMENT_NAME-audit-logs" --type=quorum --durable=true

# Create exchanges with environment prefix
sudo rabbitmqctl declare exchange --vhost=/ --name="$ENVIRONMENT_NAME-exchange" --type=direct --durable=true

# List all queues
sudo rabbitmqctl list_queues name type durable

echo "✅ Environment-specific queues created successfully"
```

### 5.2: Environment Queue Validation Script
```bash
#!/bin/bash
# File: validate-environment-queues.sh

# Load environment
source ./load-environment.sh ${1:-qa}

echo "=== Queue Validation for Environment: $ENVIRONMENT_NAME ==="

# Check environment-specific queues
echo "Environment Queues:"
sudo rabbitmqctl list_queues name type | grep "^$ENVIRONMENT_NAME-"

echo -e "\nQuorum Queue Details:"
sudo rabbitmqctl list_queues name type online_members members | grep quorum

echo -e "\nCluster Queue Distribution:"
sudo rabbitmqctl eval 'rabbit_amqqueue:info_all([name, type, leader]).' | grep "$ENVIRONMENT_NAME"
```

## 6. Environment-Specific Monitoring

### 6.1: Environment Monitoring Script
```bash
#!/bin/bash
# File: monitor-environment.sh

# Load environment
ENV_NAME=${1:-qa}
source ./load-environment.sh $ENV_NAME

echo "=== RabbitMQ Environment Monitoring: $ENVIRONMENT_NAME ==="
echo "Timestamp: $(date)"
echo "Cluster: $RABBITMQ_CLUSTER_NAME"
echo "Environment Type: $ENVIRONMENT_TYPE"
echo ""

echo "=== Cluster Status ==="
sudo rabbitmqctl cluster_status

echo -e "\n=== Environment Queues ==="
sudo rabbitmqctl list_queues name messages consumers | grep "^$ENVIRONMENT_NAME-"

echo -e "\n=== Node Resource Usage ==="
for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
    echo "Node: $hostname"
    if [ "$hostname" = "$(hostname)" ]; then
        sudo rabbitmqctl status | grep -A 3 "Memory"
    else
        ssh "root@$hostname" "rabbitmqctl status | grep -A 3 'Memory'"
    fi
done

echo -e "\n=== Alarms ==="
sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().'

echo -e "\n=== Environment Health Summary ==="
RUNNING_NODES=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
TOTAL_NODES=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
echo "Running Nodes: $RUNNING_NODES/$TOTAL_NODES"

if [ $RUNNING_NODES -eq $TOTAL_NODES ]; then
    echo "✅ All nodes operational"
else
    echo "⚠️ Some nodes are down"
fi
```

## 7. Multi-Environment Deployment

### 7.1: Deploy Across Multiple Environments
```bash
#!/bin/bash
# File: deploy-all-environments.sh

ENVIRONMENTS=("qa" "staging" "prod")

for env in "${ENVIRONMENTS[@]}"; do
    echo "=== Deploying Environment: $env ==="
    
    # Validate environment configuration
    if ./load-environment.sh validate $env; then
        echo "✅ Environment $env validation passed"
        
        # Generate configurations
        ./generate-configs.sh $env
        
        # Deploy to environment
        ./environment-manager.sh deploy $env
        
        echo "✅ Environment $env deployed successfully"
    else
        echo "❌ Environment $env validation failed"
    fi
    
    echo ""
done
```

### 7.2: Environment Comparison
```bash
# Compare configurations between environments
./environment-manager.sh diff qa prod

# Show differences in generated configurations
diff -u <(./generate-configs.sh qa && cat rabbitmq.conf) \
        <(./generate-configs.sh prod && cat rabbitmq.conf)
```

## 8. Troubleshooting Environment Issues

### 8.1: Environment Configuration Issues
```bash
# Check environment syntax
./environment-manager.sh check-syntax your-env-name

# Validate environment variables
./load-environment.sh validate your-env-name

# Show current environment settings
./load-environment.sh show your-env-name
```

### 8.2: Cluster Name Issues
```bash
# Check actual vs expected cluster name
source ./load-environment.sh your-env-name
ACTUAL_NAME=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().')
echo "Expected: $RABBITMQ_CLUSTER_NAME"
echo "Actual: $ACTUAL_NAME"

# Fix cluster name if needed (requires cluster restart)
sudo rabbitmqctl set_cluster_name "$RABBITMQ_CLUSTER_NAME"
```

### 8.3: Environment Recovery
```bash
# Use environment-aware recovery procedures
source ./load-environment.sh your-env-name
./restore-cluster-now.sh

# Re-apply environment configuration if needed
./environment-manager.sh deploy your-env-name
```

## 9. Production Considerations

### 9.1: Environment-Specific SSL Setup
```bash
# Generate SSL certificates per environment
if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
    echo "Setting up SSL for environment: $ENVIRONMENT_NAME"
    
    # Create environment-specific SSL directory
    sudo mkdir -p "$RABBITMQ_SSL_CERT_DIR/$ENVIRONMENT_NAME"
    
    # Generate certificates (customize as needed)
    # ./generate-ssl-certs.sh $ENVIRONMENT_NAME
    
    echo "SSL setup completed for environment: $ENVIRONMENT_NAME"
fi
```

### 9.2: Environment Backup Strategy
```bash
# Environment-aware backup
./environment-manager.sh backup your-env-name

# Schedule environment-specific backups
echo "$RABBITMQ_BACKUP_SCHEDULE root /opt/rabbitmq-deployment/backup-environment.sh your-env-name" | sudo tee -a /etc/crontab
```

## 10. Quick Reference

### Environment Commands
```bash
# Load environment
source ./load-environment.sh <env-name>

# Show environment details
./load-environment.sh show <env-name>

# Validate environment
./load-environment.sh validate <env-name>

# Generate configurations
./generate-configs.sh <env-name>

# Deploy environment
./environment-manager.sh deploy <env-name>

# Create new environment
./environment-manager.sh create <env-name>

# Compare environments
./environment-manager.sh diff <env1> <env2>
```

### Make Scripts Executable
```bash
chmod +x create-environment-queues.sh
chmod +x validate-environment-queues.sh
chmod +x monitor-environment.sh
chmod +x deploy-all-environments.sh
```

This environment-based deployment approach provides:
- ✅ **Static cluster names** per environment
- ✅ **Centralized configuration management**
- ✅ **Easy environment switching**
- ✅ **Consistent deployment process**
- ✅ **Environment-specific validation**
- ✅ **Simplified multi-environment management**