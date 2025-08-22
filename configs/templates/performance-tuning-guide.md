# RabbitMQ 4.1.x Performance Tuning Guide

## Overview
This comprehensive guide provides performance optimization strategies for RabbitMQ 4.1.x clusters, covering configuration tuning, system optimization, and monitoring for maximum throughput and minimal latency.

## Performance Metrics and Targets

### Key Performance Indicators (KPIs)
- **Throughput**: Messages per second (msg/s)
- **Latency**: Message delivery time (ms)
- **Memory Usage**: RAM utilization (%)
- **CPU Usage**: Processor utilization (%)
- **Disk I/O**: Read/write operations per second (IOPS)
- **Network**: Bandwidth utilization (Mbps)

### Performance Targets
| Workload Type | Throughput | Latency | Memory | CPU |
|---------------|------------|---------|---------|-----|
| **High Throughput** | 100K+ msg/s | < 10ms | < 70% | < 80% |
| **Low Latency** | 50K+ msg/s | < 5ms | < 60% | < 70% |
| **Balanced** | 75K+ msg/s | < 8ms | < 65% | < 75% |

## System-Level Optimizations

### CPU Configuration
```bash
#!/bin/bash
# File: optimize-cpu-performance.sh

set -e

echo "=== CPU Performance Optimization ==="

# Check CPU information
echo "CPU Information:"
lscpu | grep -E "(CPU\(s\)|Thread|Core|Socket)"

# Set CPU governor to performance
echo "Setting CPU governor to performance..."
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -f "$cpu" ]; then
        echo performance | sudo tee "$cpu" >/dev/null
    fi
done

# Disable CPU frequency scaling
echo "Disabling CPU frequency scaling..."
sudo systemctl disable cpupower

# Set CPU affinity for RabbitMQ process
echo "Configuring CPU affinity..."
sudo tee /etc/systemd/system/rabbitmq-server.service.d/cpu-affinity.conf << 'EOF'
[Service]
# Bind RabbitMQ to specific CPU cores (adjust based on your system)
ExecStart=
ExecStart=/bin/sh -c 'taskset -c 0-3 /usr/lib/rabbitmq/bin/rabbitmq-server'
EOF

# Enable NUMA balancing
echo "Optimizing NUMA settings..."
echo 1 | sudo tee /proc/sys/kernel/numa_balancing

# Set process scheduler
echo "Configuring process scheduler..."
sudo tee -a /etc/sysctl.d/99-rabbitmq-performance.conf << 'EOF'
# CPU scheduling optimizations
kernel.sched_min_granularity_ns = 2250000
kernel.sched_wakeup_granularity_ns = 3000000
kernel.sched_migration_cost_ns = 500000
EOF

sudo sysctl -p /etc/sysctl.d/99-rabbitmq-performance.conf

echo "CPU optimization completed!"
```

### Memory Optimization
```bash
#!/bin/bash
# File: optimize-memory-performance.sh

set -e

echo "=== Memory Performance Optimization ==="

# Get total system memory
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
echo "Total RAM: ${TOTAL_RAM_GB}GB"

# Calculate optimal settings based on RAM
RABBITMQ_RAM_GB=$((TOTAL_RAM_GB * 60 / 100))  # 60% of total RAM
VM_MEMORY_HIGH_WATERMARK="0.6"

echo "Recommended RabbitMQ RAM allocation: ${RABBITMQ_RAM_GB}GB"

# Configure memory settings
sudo tee -a /etc/sysctl.d/99-rabbitmq-performance.conf << EOF

# Memory management optimizations
vm.swappiness = 1
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 500
vm.overcommit_memory = 1
vm.overcommit_ratio = 50

# Memory allocation optimization
vm.min_free_kbytes = 1048576
vm.zone_reclaim_mode = 0
vm.vfs_cache_pressure = 50

# Huge pages configuration
vm.nr_hugepages = 512
EOF

# Disable transparent huge pages for better performance
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent
sudo tee -a /etc/rc.local << 'EOF'
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF

sudo chmod +x /etc/rc.local

# Configure swap if needed
if [ $TOTAL_RAM_GB -lt 16 ]; then
    echo "System has less than 16GB RAM, optimizing swap..."
    sudo sysctl vm.swappiness=10
else
    echo "System has sufficient RAM, minimizing swap usage..."
    sudo sysctl vm.swappiness=1
fi

echo "Memory optimization completed!"
```

