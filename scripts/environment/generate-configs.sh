#!/bin/bash
# File: generate-configs.sh
# Generate Environment-Aware RabbitMQ Configuration Files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show usage
usage() {
    echo "Usage: $0 <environment> [--output-dir <dir>]"
    echo ""
    echo "Arguments:"
    echo "  environment    Environment name (qa, staging, prod, etc.)"
    echo ""
    echo "Options:"
    echo "  --output-dir   Directory to save generated files (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0 prod                          # Generate production configs"
    echo "  $0 qa --output-dir /etc/rabbitmq # Generate QA configs to /etc/rabbitmq"
    exit 1
}

# Parse arguments
ENVIRONMENT=""
OUTPUT_DIR="$SCRIPT_DIR"

while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$1"
            else
                echo "Unknown argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: Environment is required"
    usage
fi

# Load environment configuration
echo "Loading environment: $ENVIRONMENT"
source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"

echo "Generating configuration files for environment: $ENVIRONMENT"
echo "Output directory: $OUTPUT_DIR"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate rabbitmq.conf
echo "Generating rabbitmq.conf..."
cat > "$OUTPUT_DIR/rabbitmq.conf" << EOF
# RabbitMQ Configuration for Environment: $ENVIRONMENT
# Generated on: $(date)
# Cluster Name: $RABBITMQ_CLUSTER_NAME

# === Cluster Configuration ===
cluster_name = $RABBITMQ_CLUSTER_NAME
cluster_partition_handling = $RABBITMQ_CLUSTER_PARTITION_HANDLING

# === Network Configuration ===
listeners.tcp.default = $RABBITMQ_NODE_PORT
distribution.listener.port_range.min = $RABBITMQ_DIST_PORT
distribution.listener.port_range.max = $RABBITMQ_DIST_PORT

# === Management Plugin Configuration ===
management.listener.port = $RABBITMQ_MANAGEMENT_PORT
management.listener.ssl = $RABBITMQ_SSL_ENABLED

# === Cluster Formation Configuration ===
cluster_formation.peer_discovery_backend = classic_config
EOF

# Add cluster nodes if configured
if [ -n "$RABBITMQ_CLUSTER_NODES" ]; then
    echo "cluster_formation.classic_config.nodes.1 = $RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME" >> "$OUTPUT_DIR/rabbitmq.conf"
    echo "cluster_formation.classic_config.nodes.2 = $RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_2_HOSTNAME" >> "$OUTPUT_DIR/rabbitmq.conf"
    echo "cluster_formation.classic_config.nodes.3 = $RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_3_HOSTNAME" >> "$OUTPUT_DIR/rabbitmq.conf"
fi

# Add auto-recovery settings
cat >> "$OUTPUT_DIR/rabbitmq.conf" << EOF

# === Auto-Recovery Settings ===
cluster_formation.node_cleanup.only_log_warning = $RABBITMQ_CLUSTER_FORMATION_LOG_CLEANUP
cluster_formation.node_cleanup.interval = $RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY

# === Retry Logic ===
cluster_formation.discovery_retry_limit = $RABBITMQ_CLUSTER_FORMATION_RETRY_LIMIT
cluster_formation.discovery_retry_interval = ${RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY}000

# === Startup Behavior ===
cluster_formation.randomized_startup_delay_range.min = $RABBITMQ_RANDOMIZED_STARTUP_DELAY_MIN
cluster_formation.randomized_startup_delay_range.max = $RABBITMQ_RANDOMIZED_STARTUP_DELAY_MAX
EOF

# Add SSL configuration if enabled
if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
    cat >> "$OUTPUT_DIR/rabbitmq.conf" << EOF

# === SSL/TLS Configuration ===
listeners.ssl.default = 5671
ssl_options.cacertfile = $RABBITMQ_SSL_CACERT
ssl_options.certfile = $RABBITMQ_SSL_CERT
ssl_options.keyfile = $RABBITMQ_SSL_KEY
ssl_options.verify = $RABBITMQ_SSL_VERIFY
ssl_options.fail_if_no_peer_cert = $RABBITMQ_SSL_FAIL_IF_NO_PEER_CERT

# Management SSL
management.ssl.port = 15671
management.ssl.cacertfile = $RABBITMQ_SSL_CACERT
management.ssl.certfile = $RABBITMQ_SSL_CERT
management.ssl.keyfile = $RABBITMQ_SSL_KEY
EOF
fi

# Add performance configuration
cat >> "$OUTPUT_DIR/rabbitmq.conf" << EOF

# === Memory and Disk Configuration ===
vm_memory_high_watermark.relative = $RABBITMQ_VM_MEMORY_HIGH_WATERMARK
disk_free_limit.absolute = $RABBITMQ_DISK_FREE_LIMIT

# === Performance Configuration ===
heartbeat = $RABBITMQ_HEARTBEAT
frame_max = $RABBITMQ_FRAME_MAX
channel_max = $RABBITMQ_CHANNEL_MAX

