#!/bin/bash
# File: environment-manager.sh
# Comprehensive Environment Management Tool for RabbitMQ

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/environments"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✓${NC} $message" ;;
        "error") echo -e "${RED}✗${NC} $message" ;;
        "warning") echo -e "${YELLOW}⚠${NC} $message" ;;
        "info") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

# Function to show usage
usage() {
    echo "RabbitMQ Environment Manager"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create <env_name>           - Create new environment configuration"
    echo "  clone <source> <target>     - Clone environment configuration"
    echo "  diff <env1> <env2>          - Compare two environments"
    echo "  deploy <environment>        - Deploy configuration to environment"
    echo "  backup <environment>        - Backup environment configuration"
    echo "  restore <backup_file>       - Restore environment from backup"
    echo "  template                    - Generate environment template"
    echo "  check-syntax <env>          - Check environment file syntax"
    echo "  update-hosts <env>          - Update /etc/hosts with environment hostnames"
    echo "  generate-inventory <env>    - Generate Ansible inventory"
    echo ""
    echo "Examples:"
    echo "  $0 create dev               # Create development environment"
    echo "  $0 clone qa staging         # Clone QA config to staging"
    echo "  $0 diff qa prod             # Compare QA and production"
    echo "  $0 deploy prod              # Deploy to production"
    exit 1
}

