# RabbitMQ Grafana Dashboard Setup Guide

This guide provides detailed instructions for setting up comprehensive RabbitMQ monitoring dashboards in Grafana.

## 📊 Dashboard Overview

We've created **5 specialized dashboards** for comprehensive RabbitMQ monitoring:

### 1. **Queue Performance Dashboard** (`rabbitmq-queue-dashboard.json`)
- **Focus**: Queue-specific metrics and performance
- **Key Metrics**:
  - Queue message counts and consumer counts
  - Message publishing, delivery, and acknowledgment rates
  - Message redelivery rates and error rates
  - Queue processing efficiency
  - Queue backlog analysis
  - Throughput summary table

### 2. **Channels & Connections Dashboard** (`rabbitmq-channels-connections-dashboard.json`)
- **Focus**: Connection and channel management
- **Key Metrics**:
  - Total connections and channels
  - Connection and channel rates
  - Connection and channel churn rates
  - Channels per connection ratio
  - Connection stability analysis
  - Summary table with all connection metrics

### 3. **Message Flow & Throughput Dashboard** (`rabbitmq-message-flow-dashboard.json`)
- **Focus**: Message processing pipeline and throughput
- **Key Metrics**:
  - Total message throughput (published, delivered, acknowledged)
  - Message processing pipeline visualization
  - Processing efficiency gauges
  - Message flow by queue
  - Message consumption by queue
  - Processing latency analysis
  - Throughput summary table

### 4. **System Performance Dashboard** (`rabbitmq-system-performance-dashboard.json`)
- **Focus**: System resource utilization
- **Key Metrics**:
  - Memory usage and breakdown
  - Disk usage and space analysis
  - Erlang process count
  - File descriptor usage
  - System resource alerts
  - Performance summary table

### 5. **Cluster Health Dashboard** (`rabbitmq-cluster-health-dashboard.json`)
- **Focus**: Cluster-wide health and node status
- **Key Metrics**:
  - Cluster node status
  - Cluster partition status
  - Cluster health score
  - Node memory and disk usage
  - Node process and FD usage
  - Cluster node summary table

## 🚀 Quick Setup Instructions

### Step 1: Import Dashboards

1. **Access Grafana**:
   ```bash
   # Open Grafana in your browser
   http://your-grafana-server:3000
   ```

2. **Import Each Dashboard**:
   - Click **"+"** → **"Import"**
   - Copy the JSON content from each dashboard file
   - Paste into the **"Import via panel json"** text area
   - Click **"Load"**
   - Select your **Prometheus data source**
   - Click **"Import"**

### Step 2: Configure Data Source

Ensure your Prometheus data source is configured with:
- **URL**: `http://your-rabbitmq-server:9090`
- **Access**: Server (default)
- **Scrape interval**: 15s

### Step 3: Verify Metrics

Check that these key metrics are available:
```promql
# Core RabbitMQ metrics
rabbitmq_queue_messages
rabbitmq_queue_consumers
rabbitmq_connections_total
rabbitmq_channels_total
rabbitmq_node_mem_used
rabbitmq_node_disk_free
```

## 📈 Dashboard Features

### **Color-Coded Alerts**
- 🟢 **Green**: Healthy/normal operation
- 🟡 **Yellow**: Warning conditions
- 🟠 **Orange**: Critical conditions
- 🔴 **Red**: Critical/failure conditions

### **Interactive Elements**
- **Time Range Selector**: Choose monitoring period
- **Refresh Intervals**: 30s default, customizable
- **Legend Tables**: Detailed metric breakdowns
- **Tooltips**: Hover for detailed information

### **Thresholds & Alerts**
Each dashboard includes predefined thresholds:
- **Memory Usage**: 70% (warning), 85% (critical), 95% (emergency)
- **Disk Space**: 20% free (warning), 10% free (critical)
- **Process Count**: 10K (warning), 20K (critical), 50K (emergency)
- **File Descriptors**: 70% (warning), 85% (critical), 95% (emergency)

## 🔧 Customization Options

### **Modify Thresholds**
Edit the `thresholds` section in each panel:
```json
"thresholds": {
  "steps": [
    {"color": "green", "value": 0},
    {"color": "yellow", "value": 70},
    {"color": "orange", "value": 85},
    {"color": "red", "value": 95}
  ]
}
```

### **Change Refresh Intervals**
Modify the dashboard refresh rate:
```json
"refresh": "30s"  // Options: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h
```

