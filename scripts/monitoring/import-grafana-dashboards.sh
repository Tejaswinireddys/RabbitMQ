#!/bin/bash

# RabbitMQ Grafana Dashboard Import Script
# This script automates the import of all RabbitMQ monitoring dashboards into Grafana

set -e

# Configuration
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"
PROMETHEUS_DS_NAME="${PROMETHEUS_DS_NAME:-Prometheus}"
PROMETHEUS_DS_URL="${PROMETHEUS_DS_URL:-http://localhost:9090}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    log_message "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Test Grafana connectivity
test_grafana_connection() {
    log_message "Testing Grafana connection..."
    
    local response
    if [ -n "$GRAFANA_API_KEY" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $GRAFANA_API_KEY" \
            "$GRAFANA_URL/api/health")
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
            "$GRAFANA_URL/api/health")
    fi
    
    if [ "$response" = "200" ]; then
        log_success "Grafana connection successful"
    else
        log_error "Failed to connect to Grafana (HTTP $response)"
        exit 1
    fi
}

# Get Grafana authentication header
get_auth_header() {
    if [ -n "$GRAFANA_API_KEY" ]; then
        echo "Authorization: Bearer $GRAFANA_API_KEY"
    else
        echo "Authorization: Basic $(echo -n "$GRAFANA_USER:$GRAFANA_PASSWORD" | base64)"
    fi
}

# Check if Prometheus data source exists
check_prometheus_datasource() {
    log_message "Checking Prometheus data source..."
    
    local auth_header
    auth_header=$(get_auth_header)
    
    local response
    response=$(curl -s -H "$auth_header" "$GRAFANA_URL/api/datasources")
    
    local ds_exists
    ds_exists=$(echo "$response" | jq -r ".[] | select(.name == \"$PROMETHEUS_DS_NAME\") | .name")
    
    if [ "$ds_exists" = "$PROMETHEUS_DS_NAME" ]; then
        log_success "Prometheus data source '$PROMETHEUS_DS_NAME' found"
    else
        log_warning "Prometheus data source '$PROMETHEUS_DS_NAME' not found"
        create_prometheus_datasource
    fi
}

