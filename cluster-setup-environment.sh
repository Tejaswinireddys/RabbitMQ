#!/bin/bash
# File: cluster-setup-environment.sh
# Environment-Aware RabbitMQ 4.1.x Cluster Setup Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT=""
NODE_ROLE=""
FORCE_SETUP="false"
SKIP_VALIDATION="false"

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

# Function to display usage
usage() {
    echo "Environment-Aware RabbitMQ Cluster Setup"
    echo ""
    echo "Usage: $0 -e <environment> -r <role> [options]"
    echo ""
    echo "Required Arguments:"
    echo "  -e <environment>   Environment name (qa, staging, prod, etc.)"
    echo "  -r <role>         Node role (primary, secondary, auto)"
    echo ""
    echo "Options:"
    echo "  -f                Force setup (skip confirmations)"
    echo "  -s                Skip pre-setup validation"
    echo "  -h                Show this help"
    echo ""
    echo "Node Roles:"
    echo "  primary          First node in cluster (creates cluster)"
    echo "  secondary        Additional nodes (join existing cluster)"
    echo "  auto             Auto-detect role based on hostname"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod -r primary    # Setup as primary node in production"
    echo "  $0 -e qa -r secondary    # Setup as secondary node in QA"
    echo "  $0 -e staging -r auto    # Auto-detect role in staging"
    exit 1
}

# Parse command line arguments
while getopts "e:r:fsh" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        r) NODE_ROLE="$OPTARG" ;;
        f) FORCE_SETUP="true" ;;
        s) SKIP_VALIDATION="true" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$ENVIRONMENT" ] || [ -z "$NODE_ROLE" ]; then
    print_status "error" "Environment and role are required"
    usage
fi

# Validate node role
if [[ ! "$NODE_ROLE" =~ ^(primary|secondary|auto)$ ]]; then
    print_status "error" "Invalid role: $NODE_ROLE. Must be: primary, secondary, or auto"
    exit 1
fi

print_status "info" "Starting environment-aware cluster setup"
print_status "info" "Environment: $ENVIRONMENT"
print_status "info" "Role: $NODE_ROLE"

# Load environment configuration
print_status "info" "Loading environment configuration..."
if ! source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"; then
    print_status "error" "Failed to load environment: $ENVIRONMENT"
    exit 1
fi

print_status "success" "Environment loaded: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
print_status "info" "Cluster Name: $RABBITMQ_CLUSTER_NAME"
print_status "info" "Cluster Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"

# Get current hostname
CURRENT_HOSTNAME=$(hostname)
print_status "info" "Current hostname: $CURRENT_HOSTNAME"

# Auto-detect role if requested
if [ "$NODE_ROLE" = "auto" ]; then
    if [ "$CURRENT_HOSTNAME" = "$RABBITMQ_NODE_1_HOSTNAME" ]; then
        NODE_ROLE="primary"
        print_status "info" "Auto-detected role: primary (first node)"
    else
        NODE_ROLE="secondary"
        print_status "info" "Auto-detected role: secondary"
    fi
fi

# Validate current hostname matches environment configuration
HOSTNAME_VALID="false"
for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
    if [ "$CURRENT_HOSTNAME" = "$hostname" ]; then
        HOSTNAME_VALID="true"
        break
    fi
done

if [ "$HOSTNAME_VALID" = "false" ]; then
    print_status "error" "Current hostname ($CURRENT_HOSTNAME) not found in environment configuration"
    print_status "info" "Expected hostnames: $RABBITMQ_CLUSTER_HOSTNAMES"
    
    if [ "$FORCE_SETUP" = "false" ]; then
        read -p "Do you want to update hostname to match environment? (y/n): " update_hostname
        if [ "$update_hostname" = "y" ]; then
            # Determine which hostname to use
            for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
                print_status "info" "Available hostname: $hostname"
            done
            read -p "Enter the hostname for this node: " target_hostname
            
            if [[ " $RABBITMQ_CLUSTER_HOSTNAMES " =~ " $target_hostname " ]]; then
                print_status "info" "Updating hostname to: $target_hostname"
                sudo hostnamectl set-hostname "$target_hostname"
                CURRENT_HOSTNAME="$target_hostname"
                print_status "success" "Hostname updated"
            else
                print_status "error" "Invalid hostname selected"
                exit 1
            fi
        else
            print_status "error" "Cannot proceed with mismatched hostname"
            exit 1
        fi
    fi
fi