# === Logging Configuration ===
log.console.level = $RABBITMQ_LOG_LEVEL
log.file.level = $RABBITMQ_LOG_LEVEL

# === Default Queue Type ===
default_queue_type = quorum

# === High Availability ===
ha-mode = all
ha-sync-mode = automatic

# === Environment-specific Configuration ===
# Environment: $ENVIRONMENT
# Type: $ENVIRONMENT_TYPE
EOF

# Add environment-specific optimizations
if [ "$ENVIRONMENT_TYPE" = "production" ]; then
    cat >> "$OUTPUT_DIR/rabbitmq.conf" << EOF

# === Production Optimizations ===
collect_statistics_interval = 10000
management.rates_mode = basic
background_gc_enabled = true
background_gc_target_interval = 60000
EOF
elif [ "$ENVIRONMENT_TYPE" = "development" ]; then
    cat >> "$OUTPUT_DIR/rabbitmq.conf" << EOF

# === Development Optimizations ===
collect_statistics_interval = 5000
management.rates_mode = detailed
EOF
fi

# Generate advanced.config
echo "Generating advanced.config..."
cat > "$OUTPUT_DIR/advanced.config" << EOF
%% RabbitMQ Advanced Configuration for Environment: $ENVIRONMENT
%% Generated on: $(date)

[
  {rabbit, [
    {cluster_nodes, {['$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_1_HOSTNAME',
                     '$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_2_HOSTNAME',
                     '$RABBITMQ_NODE_NAME_PREFIX@$RABBITMQ_NODE_3_HOSTNAME'], disc}},
    {tcp_listeners, [$RABBITMQ_NODE_PORT]},
    {num_acceptors_tcp, 10},
    {handshake_timeout, 10000},
    {reverse_dns_lookups, false}
EOF

# Add SSL listeners if enabled
if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
    cat >> "$OUTPUT_DIR/advanced.config" << EOF
    ,{ssl_listeners, [5671]},
    {ssl_options, [
      {cacertfile, "$RABBITMQ_SSL_CACERT"},
      {certfile, "$RABBITMQ_SSL_CERT"},
      {keyfile, "$RABBITMQ_SSL_KEY"},
      {verify, $RABBITMQ_SSL_VERIFY},
      {fail_if_no_peer_cert, $RABBITMQ_SSL_FAIL_IF_NO_PEER_CERT}
    ]}
EOF
fi

cat >> "$OUTPUT_DIR/advanced.config" << EOF
  ]},
  {rabbitmq_management, [
    {listener, [
      {port, $RABBITMQ_MANAGEMENT_PORT},
      {ssl, $RABBITMQ_SSL_ENABLED}
EOF

if [ "$RABBITMQ_SSL_ENABLED" = "true" ]; then
    cat >> "$OUTPUT_DIR/advanced.config" << EOF
      ,{ssl_opts, [
        {cacertfile, "$RABBITMQ_SSL_CACERT"},
        {certfile, "$RABBITMQ_SSL_CERT"},
        {keyfile, "$RABBITMQ_SSL_KEY"}
      ]}
EOF
fi

cat >> "$OUTPUT_DIR/advanced.config" << EOF
    ]},
    {rates_mode, basic},
    {sample_retention_policies, [
      {global, [{60, 5}, {3600, 60}, {86400, 1200}]},
      {basic, [{60, 5}, {3600, 60}]},
      {detailed, [{10, 5}]}
    ]}
  ]}
].
EOF

