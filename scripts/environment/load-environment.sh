#!/bin/bash
# File: load-environment.sh
# Environment Configuration Loader for RabbitMQ Cluster

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/environments"

# Default environment
DEFAULT_ENVIRONMENT="qa"
ENVIRONMENT="${RABBITMQ_ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"

# Function to display usage
usage() {
    echo "RabbitMQ Environment Configuration Loader"
    echo ""
    echo "Usage: source $0 [environment]"
    echo "   or: $0 [command] [environment]"
    echo ""
    echo "Environments:"
    echo "  qa       - QA environment configuration"
    echo "  staging  - Staging environment configuration"  
    echo "  prod     - Production environment configuration"
    echo ""
    echo "Commands:"
    echo "  load     - Load environment variables (default)"
    echo "  show     - Show environment configuration"
    echo "  validate - Validate environment configuration"
    echo "  list     - List available environments"
    echo ""
    echo "Environment can also be set with RABBITMQ_ENVIRONMENT variable"
    echo ""
    echo "Examples:"
    echo "  source $0 prod              # Load production environment"
    echo "  $0 show staging             # Show staging configuration"
    echo "  RABBITMQ_ENVIRONMENT=qa source $0  # Load QA environment"
    exit 1
}

# Function to validate environment file exists
validate_environment() {
    local env=$1
    local base_file="$ENV_DIR/base.env"
    local env_file="$ENV_DIR/$env.env"
    
    if [ ! -f "$base_file" ]; then
        echo "Error: Base environment file not found: $base_file"
        return 1
    fi
    
    if [ ! -f "$env_file" ]; then
        echo "Error: Environment file not found: $env_file"
        echo "Available environments:"
        list_environments
        return 1
    fi
    
    return 0
}

