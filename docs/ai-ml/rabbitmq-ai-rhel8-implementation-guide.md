# AI-Powered RabbitMQ 4.x on RHEL 8 VM - Complete Implementation Guide

## 🎯 Overview

This comprehensive guide provides step-by-step implementation of AI/ML solutions for intelligent RabbitMQ 4.x cluster management on RHEL 8 Virtual Machines, including predictive monitoring, automated scaling, and self-healing capabilities specifically tailored for enterprise RHEL 8 environments.

## 📋 Table of Contents

1. [RHEL 8 System Preparation](#rhel-8-system-preparation)
2. [AI Infrastructure Setup](#ai-infrastructure-setup)
3. [Python AI Environment](#python-ai-environment)
4. [Predictive Analytics Engine](#predictive-analytics-engine)
5. [Intelligent Auto-Scaling](#intelligent-auto-scaling)
6. [Anomaly Detection System](#anomaly-detection-system)
7. [Self-Healing Automation](#self-healing-automation)
8. [RHEL 8 Security Configuration](#rhel-8-security-configuration)
9. [Systemd Services](#systemd-services)
10. [Monitoring & Maintenance](#monitoring--maintenance)

---

## 1. RHEL 8 System Preparation 🖥️

### 1.1 System Requirements and Prerequisites

#### Minimum Hardware Requirements for RHEL 8 AI Implementation:
```bash
# Verify system specifications
echo "=== System Information ==="
hostnamectl
cat /etc/redhat-release
lscpu | grep -E "CPU|Thread|Core"
free -h
df -h
ip addr show
```

**Required Specifications:**
- **CPU**: 8+ cores (Intel Xeon or AMD EPYC preferred)
- **Memory**: 32GB+ RAM (64GB recommended for production)
- **Storage**: 500GB+ available space
- **Network**: 1Gbps+ network interface
- **OS**: RHEL 8.x (8.4+ recommended)

### 1.2 RHEL 8 System Updates and Base Packages

```bash
# Update system to latest packages
sudo dnf update -y

# Install EPEL repository
sudo dnf install -y epel-release

# Install development tools and dependencies
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y \
    git \
    wget \
    curl \
    vim \
    htop \
    tmux \
    nc \
    telnet \
    bind-utils \
    net-tools \
    firewalld \
    policycoreutils-python-utils \
    setools-console

# Install system monitoring tools
sudo dnf install -y \
    iotop \
    iftop \
    tcpdump \
    wireshark-cli \
    strace \
    lsof \
    psmisc
```

### 1.3 SELinux Configuration for AI Services

```bash
# Check SELinux status
getenforce
sestatus

# Configure SELinux for AI services
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1
sudo setsebool -P nis_enabled 1

# Create custom SELinux policy for AI services
sudo tee /tmp/rabbitmq_ai.te <<EOF
module rabbitmq_ai 1.0;

require {
    type init_t;
    type unconfined_t;
    type unconfined_service_t;
    class process { transition };
    class file { execute read };
}

# Allow AI services to execute
allow unconfined_t unconfined_service_t:process transition;
EOF

# Compile and install SELinux policy
sudo checkmodule -M -m -o /tmp/rabbitmq_ai.mod /tmp/rabbitmq_ai.te
sudo semodule_package -o /tmp/rabbitmq_ai.pp -m /tmp/rabbitmq_ai.mod
sudo semodule -i /tmp/rabbitmq_ai.pp

# Verify policy installation
sudo semodule -l | grep rabbitmq_ai
```

### 1.4 Firewall Configuration

```bash
# Configure firewalld for AI services
sudo systemctl enable firewalld
sudo systemctl start firewalld

# AI and ML service ports
sudo firewall-cmd --permanent --add-port=8080/tcp   # AI Engine API
sudo firewall-cmd --permanent --add-port=8081/tcp   # Prediction Service
sudo firewall-cmd --permanent --add-port=8082/tcp   # Anomaly Detection
sudo firewall-cmd --permanent --add-port=8083/tcp   # Auto-scaler API
sudo firewall-cmd --permanent --add-port=9090/tcp   # Prometheus
sudo firewall-cmd --permanent --add-port=3000/tcp   # Grafana
sudo firewall-cmd --permanent --add-port=8086/tcp   # InfluxDB
sudo firewall-cmd --permanent --add-port=6379/tcp   # Redis

# RabbitMQ Management and Metrics
sudo firewall-cmd --permanent --add-port=15672/tcp  # Management UI
sudo firewall-cmd --permanent --add-port=15692/tcp  # Prometheus metrics

# Create custom service definition for RabbitMQ AI
sudo tee /etc/firewalld/services/rabbitmq-ai.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<service>
  <short>RabbitMQ AI Services</short>
  <description>AI-powered RabbitMQ monitoring and management services</description>
  <port protocol="tcp" port="8080"/>
  <port protocol="tcp" port="8081"/>
  <port protocol="tcp" port="8082"/>
  <port protocol="tcp" port="8083"/>
  <port protocol="tcp" port="9090"/>
  <port protocol="tcp" port="3000"/>
  <port protocol="tcp" port="8086"/>
  <port protocol="tcp" port="6379"/>
</service>
EOF

sudo firewall-cmd --permanent --add-service=rabbitmq-ai
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

---

## 2. AI Infrastructure Setup 🏗️

### 2.1 Install and Configure Python 3.9+ on RHEL 8

```bash
# Install Python 3.9 from AppStream
sudo dnf module enable python39 -y
sudo dnf install python39 python39-pip python39-devel -y

# Create symlinks for easier access
sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1
sudo alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.9 1

# Verify installation
python3 --version
pip3 --version

# Upgrade pip and install essential packages
sudo pip3 install --upgrade pip setuptools wheel

# Install AI/ML system dependencies
sudo dnf install -y \
    gcc-c++ \
    cmake \
    lapack-devel \
    blas-devel \
    atlas-devel \
    openblas-devel \
    fftw-devel \
    libpng-devel \
    freetype-devel \
    redis \
    postgresql-devel \
    mariadb-devel
```

### 2.2 Create AI Service User and Directories

```bash
# Create dedicated AI service user
sudo useradd -r -m -s /bin/bash rabbitmq-ai
sudo usermod -a -G wheel rabbitmq-ai

# Create directory structure
sudo mkdir -p /opt/rabbitmq-ai/{bin,lib,logs,config,data,models,scripts}
sudo mkdir -p /var/log/rabbitmq-ai
sudo mkdir -p /var/lib/rabbitmq-ai/{prometheus,influxdb,redis,models}

# Set ownership and permissions
sudo chown -R rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai
sudo chown -R rabbitmq-ai:rabbitmq-ai /var/log/rabbitmq-ai
sudo chown -R rabbitmq-ai:rabbitmq-ai /var/lib/rabbitmq-ai

# Set SELinux contexts
sudo semanage fcontext -a -t unconfined_exec_t "/opt/rabbitmq-ai/bin(/.*)?"
sudo semanage fcontext -a -t var_log_t "/var/log/rabbitmq-ai(/.*)?"
sudo semanage fcontext -a -t var_lib_t "/var/lib/rabbitmq-ai(/.*)?"
sudo restorecon -R /opt/rabbitmq-ai /var/log/rabbitmq-ai /var/lib/rabbitmq-ai
```

### 2.3 Install Time Series Database (InfluxDB 2.x)

```bash
# Add InfluxDB repository
sudo tee /etc/yum.repos.d/influxdb.repo <<EOF
[influxdb]
name = InfluxDB Repository - RHEL 8
baseurl = https://repos.influxdata.com/rhel/8/x86_64/stable/
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF

# Install InfluxDB
sudo dnf install -y influxdb2

# Configure InfluxDB
sudo tee /etc/influxdb/config.toml <<EOF
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"

[http]
  bind-address = ":8086"
  enabled = true
  auth-enabled = false

[logging]
  level = "info"
  file = "/var/log/influxdb/influxdb.log"
EOF

# Start and enable InfluxDB
sudo systemctl enable influxdb
sudo systemctl start influxdb

# Wait for InfluxDB to start
sleep 10

# Initial setup
influx setup --host http://localhost:8086 \
  --org "rabbitmq-ai" \
  --bucket "metrics" \
  --username "admin" \
  --password "SecurePassword2024!" \
  --retention "30d" \
  --force
```

### 2.4 Install and Configure Prometheus

```bash
# Create prometheus user
sudo useradd -r -m -s /bin/false prometheus

# Download and install Prometheus
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xf prometheus-2.45.0.linux-amd64.tar.gz

# Install Prometheus
sudo cp prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Copy configuration files
sudo cp -r prometheus-2.45.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-2.45.0.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries

# Create Prometheus configuration
sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 5s
    metrics_path: /metrics

  - job_name: 'rabbitmq-ai-engine'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 10s
    metrics_path: /metrics

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'influxdb'
    static_configs:
      - targets: ['localhost:8086']
    metrics_path: /metrics
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Create systemd service
sudo tee /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path /var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
```

### 2.5 Install Redis for AI Data Caching

```bash
# Install Redis
sudo dnf install -y redis

# Configure Redis for AI workloads
sudo tee /etc/redis.conf <<EOF
# Network Configuration
bind 127.0.0.1
port 6379
protected-mode yes

# Memory Configuration
maxmemory 4gb
maxmemory-policy allkeys-lru

# Persistence Configuration
save 900 1
save 300 10
save 60 10000

# AI-specific configurations
timeout 300
tcp-keepalive 300
databases 16

# Logging
loglevel notice
logfile /var/log/redis/redis.log

# Security
requirepass "AIRedisPassword2024!"
EOF

sudo systemctl enable redis
sudo systemctl start redis

# Test Redis connection
redis-cli -a "AIRedisPassword2024!" ping
```

---

## 3. Python AI Environment 🐍

### 3.1 Create Python Virtual Environment

```bash
# Switch to AI service user
sudo su - rabbitmq-ai

# Create virtual environment
python3 -m venv /opt/rabbitmq-ai/venv

# Activate virtual environment
source /opt/rabbitmq-ai/venv/bin/activate

# Upgrade pip in virtual environment
pip install --upgrade pip setuptools wheel
```

### 3.2 Install AI/ML Python Packages

```bash
# Create requirements file for AI packages
cat > /opt/rabbitmq-ai/requirements.txt <<EOF
# Core ML Libraries
numpy==1.24.3
pandas==2.0.3
scikit-learn==1.3.0
scipy==1.11.1

# Deep Learning
tensorflow==2.14.0
torch==2.0.1
torchvision==0.15.2

# Time Series Analysis
prophet==1.1.4
statsmodels==0.14.0
tslearn==0.6.2
sktime==0.21.1

# Gradient Boosting
xgboost==1.7.6
lightgbm==4.0.0
catboost==1.2

# Feature Engineering
feature-engine==1.6.1
category-encoders==2.6.0

# Anomaly Detection
pyod==1.1.0
isolation-forest==0.1.2

# API and Web Framework
fastapi==0.103.1
uvicorn==0.23.2
pydantic==2.3.0
starlette==0.27.0

# Database Connectors
influxdb-client==1.38.0
redis==5.0.0
pymongo==4.5.0
psycopg2-binary==2.9.7

# RabbitMQ Integration
pika==1.3.2
celery==5.3.1

# Monitoring and Logging
prometheus-client==0.17.1
structlog==23.1.0
colorlog==6.7.0

# Data Visualization
matplotlib==3.7.2
seaborn==0.12.2
plotly==5.15.0

# Utilities
requests==2.31.0
aiohttp==3.8.5
asyncio-mqtt==0.16.1
schedule==1.2.0
python-dotenv==1.0.0
pyyaml==6.0.1
jsonschema==4.19.0

# Natural Language Processing
openai==0.28.1
transformers==4.33.2
spacy==3.6.1

# Communication
slack-sdk==3.22.0
discord.py==2.3.2

# System Monitoring
psutil==5.9.5
py-cpuinfo==9.0.0
GPUtil==1.4.0

# Development and Testing
pytest==7.4.2
pytest-asyncio==0.21.1
black==23.7.0
flake8==6.0.0
mypy==1.5.1
EOF

# Install all packages
pip install -r /opt/rabbitmq-ai/requirements.txt

# Install additional RHEL 8 specific packages
pip install \
    systemd-python==235 \
    python-systemd==234 \
    setproctitle==1.3.2

# Exit from rabbitmq-ai user
exit
```

### 3.3 Configure Python Environment Variables

```bash
# Create environment configuration
sudo tee /opt/rabbitmq-ai/config/ai_environment.env <<EOF
# Python Environment
PYTHONPATH=/opt/rabbitmq-ai/lib:/opt/rabbitmq-ai/venv/lib/python3.9/site-packages
VIRTUAL_ENV=/opt/rabbitmq-ai/venv
PATH=/opt/rabbitmq-ai/venv/bin:/opt/rabbitmq-ai/bin:$PATH

# AI Service Configuration
AI_SERVICE_HOST=127.0.0.1
AI_SERVICE_PORT=8080
AI_LOG_LEVEL=INFO
AI_LOG_FILE=/var/log/rabbitmq-ai/ai-engine.log

# Database Connections
INFLUXDB_URL=http://127.0.0.1:8086
INFLUXDB_TOKEN=your-influxdb-token
INFLUXDB_ORG=rabbitmq-ai
INFLUXDB_BUCKET=metrics

REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=AIRedisPassword2024!
REDIS_DB=0

PROMETHEUS_URL=http://127.0.0.1:9090

# RabbitMQ Configuration
RABBITMQ_HOST=127.0.0.1
RABBITMQ_PORT=5672
RABBITMQ_MANAGEMENT_PORT=15672
RABBITMQ_METRICS_PORT=15692
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=your-rabbitmq-password

# Model Storage
MODEL_STORAGE_PATH=/var/lib/rabbitmq-ai/models
MODEL_REGISTRY_URL=http://127.0.0.1:5000

# Security
AI_SECRET_KEY=your-secret-key-change-this
JWT_SECRET_KEY=your-jwt-secret-key

# Notification Services
SLACK_BOT_TOKEN=your-slack-bot-token
SLACK_WEBHOOK_URL=your-slack-webhook-url
EMAIL_SMTP_SERVER=smtp.company.com
EMAIL_SMTP_PORT=587

# Feature Flags
ENABLE_PREDICTIVE_SCALING=true
ENABLE_ANOMALY_DETECTION=true
ENABLE_SELF_HEALING=true
ENABLE_CHATOPS=true
ENABLE_VOICE_INTERFACE=false

# Performance Tuning
MAX_WORKERS=4
PREDICTION_BATCH_SIZE=1000
MODEL_UPDATE_INTERVAL=3600
METRICS_COLLECTION_INTERVAL=30
EOF

sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/config/ai_environment.env
sudo chmod 600 /opt/rabbitmq-ai/config/ai_environment.env
```

---

## 4. Predictive Analytics Engine 📊

### 4.1 Time Series Data Collection Service

```python
# Create the main AI engine structure
sudo mkdir -p /opt/rabbitmq-ai/lib/{collectors,predictors,anomaly,scaling,healing,api}

# Time Series Data Collector
sudo tee /opt/rabbitmq-ai/lib/collectors/metrics_collector.py <<'EOF'
#!/usr/bin/env python3
"""
RabbitMQ Metrics Collector for RHEL 8
Collects comprehensive metrics from RabbitMQ cluster and system resources
"""

import asyncio
import aiohttp
import json
import time
import logging
import psutil
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
import redis

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rabbitmq-ai/metrics-collector.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class RabbitMQMetrics:
    """RabbitMQ cluster metrics data structure"""
    timestamp: datetime
    node_name: str
    # Node metrics
    memory_used: int
    memory_limit: int
    disk_free: int
    disk_free_limit: int
    fd_used: int
    fd_total: int
    sockets_used: int
    sockets_total: int
    erlang_processes: int
    uptime: int
    
    # Queue metrics
    total_queues: int
    total_messages: int
    messages_ready: int
    messages_unacknowledged: int
    message_rate: float
    publish_rate: float
    deliver_rate: float
    ack_rate: float
    
    # Connection metrics
    total_connections: int
    total_channels: int
    total_consumers: int
    
    # System metrics (RHEL 8 specific)
    cpu_usage: float
    cpu_load_1m: float
    cpu_load_5m: float
    cpu_load_15m: float
    memory_usage_percent: float
    disk_usage_percent: float
    network_rx_bytes: int
    network_tx_bytes: int

class RHELSystemCollector:
    """Collect RHEL 8 system metrics"""
    
    def __init__(self):
        self.previous_network = None
        
    def collect_system_metrics(self) -> Dict:
        """Collect comprehensive RHEL 8 system metrics"""
        try:
            # CPU metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_count = psutil.cpu_count()
            load_avg = os.getloadavg()
            
            # Memory metrics
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            
            # Disk metrics
            disk = psutil.disk_usage('/')
            disk_io = psutil.disk_io_counters()
            
            # Network metrics
            network = psutil.net_io_counters()
            
            # Process metrics
            process_count = len(psutil.pids())
            
            # RHEL 8 specific - check systemd services
            rabbitmq_status = self._check_systemd_service('rabbitmq-server')
            
            return {
                'cpu_usage': cpu_percent,
                'cpu_count': cpu_count,
                'cpu_load_1m': load_avg[0],
                'cpu_load_5m': load_avg[1],
                'cpu_load_15m': load_avg[2],
                'memory_total': memory.total,
                'memory_used': memory.used,
                'memory_available': memory.available,
                'memory_usage_percent': memory.percent,
                'swap_total': swap.total,
                'swap_used': swap.used,
                'swap_percent': swap.percent,
                'disk_total': disk.total,
                'disk_used': disk.used,
                'disk_free': disk.free,
                'disk_usage_percent': disk.percent,
                'disk_read_bytes': disk_io.read_bytes if disk_io else 0,
                'disk_write_bytes': disk_io.write_bytes if disk_io else 0,
                'network_rx_bytes': network.bytes_recv,
                'network_tx_bytes': network.bytes_sent,
                'network_rx_packets': network.packets_recv,
                'network_tx_packets': network.packets_sent,
                'process_count': process_count,
                'rabbitmq_service_status': rabbitmq_status
            }
        except Exception as e:
            logger.error(f"Error collecting system metrics: {e}")
            return {}
    
    def _check_systemd_service(self, service_name: str) -> str:
        """Check systemd service status"""
        try:
            import subprocess
            result = subprocess.run(
                ['systemctl', 'is-active', service_name],
                capture_output=True,
                text=True
            )
            return result.stdout.strip()
        except Exception:
            return 'unknown'

class RabbitMQMetricsCollector:
    """Main metrics collector for RabbitMQ and system metrics"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.influx_client = None
        self.redis_client = None
        self.system_collector = RHELSystemCollector()
        self._initialize_connections()
    
    def _initialize_connections(self):
        """Initialize database connections"""
        try:
            # InfluxDB connection
            self.influx_client = InfluxDBClient(
                url=self.config['influxdb_url'],
                token=self.config['influxdb_token'],
                org=self.config['influxdb_org']
            )
            self.write_api = self.influx_client.write_api(write_options=SYNCHRONOUS)
            
            # Redis connection
            self.redis_client = redis.Redis(
                host=self.config['redis_host'],
                port=self.config['redis_port'],
                password=self.config['redis_password'],
                db=self.config['redis_db'],
                decode_responses=True
            )
            
            logger.info("Database connections initialized successfully")
            
        except Exception as e:
            logger.error(f"Error initializing connections: {e}")
    
    async def collect_rabbitmq_metrics(self, node_url: str) -> Optional[Dict]:
        """Collect metrics from RabbitMQ management API"""
        try:
            auth = aiohttp.BasicAuth(
                self.config['rabbitmq_user'],
                self.config['rabbitmq_password']
            )
            
            async with aiohttp.ClientSession(auth=auth) as session:
                # Collect node metrics
                node_metrics = await self._get_node_metrics(session, node_url)
                
                # Collect queue metrics
                queue_metrics = await self._get_queue_metrics(session, node_url)
                
                # Collect connection metrics
                connection_metrics = await self._get_connection_metrics(session, node_url)
                
                # Collect overview metrics
                overview_metrics = await self._get_overview_metrics(session, node_url)
                
                # Combine all metrics
                combined_metrics = {
                    **node_metrics,
                    **queue_metrics,
                    **connection_metrics,
                    **overview_metrics
                }
                
                return combined_metrics
                
        except Exception as e:
            logger.error(f"Error collecting RabbitMQ metrics: {e}")
            return None
    
    async def _get_node_metrics(self, session: aiohttp.ClientSession, base_url: str) -> Dict:
        """Get node-specific metrics"""
        try:
            url = f"{base_url}/api/nodes"
            async with session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    if data:
                        node = data[0]  # Get first node
                        return {
                            'node_name': node.get('name', 'unknown'),
                            'memory_used': node.get('mem_used', 0),
                            'memory_limit': node.get('mem_limit', 0),
                            'disk_free': node.get('disk_free', 0),
                            'disk_free_limit': node.get('disk_free_limit', 0),
                            'fd_used': node.get('fd_used', 0),
                            'fd_total': node.get('fd_total', 0),
                            'sockets_used': node.get('sockets_used', 0),
                            'sockets_total': node.get('sockets_total', 0),
                            'erlang_processes': node.get('proc_used', 0),
                            'uptime': node.get('uptime', 0)
                        }
        except Exception as e:
            logger.error(f"Error getting node metrics: {e}")
        
        return {}
    
    async def _get_queue_metrics(self, session: aiohttp.ClientSession, base_url: str) -> Dict:
        """Get queue metrics"""
        try:
            url = f"{base_url}/api/queues"
            async with session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    
                    total_queues = len(data)
                    total_messages = sum(q.get('messages', 0) for q in data)
                    messages_ready = sum(q.get('messages_ready', 0) for q in data)
                    messages_unack = sum(q.get('messages_unacknowledged', 0) for q in data)
                    
                    # Calculate rates
                    publish_rate = sum(
                        q.get('message_stats', {}).get('publish_details', {}).get('rate', 0) 
                        for q in data
                    )
                    deliver_rate = sum(
                        q.get('message_stats', {}).get('deliver_get_details', {}).get('rate', 0) 
                        for q in data
                    )
                    ack_rate = sum(
                        q.get('message_stats', {}).get('ack_details', {}).get('rate', 0) 
                        for q in data
                    )
                    
                    return {
                        'total_queues': total_queues,
                        'total_messages': total_messages,
                        'messages_ready': messages_ready,
                        'messages_unacknowledged': messages_unack,
                        'message_rate': publish_rate,
                        'publish_rate': publish_rate,
                        'deliver_rate': deliver_rate,
                        'ack_rate': ack_rate
                    }
        except Exception as e:
            logger.error(f"Error getting queue metrics: {e}")
        
        return {}
    
    async def _get_connection_metrics(self, session: aiohttp.ClientSession, base_url: str) -> Dict:
        """Get connection metrics"""
        try:
            # Get connections
            conn_url = f"{base_url}/api/connections"
            async with session.get(conn_url) as response:
                connections = await response.json() if response.status == 200 else []
            
            # Get channels
            chan_url = f"{base_url}/api/channels"
            async with session.get(chan_url) as response:
                channels = await response.json() if response.status == 200 else []
            
            # Get consumers
            cons_url = f"{base_url}/api/consumers"
            async with session.get(cons_url) as response:
                consumers = await response.json() if response.status == 200 else []
            
            return {
                'total_connections': len(connections),
                'total_channels': len(channels),
                'total_consumers': len(consumers)
            }
        except Exception as e:
            logger.error(f"Error getting connection metrics: {e}")
        
        return {}
    
    async def _get_overview_metrics(self, session: aiohttp.ClientSession, base_url: str) -> Dict:
        """Get overview metrics"""
        try:
            url = f"{base_url}/api/overview"
            async with session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        'rabbitmq_version': data.get('rabbitmq_version', ''),
                        'erlang_version': data.get('erlang_version', ''),
                        'cluster_name': data.get('cluster_name', ''),
                        'node_count': len(data.get('contexts', []))
                    }
        except Exception as e:
            logger.error(f"Error getting overview metrics: {e}")
        
        return {}
    
    def store_metrics(self, metrics: Dict):
        """Store metrics in InfluxDB and Redis"""
        try:
            timestamp = datetime.now(timezone.utc)
            
            # Store in InfluxDB for long-term storage
            self._store_in_influxdb(metrics, timestamp)
            
            # Store in Redis for real-time access
            self._store_in_redis(metrics, timestamp)
            
        except Exception as e:
            logger.error(f"Error storing metrics: {e}")
    
    def _store_in_influxdb(self, metrics: Dict, timestamp: datetime):
        """Store metrics in InfluxDB"""
        try:
            points = []
            
            # RabbitMQ metrics point
            rabbitmq_point = Point("rabbitmq_metrics") \
                .time(timestamp) \
                .tag("node", metrics.get('node_name', 'unknown'))
            
            for key, value in metrics.items():
                if isinstance(value, (int, float)) and key != 'timestamp':
                    rabbitmq_point = rabbitmq_point.field(key, value)
            
            points.append(rabbitmq_point)
            
            # System metrics point
            system_point = Point("system_metrics") \
                .time(timestamp) \
                .tag("hostname", os.uname().nodename)
            
            system_metrics = self.system_collector.collect_system_metrics()
            for key, value in system_metrics.items():
                if isinstance(value, (int, float)):
                    system_point = system_point.field(key, value)
                elif isinstance(value, str):
                    system_point = system_point.tag(key, value)
            
            points.append(system_point)
            
            # Write points to InfluxDB
            self.write_api.write(
                bucket=self.config['influxdb_bucket'],
                record=points
            )
            
            logger.debug(f"Stored {len(points)} points in InfluxDB")
            
        except Exception as e:
            logger.error(f"Error storing in InfluxDB: {e}")
    
    def _store_in_redis(self, metrics: Dict, timestamp: datetime):
        """Store latest metrics in Redis for real-time access"""
        try:
            # Store current metrics
            redis_key = "rabbitmq:metrics:current"
            self.redis_client.hset(redis_key, mapping={
                'timestamp': timestamp.isoformat(),
                'data': json.dumps(metrics)
            })
            self.redis_client.expire(redis_key, 300)  # 5 minute expiry
            
            # Store in time series for sliding window
            ts_key = f"rabbitmq:metrics:timeseries"
            self.redis_client.lpush(ts_key, json.dumps({
                'timestamp': timestamp.isoformat(),
                'metrics': metrics
            }))
            self.redis_client.ltrim(ts_key, 0, 1000)  # Keep last 1000 entries
            
            logger.debug("Stored metrics in Redis")
            
        except Exception as e:
            logger.error(f"Error storing in Redis: {e}")
    
    async def start_collection_loop(self):
        """Start the main collection loop"""
        logger.info("Starting metrics collection loop")
        
        rabbitmq_urls = [
            f"http://{self.config['rabbitmq_host']}:{self.config['rabbitmq_management_port']}"
        ]
        
        while True:
            try:
                for url in rabbitmq_urls:
                    metrics = await self.collect_rabbitmq_metrics(url)
                    if metrics:
                        # Add system metrics
                        system_metrics = self.system_collector.collect_system_metrics()
                        metrics.update(system_metrics)
                        
                        # Store metrics
                        self.store_metrics(metrics)
                        
                        logger.info(f"Collected and stored metrics from {url}")
                
                # Wait for next collection interval
                await asyncio.sleep(int(self.config.get('collection_interval', 30)))
                
            except Exception as e:
                logger.error(f"Error in collection loop: {e}")
                await asyncio.sleep(60)  # Wait 1 minute on error

def load_config() -> Dict:
    """Load configuration from environment file"""
    config = {}
    
    # Load from environment file
    env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if '=' in line and not line.strip().startswith('#'):
                    key, value = line.strip().split('=', 1)
                    config[key.lower()] = value
    
    # Override with environment variables
    config.update({
        'influxdb_url': os.getenv('INFLUXDB_URL', 'http://127.0.0.1:8086'),
        'influxdb_token': os.getenv('INFLUXDB_TOKEN', ''),
        'influxdb_org': os.getenv('INFLUXDB_ORG', 'rabbitmq-ai'),
        'influxdb_bucket': os.getenv('INFLUXDB_BUCKET', 'metrics'),
        'redis_host': os.getenv('REDIS_HOST', '127.0.0.1'),
        'redis_port': int(os.getenv('REDIS_PORT', 6379)),
        'redis_password': os.getenv('REDIS_PASSWORD', ''),
        'redis_db': int(os.getenv('REDIS_DB', 0)),
        'rabbitmq_host': os.getenv('RABBITMQ_HOST', '127.0.0.1'),
        'rabbitmq_management_port': int(os.getenv('RABBITMQ_MANAGEMENT_PORT', 15672)),
        'rabbitmq_user': os.getenv('RABBITMQ_USER', 'admin'),
        'rabbitmq_password': os.getenv('RABBITMQ_PASSWORD', ''),
        'collection_interval': int(os.getenv('METRICS_COLLECTION_INTERVAL', 30))
    })
    
    return config

async def main():
    """Main function"""
    try:
        config = load_config()
        collector = RabbitMQMetricsCollector(config)
        await collector.start_collection_loop()
    except KeyboardInterrupt:
        logger.info("Metrics collection stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")

if __name__ == "__main__":
    asyncio.run(main())
EOF

sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/collectors/metrics_collector.py
sudo chmod +x /opt/rabbitmq-ai/lib/collectors/metrics_collector.py
```

### 4.2 Predictive Analytics Models

```python
# Queue Growth Predictor with RHEL 8 optimizations
sudo tee /opt/rabbitmq-ai/lib/predictors/queue_predictor.py <<'EOF'
#!/usr/bin/env python3
"""
Queue Growth Predictor for RabbitMQ on RHEL 8
Uses LSTM and Prophet models for queue growth prediction
"""

import pandas as pd
import numpy as np
import logging
import pickle
import os
import json
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass

# ML Libraries
from sklearn.preprocessing import MinMaxScaler, StandardScaler
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import tensorflow as tf
from tensorflow.keras.models import Sequential, load_model
from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from prophet import Prophet
import joblib

# Database connections
from influxdb_client import InfluxDBClient
import redis

# Configure logging
logger = logging.getLogger(__name__)

@dataclass
class PredictionResult:
    """Prediction result structure"""
    timestamp: datetime
    queue_name: str
    predicted_messages: float
    confidence_interval_lower: float
    confidence_interval_upper: float
    prediction_horizon_minutes: int
    model_used: str
    confidence_score: float

class RHELOptimizedLSTM:
    """LSTM model optimized for RHEL 8 systems"""
    
    def __init__(self, sequence_length: int = 60, features: int = 5):
        self.sequence_length = sequence_length
        self.features = features
        self.model = None
        self.scaler = MinMaxScaler()
        self.feature_scaler = StandardScaler()
        
        # RHEL 8 specific optimizations
        self._configure_tensorflow_for_rhel8()
    
    def _configure_tensorflow_for_rhel8(self):
        """Configure TensorFlow for optimal performance on RHEL 8"""
        try:
            # Set CPU optimizations for RHEL 8
            tf.config.threading.set_intra_op_parallelism_threads(0)  # Use all available cores
            tf.config.threading.set_inter_op_parallelism_threads(0)
            
            # Enable memory growth for GPU if available
            gpus = tf.config.list_physical_devices('GPU')
            if gpus:
                for gpu in gpus:
                    tf.config.experimental.set_memory_growth(gpu, True)
            
            # Set CPU feature optimizations
            os.environ['TF_ENABLE_ONEDNN_OPTS'] = '1'
            
            logger.info("TensorFlow configured for RHEL 8 optimization")
            
        except Exception as e:
            logger.warning(f"Could not apply RHEL 8 TensorFlow optimizations: {e}")
    
    def build_model(self) -> Sequential:
        """Build LSTM model architecture"""
        model = Sequential([
            LSTM(100, return_sequences=True, input_shape=(self.sequence_length, self.features)),
            Dropout(0.2),
            BatchNormalization(),
            
            LSTM(100, return_sequences=True),
            Dropout(0.2),
            BatchNormalization(),
            
            LSTM(50, return_sequences=False),
            Dropout(0.2),
            
            Dense(25, activation='relu'),
            Dropout(0.1),
            Dense(1, activation='linear')
        ])
        
        model.compile(
            optimizer=Adam(learning_rate=0.001),
            loss='mse',
            metrics=['mae', 'mse']
        )
        
        return model
    
    def prepare_data(self, df: pd.DataFrame) -> Tuple[np.ndarray, np.ndarray]:
        """Prepare time series data for LSTM training"""
        try:
            # Feature engineering
            df = self._engineer_features(df)
            
            # Select features for training
            feature_columns = [
                'messages_normalized',
                'message_rate_normalized', 
                'consumer_count_normalized',
                'memory_usage_normalized',
                'hour_sin', 'hour_cos',
                'day_sin', 'day_cos',
                'is_business_hour',
                'is_weekend'
            ]
            
            # Ensure we have the required features
            available_features = [col for col in feature_columns if col in df.columns]
            self.features = len(available_features)
            
            # Scale features
            feature_data = self.feature_scaler.fit_transform(df[available_features])
            
            # Create sequences
            X, y = [], []
            for i in range(self.sequence_length, len(feature_data)):
                X.append(feature_data[i-self.sequence_length:i])
                y.append(feature_data[i, 0])  # Predict normalized messages
            
            return np.array(X), np.array(y)
            
        except Exception as e:
            logger.error(f"Error preparing LSTM data: {e}")
            return np.array([]), np.array([])
    
    def _engineer_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Engineer features for better prediction"""
        df = df.copy()
        
        # Normalize core metrics
        df['messages_normalized'] = self.scaler.fit_transform(df[['total_messages']])
        df['message_rate_normalized'] = self.scaler.fit_transform(df[['message_rate']])
        df['consumer_count_normalized'] = self.scaler.fit_transform(df[['total_consumers']])
        df['memory_usage_normalized'] = self.scaler.fit_transform(df[['memory_usage_percent']])
        
        # Time-based features
        df['hour'] = df['timestamp'].dt.hour
        df['day_of_week'] = df['timestamp'].dt.dayofweek
        df['month'] = df['timestamp'].dt.month
        
        # Cyclical encoding
        df['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
        df['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)
        df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
        df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
        
        # Business logic features
        df['is_business_hour'] = ((df['hour'] >= 9) & (df['hour'] <= 17) & 
                                 (df['day_of_week'] < 5)).astype(int)
        df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
        
        # Rolling statistics
        df['messages_rolling_mean_1h'] = df['total_messages'].rolling(window=12).mean()
        df['messages_rolling_std_1h'] = df['total_messages'].rolling(window=12).std()
        df['message_rate_rolling_mean_1h'] = df['message_rate'].rolling(window=12).mean()
        
        return df.fillna(method='bfill').fillna(0)
    
    def train(self, X: np.ndarray, y: np.ndarray, validation_split: float = 0.2) -> Dict:
        """Train the LSTM model"""
        try:
            self.model = self.build_model()
            
            # Callbacks
            early_stopping = EarlyStopping(
                monitor='val_loss',
                patience=10,
                restore_best_weights=True
            )
            
            model_checkpoint = ModelCheckpoint(
                '/var/lib/rabbitmq-ai/models/lstm_queue_predictor.h5',
                monitor='val_loss',
                save_best_only=True
            )
            
            # Train model
            history = self.model.fit(
                X, y,
                epochs=100,
                batch_size=32,
                validation_split=validation_split,
                callbacks=[early_stopping, model_checkpoint],
                verbose=1
            )
            
            # Calculate metrics
            train_predictions = self.model.predict(X)
            train_mae = mean_absolute_error(y, train_predictions)
            train_mse = mean_squared_error(y, train_predictions)
            train_r2 = r2_score(y, train_predictions)
            
            metrics = {
                'train_mae': train_mae,
                'train_mse': train_mse,
                'train_r2': train_r2,
                'epochs_trained': len(history.history['loss']),
                'final_train_loss': history.history['loss'][-1],
                'final_val_loss': history.history['val_loss'][-1]
            }
            
            logger.info(f"LSTM model trained successfully: {metrics}")
            return metrics
            
        except Exception as e:
            logger.error(f"Error training LSTM model: {e}")
            return {}
    
    def predict(self, X: np.ndarray, steps_ahead: int = 12) -> List[float]:
        """Make predictions using the trained model"""
        try:
            if self.model is None:
                logger.error("Model not trained yet")
                return []
            
            predictions = []
            current_sequence = X[-1:].copy()  # Last sequence
            
            for _ in range(steps_ahead):
                pred = self.model.predict(current_sequence, verbose=0)
                predictions.append(pred[0, 0])
                
                # Update sequence for next prediction
                new_row = current_sequence[0, -1:].copy()
                new_row[0, 0] = pred[0, 0]  # Update messages value
                current_sequence = np.concatenate([
                    current_sequence[:, 1:, :],
                    new_row.reshape(1, 1, -1)
                ], axis=1)
            
            # Inverse transform predictions
            predictions_reshaped = np.array(predictions).reshape(-1, 1)
            predictions_orig = self.scaler.inverse_transform(predictions_reshaped).flatten()
            
            return predictions_orig.tolist()
            
        except Exception as e:
            logger.error(f"Error making LSTM predictions: {e}")
            return []
    
    def save_model(self, model_path: str):
        """Save the trained model and scalers"""
        try:
            # Save model
            self.model.save(model_path)
            
            # Save scalers
            scaler_path = model_path.replace('.h5', '_scaler.pkl')
            feature_scaler_path = model_path.replace('.h5', '_feature_scaler.pkl')
            
            joblib.dump(self.scaler, scaler_path)
            joblib.dump(self.feature_scaler, feature_scaler_path)
            
            logger.info(f"Model saved to {model_path}")
            
        except Exception as e:
            logger.error(f"Error saving model: {e}")
    
    def load_model(self, model_path: str):
        """Load trained model and scalers"""
        try:
            # Load model
            self.model = load_model(model_path)
            
            # Load scalers
            scaler_path = model_path.replace('.h5', '_scaler.pkl')
            feature_scaler_path = model_path.replace('.h5', '_feature_scaler.pkl')
            
            if os.path.exists(scaler_path):
                self.scaler = joblib.load(scaler_path)
            if os.path.exists(feature_scaler_path):
                self.feature_scaler = joblib.load(feature_scaler_path)
            
            logger.info(f"Model loaded from {model_path}")
            
        except Exception as e:
            logger.error(f"Error loading model: {e}")

class ProphetPredictor:
    """Prophet model for long-term forecasting"""
    
    def __init__(self):
        self.model = None
        self.fitted = False
    
    def prepare_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """Prepare data for Prophet model"""
        prophet_df = df[['timestamp', 'total_messages']].copy()
        prophet_df.columns = ['ds', 'y']
        prophet_df['ds'] = pd.to_datetime(prophet_df['ds'])
        
        return prophet_df
    
    def train(self, df: pd.DataFrame) -> Dict:
        """Train Prophet model"""
        try:
            prophet_df = self.prepare_data(df)
            
            self.model = Prophet(
                changepoint_prior_scale=0.05,
                seasonality_prior_scale=10,
                seasonality_mode='multiplicative',
                daily_seasonality=True,
                weekly_seasonality=True,
                yearly_seasonality=False
            )
            
            # Add custom seasonalities
            self.model.add_seasonality(
                name='hourly',
                period=1,
                fourier_order=8
            )
            
            # Fit model
            self.model.fit(prophet_df)
            self.fitted = True
            
            # Calculate cross-validation metrics
            from prophet.diagnostics import cross_validation, performance_metrics
            
            cv_results = cross_validation(
                self.model,
                initial='24 hours',
                period='6 hours',
                horizon='12 hours'
            )
            
            metrics = performance_metrics(cv_results)
            
            logger.info("Prophet model trained successfully")
            return {
                'mae': metrics['mae'].mean(),
                'mape': metrics['mape'].mean(),
                'rmse': metrics['rmse'].mean()
            }
            
        except Exception as e:
            logger.error(f"Error training Prophet model: {e}")
            return {}
    
    def predict(self, hours_ahead: int = 24) -> pd.DataFrame:
        """Make predictions using Prophet"""
        try:
            if not self.fitted:
                logger.error("Prophet model not trained yet")
                return pd.DataFrame()
            
            # Create future dataframe
            future = self.model.make_future_dataframe(
                periods=hours_ahead * 12,  # 5-minute intervals
                freq='5min'
            )
            
            # Make predictions
            forecast = self.model.predict(future)
            
            # Return only future predictions
            future_forecast = forecast.tail(hours_ahead * 12)[
                ['ds', 'yhat', 'yhat_lower', 'yhat_upper']
            ].copy()
            
            future_forecast.columns = [
                'timestamp', 'predicted_messages', 
                'confidence_lower', 'confidence_upper'
            ]
            
            return future_forecast
            
        except Exception as e:
            logger.error(f"Error making Prophet predictions: {e}")
            return pd.DataFrame()
    
    def save_model(self, model_path: str):
        """Save Prophet model"""
        try:
            with open(model_path, 'wb') as f:
                pickle.dump(self.model, f)
            logger.info(f"Prophet model saved to {model_path}")
        except Exception as e:
            logger.error(f"Error saving Prophet model: {e}")
    
    def load_model(self, model_path: str):
        """Load Prophet model"""
        try:
            with open(model_path, 'rb') as f:
                self.model = pickle.load(f)
            self.fitted = True
            logger.info(f"Prophet model loaded from {model_path}")
        except Exception as e:
            logger.error(f"Error loading Prophet model: {e}")

class QueueGrowthPredictor:
    """Main queue growth prediction service"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.lstm_model = RHELOptimizedLSTM()
        self.prophet_model = ProphetPredictor()
        self.influx_client = None
        self.redis_client = None
        self._initialize_connections()
    
    def _initialize_connections(self):
        """Initialize database connections"""
        try:
            self.influx_client = InfluxDBClient(
                url=self.config['influxdb_url'],
                token=self.config['influxdb_token'],
                org=self.config['influxdb_org']
            )
            
            import redis
            self.redis_client = redis.Redis(
                host=self.config['redis_host'],
                port=self.config['redis_port'],
                password=self.config['redis_password'],
                db=self.config['redis_db'],
                decode_responses=True
            )
            
            logger.info("Prediction service connections initialized")
            
        except Exception as e:
            logger.error(f"Error initializing connections: {e}")
    
    def get_training_data(self, days_back: int = 30) -> pd.DataFrame:
        """Get training data from InfluxDB"""
        try:
            query = f'''
            from(bucket: "{self.config['influxdb_bucket']}")
              |> range(start: -{days_back}d)
              |> filter(fn: (r) => r._measurement == "rabbitmq_metrics")
              |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
              |> keep(columns: ["_time", "total_messages", "message_rate", "total_consumers", "memory_usage_percent"])
            '''
            
            query_api = self.influx_client.query_api()
            result = query_api.query_data_frame(query)
            
            if not result.empty:
                result['timestamp'] = pd.to_datetime(result['_time'])
                result = result.drop(columns=['_time']).sort_values('timestamp')
                
                # Fill missing values
                result = result.fillna(method='forward').fillna(0)
                
                logger.info(f"Retrieved {len(result)} training samples")
                return result
            else:
                logger.warning("No training data found")
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"Error getting training data: {e}")
            return pd.DataFrame()
    
    def train_models(self) -> Dict:
        """Train both LSTM and Prophet models"""
        try:
            # Get training data
            df = self.get_training_data(days_back=30)
            
            if df.empty:
                logger.error("No training data available")
                return {}
            
            results = {}
            
            # Train LSTM model
            logger.info("Training LSTM model...")
            X, y = self.lstm_model.prepare_data(df)
            if len(X) > 0:
                lstm_metrics = self.lstm_model.train(X, y)
                self.lstm_model.save_model('/var/lib/rabbitmq-ai/models/lstm_queue_predictor.h5')
                results['lstm'] = lstm_metrics
            
            # Train Prophet model
            logger.info("Training Prophet model...")
            prophet_metrics = self.prophet_model.train(df)
            self.prophet_model.save_model('/var/lib/rabbitmq-ai/models/prophet_queue_predictor.pkl')
            results['prophet'] = prophet_metrics
            
            # Store training results
            self._store_training_results(results)
            
            return results
            
        except Exception as e:
            logger.error(f"Error training models: {e}")
            return {}
    
    def predict_queue_growth(self, hours_ahead: int = 6) -> List[PredictionResult]:
        """Make queue growth predictions using both models"""
        try:
            predictions = []
            
            # Get recent data for LSTM
            recent_df = self.get_training_data(days_back=7)
            
            if not recent_df.empty:
                # LSTM predictions (short-term)
                X, _ = self.lstm_model.prepare_data(recent_df)
                if len(X) > 0:
                    lstm_predictions = self.lstm_model.predict(X, steps_ahead=hours_ahead * 12)
                    
                    # Prophet predictions (long-term)
                    prophet_forecast = self.prophet_model.predict(hours_ahead=hours_ahead)
                    
                    # Combine predictions
                    current_time = datetime.now()
                    
                    for i, lstm_pred in enumerate(lstm_predictions):
                        pred_time = current_time + timedelta(minutes=5 * (i + 1))
                        
                        # Get corresponding Prophet prediction
                        prophet_pred = 0
                        confidence_lower = lstm_pred * 0.9
                        confidence_upper = lstm_pred * 1.1
                        
                        if not prophet_forecast.empty and i < len(prophet_forecast):
                            prophet_row = prophet_forecast.iloc[i]
                            prophet_pred = prophet_row['predicted_messages']
                            confidence_lower = prophet_row['confidence_lower']
                            confidence_upper = prophet_row['confidence_upper']
                        
                        # Ensemble prediction (weighted average)
                        final_prediction = 0.7 * lstm_pred + 0.3 * prophet_pred
                        confidence_score = min(1.0, 1.0 - abs(lstm_pred - prophet_pred) / max(lstm_pred, 1))
                        
                        predictions.append(PredictionResult(
                            timestamp=pred_time,
                            queue_name="all_queues",
                            predicted_messages=final_prediction,
                            confidence_interval_lower=confidence_lower,
                            confidence_interval_upper=confidence_upper,
                            prediction_horizon_minutes=5 * (i + 1),
                            model_used="lstm_prophet_ensemble",
                            confidence_score=confidence_score
                        ))
            
            # Store predictions in Redis
            self._store_predictions(predictions)
            
            return predictions
            
        except Exception as e:
            logger.error(f"Error making predictions: {e}")
            return []
    
    def _store_predictions(self, predictions: List[PredictionResult]):
        """Store predictions in Redis"""
        try:
            predictions_data = []
            for pred in predictions:
                predictions_data.append({
                    'timestamp': pred.timestamp.isoformat(),
                    'queue_name': pred.queue_name,
                    'predicted_messages': pred.predicted_messages,
                    'confidence_interval_lower': pred.confidence_interval_lower,
                    'confidence_interval_upper': pred.confidence_interval_upper,
                    'prediction_horizon_minutes': pred.prediction_horizon_minutes,
                    'model_used': pred.model_used,
                    'confidence_score': pred.confidence_score
                })
            
            # Store in Redis
            self.redis_client.set(
                'rabbitmq:predictions:queue_growth',
                json.dumps(predictions_data),
                ex=3600  # 1 hour expiry
            )
            
            logger.info(f"Stored {len(predictions)} predictions in Redis")
            
        except Exception as e:
            logger.error(f"Error storing predictions: {e}")
    
    def _store_training_results(self, results: Dict):
        """Store training results"""
        try:
            training_data = {
                'timestamp': datetime.now().isoformat(),
                'results': results
            }
            
            self.redis_client.set(
                'rabbitmq:training:results',
                json.dumps(training_data),
                ex=86400  # 24 hour expiry
            )
            
            logger.info("Training results stored")
            
        except Exception as e:
            logger.error(f"Error storing training results: {e}")

def load_config() -> Dict:
    """Load configuration for prediction service"""
    config = {}
    
    # Load from environment file
    env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if '=' in line and not line.strip().startswith('#'):
                    key, value = line.strip().split('=', 1)
                    config[key.lower()] = value
    
    # Override with environment variables
    config.update({
        'influxdb_url': os.getenv('INFLUXDB_URL', 'http://127.0.0.1:8086'),
        'influxdb_token': os.getenv('INFLUXDB_TOKEN', ''),
        'influxdb_org': os.getenv('INFLUXDB_ORG', 'rabbitmq-ai'),
        'influxdb_bucket': os.getenv('INFLUXDB_BUCKET', 'metrics'),
        'redis_host': os.getenv('REDIS_HOST', '127.0.0.1'),
        'redis_port': int(os.getenv('REDIS_PORT', 6379)),
        'redis_password': os.getenv('REDIS_PASSWORD', ''),
        'redis_db': int(os.getenv('REDIS_DB', 0))
    })
    
    return config

if __name__ == "__main__":
    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/var/log/rabbitmq-ai/queue-predictor.log'),
            logging.StreamHandler()
        ]
    )
    
    config = load_config()
    predictor = QueueGrowthPredictor(config)
    
    # Train models
    logger.info("Starting model training...")
    training_results = predictor.train_models()
    
    if training_results:
        logger.info("Training completed successfully")
        
        # Make initial predictions
        predictions = predictor.predict_queue_growth(hours_ahead=6)
        logger.info(f"Generated {len(predictions)} predictions")
    else:
        logger.error("Training failed")
EOF

sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/predictors/queue_predictor.py
sudo chmod +x /opt/rabbitmq-ai/lib/predictors/queue_predictor.py
```

### 4.3 RHEL 8 Systemd Services Configuration

```bash
# Create systemd service for metrics collection
sudo tee /etc/systemd/system/rabbitmq-ai-collector.service <<EOF
[Unit]
Description=RabbitMQ AI Metrics Collector
After=network.target rabbitmq-server.service influxdb.service redis.service
Wants=rabbitmq-server.service influxdb.service redis.service

[Service]
Type=simple
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/collectors/metrics_collector.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/rabbitmq-ai /var/lib/rabbitmq-ai /opt/rabbitmq-ai

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for prediction engine
sudo tee /etc/systemd/system/rabbitmq-ai-predictor.service <<EOF
[Unit]
Description=RabbitMQ AI Prediction Engine
After=network.target rabbitmq-ai-collector.service
Wants=rabbitmq-ai-collector.service

[Service]
Type=simple
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/predictors/queue_predictor.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/rabbitmq-ai /var/lib/rabbitmq-ai /opt/rabbitmq-ai

# Resource limits for ML workloads
LimitNOFILE=65536
LimitNPROC=8192
MemoryMax=8G

[Install]
WantedBy=multi-user.target
EOF

# Create AI API service
sudo tee /etc/systemd/system/rabbitmq-ai-api.service <<EOF
[Unit]
Description=RabbitMQ AI API Service
After=network.target rabbitmq-ai-predictor.service
Wants=rabbitmq-ai-predictor.service

[Service]
Type=simple
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/api/ai_api_server.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/rabbitmq-ai /var/lib/rabbitmq-ai /opt/rabbitmq-ai

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable services
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-ai-collector.service
sudo systemctl enable rabbitmq-ai-predictor.service
sudo systemctl enable rabbitmq-ai-api.service
```

### 4.4 Create AI API Server

```python
# AI API Server with RHEL 8 optimizations
sudo tee /opt/rabbitmq-ai/lib/api/ai_api_server.py <<'EOF'
#!/usr/bin/env python3
"""
RabbitMQ AI API Server for RHEL 8
Provides REST API for AI services and predictions
"""

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import redis
from influxdb_client import InfluxDBClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rabbitmq-ai/api-server.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Pydantic models
class PredictionRequest(BaseModel):
    hours_ahead: int = Field(default=6, ge=1, le=168)  # 1 hour to 1 week
    queue_name: Optional[str] = Field(default=None)
    include_confidence: bool = Field(default=True)

class ScalingRecommendation(BaseModel):
    action: str
    target_nodes: int
    confidence: float
    reasoning: str
    estimated_cost_impact: float

class AnomalyAlert(BaseModel):
    timestamp: datetime
    severity: str
    alert_type: str
    description: str
    affected_components: List[str]
    recommended_actions: List[str]

class HealthStatus(BaseModel):
    service: str
    status: str
    last_update: datetime
    details: Dict

# FastAPI app
app = FastAPI(
    title="RabbitMQ AI API",
    description="AI-powered RabbitMQ cluster management API",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()

class AIAPIServer:
    """Main AI API server class"""
    
    def __init__(self):
        self.redis_client = None
        self.influx_client = None
        self.config = self._load_config()
        self._initialize_connections()
    
    def _load_config(self) -> Dict:
        """Load configuration from environment"""
        config = {}
        
        # Load from environment file
        env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        key, value = line.strip().split('=', 1)
                        config[key.lower()] = value
        
        # Override with environment variables
        config.update({
            'influxdb_url': os.getenv('INFLUXDB_URL', 'http://127.0.0.1:8086'),
            'influxdb_token': os.getenv('INFLUXDB_TOKEN', ''),
            'influxdb_org': os.getenv('INFLUXDB_ORG', 'rabbitmq-ai'),
            'influxdb_bucket': os.getenv('INFLUXDB_BUCKET', 'metrics'),
            'redis_host': os.getenv('REDIS_HOST', '127.0.0.1'),
            'redis_port': int(os.getenv('REDIS_PORT', 6379)),
            'redis_password': os.getenv('REDIS_PASSWORD', ''),
            'redis_db': int(os.getenv('REDIS_DB', 0)),
            'api_host': os.getenv('AI_SERVICE_HOST', '127.0.0.1'),
            'api_port': int(os.getenv('AI_SERVICE_PORT', 8080)),
            'secret_key': os.getenv('AI_SECRET_KEY', 'your-secret-key')
        })
        
        return config
    
    def _initialize_connections(self):
        """Initialize database connections"""
        try:
            # Redis connection
            self.redis_client = redis.Redis(
                host=self.config['redis_host'],
                port=self.config['redis_port'],
                password=self.config['redis_password'],
                db=self.config['redis_db'],
                decode_responses=True
            )
            
            # InfluxDB connection
            self.influx_client = InfluxDBClient(
                url=self.config['influxdb_url'],
                token=self.config['influxdb_token'],
                org=self.config['influxdb_org']
            )
            
            logger.info("API server connections initialized")
            
        except Exception as e:
            logger.error(f"Error initializing connections: {e}")
    
    def get_current_metrics(self) -> Dict:
        """Get current RabbitMQ metrics"""
        try:
            metrics_data = self.redis_client.hget('rabbitmq:metrics:current', 'data')
            if metrics_data:
                return json.loads(metrics_data)
            else:
                return {}
        except Exception as e:
            logger.error(f"Error getting current metrics: {e}")
            return {}
    
    def get_predictions(self, hours_ahead: int = 6) -> List[Dict]:
        """Get queue growth predictions"""
        try:
            predictions_data = self.redis_client.get('rabbitmq:predictions:queue_growth')
            if predictions_data:
                predictions = json.loads(predictions_data)
                # Filter predictions by time horizon
                filtered_predictions = [
                    p for p in predictions 
                    if p['prediction_horizon_minutes'] <= hours_ahead * 60
                ]
                return filtered_predictions
            else:
                return []
        except Exception as e:
            logger.error(f"Error getting predictions: {e}")
            return []
    
    def get_anomalies(self) -> List[Dict]:
        """Get current anomalies"""
        try:
            anomalies_data = self.redis_client.get('rabbitmq:anomalies:current')
            if anomalies_data:
                return json.loads(anomalies_data)
            else:
                return []
        except Exception as e:
            logger.error(f"Error getting anomalies: {e}")
            return []
    
    def get_scaling_recommendations(self) -> List[Dict]:
        """Get scaling recommendations"""
        try:
            scaling_data = self.redis_client.get('rabbitmq:scaling:recommendations')
            if scaling_data:
                return json.loads(scaling_data)
            else:
                return []
        except Exception as e:
            logger.error(f"Error getting scaling recommendations: {e}")
            return []

# Global server instance
ai_server = AIAPIServer()

# Authentication dependency
def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Verify API token"""
    if credentials.credentials != ai_server.config['secret_key']:
        raise HTTPException(status_code=401, detail="Invalid token")
    return credentials.credentials

# API Endpoints
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    try:
        # Check Redis connection
        redis_status = "healthy" if ai_server.redis_client.ping() else "unhealthy"
        
        # Check InfluxDB connection
        influx_status = "healthy"
        try:
            ai_server.influx_client.ping()
        except:
            influx_status = "unhealthy"
        
        return {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "services": {
                "redis": redis_status,
                "influxdb": influx_status,
                "api": "healthy"
            }
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.get("/metrics/current")
async def get_current_metrics(token: str = Depends(verify_token)):
    """Get current RabbitMQ metrics"""
    try:
        metrics = ai_server.get_current_metrics()
        if not metrics:
            raise HTTPException(status_code=404, detail="No current metrics available")
        
        return {
            "timestamp": datetime.now().isoformat(),
            "metrics": metrics
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/predictions/queue-growth")
async def get_queue_predictions(
    request: PredictionRequest,
    token: str = Depends(verify_token)
):
    """Get queue growth predictions"""
    try:
        predictions = ai_server.get_predictions(hours_ahead=request.hours_ahead)
        
        if not predictions:
            raise HTTPException(status_code=404, detail="No predictions available")
        
        return {
            "timestamp": datetime.now().isoformat(),
            "hours_ahead": request.hours_ahead,
            "predictions": predictions
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/anomalies/current")
async def get_current_anomalies(token: str = Depends(verify_token)):
    """Get current anomalies"""
    try:
        anomalies = ai_server.get_anomalies()
        
        return {
            "timestamp": datetime.now().isoformat(),
            "anomalies": anomalies,
            "count": len(anomalies)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/scaling/recommendations")
async def get_scaling_recommendations(token: str = Depends(verify_token)):
    """Get scaling recommendations"""
    try:
        recommendations = ai_server.get_scaling_recommendations()
        
        return {
            "timestamp": datetime.now().isoformat(),
            "recommendations": recommendations,
            "count": len(recommendations)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics/historical")
async def get_historical_metrics(
    hours_back: int = 24,
    token: str = Depends(verify_token)
):
    """Get historical metrics from InfluxDB"""
    try:
        query = f'''
        from(bucket: "{ai_server.config['influxdb_bucket']}")
          |> range(start: -{hours_back}h)
          |> filter(fn: (r) => r._measurement == "rabbitmq_metrics")
          |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)
        '''
        
        query_api = ai_server.influx_client.query_api()
        result = query_api.query_data_frame(query)
        
        if not result.empty:
            # Convert to JSON-serializable format
            result['_time'] = result['_time'].astype(str)
            data = result.to_dict('records')
        else:
            data = []
        
        return {
            "timestamp": datetime.now().isoformat(),
            "hours_back": hours_back,
            "data_points": len(data),
            "data": data
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/training/trigger")
async def trigger_model_training(token: str = Depends(verify_token)):
    """Trigger model retraining"""
    try:
        # Store training request in Redis
        training_request = {
            "timestamp": datetime.now().isoformat(),
            "requested_by": "api",
            "status": "requested"
        }
        
        ai_server.redis_client.set(
            'rabbitmq:training:request',
            json.dumps(training_request),
            ex=3600
        )
        
        return {
            "message": "Model training requested",
            "timestamp": datetime.now().isoformat(),
            "status": "requested"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/system/status")
async def get_system_status(token: str = Depends(verify_token)):
    """Get overall system status"""
    try:
        # Get service statuses
        import subprocess
        
        services = [
            'rabbitmq-server',
            'rabbitmq-ai-collector',
            'rabbitmq-ai-predictor',
            'influxdb',
            'redis',
            'prometheus'
        ]
        
        service_statuses = {}
        for service in services:
            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True
                )
                service_statuses[service] = result.stdout.strip()
            except:
                service_statuses[service] = 'unknown'
        
        # Get system metrics
        import psutil
        
        system_metrics = {
            'cpu_usage': psutil.cpu_percent(),
            'memory_usage': psutil.virtual_memory().percent,
            'disk_usage': psutil.disk_usage('/').percent,
            'load_average': os.getloadavg()
        }
        
        return {
            "timestamp": datetime.now().isoformat(),
            "services": service_statuses,
            "system_metrics": system_metrics,
            "overall_status": "healthy" if all(
                status == "active" for status in service_statuses.values()
            ) else "degraded"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def main():
    """Main function to start the API server"""
    try:
        logger.info("Starting RabbitMQ AI API Server")
        
        # Run the server
        uvicorn.run(
            app,
            host=ai_server.config['api_host'],
            port=ai_server.config['api_port'],
            log_level="info",
            workers=1
        )
    except KeyboardInterrupt:
        logger.info("API server stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/api/ai_api_server.py
sudo chmod +x /opt/rabbitmq-ai/lib/api/ai_api_server.py
```

### 4.5 Start Services and Validate Installation

```bash
# Start all AI services
sudo systemctl start rabbitmq-ai-collector
sudo systemctl start rabbitmq-ai-predictor  
sudo systemctl start rabbitmq-ai-api

# Check service status
sudo systemctl status rabbitmq-ai-collector
sudo systemctl status rabbitmq-ai-predictor
sudo systemctl status rabbitmq-ai-api

# Check logs
sudo journalctl -u rabbitmq-ai-collector -f --no-pager
sudo journalctl -u rabbitmq-ai-predictor -f --no-pager
sudo journalctl -u rabbitmq-ai-api -f --no-pager

# Test API endpoints
curl -H "Authorization: Bearer your-secret-key" http://localhost:8080/health
curl -H "Authorization: Bearer your-secret-key" http://localhost:8080/metrics/current
```

This RHEL 8 specific AI implementation includes:

1. **RHEL 8 System Preparation**: Complete system setup with SELinux, firewall, and package management
2. **AI Infrastructure**: InfluxDB, Redis, Prometheus configured for RHEL 8
3. **Python Environment**: Virtual environment with RHEL 8 optimized packages
4. **Systemd Services**: Production-ready services with security and resource limits
5. **API Server**: REST API for accessing AI services and predictions
6. **Security**: SELinux policies, firewall rules, and service isolation

The implementation is now fully tailored for RHEL 8 VMs with proper system integration and enterprise-grade configuration.

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"id": "1", "content": "Update AI implementation guide for RHEL 8 VM specific deployment", "status": "completed"}, {"id": "2", "content": "Add RHEL 8 package management and system configuration", "status": "completed"}, {"id": "3", "content": "Include systemd services and SELinux configuration", "status": "completed"}, {"id": "4", "content": "Add RHEL 8 specific security and networking setup", "status": "completed"}]