### Network Optimization
```bash
#!/bin/bash
# File: optimize-network-performance.sh

set -e

echo "=== Network Performance Optimization ==="

# High-performance network settings
sudo tee -a /etc/sysctl.d/99-rabbitmq-performance.conf << 'EOF'

# Network performance optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 67108864
net.core.wmem_default = 262144
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600
net.core.somaxconn = 65535

# TCP optimizations
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1

# Connection tracking optimizations
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_buckets = 524288
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30

# Buffer optimizations
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
EOF

# Apply settings
sudo sysctl -p /etc/sysctl.d/99-rabbitmq-performance.conf

# Configure network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Optimizing network interface: $INTERFACE"

# Set network interface parameters
sudo ethtool -G $INTERFACE rx 4096 tx 4096 2>/dev/null || true
sudo ethtool -K $INTERFACE gso on tso on ufo on 2>/dev/null || true

echo "Network optimization completed!"
```

### Disk I/O Optimization
```bash
#!/bin/bash
# File: optimize-disk-performance.sh

set -e

echo "=== Disk I/O Performance Optimization ==="

# Detect RabbitMQ data directory
RABBITMQ_DATA_DIR="/var/lib/rabbitmq"
RABBITMQ_LOG_DIR="/var/log/rabbitmq"

# Get block devices for RabbitMQ directories
DATA_DEVICE=$(df "$RABBITMQ_DATA_DIR" | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
LOG_DEVICE=$(df "$RABBITMQ_LOG_DIR" | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')

echo "RabbitMQ data device: $DATA_DEVICE"
echo "RabbitMQ log device: $LOG_DEVICE"

# Set I/O scheduler
if [ -f "/sys/block/$(basename $DATA_DEVICE)/queue/scheduler" ]; then
    echo "Setting I/O scheduler for data device..."
    
    # Check if device is SSD or HDD
    if [ "$(cat /sys/block/$(basename $DATA_DEVICE)/queue/rotational)" = "0" ]; then
        echo "SSD detected, using noop scheduler"
        echo noop | sudo tee /sys/block/$(basename $DATA_DEVICE)/queue/scheduler
    else
        echo "HDD detected, using deadline scheduler"
        echo deadline | sudo tee /sys/block/$(basename $DATA_DEVICE)/queue/scheduler
    fi
fi

# Optimize disk I/O settings
sudo tee -a /etc/sysctl.d/99-rabbitmq-performance.conf << 'EOF'

# Disk I/O optimizations
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 500
EOF

# Configure readahead for better sequential I/O
sudo blockdev --setra 4096 $DATA_DEVICE
sudo blockdev --setra 4096 $LOG_DEVICE

# Create optimized mount options
echo "Recommended mount options for $RABBITMQ_DATA_DIR:"
echo "  noatime,nodiratime,nobarrier,data=writeback,commit=30"

echo "Disk I/O optimization completed!"
```

## RabbitMQ Configuration Optimizations

