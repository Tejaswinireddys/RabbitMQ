# 🚀 RabbitMQ Multi-Tier Monitoring Setup Guide

## 📋 Overview

This guide sets up a comprehensive **3-tier monitoring system** for RabbitMQ clusters:

- **Tier 1**: High-Level Executive Dashboard (Business Impact)
- **Tier 2**: Detailed Operations Dashboard (Operational Health)  
- **Tier 3**: Very Detailed Technical Dashboard (Deep-Dive Analysis)

## 🏗️ Architecture

```
RabbitMQ Cluster → Prometheus → Grafana Dashboards
     ↓              ↓              ↓
  Metrics      Data Store    Tier 1: Executive (5min refresh)
  Collection                Tier 2: Operations (1min refresh)
                            Tier 3: Technical (30s refresh)
```

## 🎯 Monitoring Tiers

### **Tier 1: Executive Dashboard**
- **Purpose**: Business stakeholders, executives, high-level status
- **Update Frequency**: 5 minutes
- **Focus**: Business impact, availability, capacity
- **Metrics**: Service status, cluster health, message counts, connections

### **Tier 2: Operations Dashboard**
- **Purpose**: Operations team, system administrators
- **Update Frequency**: 1 minute
- **Focus**: Performance, resource usage, operational health
- **Metrics**: Memory, disk, queues, connections, channels, consumers

### **Tier 3: Technical Dashboard**
- **Purpose**: Developers, support engineers, troubleshooting
- **Update Frequency**: 30 seconds
- **Focus**: Deep metrics, debugging, optimization
- **Metrics**: Process counts, exchange counts, queue counts, consumer counts, redelivery rates

## 🚀 Quick Setup (10 Minutes)

### Step 1: Run Enhanced Monitoring Setup
```bash
# Make script executable
chmod +x scripts/monitoring/setup-monitoring.sh

# Run setup (choose environment)
sudo scripts/monitoring/setup-monitoring.sh qa      # QA environment
sudo scripts/monitoring/setup-monitoring.sh staging # Staging environment
sudo scripts/monitoring/setup-monitoring.sh prod    # Production environment
```

### Step 2: Add Prometheus Data Source in Grafana
1. Open your remote Grafana instance
2. Go to **Configuration** → **Data Sources**
3. Click **Add data source**
4. Select **Prometheus**
5. Configure:
   - **Name**: `RabbitMQ-Prometheus`
   - **URL**: `http://YOUR_PROMETHEUS_IP:9090`
   - **Access**: `Server (default)`
6. Click **Save & Test**

### Step 3: Import Multi-Tier Dashboards

#### Import Tier 1: Executive Dashboard
1. In Grafana, go to **Dashboards** → **Import**
2. Copy content from `configs/dashboards/tier1-executive-dashboard.json`
3. Paste into the import field
4. Select your Prometheus data source
5. Click **Import**

#### Import Tier 2: Operations Dashboard
1. Copy content from the Tier 2 dashboard JSON in `configs/templates/multi-tier-monitoring.md`
2. Follow same import process

#### Import Tier 3: Technical Dashboard
1. Copy content from the Tier 3 dashboard JSON in `configs/templates/multi-tier-monitoring.md`
2. Follow same import process

## 🔧 Detailed Configuration

### Enhanced Prometheus Configuration
The setup script automatically creates:

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "rabbitmq-cluster"
    environment: "production"

rule_files:
  - "tier1_alerts.yml"    # Business alerts
  - "tier2_alerts.yml"    # Operational alerts
  - "tier3_alerts.yml"    # Technical alerts

scrape_configs:
  # Core metrics (15s)
  - job_name: 'rabbitmq-core'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 15s

  # Performance metrics (30s)
  - job_name: 'rabbitmq-performance'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 30s

  # System metrics (60s)
  - job_name: 'rabbitmq-system'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 60s

  # Cluster metrics (45s)
  - job_name: 'rabbitmq-cluster'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 45s