# Function to list available environments
list_environments() {
    echo "Available environments:"
    for env_file in "$ENV_DIR"/*.env; do
        if [ -f "$env_file" ]; then
            local env_name=$(basename "$env_file" .env)
            if [ "$env_name" != "base" ]; then
                echo "  $env_name"
            fi
        fi
    done
}

# Function to load environment configuration
load_environment() {
    local env=$1
    
    echo "Loading RabbitMQ environment: $env"
    
    # Validate environment exists
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Load base configuration first
    echo "Loading base configuration..."
    source "$ENV_DIR/base.env"
    
    # Load environment-specific configuration
    echo "Loading $env environment configuration..."
    source "$ENV_DIR/$env.env"
    
    # Export RABBITMQ_ENVIRONMENT for child processes
    export RABBITMQ_ENVIRONMENT="$env"
    
    # Set derived variables
    export RABBITMQ_NODENAME="$RABBITMQ_NODE_NAME_PREFIX@$(hostname)"
    export RABBITMQ_NODE_NAME="$RABBITMQ_NODENAME"
    
    # Create cluster node list
    if [ -n "$RABBITMQ_NODE_1_HOSTNAME" ] && [ -n "$RABBITMQ_NODE_2_HOSTNAME" ] && [ -n "$RABBITMQ_NODE_3_HOSTNAME" ]; then
        export RABBITMQ_CLUSTER_NODES="$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME,$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_2_HOSTNAME,$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_3_HOSTNAME"
        export RABBITMQ_CLUSTER_HOSTNAMES="$RABBITMQ_NODE_1_HOSTNAME $RABBITMQ_NODE_2_HOSTNAME $RABBITMQ_NODE_3_HOSTNAME"
    fi
    
    echo "✓ Environment '$env' loaded successfully"
    echo "  Cluster Name: $RABBITMQ_CLUSTER_NAME"
    echo "  Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"
    echo "  Current Node: $RABBITMQ_NODENAME"
    
    return 0
}

# Function to show environment configuration
show_environment() {
    local env=$1
    
    echo "=== RabbitMQ Environment Configuration: $env ==="
    echo ""
    
    # Validate environment exists
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Load configurations to display
    source "$ENV_DIR/base.env"
    source "$ENV_DIR/$env.env"
    
    echo "Environment Information:"
    echo "  Name: $ENVIRONMENT_NAME"
    echo "  Type: $ENVIRONMENT_TYPE"
    echo ""
    
    echo "Cluster Configuration:"
    echo "  Cluster Name: $RABBITMQ_CLUSTER_NAME"
    echo "  Node Prefix: $RABBITMQ_NODE_NAME_PREFIX"
    echo "  Partition Handling: $RABBITMQ_CLUSTER_PARTITION_HANDLING"
    echo ""
    
    echo "Node Configuration:"
    if [ -n "$RABBITMQ_NODE_1_HOSTNAME" ]; then
        echo "  Node 1: $RABBITMQ_NODE_1_HOSTNAME ($RABBITMQ_NODE_1_IP)"
        echo "  Node 2: $RABBITMQ_NODE_2_HOSTNAME ($RABBITMQ_NODE_2_IP)"
        echo "  Node 3: $RABBITMQ_NODE_3_HOSTNAME ($RABBITMQ_NODE_3_IP)"
    else
        echo "  Hostnames not configured for this environment"
    fi
    echo ""
    
    echo "Network Configuration:"
    echo "  AMQP Port: $RABBITMQ_NODE_PORT"
    echo "  Distribution Port: $RABBITMQ_DIST_PORT"
    echo "  Management Port: $RABBITMQ_MANAGEMENT_PORT"
    echo "  VIP: ${RABBITMQ_VIP:-Not configured}"
    echo ""
    
    echo "Security Configuration:"
    echo "  SSL Enabled: $RABBITMQ_SSL_ENABLED"
    echo "  Default User: $RABBITMQ_DEFAULT_USER"
    echo "  Custom Users: $RABBITMQ_CUSTOM_USER_1, $RABBITMQ_CUSTOM_USER_2"
    echo ""
    
    echo "Performance Configuration:"
    echo "  Memory High Watermark: $RABBITMQ_VM_MEMORY_HIGH_WATERMARK"
    echo "  Disk Free Limit: $RABBITMQ_DISK_FREE_LIMIT"
    echo "  Heartbeat: $RABBITMQ_HEARTBEAT"
    echo ""
    
    echo "Monitoring Configuration:"
    echo "  Prometheus: $RABBITMQ_PROMETHEUS_ENABLED"
    echo "  Email Alerts: ${EMAIL_ALERTS:-Not configured}"
    echo "  Slack Webhook: ${SLACK_WEBHOOK:-Not configured}"
    echo ""
}

# Function to validate environment configuration
validate_environment_config() {
    local env=$1
    local errors=0
    
    echo "=== Validating Environment Configuration: $env ==="
    echo ""
    
    # Validate environment exists
    if ! validate_environment "$env"; then
        return 1
    fi
    
    # Load configurations for validation
    source "$ENV_DIR/base.env"
    source "$ENV_DIR/$env.env"
    
    # Required variables validation
    local required_vars=(
        "RABBITMQ_CLUSTER_NAME"
        "RABBITMQ_NODE_NAME_PREFIX"
        "RABBITMQ_CLUSTER_PARTITION_HANDLING"
        "RABBITMQ_DEFAULT_USER"
        "RABBITMQ_DEFAULT_PASS"
    )
    
    echo "Checking required variables..."
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "  ✗ $var is not set"
            errors=$((errors + 1))
        else
            echo "  ✓ $var is set"
        fi
    done
    
    # Environment-specific validation
    if [ "$env" != "base" ]; then
        echo ""
        echo "Checking environment-specific variables..."
        
        local env_vars=(
            "ENVIRONMENT_NAME"
            "ENVIRONMENT_TYPE"
            "RABBITMQ_NODE_1_HOSTNAME"
            "RABBITMQ_NODE_2_HOSTNAME"
            "RABBITMQ_NODE_3_HOSTNAME"
        )
        
        for var in "${env_vars[@]}"; do
            if [ -z "${!var}" ]; then
                echo "  ✗ $var is not set"
                errors=$((errors + 1))
            else
                echo "  ✓ $var is set"
            fi
        done
    fi
    
    # SSL validation if enabled
    if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
        echo ""
        echo "Checking SSL configuration..."
        
        local ssl_vars=(
            "RABBITMQ_SSL_CERT_DIR"
            "RABBITMQ_SSL_CACERT"
            "RABBITMQ_SSL_CERT"
            "RABBITMQ_SSL_KEY"
        )
        
        for var in "${ssl_vars[@]}"; do
            if [ -z "${!var}" ]; then
                echo "  ⚠ $var is not set (SSL enabled but certificate path missing)"
            else
                echo "  ✓ $var is set"
            fi
        done
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        echo "✅ Environment validation passed: $env"
        return 0
    else
        echo "❌ Environment validation failed: $errors errors found"
        return 1
    fi
}

# Function to export environment for scripts
export_environment() {
    local env=$1
    
    # Load environment
    if ! load_environment "$env"; then
        return 1
    fi
    
    # Create environment export file
    local export_file="/tmp/rabbitmq-env-$env.sh"
    
    cat > "$export_file" << EOF
#!/bin/bash
# Auto-generated RabbitMQ environment exports for: $env
# Generated on: $(date)

# Load environment variables
source "$ENV_DIR/base.env"
source "$ENV_DIR/$env.env"

# Export all RabbitMQ variables
export RABBITMQ_ENVIRONMENT="$env"
export RABBITMQ_NODENAME="$RABBITMQ_NODE_NAME_PREFIX@\$(hostname)"
export RABBITMQ_NODE_NAME="\$RABBITMQ_NODENAME"

# Export cluster configuration
if [ -n "\$RABBITMQ_NODE_1_HOSTNAME" ] && [ -n "\$RABBITMQ_NODE_2_HOSTNAME" ] && [ -n "\$RABBITMQ_NODE_3_HOSTNAME" ]; then
    export RABBITMQ_CLUSTER_NODES="\$RABBITMQ_NODE_NAME_PREFIX@\$RABBITMQ_NODE_1_HOSTNAME,\$RABBITMQ_NODE_NAME_PREFIX@\$RABBITMQ_NODE_2_HOSTNAME,\$RABBITMQ_NODE_NAME_PREFIX@\$RABBITMQ_NODE_3_HOSTNAME"
    export RABBITMQ_CLUSTER_HOSTNAMES="\$RABBITMQ_NODE_1_HOSTNAME \$RABBITMQ_NODE_2_HOSTNAME \$RABBITMQ_NODE_3_HOSTNAME"
fi

echo "RabbitMQ environment variables exported for: $env"
EOF
    
    chmod +x "$export_file"
    echo "Environment export file created: $export_file"
    echo "Usage: source $export_file"
}

# Main script logic
main() {
    local command="${1:-load}"
    local env="${2:-$ENVIRONMENT}"
    
    case "$command" in
        "load")
            load_environment "$env"
            ;;
        "show")
            show_environment "$env"
            ;;
        "validate")
            validate_environment_config "$env"
            ;;
        "list")
            list_environments
            ;;
        "export")
            export_environment "$env"
            ;;
        "help"|"-h"|"--help")
            usage
            ;;
        *)
            # If first argument is an environment name, treat as load
            if [ -f "$ENV_DIR/$command.env" ]; then
                load_environment "$command"
            else
                echo "Unknown command: $command"
                usage
            fi
            ;;
    esac
}

# Check if script is being sourced or executed
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed
    main "$@"
else
    # Script is being sourced
    if [ $# -gt 0 ]; then
        main "$@"
    else
        load_environment "$ENVIRONMENT"
    fi
fi