### High-Performance Configuration Template
```bash
#!/bin/bash
# File: generate-performance-config.sh

set -e

NODE_NAME=$(hostname)
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

echo "=== Generating High-Performance RabbitMQ Configuration ==="
echo "Node: $NODE_NAME"
echo "RAM: ${TOTAL_RAM_GB}GB"
echo "CPU Cores: $CPU_CORES"

# Calculate optimal settings
VM_MEMORY_HIGH_WATERMARK="0.6"
CHANNEL_MAX=$((CPU_CORES * 512))
CONNECTION_MAX=$((CPU_CORES * 1024))
DELEGATE_COUNT=$((CPU_CORES * 4))

cat > /etc/rabbitmq/rabbitmq-performance.conf << EOF
# High-Performance RabbitMQ Configuration
# Generated for: $NODE_NAME (${TOTAL_RAM_GB}GB RAM, ${CPU_CORES} CPU cores)

# Memory Management
vm_memory_high_watermark.relative = $VM_MEMORY_HIGH_WATERMARK
vm_memory_calculation_strategy = rss
disk_free_limit.relative = 1.5

# Connection and Channel Limits
channel_max = $CHANNEL_MAX
connection_max = $CONNECTION_MAX
frame_max = 131072

# Network Configuration
heartbeat = 60
tcp_listen_options.nodelay = true
tcp_listen_options.keepalive = true
tcp_listen_options.send_timeout = 15000
tcp_listen_options.send_timeout_close = true

# Queue Configuration
default_queue_type = quorum
quorum_commands_soft_limit = 256
queue_index_embed_msgs_below = 4096

# Clustering Performance
collect_statistics_interval = 5000
delegate_count = $DELEGATE_COUNT
cluster_keepalive_interval = 10000

# Garbage Collection Optimization
collect_statistics = coarse
rates_mode = basic

# Log Configuration for Performance
log.console = false
log.file = /var/log/rabbitmq/rabbit.log
log.file.level = info
log.file.rotation.size = 10485760

# Lazy Queue Configuration
lazy_queue_explicit_gc_run_operation_threshold = 1000

# Message Store Configuration
msg_store_file_size_limit = 16777216
msg_store_credit_disc_bound = 4000

# Plugin Configuration
management.rates_mode = basic
management.sample_retention_policies.global.minute = 5
management.sample_retention_policies.global.hour = 60
management.sample_retention_policies.global.day = 1200

# Advanced Performance Settings
credit_flow_default_credit = 400
channel_operation_timeout = 15000
EOF

echo "High-performance configuration created: /etc/rabbitmq/rabbitmq-performance.conf"
echo "Include this file in your main rabbitmq.conf"
```

### Advanced Performance Configuration
```erlang
#!/bin/bash
# File: generate-advanced-performance-config.sh

CPU_CORES=$(nproc)
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')

cat > /etc/rabbitmq/advanced-performance.config << EOF
[
  {rabbit, [
    %% High-performance settings
    {tcp_listeners, [5672]},
    {num_tcp_acceptors, $(($CPU_CORES * 2))},
    {handshake_timeout, 10000},
    
    %% Memory and GC optimizations
    {vm_memory_high_watermark, 0.6},
    {vm_memory_calculation_strategy, rss},
    {disk_free_limit, {mem_relative, 1.5}},
    
    %% Connection management
    {channel_max, $(($CPU_CORES * 512))},
    {connection_max, $(($CPU_CORES * 1024))},
    {heartbeat, 60},
    
    %% Queue optimizations
    {default_queue_type, quorum},
    {quorum_commands_soft_limit, 256},
    {queue_index_embed_msgs_below, 4096},
    
    %% Clustering performance
    {delegate_count, $(($CPU_CORES * 4))},
    {cluster_keepalive_interval, 10000},
    
    %% Statistics collection
    {collect_statistics_interval, 5000},
    {collect_statistics, coarse},
    
    %% Message store optimization
    {msg_store_file_size_limit, 16777216},
    {msg_store_credit_disc_bound, 4000},
    
    %% Credit flow settings
    {credit_flow_default_credit, 400},
    
    %% Lazy queue optimization
    {lazy_queue_explicit_gc_run_operation_threshold, 1000},
    
    %% TCP buffer sizes
    {tcp_listen_options, [
      {nodelay, true},
      {keepalive, true},
      {send_timeout, 15000},
      {send_timeout_close, true},
      {sndbuf, 131072},
      {recbuf, 131072}
    ]}
  ]},
  
  {rabbitmq_management, [
    %% Management performance settings
    {rates_mode, basic},
    {sample_retention_policies, [
      {global, [
        {60, 5},    %% 5 minutes of 1-second samples
        {3600, 60}, %% 1 hour of 1-minute samples  
        {86400, 1200} %% 1 day of 20-minute samples
      ]}
    ]}
  ]},
  
  {kernel, [
    %% Erlang VM optimizations
    {inet_default_connect_options, [
      {nodelay, true},
      {keepalive, true},
      {send_timeout, 15000},
      {send_timeout_close, true}
    ]},
    
    %% Distribution settings
    {inet_dist_listen_min, 25672},
    {inet_dist_listen_max, 25672},
    
    %% Network buffer sizes
    {inet_default_listen_options, [
      {nodelay, true},
      {keepalive, true},
      {sndbuf, 131072},
      {recbuf, 131072}
    ]}
  ]},
  
  {mnesia, [
    %% Mnesia performance optimization
    {dump_log_write_threshold, 50000},
    {dc_dump_limit, 40}
  ]}
].
EOF

echo "Advanced performance configuration created"
```