# Pre-setup validation
if [ "$SKIP_VALIDATION" = "false" ]; then
    print_status "info" "Running pre-setup validation..."
    
    # Check if environment file is valid
    if ! "$SCRIPT_DIR/load-environment.sh" validate "$ENVIRONMENT"; then
        print_status "error" "Environment validation failed"
        exit 1
    fi
    
    # Check if RabbitMQ is installed
    if ! command -v rabbitmqctl >/dev/null 2>&1; then
        print_status "error" "RabbitMQ is not installed. Please install RabbitMQ first."
        exit 1
    fi
    
    # Check if required directories exist
    if [ ! -d "/var/lib/rabbitmq" ]; then
        print_status "warning" "RabbitMQ data directory not found. Creating..."
        sudo mkdir -p /var/lib/rabbitmq
        sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq
    fi
    
    print_status "success" "Pre-setup validation completed"
fi

# Generate environment-specific configurations
print_status "info" "Generating environment-specific configuration files..."
if ! "$SCRIPT_DIR/generate-configs.sh" "$ENVIRONMENT" --output-dir /tmp/rabbitmq-config; then
    print_status "error" "Failed to generate configuration files"
    exit 1
fi

# Show setup summary
print_status "info" "Setup Summary:"
echo "  Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
echo "  Cluster Name: $RABBITMQ_CLUSTER_NAME"
echo "  Node Role: $NODE_ROLE"
echo "  Current Node: $CURRENT_HOSTNAME"
echo "  Target Cluster: $RABBITMQ_CLUSTER_HOSTNAMES"
echo "  SSL Enabled: $RABBITMQ_SSL_ENABLED"

if [ "$FORCE_SETUP" = "false" ]; then
    echo ""
    read -p "Proceed with cluster setup? (y/n): " proceed
    if [ "$proceed" != "y" ]; then
        print_status "info" "Setup cancelled by user"
        exit 0
    fi
fi

# Stop RabbitMQ if running
print_status "info" "Stopping RabbitMQ service..."
sudo systemctl stop rabbitmq-server 2>/dev/null || true

# Generate and set Erlang cookie
print_status "info" "Setting up Erlang cookie..."
if [ ! -f "/var/lib/rabbitmq/.erlang.cookie" ] || [ "$FORCE_SETUP" = "true" ]; then
    # Generate a secure Erlang cookie for the environment
    ERLANG_COOKIE=$(echo "$RABBITMQ_CLUSTER_NAME-$(date +%s)" | sha256sum | cut -d' ' -f1 | head -c 20)
    echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie >/dev/null
    sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
    sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
    print_status "success" "Erlang cookie generated and set"
    print_status "warning" "IMPORTANT: Use the same cookie on all cluster nodes: $ERLANG_COOKIE"
else
    EXISTING_COOKIE=$(sudo cat /var/lib/rabbitmq/.erlang.cookie)
    print_status "info" "Using existing Erlang cookie: $EXISTING_COOKIE"
fi

# Update /etc/hosts with cluster nodes
print_status "info" "Updating /etc/hosts with cluster nodes..."
sudo cp /etc/hosts "/etc/hosts.backup.$(date +%Y%m%d-%H%M%S)"

# Remove existing RabbitMQ entries
sudo sed -i '/# RabbitMQ Cluster/,/# End RabbitMQ Cluster/d' /etc/hosts

# Add environment-specific entries
cat << EOF | sudo tee -a /etc/hosts
# RabbitMQ Cluster - $ENVIRONMENT Environment
$RABBITMQ_NODE_1_IP $RABBITMQ_NODE_1_HOSTNAME
$RABBITMQ_NODE_2_IP $RABBITMQ_NODE_2_HOSTNAME
$RABBITMQ_NODE_3_IP $RABBITMQ_NODE_3_HOSTNAME
# End RabbitMQ Cluster
EOF

print_status "success" "/etc/hosts updated with cluster nodes"

# Deploy configuration files
print_status "info" "Deploying configuration files..."
sudo cp /tmp/rabbitmq-config/rabbitmq.conf /etc/rabbitmq/
sudo cp /tmp/rabbitmq-config/advanced.config /etc/rabbitmq/
sudo cp /tmp/rabbitmq-config/definitions.json /etc/rabbitmq/

