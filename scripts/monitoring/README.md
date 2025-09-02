# 🚀 RabbitMQ Monitoring and Auto-Recovery System

## 📋 Overview

This directory contains a comprehensive **monitoring and auto-recovery system** for RabbitMQ clusters that integrates with the multi-tier monitoring architecture. The system provides:

- **Real-time cluster health monitoring**
- **Automated issue detection and recovery**
- **Integration with Prometheus and Grafana**
- **Multi-tier alerting and notifications**
- **Systemd service automation**

## 🏗️ Architecture

```
RabbitMQ Cluster → Monitoring Scripts → Prometheus → Grafana
       ↓                    ↓              ↓         ↓
   Health Checks      Auto-Recovery    Metrics   Dashboards
       ↓                    ↓              ↓         ↓
   Status Reports     Recovery Logs   Alerts    Visualizations
```

## 📁 Files Overview

### Core Scripts
- **`cluster-monitor.sh`** - Comprehensive cluster health monitoring
- **`cluster-auto-recovery.sh`** - Automated issue recovery
- **`setup-monitoring-recovery.sh`** - Complete system setup

### Configuration Files
- **`rabbitmq-monitor.service`** - Systemd service for monitoring
- **`rabbitmq-monitor.timer`** - Automated monitoring schedule
- **`tier1_alerts.yml`** - Business impact alerts
- **`tier2_alerts.yml`** - Operational health alerts
- **`tier3_alerts.yml`** - Technical deep-dive alerts

## 🚀 Quick Start

### 1. Complete Setup (Recommended)
```bash
# Make scripts executable
chmod +x scripts/monitoring/*.sh

# Run complete setup
sudo scripts/monitoring/setup-monitoring-recovery.sh qa
```

### 2. Manual Setup
```bash
# Setup monitoring only
sudo scripts/monitoring/setup-monitoring-recovery.sh qa true false

# Setup recovery only
sudo scripts/monitoring/setup-monitoring-recovery.sh qa false true
```

### 3. Individual Scripts
```bash
# Run monitoring manually
sudo /usr/local/bin/rabbitmq-monitor.sh qa

# Run recovery manually
sudo /usr/local/bin/rabbitmq-recovery.sh qa auto
```

## 🔧 Script Details

### `cluster-monitor.sh` - Cluster Health Monitoring

**Purpose**: Comprehensive cluster health assessment and reporting

**Features**:
- ✅ **Service Status**: Checks if RabbitMQ is running
- ✅ **Cluster Health**: Verifies cluster membership and partitions
- ✅ **Node Connectivity**: Tests network connectivity between nodes
- ✅ **Queue Health**: Monitors queue depths and consumer status
- ✅ **Connection Health**: Tracks connection counts and states
- ✅ **Resource Usage**: Monitors memory and disk usage
- ✅ **Consumer Health**: Checks consumer application status

**Usage**:
```bash
# Basic monitoring
./cluster-monitor.sh qa

# Help
./cluster-monitor.sh --help
```

**Output**:
- **Exit Code 0**: Cluster is healthy
- **Exit Code 1**: Cluster has warnings
- **Exit Code 2**: Cluster has critical issues
- **Exit Code 3**: Unknown status

### `cluster-auto-recovery.sh` - Automated Recovery

**Purpose**: Automatically recovers from common cluster issues

**Recovery Capabilities**:
- 🔄 **Service Recovery**: Restarts failed RabbitMQ services
- 🔄 **Cluster Recovery**: Rejoins nodes to cluster
- 🔄 **Network Recovery**: Heals network partitions
- 🔄 **Consumer Recovery**: Identifies consumer issues
- 🔄 **Memory Recovery**: Forces garbage collection
- 🔄 **Disk Recovery**: Cleans up old logs and files
- 🔄 **Force Recovery**: Complete node reset (last resort)

**Recovery Modes**:
- **`auto`**: Full automatic recovery including destructive operations
- **`manual`**: Safe recovery without destructive operations

**Usage**:
```bash
# Automatic recovery
./cluster-auto-recovery.sh qa auto

# Manual recovery
./cluster-auto-recovery.sh qa manual

# Help
./cluster-auto-recovery.sh --help
```

### `setup-monitoring-recovery.sh` - Complete Setup

**Purpose**: Installs and configures the entire monitoring and recovery system

**Setup Components**:
- 📦 **Package Installation**: Installs required dependencies
- 📊 **Prometheus Setup**: Installs and configures Prometheus
- 🚨 **Alert Manager**: Sets up multi-tier alerting
- 🔄 **Recovery System**: Installs monitoring and recovery scripts
- 🔥 **Firewall Configuration**: Opens required ports
- 📝 **Log Rotation**: Configures log management
- ⚙️ **Systemd Services**: Creates automated services