## Erlang VM Optimizations

### Erlang VM Tuning Script
```bash
#!/bin/bash
# File: optimize-erlang-vm.sh

set -e

CPU_CORES=$(nproc)
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')

echo "=== Erlang VM Performance Optimization ==="

# Calculate optimal Erlang VM settings
SCHEDULERS=$CPU_CORES
ASYNC_THREADS=$((CPU_CORES * 2))
MAX_PROCESSES=2097152
MAX_ATOMS=2097152

# Create Erlang VM environment configuration
sudo tee /etc/default/rabbitmq-server << EOF
# Erlang VM Performance Optimizations

# Scheduler configuration
export ERL_FLAGS="+S $SCHEDULERS:$SCHEDULERS +A $ASYNC_THREADS +P $MAX_PROCESSES +t $MAX_ATOMS"

# Memory management
export ERL_FLAGS="\$ERL_FLAGS +hms 2048 +hmbs 2048 +MMmcs 30"

# Garbage collection optimization
export ERL_FLAGS="\$ERL_FLAGS +scl false +sub true"

# I/O optimization  
export ERL_FLAGS="\$ERL_FLAGS +K true +swt very_low"

# Network optimization
export ERL_FLAGS="\$ERL_FLAGS +e 262144"

# Process optimization
export ERL_FLAGS="\$ERL_FLAGS +Q 262144"

# Memory allocator tuning
export ERL_FLAGS="\$ERL_FLAGS +MBas ageffcbf +MHas ageffcbf +MBlmbcs 512 +MHlmbcs 512"

# Additional performance flags
export ERL_FLAGS="\$ERL_FLAGS +W w +K true"

# Set process limits
ulimit -n 300000
ulimit -u 300000
EOF

echo "Erlang VM optimization completed!"
echo "Restart RabbitMQ to apply changes: sudo systemctl restart rabbitmq-server"
```

## Queue and Exchange Optimizations

### High-Performance Queue Policies
```bash
#!/bin/bash
# File: setup-performance-policies.sh

set -e

echo "=== Setting up High-Performance Queue Policies ==="

# High-throughput policy for bulk processing
sudo rabbitmqctl set_policy high-throughput \
    "^high-throughput\." \
    '{"queue-type":"quorum","max-length":100000,"overflow":"reject-publish","delivery-limit":3}' \
    --priority 10 --apply-to queues

# Low-latency policy for real-time processing  
sudo rabbitmqctl set_policy low-latency \
    "^low-latency\." \
    '{"queue-type":"quorum","max-length":10000,"overflow":"drop-head","delivery-limit":5}' \
    --priority 20 --apply-to queues

# Lazy queue policy for large message backlogs
sudo rabbitmqctl set_policy lazy-queue \
    "^lazy\." \
    '{"queue-mode":"lazy","queue-type":"quorum","max-length":1000000}' \
    --priority 15 --apply-to queues

# HA policy for critical queues
sudo rabbitmqctl set_policy ha-critical \
    "^critical\." \
    '{"ha-mode":"exactly","ha-params":3,"ha-sync-mode":"automatic","queue-type":"quorum"}' \
    --priority 25 --apply-to queues

echo "Performance policies created successfully!"
```

