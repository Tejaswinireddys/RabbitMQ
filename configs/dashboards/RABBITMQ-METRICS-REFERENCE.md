# RabbitMQ Metrics Reference Guide

This comprehensive guide covers all RabbitMQ metrics available through the Prometheus plugin, organized by category and use case.

## 📊 Core RabbitMQ Metrics

### **Queue Metrics**

#### **Message Counts**
```promql
# Current messages in queue
rabbitmq_queue_messages

# Messages ready for delivery
rabbitmq_queue_messages_ready

# Messages unacknowledged
rabbitmq_queue_messages_unacknowledged
```

#### **Message Rates**
```promql
# Message publishing rate
rate(rabbitmq_queue_messages_published_total[1m])

# Message delivery rate
rate(rabbitmq_queue_messages_delivered_total[1m])

# Message acknowledgment rate
rate(rabbitmq_queue_messages_ack_total[1m])

# Message redelivery rate
rate(rabbitmq_queue_messages_redelivered_total[1m])
```

#### **Queue Performance**
```promql
# Consumer count per queue
rabbitmq_queue_consumers

# Queue processing efficiency
rate(rabbitmq_queue_messages_delivered_total[1m]) / rate(rabbitmq_queue_messages_published_total[1m]) * 100

# Queue error rate
rate(rabbitmq_queue_messages_redelivered_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100

# Queue processing latency
rabbitmq_queue_messages / rate(rabbitmq_queue_messages_delivered_total[1m])
```

### **Connection Metrics**

#### **Connection Counts**
```promql
# Total active connections
rabbitmq_connections_total

# Connection rate
rate(rabbitmq_connections_total[1m])

# Connection churn rate
abs(rate(rabbitmq_connections_total[1m]))
```

#### **Connection Health**
```promql
# Connection stability
stddev(rabbitmq_connections_total[5m])

# Connection distribution
rabbitmq_connections_total by (node)
```

### **Channel Metrics**

#### **Channel Counts**
```promql
# Total active channels
rabbitmq_channels_total

# Channel rate
rate(rabbitmq_channels_total[1m])

# Channel churn rate
abs(rate(rabbitmq_channels_total[1m]))
```

#### **Channel Performance**
```promql
# Channels per connection ratio
rabbitmq_channels_total / rabbitmq_connections_total

# Channel distribution
rabbitmq_channels_total by (node)
```

### **Node Metrics**

#### **Memory Usage**
```promql
# Memory used by RabbitMQ
rabbitmq_node_mem_used

# Memory limit
rabbitmq_node_mem_limit

# Memory usage percentage
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100

# Available memory
rabbitmq_node_mem_limit - rabbitmq_node_mem_used
```

#### **Disk Usage**
```promql
# Free disk space
rabbitmq_node_disk_free

# Disk space limit
rabbitmq_node_disk_free_limit

# Disk usage percentage
(rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free) / rabbitmq_node_disk_free_limit * 100

# Used disk space
rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free
```

#### **Process Metrics**
```promql
# Erlang process count
rabbitmq_node_processes

# File descriptors used
rabbitmq_node_fd_used

# File descriptors total
rabbitmq_node_fd_total

# File descriptor usage percentage
rabbitmq_node_fd_used / rabbitmq_node_fd_total * 100
```

### **Cluster Metrics**

#### **Node Status**
```promql
# Node running status (1=running, 0=stopped)
rabbitmq_node_is_running

# Total nodes in cluster
count(rabbitmq_node_is_running)

# Running nodes
sum(rabbitmq_node_is_running)

# Cluster health percentage
sum(rabbitmq_node_is_running) / count(rabbitmq_node_is_running) * 100
```

#### **Cluster Partitions**
```promql
# Number of cluster partitions
rabbitmq_cluster_partitions

# Partition status (0=healthy, >0=partitioned)
rabbitmq_cluster_partitions
```

## 🎯 Advanced Metrics & Calculations

### **Throughput Analysis**

#### **Message Throughput**
```promql
# Total message throughput
sum(rate(rabbitmq_queue_messages_published_total[1m]))

# Throughput by queue
rate(rabbitmq_queue_messages_published_total[1m]) by (queue)

# Throughput by node
sum(rate(rabbitmq_queue_messages_published_total[1m])) by (node)
```

