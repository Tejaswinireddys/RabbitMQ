# RabbitMQ Grafana Dashboards

This directory contains comprehensive Grafana dashboards for monitoring RabbitMQ clusters with detailed metrics for queues, channels, connections, message flow, system performance, and cluster health.

## 📊 Dashboard Collection

### **Core Monitoring Dashboards**

#### 1. **Queue Performance Dashboard** (`rabbitmq-queue-dashboard.json`)
- **Purpose**: Monitor queue-specific metrics and performance
- **Key Features**:
  - Queue message counts and consumer counts
  - Message publishing, delivery, and acknowledgment rates
  - Message redelivery rates and error analysis
  - Queue processing efficiency calculations
  - Queue backlog analysis with color-coded alerts
  - Comprehensive throughput summary table

#### 2. **Channels & Connections Dashboard** (`rabbitmq-channels-connections-dashboard.json`)
- **Purpose**: Monitor connection and channel management
- **Key Features**:
  - Total connections and channels with real-time counts
  - Connection and channel creation/destruction rates
  - Connection and channel churn analysis
  - Channels per connection ratio monitoring
  - Connection stability analysis
  - Detailed summary table with all connection metrics

#### 3. **Message Flow & Throughput Dashboard** (`rabbitmq-message-flow-dashboard.json`)
- **Purpose**: Monitor message processing pipeline and throughput
- **Key Features**:
  - Total message throughput visualization
  - Message processing pipeline (published → delivered → acknowledged)
  - Processing efficiency gauges with thresholds
  - Message flow analysis by queue
  - Message consumption patterns
  - Processing latency calculations
  - Comprehensive throughput summary

#### 4. **System Performance Dashboard** (`rabbitmq-system-performance-dashboard.json`)
- **Purpose**: Monitor system resource utilization
- **Key Features**:
  - Memory usage and breakdown analysis
  - Disk usage and space monitoring
  - Erlang process count tracking
  - File descriptor usage monitoring
  - System resource alerts with thresholds
  - Performance summary with all key metrics

#### 5. **Cluster Health Dashboard** (`rabbitmq-cluster-health-dashboard.json`)
- **Purpose**: Monitor cluster-wide health and node status
- **Key Features**:
  - Cluster node status monitoring
  - Cluster partition detection
  - Cluster health score calculation
  - Node-specific resource usage
  - Node process and file descriptor monitoring
  - Comprehensive cluster node summary

### **Multi-Tier Monitoring Dashboards**

#### 6. **Executive Dashboard (Tier 1)** (`tier1-executive-dashboard.json`)
- **Purpose**: High-level business metrics for executives
- **Key Features**:
  - Service status overview
  - Cluster health summary
  - Total messages in queues
  - Active connections count
  - Message processing rate
  - System health overview
  - Disk space usage

#### 7. **Operations Dashboard (Tier 2)** (`tier2-operations-dashboard.json`)
- **Purpose**: Detailed operational metrics for operations teams
- **Key Features**:
  - Memory usage monitoring
  - Disk usage tracking
  - Queue depth analysis
  - Connection count monitoring
  - Channel count tracking
  - Message rate analysis

#### 8. **Technical Dashboard (Tier 3)** (`tier3-technical-dashboard.json`)
- **Purpose**: Deep technical metrics for developers and engineers
- **Key Features**:
  - Erlang process count
  - Exchange count monitoring
  - Queue count tracking
  - Consumer count analysis
  - Message redelivery rate
  - Message acknowledgment rate
  - Cluster links monitoring
  - Memory breakdown analysis

## 🚀 Quick Start

### **Automated Import**
```bash
# Import all dashboards automatically
./scripts/monitoring/import-grafana-dashboards.sh

# With custom Grafana settings
./scripts/monitoring/import-grafana-dashboards.sh \
  --grafana-url http://your-grafana:3000 \
  --grafana-user admin \
  --grafana-password your-password \
  --prometheus-ds-url http://your-prometheus:9090
```

### **Manual Import**
1. Open Grafana in your browser
2. Click **"+"** → **"Import"**
3. Copy JSON content from dashboard files
4. Paste into **"Import via panel json"** text area
5. Click **"Load"** and configure data source
6. Click **"Import"**

## 📈 Key Metrics Covered

### **Queue Metrics**
- Message counts (total, ready, unacknowledged)
- Message rates (published, delivered, acknowledged, redelivered)
- Consumer counts and efficiency
- Processing latency and throughput
- Error rates and redelivery patterns

### **Connection Metrics**
- Total connections and channels
- Connection/channel creation rates
- Churn analysis and stability
- Resource utilization per connection
- Connection health monitoring

### **System Metrics**
- Memory usage and limits
- Disk space and utilization
- Erlang process counts
- File descriptor usage
- System resource alerts

### **Cluster Metrics**
- Node status and health
- Cluster partition detection
- Node resource distribution
- Cluster-wide performance
- Health score calculations

## 🎯 Dashboard Features

### **Color-Coded Alerts**
- 🟢 **Green**: Healthy/normal operation
- 🟡 **Yellow**: Warning conditions (70-85% thresholds)
- 🟠 **Orange**: Critical conditions (85-95% thresholds)
- 🔴 **Red**: Emergency conditions (>95% thresholds)

### **Interactive Elements**
- **Time Range Selector**: Flexible monitoring periods
- **Refresh Intervals**: 30s default, customizable
- **Legend Tables**: Detailed metric breakdowns
- **Tooltips**: Hover for detailed information
- **Drill-down**: Click for detailed analysis

### **Thresholds & Alerts**
- **Memory Usage**: 70% (warning), 85% (critical), 95% (emergency)
- **Disk Space**: 20% free (warning), 10% free (critical)
- **Process Count**: 10K (warning), 20K (critical), 50K (emergency)
- **File Descriptors**: 70% (warning), 85% (critical), 95% (emergency)
- **Queue Depth**: 1K (warning), 5K (critical), 10K (emergency)

## 🔧 Customization

### **Modify Thresholds**
Edit the `thresholds` section in panel configurations:
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

### **Change Refresh Rates**
Modify dashboard refresh intervals:
```json
"refresh": "30s"  // Options: 5s, 10s, 30s, 1m, 5m, 15m, 30m, 1h
```

### **Adjust Time Ranges**
Set default monitoring periods:
```json
"time": {
  "from": "now-1h",  // Options: now-5m, now-15m, now-1h, now-6h, now-1d
  "to": "now"
}
```

## 📚 Documentation

### **Setup Guides**
- **`DASHBOARD-SETUP-GUIDE.md`**: Comprehensive setup instructions
- **`RABBITMQ-METRICS-REFERENCE.md`**: Complete metrics reference
- **`import-grafana-dashboards.sh`**: Automated import script

### **Configuration Files**
- **`tier1_alerts.yml`**: Executive-level alerting rules
- **`tier2_alerts.yml`**: Operations-level alerting rules
- **`tier3_alerts.yml`**: Technical-level alerting rules

## 🎯 Best Practices

### **Dashboard Usage**
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

## 🎉 Success Metrics

After setup, you should see:
- ✅ **Real-time metrics** updating every 30 seconds
- ✅ **Color-coded alerts** for different severity levels
- ✅ **Interactive dashboards** with detailed breakdowns
- ✅ **Historical data** for trend analysis
- ✅ **Comprehensive coverage** of all RabbitMQ components

## 📞 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the setup guides and documentation
3. Verify Prometheus and RabbitMQ configurations
4. Test individual metrics and queries

Your RabbitMQ monitoring system is now ready for production use! 🚀