## Monitoring and Performance Analysis

### Performance Monitoring Script
```bash
#!/bin/bash
# File: monitor-performance.sh

INTERVAL=5
LOG_FILE="/var/log/rabbitmq/performance-monitor.log"

echo "=== RabbitMQ Performance Monitor ==="
echo "Monitoring interval: ${INTERVAL}s"
echo "Log file: $LOG_FILE"

# Create log header
echo "$(date '+%Y-%m-%d %H:%M:%S'),CPU%,Memory%,Messages/s,Connections,Channels,Queues,Disk_Free_GB" > $LOG_FILE

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # System metrics
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    MEMORY_USAGE=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100.0}')
    
    # RabbitMQ metrics
    MESSAGES_RATE=$(sudo rabbitmqctl eval 'rabbit_mgmt_db:get_overview().' 2>/dev/null | \
        grep -o '"publish_details":{[^}]*}' | grep -o '"rate":[0-9.]*' | cut -d: -f2 || echo "0")
    
    CONNECTIONS=$(sudo rabbitmqctl list_connections | wc -l)
    CHANNELS=$(sudo rabbitmqctl list_channels | wc -l)
    QUEUES=$(sudo rabbitmqctl list_queues | wc -l)
    
    # Disk space
    DISK_FREE=$(df /var/lib/rabbitmq | tail -1 | awk '{printf "%.2f", $4/1024/1024}')
    
    # Log metrics
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,$MESSAGES_RATE,$CONNECTIONS,$CHANNELS,$QUEUES,$DISK_FREE" >> $LOG_FILE
    
    # Display current metrics
    printf "\r%s | CPU: %s%% | Mem: %s%% | Msg/s: %s | Conn: %s | Ch: %s | Q: %s | Disk: %sGB" \
        "$TIMESTAMP" "$CPU_USAGE" "$MEMORY_USAGE" "$MESSAGES_RATE" "$CONNECTIONS" "$CHANNELS" "$QUEUES" "$DISK_FREE"
    
    sleep $INTERVAL
done
```