#### **Processing Efficiency**
```promql
# Overall processing efficiency
sum(rate(rabbitmq_queue_messages_delivered_total[1m])) / sum(rate(rabbitmq_queue_messages_published_total[1m])) * 100

# Efficiency by queue
rate(rabbitmq_queue_messages_delivered_total[1m]) / rate(rabbitmq_queue_messages_published_total[1m]) * 100
```

### **Performance Metrics**

#### **Latency Analysis**
```promql
# Average processing time
rabbitmq_queue_messages / rate(rabbitmq_queue_messages_delivered_total[1m])

# Queue depth analysis
rabbitmq_queue_messages

# Consumer efficiency
rabbitmq_queue_consumers / rabbitmq_queue_messages
```

#### **Resource Utilization**
```promql
# Memory efficiency
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100

# Disk efficiency
(rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free) / rabbitmq_node_disk_free_limit * 100

# Process efficiency
rabbitmq_node_processes / rabbitmq_node_fd_total * 100
```

### **Error Analysis**

#### **Error Rates**
```promql
# Message error rate
rate(rabbitmq_queue_messages_redelivered_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100

# Connection error rate
abs(rate(rabbitmq_connections_total[1m])) / rabbitmq_connections_total * 100

# Channel error rate
abs(rate(rabbitmq_channels_total[1m])) / rabbitmq_channels_total * 100
```

#### **Failure Analysis**
```promql
# Node failure rate
(1 - rabbitmq_node_is_running) * 100

# Cluster partition rate
rabbitmq_cluster_partitions > 0
```

## 📈 Dashboard-Specific Metrics

### **Queue Performance Dashboard**
```promql
# Queue message counts
rabbitmq_queue_messages

# Queue consumer counts
rabbitmq_queue_consumers

# Message publishing rate
rate(rabbitmq_queue_messages_published_total[1m])

# Message delivery rate
rate(rabbitmq_queue_messages_delivered_total[1m])

# Message acknowledgment rate
rate(rabbitmq_queue_messages_ack_total[1m])

# Message redelivery rate
rate(rabbitmq_queue_messages_redelivered_total[1m])

# Queue processing efficiency
rate(rabbitmq_queue_messages_delivered_total[1m]) / rate(rabbitmq_queue_messages_published_total[1m]) * 100

# Queue error rate
rate(rabbitmq_queue_messages_redelivered_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100
```

### **Channels & Connections Dashboard**
```promql
# Total connections
rabbitmq_connections_total

# Total channels
rabbitmq_channels_total

# Connection rate
rate(rabbitmq_connections_total[1m])

# Channel rate
rate(rabbitmq_channels_total[1m])

# Connection churn rate
abs(rate(rabbitmq_connections_total[1m]))

# Channel churn rate
abs(rate(rabbitmq_channels_total[1m]))

# Channels per connection ratio
rabbitmq_channels_total / rabbitmq_connections_total

# Connection stability
stddev(rabbitmq_connections_total[5m])
```

### **Message Flow Dashboard**
```promql
# Total message throughput
rate(rabbitmq_queue_messages_published_total[1m])
rate(rabbitmq_queue_messages_delivered_total[1m])
rate(rabbitmq_queue_messages_ack_total[1m])

# Message processing pipeline
rate(rabbitmq_queue_messages_published_total[1m])
rate(rabbitmq_queue_messages_delivered_total[1m])
rate(rabbitmq_queue_messages_ack_total[1m])
rate(rabbitmq_queue_messages_redelivered_total[1m])

# Processing efficiency
rate(rabbitmq_queue_messages_delivered_total[1m]) / rate(rabbitmq_queue_messages_published_total[1m]) * 100

# Acknowledgment rate
rate(rabbitmq_queue_messages_ack_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100

# Error rate
rate(rabbitmq_queue_messages_redelivered_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100

# Message backlog
sum(rabbitmq_queue_messages)
```