# Generate definitions.json with environment-aware users
echo "Generating definitions.json..."
cat > "$OUTPUT_DIR/definitions.json" << EOF
{
  "rabbit_version": "4.1.0",
  "rabbitmq_version": "4.1.0",
  "product_name": "RabbitMQ",
  "product_version": "4.1.0",
  "users": [
    {
      "name": "$RABBITMQ_DEFAULT_USER",
      "password_hash": "$(echo -n "$RABBITMQ_DEFAULT_PASS" | openssl dgst -sha256 -binary | base64)",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["administrator"],
      "limits": {}
    },
    {
      "name": "$RABBITMQ_CUSTOM_USER_1",
      "password_hash": "$(echo -n "$RABBITMQ_CUSTOM_USER_1_PASS" | openssl dgst -sha256 -binary | base64)",
      "hashing_algorithm": "rabbit_password_hashing_sha256", 
      "tags": ["$RABBITMQ_CUSTOM_USER_1_TAGS"],
      "limits": {}
    },
    {
      "name": "$RABBITMQ_CUSTOM_USER_2",
      "password_hash": "$(echo -n "$RABBITMQ_CUSTOM_USER_2_PASS" | openssl dgst -sha256 -binary | base64)",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": ["$RABBITMQ_CUSTOM_USER_2_TAGS"],
      "limits": {}
    }
  ],
  "vhosts": [
    {
      "name": "/",
      "description": "Default virtual host for $ENVIRONMENT environment",
      "metadata": {
        "environment": "$ENVIRONMENT",
        "cluster": "$RABBITMQ_CLUSTER_NAME"
      }
    }
  ],
  "permissions": [
    {
      "user": "$RABBITMQ_DEFAULT_USER",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "$RABBITMQ_CUSTOM_USER_1",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "$RABBITMQ_CUSTOM_USER_2",
      "vhost": "/",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "topic_permissions": [],
  "parameters": [],
  "global_parameters": [
    {
      "name": "cluster_name",
      "value": "$RABBITMQ_CLUSTER_NAME"
    },
    {
      "name": "environment",
      "value": "$ENVIRONMENT"
    }
  ],
  "policies": [
    {
      "vhost": "/",
      "name": "ha-all-$ENVIRONMENT",
      "pattern": ".*",
      "apply-to": "all",
      "definition": {
        "ha-mode": "all",
        "ha-sync-mode": "automatic",
        "ha-sync-batch-size": 1
      },
      "priority": 0
    }
  ],
  "queues": [],
  "exchanges": [],
  "bindings": []
}
EOF

# Generate environment-specific systemd service file
echo "Generating rabbitmq-server.service..."
cat > "$OUTPUT_DIR/rabbitmq-server.service" << EOF
[Unit]
Description=RabbitMQ broker ($ENVIRONMENT)
After=network.target epmd@0.0.0.0.socket
Wants=network.target epmd@0.0.0.0.socket

[Service]
Type=notify
User=rabbitmq
Group=rabbitmq
NotifyAccess=all
TimeoutStartSec=3600
# Environment variables
Environment=RABBITMQ_ENVIRONMENT=$ENVIRONMENT
Environment=RABBITMQ_CLUSTER_NAME=$RABBITMQ_CLUSTER_NAME
Environment=RABBITMQ_NODENAME=$RABBITMQ_NODE_NAME_PREFIX@%H
Environment=RABBITMQ_USE_LONGNAME=$RABBITMQ_USE_LONGNAME
Environment=RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
Environment=RABBITMQ_MNESIA_BASE=$RABBITMQ_MNESIA_BASE
Environment=RABBITMQ_LOG_BASE=$RABBITMQ_LOG_BASE
# Service execution
ExecStart=/usr/lib/rabbitmq/bin/rabbitmq-server
ExecStop=/usr/lib/rabbitmq/bin/rabbitmqctl shutdown
LimitNOFILE=32768
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Generate environment info file
echo "Generating environment-info.txt..."
cat > "$OUTPUT_DIR/environment-info.txt" << EOF
RabbitMQ Environment Configuration Summary
==========================================

Environment Details:
  Name: $ENVIRONMENT
  Type: $ENVIRONMENT_TYPE
  Generated: $(date)
  Cluster Name: $RABBITMQ_CLUSTER_NAME

Cluster Nodes:
  Node 1: $RABBITMQ_NODE_1_HOSTNAME ($RABBITMQ_NODE_1_IP)
  Node 2: $RABBITMQ_NODE_2_HOSTNAME ($RABBITMQ_NODE_2_IP)  
  Node 3: $RABBITMQ_NODE_3_HOSTNAME ($RABBITMQ_NODE_3_IP)

Network Configuration:
  AMQP Port: $RABBITMQ_NODE_PORT
  Management Port: $RABBITMQ_MANAGEMENT_PORT
  Distribution Port: $RABBITMQ_DIST_PORT
  VIP: ${RABBITMQ_VIP:-Not configured}

Security:
  SSL Enabled: $RABBITMQ_SSL_ENABLED
  Default User: $RABBITMQ_DEFAULT_USER
  Custom Users: $RABBITMQ_CUSTOM_USER_1, $RABBITMQ_CUSTOM_USER_2

Performance:
  Memory High Watermark: $RABBITMQ_VM_MEMORY_HIGH_WATERMARK
  Disk Free Limit: $RABBITMQ_DISK_FREE_LIMIT
  Heartbeat: $RABBITMQ_HEARTBEAT seconds

Generated Files:
  - rabbitmq.conf (Main configuration)
  - advanced.config (Erlang configuration)
  - definitions.json (Users, vhosts, policies)
  - rabbitmq-server.service (Systemd service)
  - environment-info.txt (This file)
EOF

echo ""
echo "✅ Configuration files generated successfully!"
echo ""
echo "Generated files in $OUTPUT_DIR:"
echo "  - rabbitmq.conf"
echo "  - advanced.config"
echo "  - definitions.json"
echo "  - rabbitmq-server.service"
echo "  - environment-info.txt"
echo ""
echo "Next steps:"
echo "  1. Review the generated configuration files"
echo "  2. Deploy to cluster nodes using: ./environment-manager.sh deploy $ENVIRONMENT"
echo "  3. Restart RabbitMQ services to apply new configuration"