```

### Multi-Tier Alerting Rules

#### Tier 1: Business Impact Alerts
- **RabbitMQServiceDown**: Service unavailable
- **ClusterUnavailable**: Cluster degraded
- **HighQueueBacklog**: Message processing delays
- **ServiceDegradation**: Performance issues
- **HighErrorRate**: Quality problems
- **CapacityExceeded**: Resource limits
- **CriticalQueueOverflow**: Blocked processes
- **ClusterPartitionRisk**: Data consistency risk

#### Tier 2: Operational Health Alerts
- **HighMemoryUsage**: Resource pressure
- **LowDiskSpace**: Storage issues
- **HighConnectionCount**: Connection pressure
- **QueueDepthThreshold**: Processing delays
- **HighMessageRate**: Load monitoring
- **HighChannelCount**: Channel management
- **ConsumerDisconnect**: Consumer health
- **ClusterInstability**: Cluster health

#### Tier 3: Technical Deep-Dive Alerts
- **HighChannelCount**: Channel leaks
- **HighExchangeCount**: Configuration complexity
- **HighQueueCount**: Resource overhead
- **HighConsumerCount**: Connection overhead
- **HighMessageRedelivery**: Consumer issues
- **HighProcessCount**: Process leaks
- **HighMemoryFragmentation**: Memory efficiency
- **HighConnectionChurn**: Connection stability

## 📊 Dashboard Features

### Tier 1: Executive Dashboard
- **Service Status**: UP/DOWN indicators
- **Cluster Health**: Node count with thresholds
- **Message Counts**: Total queue messages
- **Connection Status**: Active connections
- **Processing Rates**: Published vs delivered
- **System Health**: Memory and disk usage

### Tier 2: Operations Dashboard
- **Resource Gauges**: Memory and disk usage
- **Queue Depths**: Individual queue monitoring
- **Connection Trends**: Connection count over time
- **Channel Monitoring**: Channel count trends
- **Message Rates**: Publishing, delivery, acknowledgment
- **Consumer Health**: Consumer count monitoring

### Tier 3: Technical Dashboard
- **Process Monitoring**: Erlang process counts
- **Exchange Monitoring**: Exchange count trends
- **Queue Monitoring**: Queue count trends
- **Consumer Monitoring**: Consumer count trends
- **Message Quality**: Redelivery and acknowledgment rates
- **Cluster Network**: Link monitoring
- **Memory Analysis**: Memory breakdown
- **Stability Metrics**: Churn rates and variability

## 🚨 Alert Management

### Alert Routing by Tier
```yaml
# /etc/alertmanager/alertmanager.yml
route:
  routes:
    # Tier 1: Executive alerts
    - match:
        tier: "tier1"
      receiver: 'executive-team'
      repeat_interval: 1h

    # Tier 2: Operations alerts
    - match:
        tier: "tier2"
      receiver: 'operations-team'
      repeat_interval: 30m

    # Tier 3: Technical alerts
    - match:
        tier: "tier3"
      receiver: 'development-team'
      repeat_interval: 15m
```

### Team Notifications
- **Executive Team**: Email + Slack (business impact)
- **Operations Team**: Email + Slack + PagerDuty (operational issues)
- **Development Team**: Slack + Jira tickets (technical issues)

## 🔍 Monitoring Best Practices

### 1. Dashboard Organization
- **Use consistent naming**: `RabbitMQ - [Tier] - [Purpose]`
- **Tag dashboards**: `rabbitmq`, `tier1`, `tier2`, `tier3`
- **Set appropriate refresh rates**: 5min, 1min, 30s

### 2. Alert Thresholds
- **Tier 1**: Business-critical thresholds (2-5 minutes)
- **Tier 2**: Operational thresholds (5-10 minutes)
- **Tier 3**: Technical thresholds (5-15 minutes)

### 3. Metric Collection
- **Core metrics**: High frequency (15s)
- **Performance metrics**: Medium frequency (30s)
- **System metrics**: Lower frequency (60s)

## 📈 Performance Optimization

### Scrape Intervals
- **Critical metrics**: 15s (service status, cluster health)
- **Performance metrics**: 30s (message rates, queue depths)
- **System metrics**: 60s (memory, disk, processes)

### Storage Retention
- **Tier 1**: 30 days (business metrics)
- **Tier 2**: 90 days (operational metrics)
- **Tier 3**: 180 days (technical metrics)

### Resource Usage
- **Prometheus**: 2-4 CPU cores, 4-8GB RAM
- **Alert Manager**: 1-2 CPU cores, 2-4GB RAM
- **Storage**: 100-500GB depending on retention

## 🧪 Testing and Validation

### 1. Test Metrics Collection
```bash
# Test RabbitMQ metrics
curl http://localhost:15692/metrics | grep rabbitmq

