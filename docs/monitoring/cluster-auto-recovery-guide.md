# RabbitMQ Cluster Auto-Recovery After Complete Shutdown

## Problem Scenario
When **ALL** RabbitMQ cluster nodes go down simultaneously (complete server reboot, power outage, etc.), the cluster needs specific configuration to automatically recover without manual intervention.

## Root Cause
By default, RabbitMQ waits for the **last node that was shut down** to start first to avoid data loss. When all nodes restart simultaneously, none can determine which was the "last node," causing a deadlock.

## Solution Options

### Option 1: Cluster Formation with Auto-Recovery (Recommended)
Configure the cluster to automatically form on startup using `classic_config` peer discovery.

### Option 2: Force Boot Configuration
Configure automatic force boot for specific scenarios.

### Option 3: Systemd Integration with Dependencies
Use systemd to control startup order and recovery.

## Implementation

### 1. Enhanced Environment Configuration

First, let's update the environment configuration to include auto-recovery settings:

#### Updated Base Environment (environments/base.env)
```bash
# === Auto-Recovery Configuration ===
RABBITMQ_CLUSTER_FORMATION_RETRY_DELAY="30"
RABBITMQ_CLUSTER_FORMATION_RETRY_LIMIT="10"
RABBITMQ_AUTO_RECOVERY_ENABLED="true"
RABBITMQ_AUTO_RECOVERY_DELAY="30"

# === Boot Behavior ===
RABBITMQ_FORCE_BOOT_ON_STARTUP="false"  # Set to true for aggressive recovery
RABBITMQ_STARTUP_TIMEOUT="300"          # 5 minutes timeout for startup

# === Cluster Formation Settings ===
RABBITMQ_CLUSTER_FORMATION_NODE_CLEANUP="true"
RABBITMQ_CLUSTER_FORMATION_LOG_CLEANUP="true"
```

### 2. Auto-Recovery RabbitMQ Configuration

#### Enhanced rabbitmq.conf with Auto-Recovery
```bash
# === Cluster Formation with Auto-Recovery ===
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@${RABBITMQ_NODE_1_HOSTNAME}
cluster_formation.classic_config.nodes.2 = rabbit@${RABBITMQ_NODE_2_HOSTNAME}
cluster_formation.classic_config.nodes.3 = rabbit@${RABBITMQ_NODE_3_HOSTNAME}

# === Auto-Recovery Settings ===
cluster_formation.node_cleanup.only_log_warning = true
cluster_formation.node_cleanup.interval = 30

# === Retry Logic ===
cluster_formation.discovery_retry_limit = 10
cluster_formation.discovery_retry_interval = 30000

# === Startup Behavior ===
# Allow nodes to start even if they can't immediately join cluster
cluster_formation.randomized_startup_delay_range.min = 5
cluster_formation.randomized_startup_delay_range.max = 30

# === Auto-Recovery for Network Issues ===
# Automatically recover from network partitions
cluster_partition_handling = autoheal

# Note: For production, you might prefer pause_minority for data safety
# cluster_partition_handling = pause_minority
```

### 3. Force Boot Recovery Script

Create a script that can automatically force boot the cluster when needed:

