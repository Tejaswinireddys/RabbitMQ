#!/bin/bash

# RabbitMQ Non-Root User Management Script
# Provides comprehensive user management for non-root users
# Version: 1.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as non-root user
check_user() {
    if [[ $EUID -eq 0 ]]; then
        error "This script must be run as a non-root user"
        exit 1
    fi
}

# List all users
list_users() {
    log "RabbitMQ Users:"
    sudo rabbitmqctl list_users
}

# Add user
add_user() {
    local username="$1"
    local password="$2"
    local tags="$3"
    
    if [[ -z "$username" || -z "$password" ]]; then
        error "Username and password are required"
        exit 1
    fi
    
    # Set default tags if not provided
    tags="${tags:-management}"
    
    log "Adding user: $username"
    
    # Add user
    sudo rabbitmqctl add_user "$username" "$password"
    
    # Set user tags
    sudo rabbitmqctl set_user_tags "$username" "$tags"
    
    # Set permissions for default vhost
    sudo rabbitmqctl set_permissions -p / "$username" ".*" ".*" ".*"
    
    log "User $username added successfully with tags: $tags"
}

# Delete user
delete_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        error "Username is required"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "Deleting user: $username"
    sudo rabbitmqctl delete_user "$username"
    log "User $username deleted successfully"
}

# Change user password
change_password() {
    local username="$1"
    local new_password="$2"
    
    if [[ -z "$username" || -z "$new_password" ]]; then
        error "Username and new password are required"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "Changing password for user: $username"
    sudo rabbitmqctl change_password "$username" "$new_password"
    log "Password changed successfully for user $username"
}

# Set user tags
set_user_tags() {
    local username="$1"
    local tags="$2"
    
    if [[ -z "$username" || -z "$tags" ]]; then
        error "Username and tags are required"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "Setting tags for user: $username"
    sudo rabbitmqctl set_user_tags "$username" "$tags"
    log "Tags set successfully for user $username: $tags"
}

# Set user permissions
set_permissions() {
    local username="$1"
    local vhost="$2"
    local configure="$3"
    local write="$4"
    local read="$5"
    
    if [[ -z "$username" || -z "$vhost" || -z "$configure" || -z "$write" || -z "$read" ]]; then
        error "All parameters are required: username, vhost, configure, write, read"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "Setting permissions for user: $username"
    sudo rabbitmqctl set_permissions -p "$vhost" "$username" "$configure" "$write" "$read"
    log "Permissions set successfully for user $username"
}

# List user permissions
list_permissions() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        error "Username is required"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "Permissions for user: $username"
    sudo rabbitmqctl list_user_permissions "$username"
}

# List all permissions
list_all_permissions() {
    log "All User Permissions:"
    sudo rabbitmqctl list_permissions
}

# Create vhost
create_vhost() {
    local vhost="$1"
    
    if [[ -z "$vhost" ]]; then
        error "VHost name is required"
        exit 1
    fi
    
    log "Creating vhost: $vhost"
    sudo rabbitmqctl add_vhost "$vhost"
    log "VHost $vhost created successfully"
}

# Delete vhost
delete_vhost() {
    local vhost="$1"
    
    if [[ -z "$vhost" ]]; then
        error "VHost name is required"
        exit 1
    fi
    
    log "Deleting vhost: $vhost"
    sudo rabbitmqctl delete_vhost "$vhost"
    log "VHost $vhost deleted successfully"
}

# List vhosts
list_vhosts() {
    log "RabbitMQ VHosts:"
    sudo rabbitmqctl list_vhosts
}

# Set vhost permissions for user
set_vhost_permissions() {
    local username="$1"
    local vhost="$2"
    local configure="$3"
    local write="$4"
    local read="$5"
    
    if [[ -z "$username" || -z "$vhost" || -z "$configure" || -z "$write" || -z "$read" ]]; then
        error "All parameters are required: username, vhost, configure, write, read"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    # Check if vhost exists
    if ! sudo rabbitmqctl list_vhosts | grep -q "^$vhost"; then
        error "VHost $vhost does not exist"
        exit 1
    fi
    
    log "Setting vhost permissions for user: $username on vhost: $vhost"
    sudo rabbitmqctl set_permissions -p "$vhost" "$username" "$configure" "$write" "$read"
    log "VHost permissions set successfully for user $username on vhost $vhost"
}