# Create Prometheus data source
create_prometheus_datasource() {
    log_message "Creating Prometheus data source..."
    
    local auth_header
    auth_header=$(get_auth_header)
    
    local datasource_config
    datasource_config=$(cat <<EOF
{
    "name": "$PROMETHEUS_DS_NAME",
    "type": "prometheus",
    "url": "$PROMETHEUS_DS_URL",
    "access": "proxy",
    "isDefault": true,
    "jsonData": {
        "httpMethod": "POST",
        "queryTimeout": "60s",
        "timeInterval": "15s"
    }
}
EOF
)
    
    local response
    response=$(curl -s -X POST \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$datasource_config" \
        "$GRAFANA_URL/api/datasources")
    
    local ds_id
    ds_id=$(echo "$response" | jq -r '.id')
    
    if [ "$ds_id" != "null" ] && [ "$ds_id" != "" ]; then
        log_success "Prometheus data source created with ID: $ds_id"
    else
        log_error "Failed to create Prometheus data source"
        echo "$response" | jq -r '.message // "Unknown error"'
        exit 1
    fi
}

# Import dashboard
import_dashboard() {
    local dashboard_file="$1"
    local dashboard_name="$2"
    
    log_message "Importing dashboard: $dashboard_name"
    
    if [ ! -f "$dashboard_file" ]; then
        log_error "Dashboard file not found: $dashboard_file"
        return 1
    fi
    
    local auth_header
    auth_header=$(get_auth_header)
    
    # Read dashboard JSON and update data source
    local dashboard_json
    dashboard_json=$(cat "$dashboard_file" | jq --arg ds_name "$PROMETHEUS_DS_NAME" '
        .dashboard.panels[]?.targets[]? |= 
        if .datasource == null then .datasource = $ds_name else . end
    ')
    
    local response
    response=$(curl -s -X POST \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$dashboard_json" \
        "$GRAFANA_URL/api/dashboards/db")
    
    local dashboard_id
    dashboard_id=$(echo "$response" | jq -r '.id')
    
    if [ "$dashboard_id" != "null" ] && [ "$dashboard_id" != "" ]; then
        log_success "Dashboard '$dashboard_name' imported successfully (ID: $dashboard_id)"
        return 0
    else
        log_error "Failed to import dashboard '$dashboard_name'"
        echo "$response" | jq -r '.message // "Unknown error"'
        return 1
    fi
}

# Import all dashboards
import_all_dashboards() {
    log_message "Starting dashboard import process..."
    
    local dashboards_dir="configs/dashboards"
    local success_count=0
    local total_count=0
    
    # List of dashboards to import
    local dashboards=(
        "rabbitmq-queue-dashboard.json:Queue Performance Dashboard"
        "rabbitmq-channels-connections-dashboard.json:Channels & Connections Dashboard"
        "rabbitmq-message-flow-dashboard.json:Message Flow & Throughput Dashboard"
        "rabbitmq-system-performance-dashboard.json:System Performance Dashboard"
        "rabbitmq-cluster-health-dashboard.json:Cluster Health Dashboard"
        "tier1-executive-dashboard.json:Executive Dashboard (Tier 1)"
        "tier2-operations-dashboard.json:Operations Dashboard (Tier 2)"
        "tier3-technical-dashboard.json:Technical Dashboard (Tier 3)"
    )
    
    for dashboard_info in "${dashboards[@]}"; do
        IFS=':' read -r filename display_name <<< "$dashboard_info"
        local dashboard_file="$dashboards_dir/$filename"
        
        total_count=$((total_count + 1))
        
        if import_dashboard "$dashboard_file" "$display_name"; then
            success_count=$((success_count + 1))
        fi
        
        # Small delay between imports
        sleep 2
    done
    
    log_message "Dashboard import completed: $success_count/$total_count successful"
    
    if [ $success_count -eq $total_count ]; then
        log_success "All dashboards imported successfully!"
    else
        log_warning "Some dashboards failed to import"
    fi
}

# Display dashboard URLs
display_dashboard_urls() {
    log_message "Dashboard URLs:"
    echo ""
    echo "📊 RabbitMQ Monitoring Dashboards:"
    echo "  • Queue Performance: $GRAFANA_URL/d/queue-performance"
    echo "  • Channels & Connections: $GRAFANA_URL/d/channels-connections"
    echo "  • Message Flow & Throughput: $GRAFANA_URL/d/message-flow"
    echo "  • System Performance: $GRAFANA_URL/d/system-performance"
    echo "  • Cluster Health: $GRAFANA_URL/d/cluster-health"
    echo ""
    echo "🎯 Multi-Tier Dashboards:"
    echo "  • Executive Dashboard (Tier 1): $GRAFANA_URL/d/executive-dashboard"
    echo "  • Operations Dashboard (Tier 2): $GRAFANA_URL/d/operations-dashboard"
    echo "  • Technical Dashboard (Tier 3): $GRAFANA_URL/d/technical-dashboard"
    echo ""
    echo "🔧 Grafana Configuration:"
    echo "  • Data Sources: $GRAFANA_URL/datasources"
    echo "  • Alerting: $GRAFANA_URL/alerting"
    echo "  • Users: $GRAFANA_URL/admin/users"
    echo ""
}

# Main function
main() {
    echo "🚀 RabbitMQ Grafana Dashboard Import Script"
    echo "=============================================="
    echo ""
    
    # Check if running from correct directory
    if [ ! -d "configs/dashboards" ]; then
        log_error "Please run this script from the RabbitMQ project root directory"
        exit 1
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --grafana-url)
                GRAFANA_URL="$2"
                shift 2
                ;;
            --grafana-user)
                GRAFANA_USER="$2"
                shift 2
                ;;
            --grafana-password)
                GRAFANA_PASSWORD="$2"
                shift 2
                ;;
            --grafana-api-key)
                GRAFANA_API_KEY="$2"
                shift 2
                ;;
            --prometheus-ds-name)
                PROMETHEUS_DS_NAME="$2"
                shift 2
                ;;
            --prometheus-ds-url)
                PROMETHEUS_DS_URL="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --grafana-url URL           Grafana URL (default: http://localhost:3000)"
                echo "  --grafana-user USER         Grafana username (default: admin)"
                echo "  --grafana-password PASS     Grafana password (default: admin)"
                echo "  --grafana-api-key KEY       Grafana API key (alternative to user/pass)"
                echo "  --prometheus-ds-name NAME   Prometheus data source name (default: Prometheus)"
                echo "  --prometheus-ds-url URL     Prometheus URL (default: http://localhost:9090)"
                echo "  --help                      Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  GRAFANA_URL, GRAFANA_USER, GRAFANA_PASSWORD, GRAFANA_API_KEY"
                echo "  PROMETHEUS_DS_NAME, PROMETHEUS_DS_URL"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute main workflow
    check_dependencies
    test_grafana_connection
    check_prometheus_datasource
    import_all_dashboards
    display_dashboard_urls
    
    echo ""
    log_success "Dashboard import process completed!"
    echo ""
    echo "🎉 Your RabbitMQ monitoring dashboards are now ready!"
    echo "   Visit the URLs above to start monitoring your RabbitMQ cluster."
    echo ""
}

# Run main function
main "$@"