```bash
#!/bin/bash
# File: auto-force-boot.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=""
FORCE_BOOT_TIMEOUT=300  # 5 minutes

# Load environment
usage() {
    echo "Auto Force Boot Recovery for RabbitMQ Cluster"
    echo "Usage: $0 -e <environment> [options]"
    echo ""
    echo "Options:"
    echo "  -e <env>     Environment name"
    echo "  -t <timeout> Timeout in seconds (default: 300)"
    echo "  -f           Force boot without waiting"
}

while getopts "e:t:f" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        t) FORCE_BOOT_TIMEOUT="$OPTARG" ;;
        f) FORCE_IMMEDIATE="true" ;;
        *) usage; exit 1 ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    echo "Environment required"
    usage
    exit 1
fi

# Load environment
source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"

echo "=== Auto Force Boot Recovery for $ENVIRONMENT_NAME ==="
echo "Cluster: $RABBITMQ_CLUSTER_NAME"
echo "Nodes: $RABBITMQ_CLUSTER_HOSTNAMES"

# Check if cluster is already operational
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "✅ Cluster is already operational"
    exit 0
fi

echo "🔍 Cluster not responding, initiating recovery..."

# Wait for timeout or force immediate
if [ "$FORCE_IMMEDIATE" != "true" ]; then
    echo "⏳ Waiting ${FORCE_BOOT_TIMEOUT}s for automatic recovery..."
    sleep $FORCE_BOOT_TIMEOUT
    
    # Check again after timeout
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        echo "✅ Cluster recovered automatically"
        exit 0
    fi
fi

echo "🚨 Automatic recovery failed, forcing boot..."

# Stop RabbitMQ application
sudo rabbitmqctl stop_app 2>/dev/null || true

# Force boot
echo "🔧 Force booting cluster..."
sudo rabbitmqctl force_boot

# Start application
echo "🚀 Starting RabbitMQ application..."
sudo rabbitmqctl start_app

# Verify recovery
if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
    echo "✅ Force boot successful, cluster recovered"
    
    # Show cluster status
    sudo rabbitmqctl cluster_status
    
    # Trigger other nodes to rejoin
    echo "📡 Notifying other nodes to rejoin..."
    for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
        if [ "$hostname" != "$(hostname)" ]; then
            echo "Triggering rejoin on $hostname..."
            ssh "root@$hostname" "systemctl restart rabbitmq-server" &
        fi
    done
    
    wait
    echo "✅ All nodes notified to rejoin"
else
    echo "❌ Force boot failed"
    exit 1
fi
```

### 4. Systemd Service with Auto-Recovery

Enhanced systemd service configuration:

```bash
#!/bin/bash
# File: create-auto-recovery-systemd.sh

# Create enhanced systemd service with auto-recovery
create_auto_recovery_service() {
    local environment=$1
    
    # Load environment
    source ./load-environment.sh "$environment"
    
    sudo tee /etc/systemd/system/rabbitmq-server.service << EOF
[Unit]
Description=RabbitMQ broker ($ENVIRONMENT_NAME)
After=network.target epmd@0.0.0.0.socket
Wants=network.target epmd@0.0.0.0.socket
# Wait for other cluster nodes to be reachable
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=rabbitmq
Group=rabbitmq
NotifyAccess=all
TimeoutStartSec=${RABBITMQ_STARTUP_TIMEOUT:-300}
TimeoutStopSec=120

# Environment variables
Environment=RABBITMQ_ENVIRONMENT=$ENVIRONMENT_NAME
Environment=RABBITMQ_CLUSTER_NAME=$RABBITMQ_CLUSTER_NAME
Environment=RABBITMQ_NODENAME=$RABBITMQ_NODE_NAME_PREFIX@%H
Environment=RABBITMQ_USE_LONGNAME=$RABBITMQ_USE_LONGNAME
Environment=RABBITMQ_CONFIG_FILE=/etc/rabbitmq/rabbitmq
Environment=RABBITMQ_MNESIA_BASE=$RABBITMQ_MNESIA_BASE
Environment=RABBITMQ_LOG_BASE=$RABBITMQ_LOG_BASE

# Auto-recovery settings
Environment=RABBITMQ_AUTO_RECOVERY_ENABLED=${RABBITMQ_AUTO_RECOVERY_ENABLED:-true}

# Service execution
ExecStartPre=/bin/sleep 10
ExecStart=/usr/lib/rabbitmq/bin/rabbitmq-server
ExecStop=/usr/lib/rabbitmq/bin/rabbitmqctl shutdown

# Auto-recovery on failure
Restart=always
RestartSec=${RABBITMQ_AUTO_RECOVERY_DELAY:-30}
StartLimitBurst=5
StartLimitIntervalSec=300

# If still failing after retries, run force boot
ExecStartPost=/bin/bash -c 'sleep 60 && if ! /usr/bin/rabbitmqctl cluster_status >/dev/null 2>&1; then /opt/rabbitmq-deployment/auto-force-boot.sh -e $ENVIRONMENT_NAME -f; fi'

# Resource limits
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    echo "Enhanced systemd service created for environment: $ENVIRONMENT_NAME"
}

# Usage
if [ $# -eq 0 ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

create_auto_recovery_service "$1"
```