### Performance Analysis Script
```bash
#!/bin/bash
# File: analyze-performance.sh

LOG_FILE="/var/log/rabbitmq/performance-monitor.log"
REPORT_FILE="/tmp/rabbitmq-performance-report.txt"

echo "=== RabbitMQ Performance Analysis ==="

if [ ! -f "$LOG_FILE" ]; then
    echo "Performance log file not found: $LOG_FILE"
    exit 1
fi

# Generate performance report
cat > $REPORT_FILE << EOF
RabbitMQ Performance Analysis Report
Generated: $(date)
Data Source: $LOG_FILE

=== Summary Statistics ===
EOF

# Calculate averages (skip header line)
tail -n +2 "$LOG_FILE" | awk -F, '
{
    cpu_sum += $2; mem_sum += $3; msg_sum += $4; 
    conn_sum += $5; ch_sum += $6; q_sum += $7; disk_sum += $8; 
    count++
}
END {
    if (count > 0) {
        printf "Average CPU Usage: %.1f%%\n", cpu_sum/count
        printf "Average Memory Usage: %.1f%%\n", mem_sum/count  
        printf "Average Message Rate: %.1f msg/s\n", msg_sum/count
        printf "Average Connections: %.0f\n", conn_sum/count
        printf "Average Channels: %.0f\n", ch_sum/count
        printf "Average Queues: %.0f\n", q_sum/count
        printf "Average Disk Free: %.1f GB\n", disk_sum/count
    }
}' >> $REPORT_FILE

# Find peak values
echo "" >> $REPORT_FILE
echo "=== Peak Values ===" >> $REPORT_FILE

tail -n +2 "$LOG_FILE" | awk -F, '
BEGIN { max_cpu=0; max_mem=0; max_msg=0; max_conn=0 }
{
    if ($2 > max_cpu) { max_cpu = $2; max_cpu_time = $1 }
    if ($3 > max_mem) { max_mem = $3; max_mem_time = $1 }
    if ($4 > max_msg) { max_msg = $4; max_msg_time = $1 }
    if ($5 > max_conn) { max_conn = $5; max_conn_time = $1 }
}
END {
    printf "Peak CPU: %.1f%% at %s\n", max_cpu, max_cpu_time
    printf "Peak Memory: %.1f%% at %s\n", max_mem, max_mem_time
    printf "Peak Message Rate: %.1f msg/s at %s\n", max_msg, max_msg_time
    printf "Peak Connections: %.0f at %s\n", max_conn, max_conn_time
}' >> $REPORT_FILE

# Performance recommendations
echo "" >> $REPORT_FILE
echo "=== Performance Recommendations ===" >> $REPORT_FILE

# Analyze CPU usage
AVG_CPU=$(tail -n +2 "$LOG_FILE" | awk -F, '{sum+=$2; count++} END {print sum/count}')
if (( $(echo "$AVG_CPU > 80" | bc -l) )); then
    echo "⚠ HIGH CPU USAGE: Consider adding more CPU cores or optimizing message processing" >> $REPORT_FILE
elif (( $(echo "$AVG_CPU > 60" | bc -l) )); then
    echo "⚠ MODERATE CPU USAGE: Monitor CPU usage trends and consider scaling" >> $REPORT_FILE
else
    echo "✓ CPU usage is within acceptable range" >> $REPORT_FILE
fi

# Analyze memory usage
AVG_MEM=$(tail -n +2 "$LOG_FILE" | awk -F, '{sum+=$3; count++} END {print sum/count}')
if (( $(echo "$AVG_MEM > 70" | bc -l) )); then
    echo "⚠ HIGH MEMORY USAGE: Consider increasing RAM or adjusting vm_memory_high_watermark" >> $REPORT_FILE
elif (( $(echo "$AVG_MEM > 50" | bc -l) )); then
    echo "⚠ MODERATE MEMORY USAGE: Monitor memory trends" >> $REPORT_FILE
else
    echo "✓ Memory usage is within acceptable range" >> $REPORT_FILE
fi

echo "Performance analysis completed: $REPORT_FILE"
cat $REPORT_FILE
```

## Load Testing and Benchmarking

### Performance Load Test Script
```bash
#!/bin/bash
# File: load-test-performance.sh

set -e

echo "=== RabbitMQ Performance Load Test ==="

# Test parameters
RABBITMQ_HOST="localhost"
RABBITMQ_PORT="5672"
RABBITMQ_USER="teja"
RABBITMQ_PASS="Teja@2024"
TEST_DURATION=300  # 5 minutes
PRODUCER_THREADS=10
CONSUMER_THREADS=10
MESSAGE_SIZE=1024

# Install perf-test if not available
if ! command -v rabbitmq-perf-test >/dev/null 2>&1; then
    echo "Installing RabbitMQ perf-test tool..."
    wget -O /tmp/perf-test.jar https://github.com/rabbitmq/rabbitmq-perf-test/releases/latest/download/perf-test-latest.jar
    PERF_TEST="java -jar /tmp/perf-test.jar"
else
    PERF_TEST="rabbitmq-perf-test"
fi

# High throughput test
echo "Running high throughput test..."
$PERF_TEST \
    --uri amqp://$RABBITMQ_USER:$RABBITMQ_PASS@$RABBITMQ_HOST:$RABBITMQ_PORT \
    --queue-pattern 'perf-test-high-throughput-%d' \
    --queue-pattern-from 1 \
    --queue-pattern-to 5 \
    --producers $PRODUCER_THREADS \
    --consumers $CONSUMER_THREADS \
    --time $TEST_DURATION \
    --size $MESSAGE_SIZE \
    --rate 10000 \
    --auto-ack false \
    --confirm 100 \
    --output-file /tmp/high-throughput-test.txt

# Low latency test
echo "Running low latency test..."
$PERF_TEST \
    --uri amqp://$RABBITMQ_USER:$RABBITMQ_PASS@$RABBITMQ_HOST:$RABBITMQ_PORT \
    --queue-pattern 'perf-test-low-latency-%d' \
    --queue-pattern-from 1 \
    --queue-pattern-to 3 \
    --producers 5 \
    --consumers 5 \
    --time $TEST_DURATION \
    --size 256 \
    --rate 1000 \
    --auto-ack false \
    --confirm 10 \
    --latency \
    --output-file /tmp/low-latency-test.txt

# Connection stress test
echo "Running connection stress test..."
$PERF_TEST \
    --uri amqp://$RABBITMQ_USER:$RABBITMQ_PASS@$RABBITMQ_HOST:$RABBITMQ_PORT \
    --queue-pattern 'perf-test-connection-stress' \
    --producers 100 \
    --consumers 100 \
    --time 60 \
    --size 512 \
    --rate 100 \
    --output-file /tmp/connection-stress-test.txt

echo "Load testing completed!"
echo "Results saved in /tmp/*test.txt files"
```

