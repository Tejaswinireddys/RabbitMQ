#!/bin/bash

# RabbitMQ 4.1.x Cluster Setup Script
# Run this script on each node with appropriate parameters

NODE_NAME=""
NODE_IP=""
CLUSTER_NODES="node1 node2 node3"
ERLANG_COOKIE="SWQOKODSQALRPCLNMEQG"

usage() {
    echo "Usage: $0 -n <node_name> -i <node_ip>"
    echo "  -n: Node name (node1, node2, or node3)"
    echo "  -i: Node IP address"
    exit 1
}

while getopts "n:i:" opt; do
    case $opt in
        n) NODE_NAME="$OPTARG" ;;
        i) NODE_IP="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$NODE_NAME" || -z "$NODE_IP" ]]; then
    usage
fi

echo "Setting up RabbitMQ cluster node: $NODE_NAME with IP: $NODE_IP"

# Stop RabbitMQ if running
sudo systemctl stop rabbitmq-server

# Set Erlang cookie (must be same on all nodes)
echo "$ERLANG_COOKIE" | sudo tee /var/lib/rabbitmq/.erlang.cookie
sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie

# Set hostname
sudo hostnamectl set-hostname $NODE_NAME

# Update /etc/hosts with all cluster nodes (update IPs as needed)
sudo tee -a /etc/hosts << EOF
# RabbitMQ Cluster Nodes
192.168.1.10    node1
192.168.1.11    node2  
192.168.1.12    node3
EOF

# Configure firewall
sudo firewall-cmd --permanent --add-port=5672/tcp  # AMQP
sudo firewall-cmd --permanent --add-port=15672/tcp # Management
sudo firewall-cmd --permanent --add-port=25672/tcp # Clustering
sudo firewall-cmd --permanent --add-port=4369/tcp  # EPMD
sudo firewall-cmd --permanent --add-port=35672-35682/tcp # Node communication
sudo firewall-cmd --reload

# Copy configuration files
sudo cp rabbitmq.conf /etc/rabbitmq/
sudo cp advanced.config /etc/rabbitmq/
sudo cp enabled_plugins /etc/rabbitmq/
sudo cp definitions.json /etc/rabbitmq/

# Set correct permissions
sudo chown rabbitmq:rabbitmq /etc/rabbitmq/*
sudo chmod 644 /etc/rabbitmq/rabbitmq.conf
sudo chmod 644 /etc/rabbitmq/advanced.config
sudo chmod 644 /etc/rabbitmq/enabled_plugins
sudo chmod 644 /etc/rabbitmq/definitions.json

# Start RabbitMQ
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server

# Wait for RabbitMQ to start
sleep 10

if [[ "$NODE_NAME" != "node1" ]]; then
    echo "Joining cluster..."
    # Stop app but keep Erlang VM running
    sudo rabbitmqctl stop_app
    
    # Reset node
    sudo rabbitmqctl reset
    
    # Join cluster
    sudo rabbitmqctl join_cluster rabbit@node1
    
    # Start app
    sudo rabbitmqctl start_app
else
    echo "This is the primary node (node1)"
    # Create admin user
    sudo rabbitmqctl add_user admin admin123
    sudo rabbitmqctl set_user_tags admin administrator
    sudo rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
fi

# Check cluster status
echo "Cluster status:"
sudo rabbitmqctl cluster_status

echo "Node $NODE_NAME setup completed!"
echo "Management interface: http://$NODE_IP:15672"
echo "Default credentials: admin/admin123"