### 5. Cluster Auto-Recovery Monitor

A monitoring service that detects total cluster failure and triggers recovery:

```bash
#!/bin/bash
# File: cluster-auto-recovery-monitor.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=""
CHECK_INTERVAL=60
RECOVERY_TIMEOUT=300

# Parse arguments
while getopts "e:i:t:" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        i) CHECK_INTERVAL="$OPTARG" ;;
        t) RECOVERY_TIMEOUT="$OPTARG" ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    echo "Environment required: -e <environment>"
    exit 1
fi

# Load environment
source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"

echo "=== Cluster Auto-Recovery Monitor ==="
echo "Environment: $ENVIRONMENT_NAME"
echo "Check Interval: ${CHECK_INTERVAL}s"
echo "Recovery Timeout: ${RECOVERY_TIMEOUT}s"

# Track consecutive failures
consecutive_failures=0
max_failures=3

while true; do
    echo "[$(date)] Checking cluster health..."
    
    # Check if cluster is operational
    if sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
        if [ $consecutive_failures -gt 0 ]; then
            echo "✅ Cluster recovered, resetting failure count"
            consecutive_failures=0
        fi
    else
        consecutive_failures=$((consecutive_failures + 1))
        echo "❌ Cluster check failed (failure $consecutive_failures/$max_failures)"
        
        # If we've hit max failures, trigger recovery
        if [ $consecutive_failures -ge $max_failures ]; then
            echo "🚨 Maximum failures reached, triggering auto-recovery..."
            
            # Check if RabbitMQ service is running but cluster is not formed
            if sudo systemctl is-active rabbitmq-server >/dev/null 2>&1; then
                echo "Service is running but cluster not formed, forcing recovery..."
                "$SCRIPT_DIR/auto-force-boot.sh" -e "$ENVIRONMENT" -t "$RECOVERY_TIMEOUT"
            else
                echo "Service is not running, restarting..."
                sudo systemctl restart rabbitmq-server
                sleep 30
                
                # If still not working, force boot
                if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
                    "$SCRIPT_DIR/auto-force-boot.sh" -e "$ENVIRONMENT" -f
                fi
            fi
            
            # Reset counter after recovery attempt
            consecutive_failures=0
        fi
    fi
    
    sleep $CHECK_INTERVAL
done
```

### 6. Boot Order Management Script

For environments where you want to control boot order:

