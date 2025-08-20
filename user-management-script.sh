#!/bin/bash

# RabbitMQ User Management Script
# Creates custom users Teja and Aswini with secure passwords

set -e

echo "=== RabbitMQ User Management Script ==="

# Function to create RabbitMQ user
create_rabbitmq_user() {
    local username=$1
    local password=$2
    local tags=$3
    
    echo "Creating user: $username"
    
    # Check if user already exists
    if sudo rabbitmqctl list_users | grep -q "^$username"; then
        echo "User $username already exists. Updating password..."
        sudo rabbitmqctl change_password $username $password
    else
        echo "Creating new user: $username"
        sudo rabbitmqctl add_user $username $password
    fi
    
    # Set user tags
    sudo rabbitmqctl set_user_tags $username $tags
    
    # Set permissions for default vhost
    sudo rabbitmqctl set_permissions -p / $username ".*" ".*" ".*"
    
    echo "User $username created/updated successfully with $tags permissions"
}

# Function to list all users
list_users() {
    echo "Current RabbitMQ users:"
    sudo rabbitmqctl list_users
}

# Function to create custom vhost for users (optional)
create_custom_vhost() {
    local vhost_name=$1
    
    echo "Creating custom vhost: $vhost_name"
    sudo rabbitmqctl add_vhost $vhost_name
    
    # Set permissions for custom users on new vhost
    sudo rabbitmqctl set_permissions -p $vhost_name teja ".*" ".*" ".*"
    sudo rabbitmqctl set_permissions -p $vhost_name aswini ".*" ".*" ".*"
    
    echo "Custom vhost $vhost_name created with permissions for teja and aswini"
}

# Main execution
echo "Creating custom RabbitMQ users..."

# Create user Teja with management permissions
create_rabbitmq_user "teja" "Teja@2024" "management"

# Create user Aswini with management permissions
create_rabbitmq_user "aswini" "Aswini@2024" "management"

# Ensure admin user exists
create_rabbitmq_user "admin" "admin123" "administrator"

# Remove default guest user for security
echo "Removing default guest user for security..."
sudo rabbitmqctl delete_user guest 2>/dev/null || echo "Guest user already removed or doesn't exist"

# List all users
echo ""
list_users

# Optional: Create custom vhost
read -p "Do you want to create a custom vhost? (y/n): " CREATE_VHOST
if [[ "$CREATE_VHOST" == "y" ]]; then
    read -p "Enter vhost name: " VHOST_NAME
    create_custom_vhost $VHOST_NAME
fi

echo ""
echo "=== User Management Completed ==="
echo "Created users:"
echo "- admin (administrator) - Password: admin123"
echo "- teja (management) - Password: Teja@2024"
echo "- aswini (management) - Password: Aswini@2024"
echo ""
echo "Management interface available at: http://$(hostname):15672"
echo "Users can login with their respective credentials"

# Display user permissions
echo ""
echo "User permissions:"
sudo rabbitmqctl list_permissions