### **System Performance Dashboard**
```promql
# Memory usage
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100

# Disk usage
rabbitmq_node_disk_free / rabbitmq_node_disk_free_limit * 100

# Process count
rabbitmq_node_processes

# File descriptor usage
rabbitmq_node_fd_used / rabbitmq_node_fd_total * 100

# Memory breakdown
rabbitmq_node_mem_used
rabbitmq_node_mem_limit - rabbitmq_node_mem_used

# Disk breakdown
rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free
rabbitmq_node_disk_free
```

### **Cluster Health Dashboard**
```promql
# Node status
rabbitmq_node_is_running

# Cluster partitions
rabbitmq_cluster_partitions

# Total nodes
count(rabbitmq_node_is_running)

# Running nodes
sum(rabbitmq_node_is_running)

# Cluster health score
sum(rabbitmq_node_is_running) / count(rabbitmq_node_is_running) * 100

# Node memory usage
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100

# Node disk usage
rabbitmq_node_disk_free / rabbitmq_node_disk_free_limit * 100

# Node process count
rabbitmq_node_processes

# Node file descriptor usage
rabbitmq_node_fd_used / rabbitmq_node_fd_total * 100
```

## 🔧 Custom Metric Calculations

### **Business Metrics**
```promql
# Messages per second
sum(rate(rabbitmq_queue_messages_published_total[1m]))

# Average queue depth
avg(rabbitmq_queue_messages)

# Peak queue depth
max(rabbitmq_queue_messages)

# Consumer utilization
sum(rabbitmq_queue_consumers) / sum(rabbitmq_queue_messages) * 100
```

### **Operational Metrics**
```promql
# System load
rabbitmq_node_processes / rabbitmq_node_fd_total * 100

# Memory pressure
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100

# Disk pressure
(rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free) / rabbitmq_node_disk_free_limit * 100

# Connection pressure
rabbitmq_connections_total / rabbitmq_node_fd_total * 100
```

### **Performance Metrics**
```promql
# Throughput efficiency
sum(rate(rabbitmq_queue_messages_delivered_total[1m])) / sum(rate(rabbitmq_queue_messages_published_total[1m])) * 100

# Processing latency
avg(rabbitmq_queue_messages / rate(rabbitmq_queue_messages_delivered_total[1m]))

# Error rate
sum(rate(rabbitmq_queue_messages_redelivered_total[1m])) / sum(rate(rabbitmq_queue_messages_delivered_total[1m])) * 100
```

## 📊 Metric Labels & Filtering

### **Common Labels**
- **`node`**: RabbitMQ node identifier
- **`queue`**: Queue name
- **`vhost`**: Virtual host
- **`exchange`**: Exchange name
- **`routing_key`**: Routing key

### **Filtering Examples**
```promql
# Filter by specific queue
rabbitmq_queue_messages{queue="my-queue"}

# Filter by specific node
rabbitmq_node_mem_used{node="rabbit@node1"}

# Filter by virtual host
rabbitmq_queue_messages{vhost="/"}

# Multiple filters
rabbitmq_queue_messages{queue="my-queue", vhost="/"}
```

## 🎯 Alerting Thresholds

### **Recommended Thresholds**
```promql
# Memory usage > 85%
rabbitmq_node_mem_used / rabbitmq_node_mem_limit * 100 > 85

# Disk usage > 80%
(rabbitmq_node_disk_free_limit - rabbitmq_node_disk_free) / rabbitmq_node_disk_free_limit * 100 > 80

# Process count > 20K
rabbitmq_node_processes > 20000

# File descriptor usage > 85%
rabbitmq_node_fd_used / rabbitmq_node_fd_total * 100 > 85

# Queue depth > 10K
rabbitmq_queue_messages > 10000

# Error rate > 5%
rate(rabbitmq_queue_messages_redelivered_total[1m]) / rate(rabbitmq_queue_messages_delivered_total[1m]) * 100 > 5

# Cluster partition
rabbitmq_cluster_partitions > 0

# Node down
rabbitmq_node_is_running == 0
```

This comprehensive metrics reference provides all the tools you need to create effective RabbitMQ monitoring dashboards and alerting rules! 🚀