```bash
#!/bin/bash
# File: managed-cluster-boot.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVIRONMENT=""
BOOT_MODE="auto"  # auto, ordered, force

usage() {
    echo "Managed Cluster Boot for Complete Recovery"
    echo "Usage: $0 -e <environment> -m <mode>"
    echo ""
    echo "Boot Modes:"
    echo "  auto     - Automatic recovery (default)"
    echo "  ordered  - Boot nodes in sequence"
    echo "  force    - Force boot primary then others"
}

while getopts "e:m:" opt; do
    case $opt in
        e) ENVIRONMENT="$OPTARG" ;;
        m) BOOT_MODE="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    usage
    exit 1
fi

# Load environment
source "$SCRIPT_DIR/load-environment.sh" "$ENVIRONMENT"

echo "=== Managed Cluster Boot: $ENVIRONMENT_NAME ==="
echo "Boot Mode: $BOOT_MODE"

case $BOOT_MODE in
    "auto")
        echo "🔄 Starting all nodes simultaneously..."
        for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
            if [ "$hostname" = "$(hostname)" ]; then
                sudo systemctl start rabbitmq-server
            else
                ssh "root@$hostname" "systemctl start rabbitmq-server" &
            fi
        done
        wait
        echo "⏳ Waiting for cluster formation..."
        sleep 60
        ;;
        
    "ordered")
        echo "🔄 Starting nodes in sequence..."
        for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
            echo "Starting $hostname..."
            if [ "$hostname" = "$(hostname)" ]; then
                sudo systemctl start rabbitmq-server
            else
                ssh "root@$hostname" "systemctl start rabbitmq-server"
            fi
            echo "⏳ Waiting 30s before next node..."
            sleep 30
        done
        ;;
        
    "force")
        echo "🔧 Force booting primary node first..."
        
        # Start primary node
        primary_node="$RABBITMQ_NODE_1_HOSTNAME"
        if [ "$primary_node" = "$(hostname)" ]; then
            sudo systemctl start rabbitmq-server
            sleep 30
            if ! sudo rabbitmqctl cluster_status >/dev/null 2>&1; then
                sudo rabbitmqctl force_boot
                sudo rabbitmqctl start_app
            fi
        else
            ssh "root@$primary_node" "systemctl start rabbitmq-server"
            sleep 30
            ssh "root@$primary_node" "if ! rabbitmqctl cluster_status >/dev/null 2>&1; then rabbitmqctl force_boot && rabbitmqctl start_app; fi"
        fi
        
        echo "🔄 Starting secondary nodes..."
        for hostname in $RABBITMQ_CLUSTER_HOSTNAMES; do
            if [ "$hostname" != "$primary_node" ]; then
                echo "Starting $hostname..."
                if [ "$hostname" = "$(hostname)" ]; then
                    sudo systemctl start rabbitmq-server
                else
                    ssh "root@$hostname" "systemctl start rabbitmq-server"
                fi
                sleep 15
            fi
        done
        ;;
esac

# Verify cluster
echo "🔍 Verifying cluster formation..."
sleep 30

if sudo rabbitmqctl cluster_status; then
    echo "✅ Cluster recovery successful!"
else
    echo "❌ Cluster recovery failed, manual intervention required"
    exit 1
fi
```

## Configuration Summary

### For Automatic Recovery (Recommended)

1. **Use `autoheal` partition handling** for automatic recovery:
   ```bash
   cluster_partition_handling = autoheal
   ```

2. **Configure cluster formation retry logic**:
   ```bash
   cluster_formation.discovery_retry_limit = 10
   cluster_formation.discovery_retry_interval = 30000
   ```

3. **Enable randomized startup delays**:
   ```bash
   cluster_formation.randomized_startup_delay_range.min = 5
   cluster_formation.randomized_startup_delay_range.max = 30
   ```

4. **Use enhanced systemd service** with auto-restart and force boot fallback

### For Data Safety (Production)

1. **Use `pause_minority`** with manual force boot when needed:
   ```bash
   cluster_partition_handling = pause_minority
   ```

2. **Deploy auto-recovery monitor** to detect total failures

3. **Use managed boot script** for controlled recovery

## Quick Setup Commands

```bash
# Make scripts executable
chmod +x auto-force-boot.sh
chmod +x cluster-auto-recovery-monitor.sh
chmod +x managed-cluster-boot.sh
chmod +x create-auto-recovery-systemd.sh

# Create auto-recovery systemd service
./create-auto-recovery-systemd.sh prod

# Start auto-recovery monitor (optional)
./cluster-auto-recovery-monitor.sh -e prod &

# Manual recovery when needed
./managed-cluster-boot.sh -e prod -m force
```

## Recommendations

### For Development/QA
- Use `autoheal` partition handling
- Enable automatic systemd restart
- Use auto-recovery monitor

### For Production
- Use `pause_minority` for data safety
- Deploy recovery monitor
- Have manual recovery procedures ready
- Use managed boot for controlled recovery

This comprehensive auto-recovery system ensures your RabbitMQ cluster can automatically recover from complete shutdowns while maintaining data integrity based on your environment requirements.