### **Adjust Time Ranges**
Set default time ranges:
```json
"time": {
  "from": "now-1h",  // Options: now-5m, now-15m, now-1h, now-6h, now-1d
  "to": "now"
}
```

## 📊 Key Metrics Explained

### **Queue Metrics**
- **`rabbitmq_queue_messages`**: Current messages in queue
- **`rabbitmq_queue_consumers`**: Active consumers for queue
- **`rabbitmq_queue_messages_published_total`**: Total messages published
- **`rabbitmq_queue_messages_delivered_total`**: Total messages delivered
- **`rabbitmq_queue_messages_ack_total`**: Total messages acknowledged
- **`rabbitmq_queue_messages_redelivered_total`**: Total messages redelivered

### **Connection Metrics**
- **`rabbitmq_connections_total`**: Total active connections
- **`rabbitmq_channels_total`**: Total active channels
- **Connection Churn**: Rate of connection creation/destruction
- **Channel Churn**: Rate of channel creation/destruction

### **System Metrics**
- **`rabbitmq_node_mem_used`**: Memory used by RabbitMQ
- **`rabbitmq_node_mem_limit`**: Memory limit for RabbitMQ
- **`rabbitmq_node_disk_free`**: Free disk space
- **`rabbitmq_node_processes`**: Erlang process count
- **`rabbitmq_node_fd_used`**: File descriptors used

### **Cluster Metrics**
- **`rabbitmq_node_is_running`**: Node running status (1=running, 0=stopped)
- **`rabbitmq_cluster_partitions`**: Number of cluster partitions
- **Cluster Health Score**: Percentage of healthy nodes

## 🎯 Best Practices

### **Dashboard Organization**
1. **Start with Cluster Health**: Monitor overall cluster status
2. **Check System Performance**: Ensure resources are adequate
3. **Analyze Message Flow**: Understand throughput patterns
4. **Monitor Queues**: Track queue-specific performance
5. **Watch Connections**: Monitor connection stability

### **Alerting Strategy**
1. **Set up alerts** for critical thresholds
2. **Use different severity levels** (warning, critical, emergency)
3. **Configure notification channels** (email, Slack, PagerDuty)
4. **Test alerting** before production deployment

### **Performance Optimization**
1. **Adjust scrape intervals** based on monitoring needs
2. **Use appropriate time ranges** for different use cases
3. **Filter metrics** to focus on relevant data
4. **Set up data retention** policies in Prometheus

## 🔍 Troubleshooting

### **Common Issues**

#### **No Data in Dashboards**
```bash
# Check Prometheus targets
curl http://your-prometheus:9090/api/v1/targets

# Verify RabbitMQ metrics endpoint
curl http://your-rabbitmq:15692/metrics
```

#### **Missing Metrics**
```bash
# Check RabbitMQ Prometheus plugin
rabbitmq-plugins list | grep prometheus

# Verify plugin is enabled
rabbitmq-plugins enable rabbitmq_prometheus
```

#### **Dashboard Import Errors**
- Ensure JSON format is valid
- Check Grafana version compatibility
- Verify data source configuration

### **Performance Issues**
- Reduce scrape frequency for large clusters
- Use metric relabeling to filter unnecessary metrics
- Consider using recording rules for complex queries

## 📚 Additional Resources

### **Grafana Documentation**
- [Grafana Dashboard Import](https://grafana.com/docs/grafana/latest/dashboards/export-import/)
- [Prometheus Data Source](https://grafana.com/docs/grafana/latest/datasources/prometheus/)
- [Alerting Setup](https://grafana.com/docs/grafana/latest/alerting/)

### **RabbitMQ Monitoring**
- [RabbitMQ Prometheus Plugin](https://github.com/rabbitmq/rabbitmq-prometheus)
- [RabbitMQ Monitoring Guide](https://www.rabbitmq.com/monitoring.html)
- [Performance Tuning](https://www.rabbitmq.com/runtime.html)

## 🎉 Success Metrics

After setup, you should see:
- ✅ **Real-time metrics** updating every 30 seconds
- ✅ **Color-coded alerts** for different severity levels
- ✅ **Interactive dashboards** with detailed breakdowns
- ✅ **Historical data** for trend analysis
- ✅ **Comprehensive coverage** of all RabbitMQ components

Your RabbitMQ monitoring system is now ready for production use! 🚀