# Test Prometheus
curl http://localhost:9090/api/v1/targets

# Test Alert Manager
curl http://localhost:9093/api/v1/alerts
```

### 2. Test Alert Rules
```bash
# Reload alert rules
curl -X POST http://localhost:9090/api/v1/rules/reload

# Check rule status
curl http://localhost:9090/api/v1/rules
```

### 3. Test Dashboard Queries
- Verify all panels show data
- Check time ranges and refresh rates
- Validate threshold colors and alerts

## 🔧 Troubleshooting

### Common Issues

#### 1. No Metrics in Dashboards
```bash
# Check RabbitMQ Prometheus plugin
rabbitmq-plugins list | grep prometheus

# Check metrics endpoint
curl http://localhost:15692/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets
```

#### 2. Alerts Not Firing
```bash
# Check alert rules
curl http://localhost:9090/api/v1/rules

# Check alert manager
curl http://localhost:9093/api/v1/alerts

# Check Prometheus logs
journalctl -u prometheus -f
```

#### 3. High Resource Usage
```bash
# Check Prometheus storage
du -sh /opt/prometheus/data

# Check memory usage
ps aux | grep prometheus

# Check disk I/O
iostat -x 1
```

## 📋 Maintenance

### Regular Tasks
```bash
# Daily
- Check dashboard status
- Review active alerts
- Monitor resource usage

# Weekly
- Review alert thresholds
- Clean up old metrics
- Update documentation

# Monthly
- Review monitoring coverage
- Optimize scrape intervals
- Plan capacity upgrades
```

### Updates
```bash
# Update Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.46.0/prometheus-2.46.0.linux-amd64.tar.gz
tar -xzf prometheus-2.46.0.linux-amd64.tar.gz
ln -sf prometheus-2.46.0 prometheus
sudo systemctl restart prometheus

# Update Alert Manager
cd /opt
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.26.0.linux-amd64.tar.gz
ln -sf alertmanager-0.26.0 alertmanager
sudo systemctl restart alertmanager
```

## 🎯 Success Metrics

### Business Metrics
- **Service Availability**: >99.9%
- **Alert Response Time**: <5 minutes for critical
- **Dashboard Uptime**: >99.5%

### Technical Metrics
- **Metrics Collection**: >99.9% success rate
- **Alert Accuracy**: <5% false positives
- **Dashboard Performance**: <2 second load time

## 🚀 Next Steps

1. **Deploy the monitoring stack** using the setup script
2. **Import all three dashboard tiers** to Grafana
3. **Configure team notifications** in Alert Manager
4. **Test the complete monitoring pipeline**
5. **Customize dashboards** for your specific needs
6. **Train teams** on using their respective dashboards
7. **Establish monitoring procedures** and runbooks

## 📞 Support

For issues with the multi-tier monitoring system:
1. Check the troubleshooting section above
2. Review service logs: `journalctl -u service-name -f`
3. Verify network connectivity between components
4. Check configuration files in `/etc/prometheus/` and `/etc/alertmanager/`

## 🎉 Success!

Once completed, you'll have:
- ✅ **Comprehensive monitoring** across all tiers
- ✅ **Business-focused executive dashboard**
- ✅ **Operational health monitoring**
- ✅ **Deep technical analysis capabilities**
- ✅ **Multi-team alerting and notifications**
- ✅ **Production-ready monitoring architecture**

Your RabbitMQ cluster is now fully monitored with enterprise-grade, multi-tier visibility! 🚀