# Set proper ownership
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*.conf /etc/rabbitmq/*.config /etc/rabbitmq/*.json
sudo chmod 644 /etc/rabbitmq/*.conf /etc/rabbitmq/*.config /etc/rabbitmq/*.json

print_status "success" "Configuration files deployed"

# Enable required plugins
print_status "info" "Enabling RabbitMQ plugins..."
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_management_agent
sudo rabbitmq-plugins enable rabbitmq_prometheus

# Enable additional plugins based on environment type
if [ "$ENVIRONMENT_TYPE" = "production" ]; then
    sudo rabbitmq-plugins enable rabbitmq_federation
    sudo rabbitmq-plugins enable rabbitmq_shovel
    print_status "info" "Production plugins enabled"
fi

# Start RabbitMQ service
print_status "info" "Starting RabbitMQ service..."
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Wait for service to start
print_status "info" "Waiting for RabbitMQ to start..."
for i in {1..30}; do
    if sudo rabbitmqctl ping >/dev/null 2>&1; then
        print_status "success" "RabbitMQ started successfully"
        break
    fi
    
    if [ $i -eq 30 ]; then
        print_status "error" "RabbitMQ failed to start within timeout"
        print_status "info" "Check logs: sudo journalctl -u rabbitmq-server -f"
        exit 1
    fi
    
    sleep 2
done

# Role-specific setup
if [ "$NODE_ROLE" = "primary" ]; then
    print_status "info" "Setting up primary node..."
    
    # Import user definitions and policies
    print_status "info" "Importing user definitions..."
    sudo rabbitmqctl import_definitions /etc/rabbitmq/definitions.json
    
    # Set cluster name
    print_status "info" "Setting cluster name: $RABBITMQ_CLUSTER_NAME"
    sudo rabbitmqctl set_cluster_name "$RABBITMQ_CLUSTER_NAME"
    
    # Delete default guest user for security
    sudo rabbitmqctl delete_user guest 2>/dev/null || true
    
    print_status "success" "Primary node setup completed"
    
    # Show cluster status
    print_status "info" "Cluster status:"
    sudo rabbitmqctl cluster_status
    
    print_status "info" "Next steps:"
    echo "  1. Setup secondary nodes using: $0 -e $ENVIRONMENT -r secondary"
    echo "  2. Access management UI: http://$CURRENT_HOSTNAME:$RABBITMQ_MANAGEMENT_PORT"
    echo "  3. Login with: $RABBITMQ_CUSTOM_USER_1 or $RABBITMQ_CUSTOM_USER_2"

elif [ "$NODE_ROLE" = "secondary" ]; then
    print_status "info" "Setting up secondary node..."
    
    # Wait a bit for primary node to be ready
    sleep 5
    
    # Join cluster
    print_status "info" "Joining cluster..."
    sudo rabbitmqctl stop_app
    sudo rabbitmqctl reset
    
    # Try to join the primary node
    PRIMARY_NODE="$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME"
    if sudo rabbitmqctl join_cluster "$PRIMARY_NODE"; then
        print_status "success" "Successfully joined cluster"
    else
        print_status "error" "Failed to join cluster"
        print_status "info" "Ensure primary node is running and accessible"
        exit 1
    fi
    
    # Start application
    sudo rabbitmqctl start_app
    
    print_status "success" "Secondary node setup completed"
    
    # Show cluster status
    print_status "info" "Cluster status:"
    sudo rabbitmqctl cluster_status
fi

# Final validation
print_status "info" "Running final validation..."

# Check cluster status
if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    print_status "error" "Cluster status check failed"
    exit 1
fi

# Check node health
if ! sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
    print_status "error" "Node health check failed"
    exit 1
fi

# Verify cluster name
ACTUAL_CLUSTER_NAME=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' | sed 's/<<"\(.*\)">>/\1/')
if [ "$ACTUAL_CLUSTER_NAME" = "$RABBITMQ_CLUSTER_NAME" ]; then
    print_status "success" "Cluster name verified: $ACTUAL_CLUSTER_NAME"
else
    print_status "warning" "Cluster name mismatch. Expected: $RABBITMQ_CLUSTER_NAME, Actual: $ACTUAL_CLUSTER_NAME"
fi

print_status "success" "Environment-aware cluster setup completed successfully!"

# Show environment summary
echo ""
echo "=== Setup Summary ==="
echo "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
echo "Cluster Name: $RABBITMQ_CLUSTER_NAME"
echo "Node Role: $NODE_ROLE"
echo "Current Node: $CURRENT_HOSTNAME"
echo "Management UI: http://$CURRENT_HOSTNAME:$RABBITMQ_MANAGEMENT_PORT"
echo "Environment Config: $SCRIPT_DIR/environments/$ENVIRONMENT.env"

# Show next steps based on role
echo ""
echo "=== Next Steps ==="
if [ "$NODE_ROLE" = "primary" ]; then
    echo "1. Setup remaining cluster nodes:"
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" != "$CURRENT_HOSTNAME" ]; then
            echo "   ssh root@$hostname '$SCRIPT_DIR/cluster-setup-environment.sh -e $ENVIRONMENT -r secondary'"
        fi
    done
    echo "2. Verify cluster: sudo rabbitmqctl cluster_status"
    echo "3. Create queues: $SCRIPT_DIR/create-environment-queues.sh $ENVIRONMENT"
else
    echo "1. Verify cluster status: sudo rabbitmqctl cluster_status"
    echo "2. Check all nodes are running: sudo rabbitmqctl list_nodes"
fi

echo ""
print_status "success" "Environment-aware RabbitMQ cluster setup completed!"