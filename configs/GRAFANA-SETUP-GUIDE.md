# Quick Grafana Setup Guide for RabbitMQ Monitoring

## 🚀 Quick Start (5 Minutes)

### Step 1: Run the Monitoring Setup Script
```bash
# Make the script executable
chmod +x scripts/monitoring/setup-monitoring.sh

# Run as root (choose your environment)
sudo scripts/monitoring/setup-monitoring.sh qa      # For QA environment
sudo scripts/monitoring/setup-monitoring.sh staging # For staging environment
sudo scripts/monitoring/setup-monitoring.sh prod    # For production environment
```

### Step 2: Get Your Prometheus Server Details
After running the script, note the Prometheus URL:
```bash
# The script will show you something like:
# Prometheus: http://192.168.1.100:9090
```

### Step 3: Add Data Source in Your Remote Grafana

1. **Open your remote Grafana instance**
2. **Go to Configuration → Data Sources**
3. **Click "Add data source"**
4. **Select "Prometheus"**
5. **Configure:**
   - **Name**: `RabbitMQ-Prometheus`
   - **URL**: `http://YOUR_PROMETHEUS_IP:9090` (replace with actual IP)
   - **Access**: `Server (default)`
   - **HTTP Method**: `GET`
6. **Click "Save & Test"**

### Step 4: Import RabbitMQ Dashboard

#### Option A: Use Official Dashboard
1. In Grafana, go to **Dashboards → Import**
2. Enter dashboard ID: `10991`
3. Select your Prometheus data source
4. Click **Import**

#### Option B: Use Custom Dashboard
1. Copy the dashboard JSON from `configs/templates/monitoring-config.md`
2. In Grafana, go to **Dashboards → Import**
3. Paste the JSON content
4. Select your Prometheus data source
5. Click **Import**

## 🔧 Configuration Details

### What Gets Installed
- **Prometheus** (Port 9090) - Metrics collection
- **Alert Manager** (Port 9093) - Alert management
- **Systemd services** - Auto-start on boot
- **Firewall rules** - Open necessary ports
- **Log rotation** - Manage log files

### What Gets Monitored
- ✅ RabbitMQ cluster status
- ✅ Memory and disk usage
- ✅ Queue depths and message rates
- ✅ Connection counts
- ✅ Cluster partition detection
- ✅ Performance metrics

### Alert Rules Included
- 🚨 **Critical**: RabbitMQ down, cluster partition
- ⚠️ **Warning**: High memory/disk usage, queue depth, connections

## 🌐 Network Configuration

### Required Ports
- **9090** - Prometheus web interface
- **9093** - Alert Manager web interface
- **15692** - RabbitMQ Prometheus metrics (already open)

### Firewall Setup
The script automatically configures firewall-cmd. If you're using a different firewall:

```bash
# UFW
sudo ufw allow 9090/tcp
sudo ufw allow 9093/tcp

# iptables
sudo iptables -A INPUT -p tcp --dport 9090 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9093 -j ACCEPT
```

## 📊 Dashboard Features

### Main Panels
1. **Cluster Status** - Shows all nodes and their health
2. **Memory Usage** - Gauge showing memory consumption
3. **Disk Usage** - Gauge showing disk space
4. **Queue Messages** - Time series of queue depths
5. **Connections** - Active connection count
6. **Message Rates** - Publishing/consuming rates

### Time Ranges
- **Last 1 hour** - Quick status check
- **Last 6 hours** - Daily operations
- **Last 24 hours** - Daily patterns
- **Last 7 days** - Weekly trends

## 🚨 Alerting Setup

### Configure Alert Channels
Edit `/etc/alertmanager/alertmanager.yml`:

```yaml
receivers:
  - name: 'team-rabbitmq'
    email_configs:
      - to: 'your-team@company.com'  # Change this
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'  # Change this
        channel: '#rabbitmq-alerts'         # Change this
```

### Test Alerts
```bash
# Test alert rule evaluation
curl -X POST http://localhost:9090/api/v1/rules/reload

# Check alert manager
curl http://localhost:9093/api/v1/alerts
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Prometheus Not Starting
```bash
# Check status
sudo systemctl status prometheus

# Check logs
sudo journalctl -u prometheus -f

# Check configuration
sudo -u prometheus /opt/prometheus/prometheus --config.file=/etc/prometheus/prometheus.yml --check-config
```

#### 2. Can't Connect from Grafana
```bash
# Check if Prometheus is listening
netstat -tlnp | grep :9090

# Check firewall
sudo firewall-cmd --list-ports

# Test connectivity
curl http://localhost:9090/api/v1/targets
```

#### 3. No RabbitMQ Metrics
```bash
# Check if RabbitMQ is running
sudo systemctl status rabbitmq-server

# Check if Prometheus plugin is enabled
sudo rabbitmq-plugins list | grep prometheus

# Test metrics endpoint
curl http://localhost:15692/metrics
```

### Useful Commands
```bash
# Check all services
sudo systemctl status prometheus alertmanager rabbitmq-server

# View Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq

# Check alert rules
curl -s http://localhost:9090/api/v1/rules | jq

# View alert manager alerts
curl -s http://localhost:9093/api/v1/alerts | jq
```

## 📈 Performance Tuning

### Prometheus Settings
```yaml
# In /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s        # Default: 15s
  evaluation_interval: 15s    # Default: 15s

scrape_configs:
  - job_name: 'rabbitmq'
    scrape_interval: 30s      # RabbitMQ metrics every 30s
    scrape_timeout: 10s       # Timeout for scraping
```

### Storage Retention
```bash
# Default retention is 30 days
# To change, modify the service file:
ExecStart=/opt/prometheus/prometheus \
    --storage.tsdb.retention.time=60d  # 60 days
```

## 🔐 Security Considerations

### Network Security
- Only open Prometheus ports to your Grafana server
- Use VPN or private network for management
- Consider reverse proxy with authentication

### Access Control
- Prometheus and Alert Manager run as non-root user
- Configuration files have restricted permissions
- Logs are rotated and managed

### SSL/TLS (Optional)
```bash
# For production, consider adding SSL
# Update Prometheus service to use HTTPS
--web.config.file=/etc/prometheus/web.yml
```

## 📋 Maintenance

### Regular Tasks
```bash
# Check disk usage
du -sh /opt/prometheus/data

# Check service health
sudo systemctl status prometheus alertmanager

# View recent logs
sudo journalctl -u prometheus --since "1 hour ago"
sudo journalctl -u alertmanager --since "1 hour ago"
```

### Updates
```bash
# Update Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.46.0/prometheus-2.46.0.linux-amd64.tar.gz
tar -xzf prometheus-2.46.0.linux-amd64.tar.gz
ln -sf prometheus-2.46.0 prometheus
sudo systemctl restart prometheus
```

## 🎯 Next Steps

1. **✅ Run the setup script** (5 minutes)
2. **✅ Add data source in Grafana** (2 minutes)
3. **✅ Import dashboard** (2 minutes)
4. **🔧 Configure alerting** (10 minutes)
5. **🧪 Test monitoring** (5 minutes)
6. **📚 Customize dashboards** (as needed)

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review service logs: `journalctl -u service-name -f`
3. Verify network connectivity between Grafana and Prometheus
4. Check firewall and security group settings

## 🎉 Success!

Once completed, you'll have:
- Real-time RabbitMQ monitoring
- Beautiful Grafana dashboards
- Automated alerting
- Historical metrics
- Production-ready monitoring stack

Your RabbitMQ cluster is now fully monitored! 🚀
