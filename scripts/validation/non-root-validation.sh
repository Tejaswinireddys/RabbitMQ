#!/bin/bash

# RabbitMQ Non-Root Setup Validation Script
# Comprehensive validation of non-root RabbitMQ installation and configuration
# Version: 1.0

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")/../installation/rabbitmq-deployment"
LOG_FILE="$DEPLOYMENT_DIR/logs/validation-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Initialize validation
init_validation() {
    mkdir -p "$(dirname "$LOG_FILE")"
    log "Starting RabbitMQ Non-Root Setup Validation"
    log "Log file: $LOG_FILE"
}

# Check user permissions
check_user_permissions() {
    log "=== Checking User Permissions ==="
    
    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        error "This script must be run as a non-root user"
        return 1
    fi
    
    log "✓ Running as non-root user: $(whoami)"
    
    # Check sudo permissions
    if sudo -l >/dev/null 2>&1; then
        log "✓ Sudo permissions available"
        
        # Check specific RabbitMQ commands
        if sudo -l | grep -q "rabbitmqctl"; then
            log "✓ rabbitmqctl command available via sudo"
        else
            warn "rabbitmqctl command not available via sudo"
        fi
        
        if sudo -l | grep -q "systemctl.*rabbitmq-server"; then
            log "✓ systemctl rabbitmq-server command available via sudo"
        else
            warn "systemctl rabbitmq-server command not available via sudo"
        fi
    else
        error "No sudo permissions available"
        return 1
    fi
}