**Usage**:
```bash
# Complete setup
./setup-monitoring-recovery.sh qa

# Monitoring only
./setup-monitoring-recovery.sh qa true false

# Recovery only
./setup-monitoring-recovery.sh qa false true

# Help
./setup-monitoring-recovery.sh --help
```

## ⚙️ Systemd Services

### Monitoring Service
```bash
# Service file: /etc/systemd/system/rabbitmq-monitor.service
# Timer file: /etc/systemd/system/rabbitmq-monitor.timer

# Check status
systemctl status rabbitmq-monitor.timer

# View logs
journalctl -u rabbitmq-monitor -f

# Manual run
systemctl start rabbitmq-monitor
```

### Monitoring Schedule
- **Frequency**: Every 5 minutes
- **Randomized Delay**: 0-30 seconds (prevents thundering herd)
- **Automatic Recovery**: Triggers recovery if monitoring fails

## 📊 Monitoring Integration

### Prometheus Metrics
The system automatically configures Prometheus with:
- **Core metrics**: 15-second scrape interval
- **Performance metrics**: 30-second scrape interval
- **System metrics**: 60-second scrape interval
- **Cluster metrics**: 45-second scrape interval

### Multi-Tier Alerting
- **Tier 1**: Business impact alerts (executive team)
- **Tier 2**: Operational health alerts (operations team)
- **Tier 3**: Technical deep-dive alerts (development team)

### Grafana Dashboards
Import the multi-tier dashboards:
- **Executive Dashboard**: High-level business metrics
- **Operations Dashboard**: Detailed operational health
- **Technical Dashboard**: Deep technical analysis

## 🔍 Monitoring Checks

### Health Check Categories

#### 1. Service Health
- RabbitMQ service status
- Process availability
- Port accessibility

#### 2. Cluster Health
- Node membership count
- Network partitions
- Cluster stability

#### 3. Performance Health
- Queue depths
- Message rates
- Consumer status

#### 4. Resource Health
- Memory usage
- Disk space
- Connection counts

#### 5. Application Health
- Consumer applications
- Queue consumers
- Message processing

### Health Status Levels

#### 🟢 **HEALTHY** (Exit Code 0)
- All checks passed
- No warnings or errors
- Cluster operating normally

#### 🟡 **WARNING** (Exit Code 1)
- Some checks have warnings
- No critical failures
- Monitor closely

#### 🔴 **CRITICAL** (Exit Code 2)
- Critical health issues detected
- Immediate attention required
- Auto-recovery will attempt fixes

## 🚨 Recovery Actions

### Automatic Recovery Sequence

1. **Service Recovery**
   - Stop RabbitMQ service
   - Clean up processes
   - Restart service

2. **Cluster Recovery**
   - Check cluster membership
   - Rejoin nodes if needed
   - Verify cluster stability

3. **Network Recovery**
   - Detect partitions
   - Enable auto-healing
   - Monitor resolution

4. **Resource Recovery**
   - Force garbage collection
   - Clean up disk space
   - Monitor resource usage

5. **Force Recovery** (Last Resort)
   - Backup data
   - Reset node completely
   - Rejoin cluster

### Recovery Safety Features

- **Backup Creation**: Automatic data backup before destructive operations
- **Mode Control**: Manual mode prevents destructive operations
- **Logging**: Complete audit trail of all recovery actions
- **Verification**: Post-recovery health checks

## 📝 Logging and Monitoring

### Log Files
- **Monitoring Logs**: `/var/log/rabbitmq/cluster-monitor.log`
- **Recovery Logs**: `/var/log/rabbitmq/auto-recovery.log`
- **Systemd Logs**: `journalctl -u rabbitmq-monitor`

### Log Rotation
- **Frequency**: Daily
- **Retention**: 30 days
- **Compression**: Enabled
- **Post-rotate**: Service reload

### Monitoring Metrics
- **Recovery Success Rate**: Percentage of successful recoveries
- **Recovery Time**: Time taken for each recovery action
- **Issue Frequency**: How often issues occur
- **Resolution Time**: Time from detection to resolution

## 🔧 Configuration

### Environment Variables
```bash
# Set in environment files or systemd service
RABBITMQ_ENVIRONMENT=production
EXTERNAL_MONITORING_URL=https://monitoring.company.com/api
```

### Customization
- **Alert Thresholds**: Modify alert rule files
- **Recovery Actions**: Customize recovery scripts
- **Monitoring Frequency**: Adjust systemd timer
- **Notification Channels**: Update Alert Manager config