## Troubleshooting Performance Issues

### Performance Issue Diagnostic Script
```bash
#!/bin/bash
# File: diagnose-performance-issues.sh

echo "=== RabbitMQ Performance Diagnostics ==="

# System resource check
echo "1. System Resources:"
echo "   CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
echo "   Memory Usage: $(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100.0}')"
echo "   Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo "   Disk I/O: $(iostat -x 1 1 | tail -n +4 | awk '{print $1, $10"%"}' | head -5)"

# RabbitMQ status check
echo "2. RabbitMQ Status:"
sudo rabbitmqctl status | grep -E "(memory|file_descriptors|sockets)"

# Queue analysis
echo "3. Queue Analysis:"
echo "   Total Queues: $(sudo rabbitmqctl list_queues | wc -l)"
echo "   Queues with messages:"
sudo rabbitmqctl list_queues name messages | awk '$2 > 0 {print "     " $1 ": " $2 " messages"}'

# Connection analysis
echo "4. Connection Analysis:"
echo "   Total Connections: $(sudo rabbitmqctl list_connections | wc -l)"
echo "   Total Channels: $(sudo rabbitmqctl list_channels | wc -l)"

# Memory analysis
echo "5. Memory Analysis:"
sudo rabbitmqctl eval 'rabbit_vm:memory().' | grep -E "(total|processes|system)"

# Performance bottleneck detection
echo "6. Potential Bottlenecks:"

# Check for memory alarms
if sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' | grep -q "memory"; then
    echo "   ⚠ MEMORY ALARM: RabbitMQ memory usage is high"
fi

# Check for disk alarms
if sudo rabbitmqctl eval 'rabbit_alarm:get_alarms().' | grep -q "disk"; then
    echo "   ⚠ DISK ALARM: Disk space is low"
fi

# Check for high queue depths
MAX_MESSAGES=$(sudo rabbitmqctl list_queues messages | tail -n +2 | sort -nr | head -1)
if [ "$MAX_MESSAGES" -gt 10000 ]; then
    echo "   ⚠ HIGH QUEUE DEPTH: Maximum queue depth is $MAX_MESSAGES messages"
fi

# Check file descriptor usage
FD_USED=$(sudo rabbitmqctl status | grep file_descriptors | awk '{print $3}' | tr -d ',')
FD_LIMIT=$(sudo rabbitmqctl status | grep file_descriptors | awk '{print $5}' | tr -d '}')
if [ "$FD_USED" -gt $((FD_LIMIT * 80 / 100)) ]; then
    echo "   ⚠ HIGH FILE DESCRIPTOR USAGE: $FD_USED/$FD_LIMIT ($(($FD_USED * 100 / FD_LIMIT))%)"
fi

echo "Performance diagnostics completed!"
```

This comprehensive performance tuning guide provides the tools and configurations needed to optimize RabbitMQ 4.1.x for maximum throughput, minimal latency, and efficient resource utilization across any cluster size.