# Check system requirements
check_system_requirements() {
    log "=== Checking System Requirements ==="
    
    # Check OS version
    if [[ -f /etc/redhat-release ]]; then
        local os_version=$(cat /etc/redhat-release)
        log "✓ OS: $os_version"
        
        if echo "$os_version" | grep -q "8\."; then
            log "✓ RHEL/CentOS 8.x detected"
        else
            warn "Non-RHEL/CentOS 8.x system detected"
        fi
    else
        warn "Unable to determine OS version"
    fi
    
    # Check memory
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    log "Total memory: ${total_mem}MB"
    
    if [[ $total_mem -ge 4096 ]]; then
        log "✓ Sufficient memory (4GB+)"
    else
        warn "Low memory detected (${total_mem}MB). Recommended: 4GB+"
    fi
    
    # Check disk space
    local disk_usage=$(df /var/lib/rabbitmq | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    log "Disk usage for /var/lib/rabbitmq: ${disk_usage}%"
    
    if [[ $disk_usage -lt 80 ]]; then
        log "✓ Sufficient disk space"
    else
        warn "High disk usage detected (${disk_usage}%)"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    log "CPU cores: $cpu_cores"
    
    if [[ $cpu_cores -ge 2 ]]; then
        log "✓ Sufficient CPU cores (2+)"
    else
        warn "Low CPU core count ($cpu_cores). Recommended: 2+"
    fi
}

# Check RabbitMQ installation
check_rabbitmq_installation() {
    log "=== Checking RabbitMQ Installation ==="
    
    # Check if RabbitMQ is installed
    if rpm -qa | grep -q rabbitmq-server; then
        local version=$(rpm -qa | grep rabbitmq-server | cut -d'-' -f3)
        log "✓ RabbitMQ installed: $version"
    else
        error "RabbitMQ not installed"
        return 1
    fi
    
    # Check Erlang installation
    if command -v erl >/dev/null 2>&1; then
        local erlang_version=$(erl -version 2>&1 | head -1)
        log "✓ Erlang installed: $erlang_version"
    else
        error "Erlang not installed"
        return 1
    fi
    
    # Check RabbitMQ service
    if sudo systemctl is-active --quiet rabbitmq-server; then
        log "✓ RabbitMQ service is running"
    else
        warn "RabbitMQ service is not running"
    fi
    
    # Check if service is enabled
    if sudo systemctl is-enabled --quiet rabbitmq-server; then
        log "✓ RabbitMQ service is enabled"
    else
        warn "RabbitMQ service is not enabled"
    fi
}

# Check configuration files
check_configuration_files() {
    log "=== Checking Configuration Files ==="
    
    # Check main configuration file
    if [[ -f /etc/rabbitmq/rabbitmq.conf ]]; then
        log "✓ rabbitmq.conf exists"
        
        # Check for important settings
        if grep -q "listeners.tcp.default" /etc/rabbitmq/rabbitmq.conf; then
            log "✓ TCP listener configured"
        else
            warn "TCP listener not configured"
        fi
        
        if grep -q "management.tcp.port" /etc/rabbitmq/rabbitmq.conf; then
            log "✓ Management interface configured"
        else
            warn "Management interface not configured"
        fi
    else
        error "rabbitmq.conf not found"
        return 1
    fi
    
    # Check enabled plugins
    if [[ -f /etc/rabbitmq/enabled_plugins ]]; then
        log "✓ enabled_plugins file exists"
        
        if grep -q "rabbitmq_management" /etc/rabbitmq/enabled_plugins; then
            log "✓ Management plugin enabled"
        else
            warn "Management plugin not enabled"
        fi
    else
        warn "enabled_plugins file not found"
    fi
    
    # Check file permissions
    local config_owner=$(ls -la /etc/rabbitmq/ | head -2 | tail -1 | awk '{print $3}')
    if [[ "$config_owner" == "rabbitmq" ]]; then
        log "✓ Configuration files owned by rabbitmq user"
    else
        warn "Configuration files not owned by rabbitmq user"
    fi
}

# Check system limits
check_system_limits() {
    log "=== Checking System Limits ==="
    
    # Check current limits
    local nofile_limit=$(ulimit -n)
    log "Current nofile limit: $nofile_limit"
    
    if [[ $nofile_limit -ge 65536 ]]; then
        log "✓ Sufficient nofile limit (65536+)"
    else
        warn "Low nofile limit ($nofile_limit). Recommended: 65536+"
    fi
    
    # Check systemd service limits
    if [[ -f /etc/systemd/system/rabbitmq-server.service.d/limits.conf ]]; then
        log "✓ Systemd service limits configured"
        
        if grep -q "LimitNOFILE=300000" /etc/systemd/system/rabbitmq-server.service.d/limits.conf; then
            log "✓ Service nofile limit set to 300000"
        else
            warn "Service nofile limit not properly configured"
        fi
    else
        warn "Systemd service limits not configured"
    fi
    
    # Check system-wide limits
    if [[ -f /etc/security/limits.d/99-rabbitmq.conf ]]; then
        log "✓ System-wide limits configured"
    else
        warn "System-wide limits not configured"
    fi
}

# Check kernel parameters
check_kernel_parameters() {
    log "=== Checking Kernel Parameters ==="
    
    # Check important kernel parameters
    local somaxconn=$(cat /proc/sys/net/core/somaxconn)
    log "somaxconn: $somaxconn"
    
    if [[ $somaxconn -ge 2048 ]]; then
        log "✓ somaxconn is sufficient ($somaxconn)"
    else
        warn "Low somaxconn ($somaxconn). Recommended: 2048+"
    fi
    
    local swappiness=$(cat /proc/sys/vm/swappiness)
    log "swappiness: $swappiness"
    
    if [[ $swappiness -le 10 ]]; then
        log "✓ swappiness is optimal ($swappiness)"
    else
        warn "High swappiness ($swappiness). Recommended: 10 or less"
    fi
    
    local file_max=$(cat /proc/sys/fs/file-max)
    log "file-max: $file_max"
    
    if [[ $file_max -ge 2097152 ]]; then
        log "✓ file-max is sufficient ($file_max)"
    else
        warn "Low file-max ($file_max). Recommended: 2097152+"
    fi
}

# Check firewall configuration
check_firewall_configuration() {
    log "=== Checking Firewall Configuration ==="
    
    # Check if firewall is running
    if sudo firewall-cmd --state >/dev/null 2>&1; then
        log "✓ Firewall is running"
        
        # Check required ports
        local required_ports=(5672 15672 25672 4369 15692)
        
        for port in "${required_ports[@]}"; do
            if sudo firewall-cmd --list-ports | grep -q "$port"; then
                log "✓ Port $port is open"
            else
                warn "Port $port is not open"
            fi
        done
        
        # Check port ranges
        if sudo firewall-cmd --list-ports | grep -q "35672-35682"; then
            log "✓ Port range 35672-35682 is open"
        else
            warn "Port range 35672-35682 is not open"
        fi
    else
        warn "Firewall is not running or not accessible"
    fi
}

# Check RabbitMQ functionality
check_rabbitmq_functionality() {
    log "=== Checking RabbitMQ Functionality ==="
    
    # Check if RabbitMQ is responding
    if sudo rabbitmqctl status >/dev/null 2>&1; then
        log "✓ RabbitMQ is responding to commands"
    else
        error "RabbitMQ is not responding to commands"
        return 1
    fi
    
    # Check node health
    if sudo rabbitmqctl node_health_check >/dev/null 2>&1; then
        log "✓ Node health check passed"
    else
        warn "Node health check failed"
    fi
    
    # Check cluster status
    local cluster_status=$(sudo rabbitmqctl cluster_status 2>/dev/null)
    if [[ -n "$cluster_status" ]]; then
        log "✓ Cluster status accessible"
        
        if echo "$cluster_status" | grep -q "running_nodes"; then
            log "✓ Cluster is running"
        else
            warn "Cluster may not be properly configured"
        fi
    else
        warn "Unable to get cluster status"
    fi
    
    # Check for alarms
    local alarms=$(sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' 2>/dev/null)
    if [[ "$alarms" == "[]" ]]; then
        log "✓ No alarms detected"
    else
        warn "Alarms detected: $alarms"
    fi
}

# Check user management
check_user_management() {
    log "=== Checking User Management ==="
    
    # Check if users exist
    local users=$(sudo rabbitmqctl list_users 2>/dev/null)
    if [[ -n "$users" ]]; then
        log "✓ User management accessible"
        
        # Check for default users
        if echo "$users" | grep -q "admin"; then
            log "✓ Admin user exists"
        else
            warn "Admin user not found"
        fi
        
        if echo "$users" | grep -q "guest"; then
            warn "Guest user still exists (security risk)"
        else
            log "✓ Guest user removed"
        fi
    else
        warn "Unable to access user management"
    fi
}

# Check monitoring capabilities
check_monitoring_capabilities() {
    log "=== Checking Monitoring Capabilities ==="
    
    # Check if management plugin is enabled
    if sudo rabbitmq-plugins list | grep -q "rabbitmq_management.*E"; then
        log "✓ Management plugin is enabled"
    else
        warn "Management plugin is not enabled"
    fi
    
    # Check if prometheus plugin is enabled
    if sudo rabbitmq-plugins list | grep -q "rabbitmq_prometheus.*E"; then
        log "✓ Prometheus plugin is enabled"
    else
        warn "Prometheus plugin is not enabled"
    fi
    
    # Check management interface accessibility
    if curl -s http://localhost:15672 >/dev/null 2>&1; then
        log "✓ Management interface is accessible"
    else
        warn "Management interface is not accessible"
    fi
}

# Check backup capabilities
check_backup_capabilities() {
    log "=== Checking Backup Capabilities ==="
    
    # Check if backup directory exists
    if [[ -d "$DEPLOYMENT_DIR/backup" ]]; then
        log "✓ Backup directory exists"
    else
        warn "Backup directory not found"
    fi
    
    # Check if definitions can be exported
    if sudo rabbitmqctl export_definitions /tmp/test-definitions.json >/dev/null 2>&1; then
        log "✓ Definitions export works"
        rm -f /tmp/test-definitions.json
    else
        warn "Definitions export failed"
    fi
}

# Generate validation report
generate_validation_report() {
    local report_file="$DEPLOYMENT_DIR/logs/validation-report-$(date +%Y%m%d_%H%M%S).txt"
    
    log "Generating validation report: $report_file"
    
    {
        echo "=== RabbitMQ Non-Root Setup Validation Report ==="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo ""
        
        echo "=== System Information ==="
        uname -a
        cat /etc/redhat-release 2>/dev/null || echo "OS version not available"
        echo ""
        
        echo "=== Memory Information ==="
        free -h
        echo ""
        
        echo "=== Disk Information ==="
        df -h /var/lib/rabbitmq /var/log/rabbitmq
        echo ""
        
        echo "=== RabbitMQ Status ==="
        sudo systemctl status rabbitmq-server
        echo ""
        
        echo "=== Cluster Status ==="
        sudo rabbitmqctl cluster_status
        echo ""
        
        echo "=== User List ==="
        sudo rabbitmqctl list_users
        echo ""
        
        echo "=== Queue List ==="
        sudo rabbitmqctl list_queues
        echo ""
        
        echo "=== Connection List ==="
        sudo rabbitmqctl list_connections
        echo ""
        
    } > "$report_file"
    
    log "Validation report generated: $report_file"
}

# Main validation function
run_validation() {
    init_validation
    
    local validation_passed=true
    
    # Run all validation checks
    check_user_permissions || validation_passed=false
    check_system_requirements || validation_passed=false
    check_rabbitmq_installation || validation_passed=false
    check_configuration_files || validation_passed=false
    check_system_limits || validation_passed=false
    check_kernel_parameters || validation_passed=false
    check_firewall_configuration || validation_passed=false
    check_rabbitmq_functionality || validation_passed=false
    check_user_management || validation_passed=false
    check_monitoring_capabilities || validation_passed=false
    check_backup_capabilities || validation_passed=false
    
    # Generate report
    generate_validation_report
    
    # Final result
    if [[ "$validation_passed" == "true" ]]; then
        log "=== Validation Completed Successfully ==="
        log "All critical checks passed"
        log "RabbitMQ non-root setup is working correctly"
    else
        error "=== Validation Failed ==="
        error "Some checks failed. Please review the log file: $LOG_FILE"
        error "Review the validation report for detailed information"
    fi
    
    return $([ "$validation_passed" == "true" ] && echo 0 || echo 1)
}

# Show usage information
show_usage() {
    cat << EOF
RabbitMQ Non-Root Setup Validation Script

Usage: $0 [options]

Options:
    --help, -h          Show this help message
    --report-only       Generate report without running checks
    --quiet             Suppress output (log to file only)

This script validates the RabbitMQ non-root setup including:
- User permissions and sudo access
- System requirements and resources
- RabbitMQ installation and configuration
- System limits and kernel parameters
- Firewall configuration
- RabbitMQ functionality and cluster status
- User management capabilities
- Monitoring and backup capabilities

Examples:
    $0                  # Run full validation
    $0 --report-only    # Generate report only
    $0 --quiet          # Run validation quietly

EOF
}

# Main function
main() {
    local quiet_mode=false
    local report_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --quiet)
                quiet_mode=true
                shift
                ;;
            --report-only)
                report_only=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up logging
    if [[ "$quiet_mode" == "true" ]]; then
        exec > "$LOG_FILE" 2>&1
    fi
    
    # Run validation or generate report only
    if [[ "$report_only" == "true" ]]; then
        init_validation
        generate_validation_report
    else
        run_validation
    fi
}

# Run main function
main "$@"
