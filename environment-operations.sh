#!/bin/bash
# File: environment-operations.sh
# Comprehensive Environment Operations Dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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
        "header") echo -e "${PURPLE}$message${NC}" ;;
        "highlight") echo -e "${CYAN}$message${NC}" ;;
    esac
}

# Function to display usage
usage() {
    echo "RabbitMQ Environment Operations Dashboard"
    echo ""
    echo "Usage: $0 <command> [environment] [options]"
    echo ""
    echo "Commands:"
    echo "  dashboard [env]           Show environment status dashboard"
    echo "  list-environments        List all available environments"
    echo "  quick-setup <env>         Quick environment setup wizard"
    echo "  health-check <env>        Comprehensive health check"
    echo "  operations-menu <env>     Interactive operations menu"
    echo "  backup-all               Backup all environments"
    echo "  compare <env1> <env2>     Compare two environments"
    echo "  migrate <src> <dest>      Migrate configuration between environments"
    echo ""
    echo "Examples:"
    echo "  $0 dashboard prod         # Show production dashboard"
    echo "  $0 quick-setup qa         # Setup QA environment"
    echo "  $0 health-check staging   # Check staging health"
    echo "  $0 operations-menu prod   # Interactive menu for production"
    exit 1
}

# Function to show environment dashboard
show_dashboard() {
    local env=$1
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name required for dashboard"
        return 1
    fi
    
    clear
    print_status "header" "╔════════════════════════════════════════════════════════════════╗"
    print_status "header" "║               RabbitMQ Environment Dashboard                   ║"
    print_status "header" "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Load environment
    if ! source "$SCRIPT_DIR/load-environment.sh" "$env" >/dev/null 2>&1; then
        print_status "error" "Failed to load environment: $env"
        return 1
    fi
    
    print_status "highlight" "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
    print_status "highlight" "Cluster: $RABBITMQ_CLUSTER_NAME"
    print_status "highlight" "Timestamp: $(date)"
    echo ""
    
    # Environment Information
    print_status "header" "═══ Environment Configuration ═══"
    echo "  Name: $ENVIRONMENT_NAME"
    echo "  Type: $ENVIRONMENT_TYPE"
    echo "  Cluster Name: $RABBITMQ_CLUSTER_NAME"
    echo "  SSL Enabled: $RABBITMQ_SSL_ENABLED"
    echo "  Partition Handling: $RABBITMQ_CLUSTER_PARTITION_HANDLING"
    echo ""
    
    # Node Information
    print_status "header" "═══ Cluster Nodes ═══"
    local node_index=1
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        local ip_var="RABBITMQ_NODE_${node_index}_IP"
        local ip=${!ip_var}
        
        # Check node status
        local status="❓"
        local status_text="Unknown"
        
        if [ "$hostname" = "$(hostname)" ]; then
            if sudo rabbitmqctl ping >/dev/null 2>&1; then
                status="✅"
                status_text="Running (Local)"
            else
                status="❌"
                status_text="Down (Local)"
            fi
        else
            if ssh -o ConnectTimeout=2 "root@$hostname" "rabbitmqctl ping" >/dev/null 2>&1; then
                status="✅"
                status_text="Running"
            else
                status="❌"
                status_text="Down/Unreachable"
            fi
        fi
        
        echo "  Node $node_index: $hostname ($ip) $status $status_text"
        node_index=$((node_index + 1))
    done
    echo ""
    
    # Cluster Status
    print_status "header" "═══ Cluster Status ═══"
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        local total_nodes=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
        
        print_status "success" "Cluster operational: $running_nodes/$total_nodes nodes running"
        
        # Check cluster name
        local actual_cluster_name=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' 2>/dev/null | sed 's/<<"\(.*\)">>/\1/' || echo "Unknown")
        if [ "$actual_cluster_name" = "$RABBITMQ_CLUSTER_NAME" ]; then
            print_status "success" "Cluster name correct: $actual_cluster_name"
        else
            print_status "warning" "Cluster name mismatch: expected $RABBITMQ_CLUSTER_NAME, got $actual_cluster_name"
        fi
    else
        print_status "error" "Cluster not operational (minority partition or service down)"
    fi
    echo ""
    
    # Resource Status
    print_status "header" "═══ Resource Status ═══"
    if sudo rabbitmqctl status >/dev/null 2>&1; then
        # Alarms
        local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
        if [ "$alarms" = "[]" ]; then
            print_status "success" "No resource alarms"
        else
            print_status "warning" "Resource alarms: $alarms"
        fi
        
        # Memory usage
        local memory_used=$(sudo rabbitmqctl status | grep -A 1 "Memory" | tail -1 | awk '{print $2}' | tr -d ',' || echo "Unknown")
        echo "  Memory used: $memory_used bytes"
        
        # Partitions
        local partitions=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "[]")
        if [ "$partitions" = "[]" ]; then
            print_status "success" "No network partitions"
        else
            print_status "error" "Network partitions detected: $partitions"
        fi
    else
        print_status "warning" "Cannot retrieve resource status"
    fi
    echo ""
    
    # Queue Information
    print_status "header" "═══ Queue Information ═══"
    if sudo rabbitmqctl list_queues >/dev/null 2>&1; then
        local total_queues=$(sudo rabbitmqctl list_queues 2>/dev/null | wc -l)
        local env_queues=$(sudo rabbitmqctl list_queues name 2>/dev/null | grep "^$ENVIRONMENT_NAME-" | wc -l || echo "0")
        local total_messages=$(sudo rabbitmqctl list_queues messages 2>/dev/null | tail -n +2 | awk '{sum += $1} END {print sum}' || echo "0")
        
        echo "  Total queues: $total_queues"
        echo "  Environment-specific queues: $env_queues"
        echo "  Total messages: $total_messages"
        
        # Show environment queues if any
        if [ $env_queues -gt 0 ]; then
            echo "  Environment queues:"
            sudo rabbitmqctl list_queues name messages consumers 2>/dev/null | grep "^$ENVIRONMENT_NAME-" | while read name messages consumers; do
                echo "    $name: $messages messages, $consumers consumers"
            done
        fi
    else
        print_status "warning" "Cannot retrieve queue information"
    fi
    echo ""
    
    # Management Interface
    print_status "header" "═══ Management Interface ═══"
    echo "  Management URLs:"
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        echo "    http://$hostname:$RABBITMQ_MANAGEMENT_PORT"
    done
    if [ -n "$RABBITMQ_VIP" ]; then
        echo "    VIP: http://$RABBITMQ_VIP:$RABBITMQ_MANAGEMENT_PORT"
    fi
    echo "  Users: $RABBITMQ_CUSTOM_USER_1, $RABBITMQ_CUSTOM_USER_2, $RABBITMQ_DEFAULT_USER"
    echo ""
    
    # Quick Actions
    print_status "header" "═══ Quick Actions ═══"
    echo "  Monitor:     $SCRIPT_DIR/monitor-environment.sh -e $env"
    echo "  Restart:     $SCRIPT_DIR/rolling-restart-environment.sh -e $env"
    echo "  Health:      $SCRIPT_DIR/environment-operations.sh health-check $env"
    echo "  Operations:  $SCRIPT_DIR/environment-operations.sh operations-menu $env"
    echo ""
}

