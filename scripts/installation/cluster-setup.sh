#!/bin/bash

# RabbitMQ 4.1.x Cluster Setup Script
# Run this script on each node with appropriate parameters

set -e  # Exit on any error

NODE_NAME=""
NODE_IP=""
CLUSTER_NODES="node1 node2 node3"
ERLANG_COOKIE="SWQOKODSQALRPCLNMEQG"

# Load environment if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" qa
fi

usage() {
    echo "Usage: $0 -n <node_name> -i <node_ip> [-e <environment>]"
    echo "  -n: Node name (node1, node2, or node3)"
    echo "  -i: Node IP address"
    echo "  -e: Environment (qa, staging, prod) - defaults to qa"
    exit 1
}

while getopts "n:i:e:" opt; do
    case $opt in
        n) NODE_NAME="$OPTARG" ;;
        i) NODE_IP="$OPTARG" ;;
        e) ENVIRONMENT="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$NODE_NAME" || -z "$NODE_IP" ]]; then
    usage
fi

# Set default environment if not specified
ENVIRONMENT="${ENVIRONMENT:-qa}"

echo "Setting up RabbitMQ cluster node: $NODE_NAME with IP: $NODE_IP in $ENVIRONMENT environment"

# Load environment configuration
if [ -f "$SCRIPT_DIR/../environment/load-environment.sh" ]; then
    source "$SCRIPT_DIR/../environment/load-environment.sh" "$ENVIRONMENT"
fi

# Validate required environment variables
if [[ -z "$RABBITMQ_DEFAULT_USER" || -z "$RABBITMQ_DEFAULT_PASS" ]]; then
    echo "Error: Required environment variables not loaded. Please check environment configuration."
    exit 1
fi

# Stop RabbitMQ if running
echo "Stopping RabbitMQ service..."
sudo systemctl stop rabbitmq-server || true

# Set Erlang cookie (must be same on all nodes)
echo "Setting Erlang cookie..."
echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Set hostname
echo "Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"

# Update /etc/hosts with all cluster nodes
echo "Updating /etc/hosts..."
# Remove existing RabbitMQ entries
sudo sed -i '/# RabbitMQ Cluster Nodes/,+3d' /etc/hosts || true

# Add new entries
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster Nodes
${RABBITMQ_NODE_1_IP:-192.168.1.10}    ${RABBITMQ_NODE_1_HOSTNAME:-node1}
${RABBITMQ_NODE_2_IP:-192.168.1.11}    ${RABBITMQ_NODE_2_HOSTNAME:-node2}
${RABBITMQ_NODE_3_IP:-192.168.1.12}    ${RABBITMQ_NODE_3_HOSTNAME:-node3}
EOF

# Configure firewall
echo "Configuring firewall..."
sudo firewall-cmd --permanent --add-port=5672/tcp  # AMQP
sudo firewall-cmd --permanent --add-port=15672/tcp # Management
sudo firewall-cmd --permanent --add-port=25672/tcp # Clustering
sudo firewall-cmd --permanent --add-port=4369/tcp  # EPMD
sudo firewall-cmd --permanent --add-port=35672-35682/tcp # Node communication
sudo firewall-cmd --reload

# Create RabbitMQ config directory if it doesn't exist
sudo mkdir -p /etc/rabbitmq

# Copy configuration files from templates
echo "Copying configuration files..."
if [ -f "$SCRIPT_DIR/../../configs/templates/rabbitmq.conf" ]; then
    sudo cp "$SCRIPT_DIR/../../configs/templates/rabbitmq.conf" /etc/rabbitmq/
else
    echo "Warning: rabbitmq.conf template not found"
fi

if [ -f "$SCRIPT_DIR/../../configs/templates/advanced.config" ]; then
    sudo cp "$SCRIPT_DIR/../../configs/templates/advanced.config" /etc/rabbitmq/
else
    echo "Warning: advanced.config template not found"
fi

if [ -f "$SCRIPT_DIR/../../configs/templates/enabled_plugins" ]; then
    sudo cp "$SCRIPT_DIR/../../configs/templates/enabled_plugins" /etc/rabbitmq/
else
    echo "Warning: enabled_plugins template not found"
