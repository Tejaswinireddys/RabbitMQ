#!/bin/bash

# RabbitMQ 4.1.x Installation Script for RHEL 8
# Run this on all three nodes

set -e

echo "Installing RabbitMQ 4.1.x on RHEL 8..."

# Update system
sudo dnf update -y

# Install required packages
sudo dnf install -y curl wget gnupg2 socat logrotate

# Install Erlang 26.x (required for RabbitMQ 4.1.x)
sudo dnf install -y epel-release
sudo dnf install -y erlang

# Add RabbitMQ signing key
curl -1sLf 'https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA' | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null

# Add RabbitMQ repository
echo "deb [signed-by=/usr/share/keyrings/com.rabbitmq.team.gpg] https://packagecloud.io/rabbitmq/rabbitmq-server/el/8/\$basearch main" | sudo tee /etc/yum.repos.d/rabbitmq.repo

# Import repository signing key
sudo rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
sudo rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'

# Update package cache
sudo dnf update -y

# Install RabbitMQ 4.1.x
sudo dnf install -y rabbitmq-server

# Create directories
sudo mkdir -p /etc/rabbitmq
sudo mkdir -p /var/log/rabbitmq
sudo mkdir -p /var/lib/rabbitmq

# Set permissions
sudo chown -R rabbitmq:rabbitmq /var/log/rabbitmq
sudo chown -R rabbitmq:rabbitmq /var/lib/rabbitmq
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq

# Enable and start RabbitMQ service
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

# Enable management plugin
sudo rabbitmq-plugins enable rabbitmq_management
sudo rabbitmq-plugins enable rabbitmq_prometheus
sudo rabbitmq-plugins enable rabbitmq_federation
sudo rabbitmq-plugins enable rabbitmq_shovel

echo "RabbitMQ 4.1.x installation completed!"
echo "Please configure /etc/rabbitmq/rabbitmq.conf and /etc/rabbitmq/advanced.config"
echo "Then restart the service: sudo systemctl restart rabbitmq-server"