# Function to create new environment
create_environment() {
    local env_name=$1
    local env_file="$ENV_DIR/$env_name.env"
    
    if [ -z "$env_name" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    if [ -f "$env_file" ]; then
        print_status "warning" "Environment '$env_name' already exists"
        read -p "Overwrite? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            return 1
        fi
    fi
    
    print_status "info" "Creating environment: $env_name"
    
    # Get user input for basic configuration
    echo "Enter configuration for environment: $env_name"
    read -p "Environment type (development/testing/staging/production): " env_type
    read -p "Node 1 hostname: " node1_hostname
    read -p "Node 2 hostname: " node2_hostname  
    read -p "Node 3 hostname: " node3_hostname
    read -p "Node 1 IP: " node1_ip
    read -p "Node 2 IP: " node2_ip
    read -p "Node 3 IP: " node3_ip
    read -p "VIP address: " vip_address
    
    # Generate environment file
    cat > "$env_file" << EOF
# RabbitMQ $env_name Environment Configuration
# Created on: $(date)

# === Environment Info ===
ENVIRONMENT_NAME="$env_name"
ENVIRONMENT_TYPE="$env_type"

# === Cluster Name (Environment Specific) ===
RABBITMQ_CLUSTER_NAME="rabbitmq-$env_name-cluster"

# === Node Configuration ===
RABBITMQ_NODE_1_HOSTNAME="$node1_hostname"
RABBITMQ_NODE_2_HOSTNAME="$node2_hostname"
RABBITMQ_NODE_3_HOSTNAME="$node3_hostname"

# === IP Addresses ===
RABBITMQ_NODE_1_IP="$node1_ip"
RABBITMQ_NODE_2_IP="$node2_ip"
RABBITMQ_NODE_3_IP="$node3_ip"

# === Load Balancer Configuration ===
RABBITMQ_VIP="$vip_address"

# === SSL Certificate Paths ===
RABBITMQ_SSL_CACERT="\$RABBITMQ_SSL_CERT_DIR/$env_name/ca_certificate.pem"
RABBITMQ_SSL_CERT="\$RABBITMQ_SSL_CERT_DIR/$env_name/server_certificate.pem"
RABBITMQ_SSL_KEY="\$RABBITMQ_SSL_CERT_DIR/$env_name/server_key.pem"

# === Environment-specific Performance Settings ===
RABBITMQ_VM_MEMORY_HIGH_WATERMARK="0.6"
RABBITMQ_DISK_FREE_LIMIT="2GB"

# === Monitoring ===
EMAIL_ALERTS="admin@company.com"
SLACK_WEBHOOK=""

# === Backup Configuration ===
RABBITMQ_BACKUP_RETENTION_DAYS="7"
RABBITMQ_BACKUP_SCHEDULE="0 2 * * *"
EOF
    
    print_status "success" "Environment '$env_name' created at: $env_file"
    print_status "info" "Edit the file to customize additional settings"
}

# Function to clone environment
clone_environment() {
    local source_env=$1
    local target_env=$2
    local source_file="$ENV_DIR/$source_env.env"
    local target_file="$ENV_DIR/$target_env.env"
    
    if [ -z "$source_env" ] || [ -z "$target_env" ]; then
        print_status "error" "Source and target environment names are required"
        return 1
    fi
    
    if [ ! -f "$source_file" ]; then
        print_status "error" "Source environment '$source_env' does not exist"
        return 1
    fi
    
    if [ -f "$target_file" ]; then
        print_status "warning" "Target environment '$target_env' already exists"
        read -p "Overwrite? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            return 1
        fi
    fi
    
    print_status "info" "Cloning environment: $source_env -> $target_env"
    
    # Copy and modify the environment file
    cp "$source_file" "$target_file"
    
    # Update environment-specific variables
    sed -i "s/ENVIRONMENT_NAME=\"$source_env\"/ENVIRONMENT_NAME=\"$target_env\"/g" "$target_file"
    sed -i "s/rabbitmq-$source_env-cluster/rabbitmq-$target_env-cluster/g" "$target_file"
    sed -i "s/$source_env/$target_env/g" "$target_file"
    
    print_status "success" "Environment cloned successfully"
    print_status "info" "Review and update hostnames/IPs in: $target_file"
}

# Function to compare environments
diff_environments() {
    local env1=$1
    local env2=$2
    local file1="$ENV_DIR/$env1.env"
    local file2="$ENV_DIR/$env2.env"
    
    if [ -z "$env1" ] || [ -z "$env2" ]; then
        print_status "error" "Two environment names are required"
        return 1
    fi
    
    if [ ! -f "$file1" ]; then
        print_status "error" "Environment '$env1' does not exist"
        return 1
    fi
    
    if [ ! -f "$file2" ]; then
        print_status "error" "Environment '$env2' does not exist"
        return 1
    fi
    
    print_status "info" "Comparing environments: $env1 vs $env2"
    echo ""
    
    # Use diff to show differences
    if diff -u "$file1" "$file2"; then
        print_status "success" "Environments are identical"
    else
        print_status "info" "Differences found between environments"
    fi
}

# Function to deploy environment
deploy_environment() {
    local env=$1
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    print_status "info" "Deploying environment: $env"
    
    # Load environment
    if ! source "$SCRIPT_DIR/load-environment.sh" "$env"; then
        print_status "error" "Failed to load environment"
        return 1
    fi
    
    # Deploy configuration files
    print_status "info" "Generating configuration files for $env"
    
    # Generate rabbitmq.conf
    "$SCRIPT_DIR/generate-configs.sh" "$env"
    
    # Copy to nodes
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        print_status "info" "Deploying to $hostname"
        
        if [ "$hostname" != "$(hostname)" ]; then
            # Copy configuration files
            scp "$SCRIPT_DIR/rabbitmq.conf" "root@$hostname:/etc/rabbitmq/"
            scp "$SCRIPT_DIR/advanced.config" "root@$hostname:/etc/rabbitmq/"
            scp "$SCRIPT_DIR/definitions.json" "root@$hostname:/etc/rabbitmq/"
            
            # Set permissions
            ssh "root@$hostname" "chown rabbitmq:rabbitmq /etc/rabbitmq/*.conf /etc/rabbitmq/*.config /etc/rabbitmq/*.json"
        else
            # Local node
            sudo cp "$SCRIPT_DIR/rabbitmq.conf" "/etc/rabbitmq/"
            sudo cp "$SCRIPT_DIR/advanced.config" "/etc/rabbitmq/"
            sudo cp "$SCRIPT_DIR/definitions.json" "/etc/rabbitmq/"
            sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*.conf /etc/rabbitmq/*.config /etc/rabbitmq/*.json
        fi
    done
    
    print_status "success" "Environment deployed successfully"
}

# Function to backup environment
backup_environment() {
    local env=$1
    local backup_dir="$SCRIPT_DIR/backups/$(date +%Y%m%d-%H%M%S)-$env"
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    print_status "info" "Creating backup for environment: $env"
    
    mkdir -p "$backup_dir"
    
    # Backup environment file
    cp "$ENV_DIR/$env.env" "$backup_dir/"
    
    # Backup base environment
    cp "$ENV_DIR/base.env" "$backup_dir/"
    
    # Create backup metadata
    cat > "$backup_dir/backup-info.txt" << EOF
Backup Information
==================
Environment: $env
Created: $(date)
Backup Directory: $backup_dir
Source Environment File: $ENV_DIR/$env.env
EOF
    
    print_status "success" "Backup created: $backup_dir"
}

# Function to generate template
generate_template() {
    local template_file="$SCRIPT_DIR/environment-template.env"
    
    print_status "info" "Generating environment template"
    
    cat > "$template_file" << 'EOF'
# RabbitMQ Environment Configuration Template
# Copy this file to environments/your-env.env and customize

# === Environment Info ===
ENVIRONMENT_NAME="your-environment-name"
ENVIRONMENT_TYPE="development|testing|staging|production"

# === Cluster Name (Environment Specific) ===
RABBITMQ_CLUSTER_NAME="rabbitmq-your-env-cluster"

# === Node Configuration ===
RABBITMQ_NODE_1_HOSTNAME="node1.your-domain.com"
RABBITMQ_NODE_2_HOSTNAME="node2.your-domain.com"
RABBITMQ_NODE_3_HOSTNAME="node3.your-domain.com"

# === IP Addresses ===
RABBITMQ_NODE_1_IP="10.0.0.10"
RABBITMQ_NODE_2_IP="10.0.0.11"
RABBITMQ_NODE_3_IP="10.0.0.12"

# === Load Balancer Configuration ===
RABBITMQ_VIP="10.0.0.100"
HAPROXY_HOST="10.0.0.101"

# === SSL Certificate Paths ===
RABBITMQ_SSL_CACERT="$RABBITMQ_SSL_CERT_DIR/your-env/ca_certificate.pem"
RABBITMQ_SSL_CERT="$RABBITMQ_SSL_CERT_DIR/your-env/server_certificate.pem"
RABBITMQ_SSL_KEY="$RABBITMQ_SSL_CERT_DIR/your-env/server_key.pem"

# === Environment-specific Performance Settings ===
RABBITMQ_VM_MEMORY_HIGH_WATERMARK="0.6"
RABBITMQ_DISK_FREE_LIMIT="2GB"

# === Monitoring ===
EMAIL_ALERTS="admin@your-company.com"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# === Backup Configuration ===
RABBITMQ_BACKUP_RETENTION_DAYS="7"
RABBITMQ_BACKUP_SCHEDULE="0 2 * * *"
EOF
    
    print_status "success" "Template generated: $template_file"
}

# Function to check syntax
check_syntax() {
    local env=$1
    local env_file="$ENV_DIR/$env.env"
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    if [ ! -f "$env_file" ]; then
        print_status "error" "Environment file does not exist: $env_file"
        return 1
    fi
    
    print_status "info" "Checking syntax for environment: $env"
    
    # Check if file can be sourced without errors
    if bash -n "$env_file"; then
        print_status "success" "Syntax check passed"
    else
        print_status "error" "Syntax errors found"
        return 1
    fi
}

# Function to update /etc/hosts
update_hosts() {
    local env=$1
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    # Load environment
    source "$SCRIPT_DIR/load-environment.sh" "$env"
    
    print_status "info" "Updating /etc/hosts for environment: $env"
    
    # Backup current hosts file
    sudo cp /etc/hosts "/etc/hosts.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Remove existing RabbitMQ entries
    sudo sed -i '/# RabbitMQ Cluster/,/# End RabbitMQ Cluster/d' /etc/hosts
    
    # Add new entries
    cat << EOF | sudo tee -a /etc/hosts
# RabbitMQ Cluster - $env Environment
$RABBITMQ_NODE_1_IP $RABBITMQ_NODE_1_HOSTNAME
$RABBITMQ_NODE_2_IP $RABBITMQ_NODE_2_HOSTNAME
$RABBITMQ_NODE_3_IP $RABBITMQ_NODE_3_HOSTNAME
# End RabbitMQ Cluster
EOF
    
    print_status "success" "Hosts file updated for environment: $env"
}

# Function to generate Ansible inventory
generate_inventory() {
    local env=$1
    local inventory_file="$SCRIPT_DIR/inventory-$env.ini"
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name is required"
        return 1
    fi
    
    # Load environment
    source "$SCRIPT_DIR/load-environment.sh" "$env"
    
    print_status "info" "Generating Ansible inventory for environment: $env"
    
    cat > "$inventory_file" << EOF
# Ansible Inventory for RabbitMQ $env Environment
# Generated on: $(date)

[rabbitmq_cluster]
$RABBITMQ_NODE_1_HOSTNAME ansible_host=$RABBITMQ_NODE_1_IP
$RABBITMQ_NODE_2_HOSTNAME ansible_host=$RABBITMQ_NODE_2_IP
$RABBITMQ_NODE_3_HOSTNAME ansible_host=$RABBITMQ_NODE_3_IP

[rabbitmq_cluster:vars]
ansible_user=root
ansible_ssh_private_key_file=~/.ssh/id_rsa
rabbitmq_cluster_name=$RABBITMQ_CLUSTER_NAME
rabbitmq_environment=$env
EOF
    
    print_status "success" "Ansible inventory generated: $inventory_file"
}

# Main function
main() {
    local command=$1
    shift
    
    case "$command" in
        "create")
            create_environment "$@"
            ;;
        "clone")
            clone_environment "$@"
            ;;
        "diff")
            diff_environments "$@"
            ;;
        "deploy")
            deploy_environment "$@"
            ;;
        "backup")
            backup_environment "$@"
            ;;
        "template")
            generate_template
            ;;
        "check-syntax")
            check_syntax "$@"
            ;;
        "update-hosts")
            update_hosts "$@"
            ;;
        "generate-inventory")
            generate_inventory "$@"
            ;;
        "help"|"-h"|"--help"|"")
            usage
            ;;
        *)
            print_status "error" "Unknown command: $command"
            usage
            ;;
    esac
}

main "$@"