# Function to list all environments
list_environments() {
    print_status "header" "Available RabbitMQ Environments"
    echo ""
    
    local env_dir="$SCRIPT_DIR/environments"
    if [ ! -d "$env_dir" ]; then
        print_status "error" "Environment directory not found: $env_dir"
        return 1
    fi
    
    echo "Environment files found in $env_dir:"
    echo ""
    
    for env_file in "$env_dir"/*.env; do
        if [ -f "$env_file" ]; then
            local env_name=$(basename "$env_file" .env)
            
            if [ "$env_name" = "base" ]; then
                continue
            fi
            
            # Load environment to get details
            if source "$env_file" 2>/dev/null; then
                echo "  📁 $env_name"
                echo "     Name: ${ENVIRONMENT_NAME:-Unknown}"
                echo "     Type: ${ENVIRONMENT_TYPE:-Unknown}"
                echo "     Cluster: ${RABBITMQ_CLUSTER_NAME:-Unknown}"
                echo "     Nodes: ${RABBITMQ_NODE_1_HOSTNAME:-Unknown} ${RABBITMQ_NODE_2_HOSTNAME:-Unknown} ${RABBITMQ_NODE_3_HOSTNAME:-Unknown}"
                echo ""
            else
                echo "  ❌ $env_name (invalid configuration)"
                echo ""
            fi
        fi
    done
}

# Function for quick setup wizard
quick_setup() {
    local env=$1
    
    if [ -z "$env" ]; then
        read -p "Enter environment name: " env
    fi
    
    print_status "header" "Quick Setup Wizard for Environment: $env"
    echo ""
    
    # Check if environment exists
    if [ -f "$SCRIPT_DIR/environments/$env.env" ]; then
        print_status "info" "Environment configuration found"
        
        # Validate configuration
        if "$SCRIPT_DIR/load-environment.sh" validate "$env"; then
            print_status "success" "Environment configuration is valid"
        else
            print_status "error" "Environment configuration has issues"
            read -p "Continue anyway? (y/n): " continue_setup
            if [ "$continue_setup" != "y" ]; then
                return 1
            fi
        fi
    else
        print_status "info" "Environment not found, creating new environment"
        "$SCRIPT_DIR/environment-manager.sh" create "$env"
        
        print_status "info" "Please edit the environment file and run setup again"
        echo "Edit: $SCRIPT_DIR/environments/$env.env"
        return 0
    fi
    
    # Load environment
    source "$SCRIPT_DIR/load-environment.sh" "$env"
    
    print_status "info" "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
    print_status "info" "Cluster: $RABBITMQ_CLUSTER_NAME"
    print_status "info" "Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"
    echo ""
    
    # Setup menu
    echo "Quick Setup Options:"
    echo "1. Generate configuration files"
    echo "2. Setup cluster nodes"
    echo "3. Deploy to all nodes"
    echo "4. Validate deployment"
    echo "5. Create environment queues"
    echo "6. Start monitoring"
    echo "7. Complete setup (all steps)"
    echo ""
    
    read -p "Select option (1-7): " option
    
    case $option in
        1)
            print_status "info" "Generating configuration files..."
            "$SCRIPT_DIR/generate-configs.sh" "$env"
            print_status "success" "Configuration files generated"
            ;;
        2)
            print_status "info" "Setting up cluster nodes..."
            echo "Run on each node:"
            for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
                echo "  ssh root@$hostname '$SCRIPT_DIR/cluster-setup-environment.sh -e $env -r auto'"
            done
            ;;
        3)
            print_status "info" "Deploying to all nodes..."
            "$SCRIPT_DIR/environment-manager.sh" deploy "$env"
            ;;
        4)
            print_status "info" "Validating deployment..."
            quick_health_check "$env"
            ;;
        5)
            print_status "info" "Creating environment queues..."
            if [ -f "$SCRIPT_DIR/create-environment-queues.sh" ]; then
                "$SCRIPT_DIR/create-environment-queues.sh" "$env"
            else
                print_status "warning" "Environment queue script not found"
            fi
            ;;
        6)
            print_status "info" "Starting monitoring..."
            "$SCRIPT_DIR/monitor-environment.sh" -e "$env" -m once
            ;;
        7)
            print_status "info" "Running complete setup..."
            "$SCRIPT_DIR/generate-configs.sh" "$env"
            "$SCRIPT_DIR/environment-manager.sh" deploy "$env"
            print_status "success" "Setup completed. Now run cluster setup on each node."
            ;;
        *)
            print_status "error" "Invalid option"
            ;;
    esac
}

# Function for comprehensive health check
comprehensive_health_check() {
    local env=$1
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name required for health check"
        return 1
    fi
    
    print_status "header" "Comprehensive Health Check: $env"
    echo ""
    
    # Load environment
    if ! source "$SCRIPT_DIR/load-environment.sh" "$env" >/dev/null 2>&1; then
        print_status "error" "Failed to load environment: $env"
        return 1
    fi
    
    local issues=0
    
    # 1. Environment configuration validation
    print_status "info" "1. Validating environment configuration..."
    if "$SCRIPT_DIR/load-environment.sh" validate "$env" >/dev/null 2>&1; then
        print_status "success" "Environment configuration valid"
    else
        print_status "error" "Environment configuration has issues"
        issues=$((issues + 1))
    fi
    
    # 2. Node connectivity check
    print_status "info" "2. Checking node connectivity..."
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" = "$(hostname)" ]; then
            print_status "success" "$hostname (local): Reachable"
        elif ping -c 1 -W 2 "$hostname" >/dev/null 2>&1; then
            if ssh -o ConnectTimeout=5 "root@$hostname" "echo test" >/dev/null 2>&1; then
                print_status "success" "$hostname: Reachable via SSH"
            else
                print_status "error" "$hostname: Network reachable but SSH failed"
                issues=$((issues + 1))
            fi
        else
            print_status "error" "$hostname: Network unreachable"
            issues=$((issues + 1))
        fi
    done
    
    # 3. RabbitMQ service status
    print_status "info" "3. Checking RabbitMQ service status..."
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" = "$(hostname)" ]; then
            if sudo systemctl is-active rabbitmq-server >/dev/null 2>&1; then
                print_status "success" "$hostname: RabbitMQ service active"
            else
                print_status "error" "$hostname: RabbitMQ service not active"
                issues=$((issues + 1))
            fi
        else
            if ssh "root@$hostname" "systemctl is-active rabbitmq-server" >/dev/null 2>&1; then
                print_status "success" "$hostname: RabbitMQ service active"
            else
                print_status "error" "$hostname: RabbitMQ service not active"
                issues=$((issues + 1))
            fi
        fi
    done
    
    # 4. Cluster status
    print_status "info" "4. Checking cluster status..."
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        local running_nodes=$(sudo rabbitmqctl cluster_status | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l)
        local total_nodes=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
        
        if [ $running_nodes -eq $total_nodes ]; then
            print_status "success" "All nodes running in cluster ($running_nodes/$total_nodes)"
        else
            print_status "warning" "Some nodes missing from cluster ($running_nodes/$total_nodes)"
            issues=$((issues + 1))
        fi
        
        # Check cluster name
        local actual_cluster_name=$(sudo rabbitmqctl eval 'rabbit_nodes:cluster_name().' 2>/dev/null | sed 's/<<"\(.*\)">>/\1/' || echo "Unknown")
        if [ "$actual_cluster_name" = "$RABBITMQ_CLUSTER_NAME" ]; then
            print_status "success" "Cluster name correct: $actual_cluster_name"
        else
            print_status "warning" "Cluster name mismatch: expected $RABBITMQ_CLUSTER_NAME, got $actual_cluster_name"
            issues=$((issues + 1))
        fi
    else
        print_status "error" "Cluster status check failed"
        issues=$((issues + 1))
    fi
    
    # 5. Resource alarms
    print_status "info" "5. Checking resource alarms..."
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
    if [ "$alarms" = "[]" ]; then
        print_status "success" "No resource alarms"
    else
        print_status "warning" "Resource alarms detected: $alarms"
        issues=$((issues + 1))
    fi
    
    # 6. Network partitions
    print_status "info" "6. Checking network partitions..."
    local partitions=$(sudo rabbitmqctl eval 'rabbit_node_monitor:partitions().' 2>/dev/null || echo "[]")
    if [ "$partitions" = "[]" ]; then
        print_status "success" "No network partitions"
    else
        print_status "error" "Network partitions detected: $partitions"
        issues=$((issues + 1))
    fi
    
    # Summary
    echo ""
    print_status "header" "Health Check Summary"
    if [ $issues -eq 0 ]; then
        print_status "success" "All checks passed! Environment is healthy."
    else
        print_status "warning" "$issues issues found. Review the above output."
    fi
    
    return $issues
}

# Function for interactive operations menu
operations_menu() {
    local env=$1
    
    if [ -z "$env" ]; then
        print_status "error" "Environment name required for operations menu"
        return 1
    fi
    
    # Load environment
    if ! source "$SCRIPT_DIR/load-environment.sh" "$env" >/dev/null 2>&1; then
        print_status "error" "Failed to load environment: $env"
        return 1
    fi
    
    while true; do
        clear
        print_status "header" "╔══════════════════════════════════════════════════════════════════╗"
        print_status "header" "║            RabbitMQ Environment Operations Menu                  ║"
        print_status "header" "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        print_status "highlight" "Environment: $ENVIRONMENT_NAME ($ENVIRONMENT_TYPE)"
        print_status "highlight" "Cluster: $RABBITMQ_CLUSTER_NAME"
        echo ""
        
        echo "Operations Menu:"
        echo ""
        echo "  📊  1. Show Dashboard"
        echo "  🔍  2. Health Check"
        echo "  📈  3. Monitor (once)"
        echo "  📈  4. Monitor (continuous)"
        echo "  🔄  5. Rolling Restart"
        echo "  ⚙️   6. Generate Configs"
        echo "  🚀  7. Deploy to Nodes"
        echo "  📋  8. List Queues"
        echo "  ➕  9. Create Environment Queues"
        echo "  💾  10. Backup Environment"
        echo "  🧪  11. Run Tests"
        echo "  📤  12. Export Definitions"
        echo "  📥  13. Import Definitions"
        echo "  🔧  14. Environment Settings"
        echo "  ❌  0. Exit"
        echo ""
        
        read -p "Select operation (0-14): " choice
        
        case $choice in
            1)
                show_dashboard "$env"
                read -p "Press Enter to continue..."
                ;;
            2)
                comprehensive_health_check "$env"
                read -p "Press Enter to continue..."
                ;;
            3)
                "$SCRIPT_DIR/monitor-environment.sh" -e "$env" -m once
                read -p "Press Enter to continue..."
                ;;
            4)
                echo "Starting continuous monitoring (Ctrl+C to stop)..."
                "$SCRIPT_DIR/monitor-environment.sh" -e "$env" -m continuous -i 30
                ;;
            5)
                echo "Starting rolling restart..."
                "$SCRIPT_DIR/rolling-restart-environment.sh" -e "$env"
                read -p "Press Enter to continue..."
                ;;
            6)
                "$SCRIPT_DIR/generate-configs.sh" "$env"
                read -p "Press Enter to continue..."
                ;;
            7)
                "$SCRIPT_DIR/environment-manager.sh" deploy "$env"
                read -p "Press Enter to continue..."
                ;;
            8)
                echo "Current queues:"
                sudo rabbitmqctl list_queues name messages consumers type
                read -p "Press Enter to continue..."
                ;;
            9)
                if [ -f "$SCRIPT_DIR/create-environment-queues.sh" ]; then
                    "$SCRIPT_DIR/create-environment-queues.sh" "$env"
                else
                    print_status "warning" "Environment queue script not found"
                fi
                read -p "Press Enter to continue..."
                ;;
            10)
                "$SCRIPT_DIR/environment-manager.sh" backup "$env"
                read -p "Press Enter to continue..."
                ;;
            11)
                if [ -f "$SCRIPT_DIR/test-cluster-behavior.sh" ]; then
                    "$SCRIPT_DIR/test-cluster-behavior.sh" "$env"
                else
                    print_status "warning" "Test script not found"
                fi
                read -p "Press Enter to continue..."
                ;;
            12)
                local export_file="/tmp/definitions-$env-$(date +%Y%m%d-%H%M%S).json"
                sudo rabbitmqctl export_definitions "$export_file"
                print_status "success" "Definitions exported to: $export_file"
                read -p "Press Enter to continue..."
                ;;
            13)
                read -p "Enter definitions file path: " import_file
                if [ -f "$import_file" ]; then
                    sudo rabbitmqctl import_definitions "$import_file"
                    print_status "success" "Definitions imported"
                else
                    print_status "error" "File not found: $import_file"
                fi
                read -p "Press Enter to continue..."
                ;;
            14)
                "$SCRIPT_DIR/load-environment.sh" show "$env"
                read -p "Press Enter to continue..."
                ;;
            0)
                print_status "info" "Exiting operations menu"
                break
                ;;
            *)
                print_status "error" "Invalid option"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Quick health check function
quick_health_check() {
    local env=$1
    
    # Load environment
    source "$SCRIPT_DIR/load-environment.sh" "$env" >/dev/null 2>&1
    
    # Quick checks
    local checks_passed=0
    local total_checks=3
    
    # Check 1: Cluster status
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        print_status "success" "Cluster operational"
        checks_passed=$((checks_passed + 1))
    else
        print_status "error" "Cluster not operational"
    fi
    
    # Check 2: All nodes running
    local running_nodes=$(sudo rabbitmqctl cluster_status 2>/dev/null | grep "Running" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' | wc -l || echo "0")
    local expected_nodes=$(echo $RABBITMQ_CLUSTER_HOSTNAMES | wc -w)
    
    if [ $running_nodes -eq $expected_nodes ]; then
        print_status "success" "All nodes running ($running_nodes/$expected_nodes)"
        checks_passed=$((checks_passed + 1))
    else
        print_status "warning" "Some nodes missing ($running_nodes/$expected_nodes)"
    fi
    
    # Check 3: No alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null || echo "[]")
    if [ "$alarms" = "[]" ]; then
        print_status "success" "No resource alarms"
        checks_passed=$((checks_passed + 1))
    else
        print_status "warning" "Resource alarms detected"
    fi
    
    print_status "info" "Quick health check: $checks_passed/$total_checks checks passed"
}

# Main function
main() {
    local command=${1:-help}
    shift
    
    case $command in
        "dashboard")
            show_dashboard "$1"
            ;;
        "list-environments")
            list_environments
            ;;
        "quick-setup")
            quick_setup "$1"
            ;;
        "health-check")
            comprehensive_health_check "$1"
            ;;
        "operations-menu")
            operations_menu "$1"
            ;;
        "backup-all")
            echo "Backing up all environments..."
            for env_file in "$SCRIPT_DIR/environments"/*.env; do
                if [ -f "$env_file" ]; then
                    local env_name=$(basename "$env_file" .env)
                    if [ "$env_name" != "base" ]; then
                        print_status "info" "Backing up environment: $env_name"
                        "$SCRIPT_DIR/environment-manager.sh" backup "$env_name"
                    fi
                fi
            done
            ;;
        "compare")
            if [ $# -lt 2 ]; then
                print_status "error" "Two environment names required for comparison"
                exit 1
            fi
            "$SCRIPT_DIR/environment-manager.sh" diff "$1" "$2"
            ;;
        "migrate")
            if [ $# -lt 2 ]; then
                print_status "error" "Source and destination environment names required"
                exit 1
            fi
            "$SCRIPT_DIR/environment-manager.sh" clone "$1" "$2"
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