# Create default users
create_default_users() {
    log "Creating default RabbitMQ users..."
    
    # Create admin user
    add_user "admin" "admin123" "administrator"
    
    # Create management users
    add_user "teja" "Teja@2024" "management"
    add_user "aswini" "Aswini@2024" "management"
    
    # Delete guest user
    if sudo rabbitmqctl list_users | grep -q "^guest"; then
        log "Deleting default guest user..."
        sudo rabbitmqctl delete_user guest
    fi
    
    log "Default users created successfully"
}

# Export user definitions
export_definitions() {
    local output_file="$1"
    
    if [[ -z "$output_file" ]]; then
        output_file="rabbitmq-definitions-$(date +%Y%m%d_%H%M%S).json"
    fi
    
    log "Exporting user definitions to: $output_file"
    sudo rabbitmqctl export_definitions "$output_file"
    log "Definitions exported successfully to $output_file"
}

# Import user definitions
import_definitions() {
    local input_file="$1"
    
    if [[ -z "$input_file" ]]; then
        error "Input file is required"
        exit 1
    fi
    
    if [[ ! -f "$input_file" ]]; then
        error "Input file not found: $input_file"
        exit 1
    fi
    
    log "Importing user definitions from: $input_file"
    sudo rabbitmqctl import_definitions "$input_file"
    log "Definitions imported successfully from $input_file"
}

# Show user information
show_user_info() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        error "Username is required"
        exit 1
    fi
    
    # Check if user exists
    if ! sudo rabbitmqctl list_users | grep -q "^$username"; then
        error "User $username does not exist"
        exit 1
    fi
    
    log "User Information for: $username"
    echo ""
    echo "User Details:"
    sudo rabbitmqctl list_users | grep "^$username"
    echo ""
    echo "User Permissions:"
    sudo rabbitmqctl list_user_permissions "$username"
    echo ""
    echo "User Tags:"
    sudo rabbitmqctl list_users | grep "^$username" | awk '{print $2}'
}

# Show usage information
show_usage() {
    cat << EOF
RabbitMQ Non-Root User Management Script

Usage: $0 <command> [options]

Commands:
    list-users                     List all users
    add-user <user> <pass> [tags]  Add new user
    delete-user <user>             Delete user
    change-password <user> <pass>  Change user password
    set-tags <user> <tags>         Set user tags
    set-permissions <user> <vhost> <configure> <write> <read>  Set user permissions
    list-permissions <user>        List user permissions
    list-all-permissions           List all permissions
    create-vhost <vhost>           Create vhost
    delete-vhost <vhost>           Delete vhost
    list-vhosts                    List all vhosts
    set-vhost-permissions <user> <vhost> <configure> <write> <read>  Set vhost permissions
    create-default-users           Create default users (admin, teja, aswini)
    export-definitions [file]      Export user definitions
    import-definitions <file>      Import user definitions
    show-user-info <user>          Show detailed user information
    help                           Show this help message

Examples:
    $0 list-users
    $0 add-user myuser mypass administrator
    $0 delete-user myuser
    $0 change-password myuser newpass
    $0 set-tags myuser management
    $0 set-permissions myuser / ".*" ".*" ".*"
    $0 create-vhost /myapp
    $0 create-default-users
    $0 export-definitions my-backup.json
    $0 show-user-info admin

EOF
}

# Main function
main() {
    check_user
    
    case "${1:-help}" in
        list-users)
            list_users
            ;;
        add-user)
            add_user "$2" "$3" "$4"
            ;;
        delete-user)
            delete_user "$2"
            ;;
        change-password)
            change_password "$2" "$3"
            ;;
        set-tags)
            set_user_tags "$2" "$3"
            ;;
        set-permissions)
            set_permissions "$2" "$3" "$4" "$5" "$6"
            ;;
        list-permissions)
            list_permissions "$2"
            ;;
        list-all-permissions)
            list_all_permissions
            ;;
        create-vhost)
            create_vhost "$2"
            ;;
        delete-vhost)
            delete_vhost "$2"
            ;;
        list-vhosts)
            list_vhosts
            ;;
        set-vhost-permissions)
            set_vhost_permissions "$2" "$3" "$4" "$5" "$6"
            ;;
        create-default-users)
            create_default_users
            ;;
        export-definitions)
            export_definitions "$2"
            ;;
        import-definitions)
            import_definitions "$2"
            ;;
        show-user-info)
            show_user_info "$2"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