fi

if [ -f "$SCRIPT_DIR/../../configs/examples/definitions.json" ]; then
    sudo cp "$SCRIPT_DIR/../../configs/examples/definitions.json" /etc/rabbitmq/
else
    echo "Warning: definitions.json not found"
fi

# Set correct permissions
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*
sudo chmod 644 /etc/rabbitmq/rabbitmq.conf 2>/dev/null || true
sudo chmod 644 /etc/rabbitmq/advanced.config 2>/dev/null || true
sudo chmod 644 /etc/rabbitmq/enabled_plugins 2>/dev/null || true
sudo chmod 644 /etc/rabbitmq/definitions.json 2>/dev/null || true

# Start RabbitMQ
echo "Starting RabbitMQ service..."
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server

# Wait for RabbitMQ to start
echo "Waiting for RabbitMQ to start..."
sleep 15

# Check if RabbitMQ is running
if ! sudo systemctl is-active --quiet rabbitmq-server; then
    echo "Error: RabbitMQ failed to start"
    sudo systemctl status rabbitmq-server
    exit 1
fi

if [[ "$NODE_NAME" != "node1" ]]; then
    echo "Joining cluster..."
    # Stop app but keep Erlang VM running
    sudo rabbitmqctl stop_app
    
    # Reset node
    sudo rabbitmqctl reset
    
    # Join cluster
    sudo rabbitmqctl join_cluster "rabbit@${RABBITMQ_NODE_1_HOSTNAME:-node1}"
    
    # Start app
    sudo rabbitmqctl start_app
else
    echo "This is the primary node (node1)"
    # Create admin user using environment variables
    sudo rabbitmqctl add_user "$RABBITMQ_DEFAULT_USER" "$RABBITMQ_DEFAULT_PASS"
    sudo rabbitmqctl set_user_tags "$RABBITMQ_DEFAULT_USER" administrator
    sudo rabbitmqctl set_permissions -p / "$RABBITMQ_DEFAULT_USER" ".*" ".*" ".*"
    
    # Create custom users if defined in environment
    if [[ -n "$RABBITMQ_CUSTOM_USER_1" && -n "$RABBITMQ_CUSTOM_USER_1_PASS" ]]; then
        sudo rabbitmqctl add_user "$RABBITMQ_CUSTOM_USER_1" "$RABBITMQ_CUSTOM_USER_1_PASS"
        sudo rabbitmqctl set_user_tags "$RABBITMQ_CUSTOM_USER_1" management
        sudo rabbitmqctl set_permissions -p / "$RABBITMQ_CUSTOM_USER_1" ".*" ".*" ".*"
        echo "Created user: $RABBITMQ_CUSTOM_USER_1"
    fi
    
    if [[ -n "$RABBITMQ_CUSTOM_USER_2" && -n "$RABBITMQ_CUSTOM_USER_2_PASS" ]]; then
        sudo rabbitmqctl add_user "$RABBITMQ_CUSTOM_USER_2" "$RABBITMQ_CUSTOM_USER_2_PASS"
        sudo rabbitmqctl set_user_tags "$RABBITMQ_CUSTOM_USER_2" management
        sudo rabbitmqctl set_permissions -p / "$RABBITMQ_CUSTOM_USER_2" ".*" ".*" ".*"
        echo "Created user: $RABBITMQ_CUSTOM_USER_2"
    fi
    
    echo "Created users: $RABBITMQ_DEFAULT_USER"
fi

# Check cluster status
echo "Cluster status:"
sudo rabbitmqctl cluster_status

echo "Node $NODE_NAME setup completed!"
echo "Management interface: http://$NODE_IP:15672"
echo "Available credentials:"
echo "  - $RABBITMQ_DEFAULT_USER/[password from environment] (Administrator)"
if [[ -n "$RABBITMQ_CUSTOM_USER_1" ]]; then
    echo "  - $RABBITMQ_CUSTOM_USER_1/[password from environment] (Management User)"
fi
if [[ -n "$RABBITMQ_CUSTOM_USER_2" ]]; then
    echo "  - $RABBITMQ_CUSTOM_USER_2/[password from environment] (Management User)"
fi