### Security Considerations
- **Root Access**: Required for recovery operations
- **File Permissions**: Restricted access to sensitive files
- **Network Security**: Firewall rules for monitoring ports
- **Log Security**: Secure log file access

## 🧪 Testing and Validation

### Test Monitoring
```bash
# Test monitoring script
/usr/local/bin/rabbitmq-monitor.sh qa

# Check exit code
echo $?
```

### Test Recovery
```bash
# Test recovery script
/usr/local/bin/rabbitmq-recovery.sh qa manual

# Check recovery actions
tail -f /var/log/rabbitmq/auto-recovery.log
```

### Test Services
```bash
# Check service status
systemctl status prometheus alertmanager rabbitmq-monitor.timer

# Test endpoints
curl http://localhost:9090/api/v1/query?query=up
curl http://localhost:9093/api/v1/alerts
```

## 📋 Maintenance

### Regular Tasks

#### Daily
- Check monitoring logs for errors
- Review recovery actions
- Monitor system resource usage

#### Weekly
- Review alert thresholds
- Clean up old logs
- Update monitoring scripts

#### Monthly
- Review recovery success rates
- Optimize monitoring intervals
- Plan capacity upgrades

### Updates
```bash
# Update Prometheus
cd /opt
wget https://github.com/prometheus/prometheus/releases/download/v2.46.0/prometheus-2.46.0.linux-amd64.tar.gz
tar -xzf prometheus-2.46.0.linux-amd64.tar.gz
ln -sf prometheus-2.46.0 prometheus
systemctl restart prometheus

# Update Alert Manager
cd /opt
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar -xzf alertmanager-0.26.0.linux-amd64.tar.gz
ln -sf alertmanager-0.26.0 alertmanager
systemctl restart alertmanager
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Monitoring Script Fails
```bash
# Check permissions
ls -la /usr/local/bin/rabbitmq-monitor.sh

# Check dependencies
which rabbitmqctl

# Check logs
tail -f /var/log/rabbitmq/cluster-monitor.log
```

#### 2. Recovery Script Fails
```bash
# Check root access
whoami

# Check RabbitMQ status
systemctl status rabbitmq-server

# Check logs
tail -f /var/log/rabbitmq/auto-recovery.log
```

#### 3. Services Not Starting
```bash
# Check systemd status
systemctl status rabbitmq-monitor.timer

# Check service files
ls -la /etc/systemd/system/rabbitmq-monitor*

# Reload systemd
systemctl daemon-reload
```

#### 4. Prometheus Not Accessible
```bash
# Check service status
systemctl status prometheus

# Check port
netstat -tlnp | grep 9090

# Check logs
journalctl -u prometheus -f
```

### Debug Mode
```bash
# Run with verbose output
bash -x /usr/local/bin/rabbitmq-monitor.sh qa

# Check environment variables
env | grep RABBITMQ
```

## 📞 Support

### Getting Help
1. Check the troubleshooting section above
2. Review service logs: `journalctl -u service-name -f`
3. Check script logs: `/var/log/rabbitmq/*.log`
4. Verify configuration files in `/etc/systemd/system/`

### Reporting Issues
When reporting issues, include:
- Environment (qa/staging/prod)
- Script output and exit codes
- Relevant log entries
- System information (OS, RabbitMQ version)
- Steps to reproduce

## 🎯 Success Metrics

### Business Metrics
- **Service Availability**: >99.9%
- **Recovery Success Rate**: >95%
- **Mean Time to Recovery**: <5 minutes
- **Alert Response Time**: <2 minutes

### Technical Metrics
- **Monitoring Coverage**: 100% of cluster nodes
- **Recovery Automation**: >90% of issues auto-resolved
- **False Positive Rate**: <5%
- **System Resource Usage**: <10% overhead

## 🎉 Success!

Once completed, you'll have:
- ✅ **Automated cluster monitoring** every 5 minutes
- ✅ **Intelligent auto-recovery** for common issues
- ✅ **Multi-tier alerting** with team routing
- ✅ **Comprehensive logging** and audit trails
- ✅ **Production-ready monitoring** architecture
- ✅ **Zero-downtime recovery** capabilities

Your RabbitMQ cluster is now **self-monitoring and self-healing**! 🚀

## 📚 Additional Resources

- [Multi-Tier Monitoring Setup](../configs/MULTI-TIER-MONITORING-SETUP.md)
- [Grafana Setup Guide](../configs/GRAFANA-SETUP-GUIDE.md)
- [Security Checklist](../docs/security/security-checklist.md)
- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Alert Manager Documentation](https://prometheus.io/docs/alerting/alertmanager/)
