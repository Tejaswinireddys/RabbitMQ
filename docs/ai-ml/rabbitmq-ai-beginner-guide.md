# RabbitMQ AI Implementation - Complete Beginner's Guide for RHEL 8

## 🎯 Welcome to AI-Powered RabbitMQ!

This guide is designed for complete beginners to AI/ML who want to implement intelligent monitoring and management for RabbitMQ on RHEL 8. We'll explain every concept, command, and step in detail.

## 📚 What You'll Learn

By the end of this guide, you'll understand:
- What AI/ML can do for RabbitMQ monitoring
- How to set up a complete AI system on RHEL 8
- How to train models to predict queue behavior
- How to create automated alerts and scaling
- How to maintain and troubleshoot the system

## 📋 Table of Contents

1. [AI/ML Concepts for Beginners](#aiml-concepts-for-beginners)
2. [Prerequisites and Preparation](#prerequisites-and-preparation)
3. [Phase 1: System Foundation](#phase-1-system-foundation)
4. [Phase 2: Data Collection Setup](#phase-2-data-collection-setup)
5. [Phase 3: Basic AI Implementation](#phase-3-basic-ai-implementation)
6. [Phase 4: Advanced Features](#phase-4-advanced-features)
7. [Testing and Validation](#testing-and-validation)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Maintenance and Monitoring](#maintenance-and-monitoring)

---

## 1. AI/ML Concepts for Beginners 🧠

### What is AI/ML and Why Do We Need It?

**Artificial Intelligence (AI)** helps computers make decisions like humans do. **Machine Learning (ML)** is a subset of AI where computers learn patterns from data.

### For RabbitMQ, AI/ML helps us:

#### 🔮 **Predictive Analytics**
- **What it does**: Predicts future queue sizes, memory usage, and message rates
- **Why it helps**: You can scale before problems occur, not after
- **Example**: "Based on historical data, queue depth will increase by 300% at 2 PM"

#### 🚨 **Anomaly Detection**
- **What it does**: Automatically detects unusual behavior
- **Why it helps**: Catches problems before they become outages
- **Example**: "Memory usage is 50% higher than normal for this time of day"

#### 🔄 **Auto-Scaling**
- **What it does**: Automatically adds/removes resources based on predictions
- **Why it helps**: Maintains performance while controlling costs
- **Example**: "Adding 2 more nodes because high load is predicted in 30 minutes"

#### 🔧 **Self-Healing**
- **What it does**: Automatically fixes common problems
- **Why it helps**: Reduces manual intervention and downtime
- **Example**: "Restarting node because memory leak pattern detected"

### Key Terms You'll Encounter:

- **Dataset**: Historical data we use to train our AI models
- **Training**: Teaching the AI system using historical data
- **Model**: The "brain" that makes predictions
- **Prediction**: What the AI thinks will happen in the future
- **Confidence**: How sure the AI is about its prediction (0-100%)
- **Feature**: A piece of data the AI uses (like queue size, memory usage)

---

## 2. Prerequisites and Preparation 📋

### 2.1 What You Need Before Starting

#### System Requirements:
```bash
# Check your system meets requirements
echo "=== System Requirements Check ==="

# Check RHEL version (must be 8.x)
cat /etc/redhat-release

# Check CPU (need 4+ cores)
nproc

# Check RAM (need 8GB+, 16GB+ recommended)
free -h

# Check disk space (need 100GB+ free)
df -h /

# Check network connectivity
ping -c 3 google.com
```

**Expected Output:**
```
Red Hat Enterprise Linux release 8.x
4 (or higher)
              total        used        free
Mem:           15Gi        2.1Gi        13Gi  (should be 8GB+ total)
Filesystem     Size  Used Avail Use% Mounted on
/dev/sda1      200G   50G  150G  25%  /      (should have 100GB+ available)
PING google.com ... 64 bytes from ... (should show successful pings)
```

#### Knowledge Prerequisites:
- Basic Linux command line skills
- Understanding of RabbitMQ concepts (queues, exchanges, messages)
- Basic text editing (vi/vim or nano)

### 2.2 Pre-Installation Checklist

**Complete this checklist before proceeding:**

- [ ] RHEL 8 system with sudo access
- [ ] RabbitMQ 4.x already installed and running
- [ ] Network access to download packages
- [ ] 4+ hours of time for complete setup
- [ ] Backup of current RabbitMQ configuration

#### Verify RabbitMQ is Running:
```bash
# Check RabbitMQ service status
sudo systemctl status rabbitmq-server

# Check RabbitMQ management interface
curl -u admin:password http://localhost:15672/api/overview

# Expected: Should return JSON data about your cluster
```

---

## 3. Phase 1: System Foundation ⚙️

### 3.1 Understanding What We're Building

Before we start, let's understand the architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                     AI System Architecture                 │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  RabbitMQ   │───►│   Data      │───►│    AI       │     │
│  │  Cluster    │    │ Collection  │    │  Models     │     │
│  │             │    │ (Metrics)   │    │ (Predict)   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                   │                   │          │
│         ▼                   ▼                   ▼          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ Management  │    │  InfluxDB   │    │   Actions   │     │
│  │ Interface   │    │ (Storage)   │    │ (Auto-fix)  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Step 1: Update Your RHEL 8 System

**What we're doing**: Ensuring your system has the latest security updates and packages.

```bash
# Step 1: Update system packages
echo "Updating RHEL 8 system packages..."
sudo dnf update -y

# Step 2: Install development tools (needed for AI libraries)
echo "Installing development tools..."
sudo dnf groupinstall -y "Development Tools"

# Step 3: Install EPEL repository (Extra Packages for Enterprise Linux)
echo "Installing EPEL repository..."
sudo dnf install -y epel-release

# Step 4: Install basic utilities we'll need
echo "Installing basic utilities..."
sudo dnf install -y \
    git \
    wget \
    curl \
    vim \
    htop \
    tmux \
    tree \
    unzip
```

**Validation Step:**
```bash
# Verify installations
which git && echo "✓ Git installed"
which python3 && echo "✓ Python3 available"
which curl && echo "✓ Curl installed"
dnf list installed | grep -E "(git|curl|vim)" | wc -l
# Should show 3 or more packages
```

### 3.3 Step 2: Configure SELinux for AI Services

**What is SELinux?** Security-Enhanced Linux - it's a security system that controls what programs can do.

**Why configure it?** Our AI services need specific permissions to work properly.

```bash
# Step 1: Check current SELinux status
echo "Checking SELinux status..."
getenforce
# Should show: Enforcing, Permissive, or Disabled

# Step 2: Check SELinux details
sestatus

# Step 3: Configure SELinux for our AI services
echo "Configuring SELinux for AI services..."
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1
sudo setsebool -P nis_enabled 1

# Step 4: Verify changes
getsebool httpd_can_network_connect
getsebool httpd_can_network_relay
getsebool nis_enabled
# All should show "on"
```

**What each setting does:**
- `httpd_can_network_connect`: Allows our AI API to make network connections
- `httpd_can_network_relay`: Allows network traffic forwarding
- `nis_enabled`: Allows network services to work properly

### 3.4 Step 3: Configure Firewall

**What we're doing**: Opening network ports so our AI services can communicate.

```bash
# Step 1: Start and enable firewall
echo "Configuring firewall..."
sudo systemctl enable firewalld
sudo systemctl start firewalld

# Step 2: Check firewall status
sudo firewall-cmd --state
# Should show: running

# Step 3: Open ports for AI services
echo "Opening AI service ports..."

# AI Engine API
sudo firewall-cmd --permanent --add-port=8080/tcp

# Database services
sudo firewall-cmd --permanent --add-port=8086/tcp  # InfluxDB
sudo firewall-cmd --permanent --add-port=6379/tcp  # Redis
sudo firewall-cmd --permanent --add-port=9090/tcp  # Prometheus

# Monitoring services
sudo firewall-cmd --permanent --add-port=3000/tcp  # Grafana

# Step 4: Apply firewall changes
sudo firewall-cmd --reload

# Step 5: Verify open ports
sudo firewall-cmd --list-ports
# Should show: 8080/tcp 8086/tcp 6379/tcp 9090/tcp 3000/tcp
```

**Port Explanation:**
- **8080**: Our AI API service (where we'll get predictions)
- **8086**: InfluxDB (stores time-series data)
- **6379**: Redis (fast data cache)
- **9090**: Prometheus (metrics collection)
- **3000**: Grafana (dashboards and visualization)

### 3.5 Step 4: Create AI Service User

**Why create a separate user?** Security best practice - our AI services run under a dedicated user, not root.

```bash
# Step 1: Create AI service user
echo "Creating rabbitmq-ai service user..."
sudo useradd -r -m -s /bin/bash rabbitmq-ai

# Step 2: Add user to wheel group (for sudo if needed)
sudo usermod -a -G wheel rabbitmq-ai

# Step 3: Create directory structure
echo "Creating AI directory structure..."
sudo mkdir -p /opt/rabbitmq-ai/{bin,lib,logs,config,data,models,scripts}
sudo mkdir -p /var/log/rabbitmq-ai
sudo mkdir -p /var/lib/rabbitmq-ai/{prometheus,influxdb,redis,models}

# Step 4: Set proper ownership
sudo chown -R rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai
sudo chown -R rabbitmq-ai:rabbitmq-ai /var/log/rabbitmq-ai
sudo chown -R rabbitmq-ai:rabbitmq-ai /var/lib/rabbitmq-ai

# Step 5: Verify directory structure
tree /opt/rabbitmq-ai
tree /var/log/rabbitmq-ai
tree /var/lib/rabbitmq-ai
```

**What each directory is for:**
- `/opt/rabbitmq-ai/bin`: Executable scripts
- `/opt/rabbitmq-ai/lib`: Python code and libraries
- `/opt/rabbitmq-ai/config`: Configuration files
- `/opt/rabbitmq-ai/models`: Trained AI models
- `/var/log/rabbitmq-ai`: Log files
- `/var/lib/rabbitmq-ai`: Data storage

---

## 4. Phase 2: Data Collection Setup 📊

### 4.1 Understanding Data Collection

**What is data collection?** We need to gather information about your RabbitMQ cluster so our AI can learn patterns.

**What data do we collect?**
- Queue sizes and message rates
- Memory and CPU usage
- Connection counts
- System performance metrics

### 4.2 Step 1: Install InfluxDB (Time-Series Database)

**What is InfluxDB?** A database designed for storing time-stamped data (like metrics over time).

```bash
# Step 1: Add InfluxDB repository
echo "Adding InfluxDB repository..."
sudo tee /etc/yum.repos.d/influxdb.repo <<EOF
[influxdb]
name = InfluxDB Repository - RHEL 8
baseurl = https://repos.influxdata.com/rhel/8/x86_64/stable/
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
EOF

# Step 2: Install InfluxDB
echo "Installing InfluxDB..."
sudo dnf install -y influxdb2

# Step 3: Start and enable InfluxDB
sudo systemctl enable influxdb
sudo systemctl start influxdb

# Step 4: Wait for InfluxDB to start
echo "Waiting for InfluxDB to start..."
sleep 15

# Step 5: Check if InfluxDB is running
sudo systemctl status influxdb
# Should show: active (running)

# Step 6: Test InfluxDB connection
curl http://localhost:8086/health
# Should return: {"name":"influxdb","message":"ready for queries and writes","status":"pass"}
```

**Validation Steps:**
```bash
# Check InfluxDB process
ps aux | grep influx
# Should show influxd process running

# Check InfluxDB port
netstat -tlnp | grep 8086
# Should show InfluxDB listening on port 8086
```

### 4.3 Step 2: Configure InfluxDB

**What we're doing**: Setting up InfluxDB with our specific configuration for RabbitMQ metrics.

```bash
# Step 1: Initial setup (run this as a single command)
echo "Configuring InfluxDB..."
influx setup \
  --host http://localhost:8086 \
  --org "rabbitmq-ai" \
  --bucket "metrics" \
  --username "admin" \
  --password "SecurePassword2024!" \
  --retention "30d" \
  --force

# Step 2: Create additional buckets for different data types
influx bucket create \
  --host http://localhost:8086 \
  --org "rabbitmq-ai" \
  --name "predictions" \
  --retention "7d"

influx bucket create \
  --host http://localhost:8086 \
  --org "rabbitmq-ai" \
  --name "anomalies" \
  --retention "30d"

# Step 3: Create authentication token for our services
TOKEN=$(influx auth create \
  --host http://localhost:8086 \
  --org "rabbitmq-ai" \
  --all-access \
  --description "RabbitMQ AI Token" | grep -o 'token[[:space:]]*[[:alnum:]_-]*' | cut -d' ' -f2)

echo "Your InfluxDB token: $TOKEN"
echo "Save this token - you'll need it later!"

# Step 4: Test the setup
influx bucket list --host http://localhost:8086
# Should show: metrics, predictions, anomalies buckets
```

**Important**: Save the token that's displayed - you'll need it later!

### 4.4 Step 3: Install Redis (Data Cache)

**What is Redis?** A fast in-memory database that we use for real-time data caching.

```bash
# Step 1: Install Redis
echo "Installing Redis..."
sudo dnf install -y redis

# Step 2: Configure Redis for AI workloads
echo "Configuring Redis..."
sudo tee /etc/redis.conf <<EOF
# Network Configuration
bind 127.0.0.1
port 6379
protected-mode yes

# Memory Configuration for AI workloads
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence Configuration
save 900 1
save 300 10
save 60 10000

# Security
requirepass "AIRedisPassword2024!"

# Logging
loglevel notice
logfile /var/log/redis/redis.log
EOF

# Step 3: Start and enable Redis
sudo systemctl enable redis
sudo systemctl start redis

# Step 4: Test Redis connection
redis-cli -a "AIRedisPassword2024!" ping
# Should return: PONG
```

**Validation Steps:**
```bash
# Check Redis status
sudo systemctl status redis
# Should show: active (running)

# Test Redis with authentication
redis-cli -a "AIRedisPassword2024!" info server
# Should show server information
```

### 4.5 Step 4: Install Prometheus (Metrics Collection)

**What is Prometheus?** A system that collects metrics from various sources, including RabbitMQ.

```bash
# Step 1: Create prometheus user
echo "Creating prometheus user..."
sudo useradd -r -m -s /bin/false prometheus

# Step 2: Download Prometheus
echo "Downloading Prometheus..."
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz

# Step 3: Extract and install
tar xf prometheus-2.45.0.linux-amd64.tar.gz
sudo cp prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/

# Step 4: Set permissions
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool

# Step 5: Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Step 6: Copy configuration files
sudo cp -r prometheus-2.45.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-2.45.0.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus/

# Step 7: Create Prometheus configuration
sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['localhost:15692']
    scrape_interval: 10s
    metrics_path: /metrics
    basic_auth:
      username: 'admin'
      password: 'your-rabbitmq-password'

  - job_name: 'rabbitmq-ai'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 30s
    metrics_path: /metrics
EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Step 8: Create systemd service
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
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

# Step 9: Start Prometheus
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Step 10: Test Prometheus
curl http://localhost:9090/api/v1/status/config
# Should return configuration information
```

**Validation Steps:**
```bash
# Check Prometheus web interface
curl http://localhost:9090/
# Should return HTML page

# Check if Prometheus can reach RabbitMQ
curl http://localhost:9090/api/v1/targets
# Should show RabbitMQ target
```

---

## 5. Phase 3: Basic AI Implementation 🤖

### 5.1 Understanding What We're Building

In this phase, we'll:
1. Set up Python environment with AI libraries
2. Create a data collection service
3. Build a simple prediction model
4. Test everything works

### 5.2 Step 1: Python Environment Setup

**What we're doing**: Installing Python and all the AI/ML libraries we need.

```bash
# Step 1: Install Python 3.9
echo "Installing Python 3.9..."
sudo dnf module enable python39 -y
sudo dnf install python39 python39-pip python39-devel -y

# Step 2: Create symbolic links for easier access
sudo alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1
sudo alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip3.9 1

# Step 3: Verify installation
python3 --version
# Should show: Python 3.9.x

pip3 --version
# Should show: pip 21.x.x or higher

# Step 4: Install system dependencies for AI libraries
echo "Installing system dependencies..."
sudo dnf install -y \
    gcc-c++ \
    cmake \
    lapack-devel \
    blas-devel \
    atlas-devel \
    openblas-devel \
    python39-tkinter
```

### 5.3 Step 2: Create Python Virtual Environment

**What is a virtual environment?** An isolated Python environment where we can install packages without affecting the system Python.

```bash
# Step 1: Switch to AI service user
sudo su - rabbitmq-ai

# Step 2: Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv /opt/rabbitmq-ai/venv

# Step 3: Activate virtual environment
source /opt/rabbitmq-ai/venv/bin/activate

# Step 4: Upgrade pip in virtual environment
pip install --upgrade pip setuptools wheel

# Step 5: Verify virtual environment
which python
# Should show: /opt/rabbitmq-ai/venv/bin/python

which pip
# Should show: /opt/rabbitmq-ai/venv/bin/pip
```

### 5.4 Step 3: Install AI/ML Libraries

**What we're installing**: All the Python libraries needed for machine learning and data analysis.

```bash
# Still as rabbitmq-ai user with activated virtual environment

# Step 1: Create requirements file
cat > /opt/rabbitmq-ai/requirements.txt <<EOF
# Basic data processing
numpy==1.24.3
pandas==2.0.3
scipy==1.11.1

# Machine learning
scikit-learn==1.3.0
xgboost==1.7.6

# Time series forecasting
prophet==1.1.4
statsmodels==0.14.0

# Deep learning (TensorFlow)
tensorflow==2.14.0

# Database connections
influxdb-client==1.38.0
redis==5.0.0

# RabbitMQ integration
pika==1.3.2

# API framework
fastapi==0.103.1
uvicorn==0.23.2

# Utilities
requests==2.31.0
aiohttp==3.8.5
python-dotenv==1.0.0
pyyaml==6.0.1

# Monitoring
prometheus-client==0.17.1

# System monitoring
psutil==5.9.5
EOF

# Step 2: Install all packages (this will take 10-15 minutes)
echo "Installing AI/ML packages... This will take several minutes."
pip install -r /opt/rabbitmq-ai/requirements.txt

# Step 3: Verify critical installations
python -c "import numpy; print('✓ NumPy version:', numpy.__version__)"
python -c "import pandas; print('✓ Pandas version:', pandas.__version__)"
python -c "import sklearn; print('✓ Scikit-learn version:', sklearn.__version__)"
python -c "import tensorflow; print('✓ TensorFlow version:', tensorflow.__version__)"

# Step 4: Exit from rabbitmq-ai user
exit
```

**Expected Output:**
```
✓ NumPy version: 1.24.3
✓ Pandas version: 2.0.3
✓ Scikit-learn version: 1.3.0
✓ TensorFlow version: 2.14.0
```

### 5.5 Step 4: Create Configuration File

**What we're doing**: Creating a configuration file that stores all our settings.

```bash
# Step 1: Create environment configuration
sudo tee /opt/rabbitmq-ai/config/ai_environment.env <<EOF
# Python Environment
PYTHONPATH=/opt/rabbitmq-ai/lib
VIRTUAL_ENV=/opt/rabbitmq-ai/venv

# AI Service Configuration
AI_SERVICE_HOST=127.0.0.1
AI_SERVICE_PORT=8080
AI_LOG_LEVEL=INFO
AI_LOG_FILE=/var/log/rabbitmq-ai/ai-engine.log

# Database Connections
INFLUXDB_URL=http://127.0.0.1:8086
INFLUXDB_TOKEN=your-influxdb-token-here
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

# Security
AI_SECRET_KEY=change-this-secret-key-in-production

# Feature Flags (what AI features to enable)
ENABLE_PREDICTIVE_SCALING=true
ENABLE_ANOMALY_DETECTION=true
ENABLE_SELF_HEALING=false
ENABLE_CHATOPS=false

# Performance Settings
MAX_WORKERS=2
PREDICTION_BATCH_SIZE=100
MODEL_UPDATE_INTERVAL=3600
METRICS_COLLECTION_INTERVAL=30
EOF

# Step 2: Set proper permissions
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/config/ai_environment.env
sudo chmod 600 /opt/rabbitmq-ai/config/ai_environment.env

# Step 3: Update with your actual tokens
echo "IMPORTANT: Update the configuration file with your actual values:"
echo "1. Replace 'your-influxdb-token-here' with your InfluxDB token"
echo "2. Replace 'your-rabbitmq-password' with your RabbitMQ password"
echo "3. Change the secret key to something secure"
```

**Manual Step Required:**
```bash
# Edit the configuration file and update these values:
sudo nano /opt/rabbitmq-ai/config/ai_environment.env

# Replace these lines with your actual values:
# INFLUXDB_TOKEN=your-actual-influxdb-token
# RABBITMQ_PASSWORD=your-actual-rabbitmq-password
# AI_SECRET_KEY=your-unique-secret-key
```

### 5.6 Step 5: Create Data Collection Service

**What this does**: Collects metrics from RabbitMQ and stores them in our database.

```bash
# Step 1: Create the collectors directory
sudo mkdir -p /opt/rabbitmq-ai/lib/collectors

# Step 2: Create the data collection script
sudo tee /opt/rabbitmq-ai/lib/collectors/simple_collector.py <<'EOF'
#!/usr/bin/env python3
"""
Simple RabbitMQ Metrics Collector for Beginners
This script collects basic metrics from RabbitMQ and stores them in InfluxDB
"""

import asyncio
import aiohttp
import json
import logging
import os
import psutil
import time
from datetime import datetime, timezone
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rabbitmq-ai/collector.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SimpleMetricsCollector:
    """Simple metrics collector for beginners"""
    
    def __init__(self):
        self.config = self.load_config()
        self.influx_client = None
        self.initialize_connections()
    
    def load_config(self):
        """Load configuration from environment file"""
        config = {}
        
        # Load environment file
        env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        key, value = line.strip().split('=', 1)
                        config[key.lower()] = value
        
        return config
    
    def initialize_connections(self):
        """Initialize database connections"""
        try:
            self.influx_client = InfluxDBClient(
                url=self.config.get('influxdb_url', 'http://127.0.0.1:8086'),
                token=self.config.get('influxdb_token', ''),
                org=self.config.get('influxdb_org', 'rabbitmq-ai')
            )
            self.write_api = self.influx_client.write_api(write_options=SYNCHRONOUS)
            logger.info("✓ Connected to InfluxDB")
            
        except Exception as e:
            logger.error(f"✗ Error connecting to InfluxDB: {e}")
    
    async def collect_rabbitmq_metrics(self):
        """Collect basic RabbitMQ metrics"""
        try:
            # RabbitMQ management API URL
            base_url = f"http://{self.config.get('rabbitmq_host', 'localhost')}:{self.config.get('rabbitmq_management_port', '15672')}"
            
            # Authentication
            auth = aiohttp.BasicAuth(
                self.config.get('rabbitmq_user', 'admin'),
                self.config.get('rabbitmq_password', '')
            )
            
            async with aiohttp.ClientSession(auth=auth) as session:
                # Get overview data
                overview_url = f"{base_url}/api/overview"
                async with session.get(overview_url) as response:
                    if response.status == 200:
                        overview_data = await response.json()
                        logger.info("✓ Collected overview metrics")
                    else:
                        logger.error(f"✗ Failed to get overview: {response.status}")
                        return None
                
                # Get queue data
                queues_url = f"{base_url}/api/queues"
                async with session.get(queues_url) as response:
                    if response.status == 200:
                        queues_data = await response.json()
                        logger.info(f"✓ Collected data for {len(queues_data)} queues")
                    else:
                        logger.error(f"✗ Failed to get queues: {response.status}")
                        queues_data = []
                
                # Process and return metrics
                return self.process_metrics(overview_data, queues_data)
                
        except Exception as e:
            logger.error(f"✗ Error collecting RabbitMQ metrics: {e}")
            return None
    
    def process_metrics(self, overview_data, queues_data):
        """Process raw metrics into structured format"""
        try:
            # Calculate queue metrics
            total_messages = sum(q.get('messages', 0) for q in queues_data)
            total_queues = len(queues_data)
            
            # Calculate message rates
            publish_rate = sum(
                q.get('message_stats', {}).get('publish_details', {}).get('rate', 0) 
                for q in queues_data
            )
            
            # Get system metrics
            cpu_percent = psutil.cpu_percent()
            memory = psutil.virtual_memory()
            
            metrics = {
                'timestamp': datetime.now(timezone.utc),
                'total_queues': total_queues,
                'total_messages': total_messages,
                'publish_rate': publish_rate,
                'cpu_usage': cpu_percent,
                'memory_usage_percent': memory.percent,
                'memory_used_gb': memory.used / (1024**3),
                'cluster_name': overview_data.get('cluster_name', 'unknown')
            }
            
            logger.info(f"✓ Processed metrics: {total_queues} queues, {total_messages} messages")
            return metrics
            
        except Exception as e:
            logger.error(f"✗ Error processing metrics: {e}")
            return None
    
    def store_metrics(self, metrics):
        """Store metrics in InfluxDB"""
        try:
            if not metrics:
                return
            
            # Create InfluxDB point
            point = Point("rabbitmq_basic_metrics") \
                .time(metrics['timestamp']) \
                .tag("cluster", metrics['cluster_name']) \
                .field("total_queues", metrics['total_queues']) \
                .field("total_messages", metrics['total_messages']) \
                .field("publish_rate", metrics['publish_rate']) \
                .field("cpu_usage", metrics['cpu_usage']) \
                .field("memory_usage_percent", metrics['memory_usage_percent']) \
                .field("memory_used_gb", metrics['memory_used_gb'])
            
            # Write to InfluxDB
            self.write_api.write(
                bucket=self.config.get('influxdb_bucket', 'metrics'),
                record=point
            )
            
            logger.info("✓ Stored metrics in InfluxDB")
            
        except Exception as e:
            logger.error(f"✗ Error storing metrics: {e}")
    
    async def run_collection_loop(self):
        """Main collection loop"""
        logger.info("🚀 Starting metrics collection...")
        
        while True:
            try:
                # Collect metrics
                metrics = await self.collect_rabbitmq_metrics()
                
                # Store metrics
                if metrics:
                    self.store_metrics(metrics)
                    print(f"📊 Collected at {metrics['timestamp'].strftime('%H:%M:%S')}: "
                          f"{metrics['total_messages']} messages, "
                          f"{metrics['cpu_usage']:.1f}% CPU, "
                          f"{metrics['memory_usage_percent']:.1f}% memory")
                
                # Wait before next collection
                interval = int(self.config.get('metrics_collection_interval', 30))
                await asyncio.sleep(interval)
                
            except KeyboardInterrupt:
                logger.info("👋 Collection stopped by user")
                break
            except Exception as e:
                logger.error(f"✗ Error in collection loop: {e}")
                await asyncio.sleep(60)  # Wait 1 minute on error

async def main():
    """Main function"""
    collector = SimpleMetricsCollector()
    await collector.run_collection_loop()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Step 3: Set permissions
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/collectors/simple_collector.py
sudo chmod +x /opt/rabbitmq-ai/lib/collectors/simple_collector.py
```

### 5.7 Step 6: Test Data Collection

**What we're doing**: Testing that our data collection service works correctly.

```bash
# Step 1: Test the collector manually
echo "Testing data collection..."
sudo su - rabbitmq-ai

# Activate virtual environment
source /opt/rabbitmq-ai/venv/bin/activate

# Run the collector for 2 minutes to test
timeout 120 python /opt/rabbitmq-ai/lib/collectors/simple_collector.py

# Exit from rabbitmq-ai user
exit
```

**Expected Output:**
```
🚀 Starting metrics collection...
✓ Connected to InfluxDB
✓ Collected overview metrics
✓ Collected data for 5 queues
✓ Processed metrics: 5 queues, 1234 messages
✓ Stored metrics in InfluxDB
📊 Collected at 14:30:15: 1234 messages, 25.3% CPU, 45.2% memory
```

**Validation Steps:**
```bash
# Check if data was stored in InfluxDB
curl -G http://localhost:8086/query \
  --data-urlencode "db=metrics" \
  --data-urlencode "q=SHOW MEASUREMENTS"

# Should show rabbitmq_basic_metrics measurement
```

### 5.8 Step 7: Create Simple Prediction Model

**What this does**: Creates a basic AI model that can predict future queue sizes.

```bash
# Step 1: Create predictors directory
sudo mkdir -p /opt/rabbitmq-ai/lib/predictors

# Step 2: Create simple prediction script
sudo tee /opt/rabbitmq-ai/lib/predictors/simple_predictor.py <<'EOF'
#!/usr/bin/env python3
"""
Simple Queue Prediction Model for Beginners
This creates a basic machine learning model to predict queue growth
"""

import pandas as pd
import numpy as np
import logging
import os
import pickle
from datetime import datetime, timedelta
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, r2_score
from sklearn.preprocessing import StandardScaler
from influxdb_client import InfluxDBClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rabbitmq-ai/predictor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SimpleQueuePredictor:
    """Simple queue prediction model for beginners"""
    
    def __init__(self):
        self.config = self.load_config()
        self.influx_client = None
        self.model = None
        self.scaler = StandardScaler()
        self.initialize_connections()
    
    def load_config(self):
        """Load configuration from environment file"""
        config = {}
        
        env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        key, value = line.strip().split('=', 1)
                        config[key.lower()] = value
        
        return config
    
    def initialize_connections(self):
        """Initialize database connections"""
        try:
            self.influx_client = InfluxDBClient(
                url=self.config.get('influxdb_url', 'http://127.0.0.1:8086'),
                token=self.config.get('influxdb_token', ''),
                org=self.config.get('influxdb_org', 'rabbitmq-ai')
            )
            logger.info("✓ Connected to InfluxDB")
            
        except Exception as e:
            logger.error(f"✗ Error connecting to InfluxDB: {e}")
    
    def get_historical_data(self, days_back=7):
        """Get historical data for training"""
        try:
            # Query to get the last 7 days of data
            query = f'''
            from(bucket: "{self.config.get('influxdb_bucket', 'metrics')}")
              |> range(start: -{days_back}d)
              |> filter(fn: (r) => r._measurement == "rabbitmq_basic_metrics")
              |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
            '''
            
            query_api = self.influx_client.query_api()
            result = query_api.query_data_frame(query)
            
            if not result.empty:
                # Clean and prepare data
                result['timestamp'] = pd.to_datetime(result['_time'])
                result = result.sort_values('timestamp')
                
                # Create time-based features
                result['hour'] = result['timestamp'].dt.hour
                result['day_of_week'] = result['timestamp'].dt.dayofweek
                result['is_business_hour'] = ((result['hour'] >= 9) & 
                                             (result['hour'] <= 17) & 
                                             (result['day_of_week'] < 5)).astype(int)
                
                logger.info(f"✓ Retrieved {len(result)} data points for training")
                return result
            else:
                logger.warning("✗ No historical data found")
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"✗ Error getting historical data: {e}")
            return pd.DataFrame()
    
    def prepare_training_data(self, df):
        """Prepare data for machine learning"""
        try:
            if df.empty:
                return None, None, None, None
            
            # Features for prediction
            feature_columns = [
                'total_queues',
                'publish_rate', 
                'cpu_usage',
                'memory_usage_percent',
                'hour',
                'day_of_week',
                'is_business_hour'
            ]
            
            # Make sure all columns exist
            for col in feature_columns:
                if col not in df.columns:
                    df[col] = 0
            
            # Prepare features (X) and target (y)
            X = df[feature_columns].fillna(0)
            y = df['total_messages'].fillna(0)
            
            # Split data into training and testing
            split_point = int(len(df) * 0.8)
            X_train = X[:split_point]
            X_test = X[split_point:]
            y_train = y[:split_point]
            y_test = y[split_point:]
            
            # Scale features
            X_train_scaled = self.scaler.fit_transform(X_train)
            X_test_scaled = self.scaler.transform(X_test)
            
            logger.info(f"✓ Prepared training data: {len(X_train)} training, {len(X_test)} testing samples")
            return X_train_scaled, X_test_scaled, y_train, y_test
            
        except Exception as e:
            logger.error(f"✗ Error preparing training data: {e}")
            return None, None, None, None
    
    def train_model(self, X_train, y_train, X_test, y_test):
        """Train the prediction model"""
        try:
            # Create a Random Forest model (good for beginners)
            self.model = RandomForestRegressor(
                n_estimators=50,  # Number of trees
                max_depth=10,     # Maximum tree depth
                random_state=42   # For reproducible results
            )
            
            # Train the model
            logger.info("🧠 Training prediction model...")
            self.model.fit(X_train, y_train)
            
            # Test the model
            y_pred = self.model.predict(X_test)
            
            # Calculate accuracy metrics
            mae = mean_absolute_error(y_test, y_pred)
            r2 = r2_score(y_test, y_pred)
            
            logger.info(f"✓ Model trained successfully!")
            logger.info(f"   Mean Absolute Error: {mae:.2f}")
            logger.info(f"   R² Score: {r2:.3f}")
            
            # Save the model
            self.save_model()
            
            return {
                'mae': mae,
                'r2_score': r2,
                'training_samples': len(X_train),
                'test_samples': len(X_test)
            }
            
        except Exception as e:
            logger.error(f"✗ Error training model: {e}")
            return None
    
    def save_model(self):
        """Save the trained model"""
        try:
            model_path = '/var/lib/rabbitmq-ai/models/simple_predictor.pkl'
            scaler_path = '/var/lib/rabbitmq-ai/models/simple_scaler.pkl'
            
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(model_path), exist_ok=True)
            
            # Save model and scaler
            with open(model_path, 'wb') as f:
                pickle.dump(self.model, f)
            
            with open(scaler_path, 'wb') as f:
                pickle.dump(self.scaler, f)
            
            logger.info(f"✓ Model saved to {model_path}")
            
        except Exception as e:
            logger.error(f"✗ Error saving model: {e}")
    
    def load_model(self):
        """Load a previously trained model"""
        try:
            model_path = '/var/lib/rabbitmq-ai/models/simple_predictor.pkl'
            scaler_path = '/var/lib/rabbitmq-ai/models/simple_scaler.pkl'
            
            if os.path.exists(model_path) and os.path.exists(scaler_path):
                with open(model_path, 'rb') as f:
                    self.model = pickle.load(f)
                
                with open(scaler_path, 'rb') as f:
                    self.scaler = pickle.load(f)
                
                logger.info("✓ Model loaded successfully")
                return True
            else:
                logger.warning("✗ No saved model found")
                return False
                
        except Exception as e:
            logger.error(f"✗ Error loading model: {e}")
            return False
    
    def make_prediction(self, current_data):
        """Make a prediction using the trained model"""
        try:
            if self.model is None:
                logger.error("✗ No model available for prediction")
                return None
            
            # Prepare features for prediction
            features = [
                current_data.get('total_queues', 0),
                current_data.get('publish_rate', 0),
                current_data.get('cpu_usage', 0),
                current_data.get('memory_usage_percent', 0),
                datetime.now().hour,
                datetime.now().weekday(),
                1 if (9 <= datetime.now().hour <= 17 and datetime.now().weekday() < 5) else 0
            ]
            
            # Scale features
            features_scaled = self.scaler.transform([features])
            
            # Make prediction
            prediction = self.model.predict(features_scaled)[0]
            
            logger.info(f"🔮 Prediction: {prediction:.0f} messages expected")
            return prediction
            
        except Exception as e:
            logger.error(f"✗ Error making prediction: {e}")
            return None

def main():
    """Main function to train and test the model"""
    try:
        predictor = SimpleQueuePredictor()
        
        # Get historical data
        print("📊 Getting historical data...")
        df = predictor.get_historical_data(days_back=7)
        
        if df.empty:
            print("❌ No data available for training. Run the collector first!")
            return
        
        # Prepare training data
        print("🔧 Preparing training data...")
        X_train, X_test, y_train, y_test = predictor.prepare_training_data(df)
        
        if X_train is None:
            print("❌ Could not prepare training data")
            return
        
        # Train model
        print("🧠 Training model...")
        results = predictor.train_model(X_train, y_train, X_test, y_test)
        
        if results:
            print("✅ Training completed successfully!")
            print(f"   Accuracy (R² Score): {results['r2_score']:.1%}")
            print(f"   Average Error: {results['mae']:.0f} messages")
            
            # Test prediction with current data
            print("🔮 Testing prediction...")
            current_data = {
                'total_queues': 5,
                'publish_rate': 100,
                'cpu_usage': 30,
                'memory_usage_percent': 45
            }
            
            prediction = predictor.make_prediction(current_data)
            if prediction:
                print(f"   Predicted queue size in next period: {prediction:.0f} messages")
        else:
            print("❌ Training failed")
    
    except Exception as e:
        logger.error(f"Fatal error: {e}")

if __name__ == "__main__":
    main()
EOF

# Step 3: Set permissions
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/predictors/simple_predictor.py
sudo chmod +x /opt/rabbitmq-ai/lib/predictors/simple_predictor.py
```

### 5.9 Step 8: Test the Prediction Model

**What we're doing**: Testing that our AI model can learn from data and make predictions.

```bash
# Step 1: Make sure we have some data to train on
echo "Ensuring we have training data..."
sudo su - rabbitmq-ai

# Activate virtual environment
source /opt/rabbitmq-ai/venv/bin/activate

# Run collector for 5 minutes to gather some data
echo "Running collector for 5 minutes to gather training data..."
timeout 300 python /opt/rabbitmq-ai/lib/collectors/simple_collector.py &

# Wait for data collection
sleep 300

# Step 2: Train the model
echo "Training the AI model..."
python /opt/rabbitmq-ai/lib/predictors/simple_predictor.py

# Exit from rabbitmq-ai user
exit
```

**Expected Output:**
```
📊 Getting historical data...
✓ Retrieved 15 data points for training
🔧 Preparing training data...
✓ Prepared training data: 12 training, 3 testing samples
🧠 Training model...
🧠 Training prediction model...
✓ Model trained successfully!
   Mean Absolute Error: 45.23
   R² Score: 0.856
✓ Model saved to /var/lib/rabbitmq-ai/models/simple_predictor.pkl
✅ Training completed successfully!
   Accuracy (R² Score): 85.6%
   Average Error: 45 messages
🔮 Testing prediction...
   Predicted queue size in next period: 1,234 messages
```

---

## 6. Phase 4: Advanced Features 🚀

### 6.1 Create Systemd Services

**What we're doing**: Setting up our AI services to run automatically as system services.

```bash
# Step 1: Create systemd service for data collection
sudo tee /etc/systemd/system/rabbitmq-ai-collector.service <<EOF
[Unit]
Description=RabbitMQ AI Data Collector
After=network.target rabbitmq-server.service influxdb.service
Wants=rabbitmq-server.service influxdb.service

[Service]
Type=simple
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/collectors/simple_collector.py
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=/var/log/rabbitmq-ai /var/lib/rabbitmq-ai

[Install]
WantedBy=multi-user.target
EOF

# Step 2: Create daily model training service
sudo tee /etc/systemd/system/rabbitmq-ai-training.service <<EOF
[Unit]
Description=RabbitMQ AI Model Training
After=network.target rabbitmq-ai-collector.service

[Service]
Type=oneshot
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/predictors/simple_predictor.py
StandardOutput=journal
StandardError=journal
EOF

# Step 3: Create timer for daily training
sudo tee /etc/systemd/system/rabbitmq-ai-training.timer <<EOF
[Unit]
Description=Run RabbitMQ AI model training daily
Requires=rabbitmq-ai-training.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Step 4: Reload systemd and enable services
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-ai-collector.service
sudo systemctl enable rabbitmq-ai-training.timer

# Step 5: Start the collector service
sudo systemctl start rabbitmq-ai-collector.service

# Step 6: Start the training timer
sudo systemctl start rabbitmq-ai-training.timer

# Step 7: Check service status
sudo systemctl status rabbitmq-ai-collector.service
sudo systemctl status rabbitmq-ai-training.timer
```

### 6.2 Create Simple API Service

**What this does**: Creates a simple web API where you can get predictions and metrics.

```bash
# Step 1: Create API directory
sudo mkdir -p /opt/rabbitmq-ai/lib/api

# Step 2: Create simple API server
sudo tee /opt/rabbitmq-ai/lib/api/simple_api.py <<'EOF'
#!/usr/bin/env python3
"""
Simple RabbitMQ AI API for Beginners
Provides basic endpoints to get metrics and predictions
"""

import json
import logging
import os
import pickle
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from influxdb_client import InfluxDBClient
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rabbitmq-ai/api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="RabbitMQ AI API",
    description="Simple API for RabbitMQ AI predictions",
    version="1.0.0"
)

class SimpleAPI:
    """Simple API for RabbitMQ AI"""
    
    def __init__(self):
        self.config = self.load_config()
        self.influx_client = None
        self.model = None
        self.scaler = None
        self.initialize_connections()
        self.load_model()
    
    def load_config(self):
        """Load configuration"""
        config = {}
        env_file = '/opt/rabbitmq-ai/config/ai_environment.env'
        
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        key, value = line.strip().split('=', 1)
                        config[key.lower()] = value
        
        return config
    
    def initialize_connections(self):
        """Initialize database connections"""
        try:
            self.influx_client = InfluxDBClient(
                url=self.config.get('influxdb_url', 'http://127.0.0.1:8086'),
                token=self.config.get('influxdb_token', ''),
                org=self.config.get('influxdb_org', 'rabbitmq-ai')
            )
            logger.info("✓ API connected to InfluxDB")
        except Exception as e:
            logger.error(f"✗ API connection error: {e}")
    
    def load_model(self):
        """Load the trained model"""
        try:
            model_path = '/var/lib/rabbitmq-ai/models/simple_predictor.pkl'
            scaler_path = '/var/lib/rabbitmq-ai/models/simple_scaler.pkl'
            
            if os.path.exists(model_path) and os.path.exists(scaler_path):
                with open(model_path, 'rb') as f:
                    self.model = pickle.load(f)
                with open(scaler_path, 'rb') as f:
                    self.scaler = pickle.load(f)
                logger.info("✓ AI model loaded")
            else:
                logger.warning("⚠ No trained model found")
        except Exception as e:
            logger.error(f"✗ Error loading model: {e}")
    
    def get_latest_metrics(self):
        """Get latest metrics from InfluxDB"""
        try:
            query = f'''
            from(bucket: "{self.config.get('influxdb_bucket', 'metrics')}")
              |> range(start: -1h)
              |> filter(fn: (r) => r._measurement == "rabbitmq_basic_metrics")
              |> last()
            '''
            
            query_api = self.influx_client.query_api()
            result = query_api.query_data_frame(query)
            
            if not result.empty:
                latest = result.iloc[-1]
                return {
                    'timestamp': str(latest.get('_time', datetime.now())),
                    'total_queues': int(latest.get('total_queues', 0)),
                    'total_messages': int(latest.get('total_messages', 0)),
                    'publish_rate': float(latest.get('publish_rate', 0)),
                    'cpu_usage': float(latest.get('cpu_usage', 0)),
                    'memory_usage_percent': float(latest.get('memory_usage_percent', 0))
                }
            else:
                return None
        except Exception as e:
            logger.error(f"✗ Error getting metrics: {e}")
            return None

# Global API instance
api = SimpleAPI()

@app.get("/")
async def root():
    """Welcome message"""
    return {
        "message": "Welcome to RabbitMQ AI API",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Check API health",
            "/metrics/latest": "Get latest metrics",
            "/predict": "Get queue prediction"
        }
    }

@app.get("/health")
async def health():
    """Health check"""
    try:
        # Check InfluxDB connection
        api.influx_client.ping()
        influx_status = "healthy"
    except:
        influx_status = "unhealthy"
    
    model_status = "loaded" if api.model is not None else "not_loaded"
    
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "services": {
            "influxdb": influx_status,
            "model": model_status
        }
    }

@app.get("/metrics/latest")
async def get_latest_metrics():
    """Get latest RabbitMQ metrics"""
    metrics = api.get_latest_metrics()
    
    if metrics:
        return {
            "status": "success",
            "data": metrics
        }
    else:
        raise HTTPException(status_code=404, detail="No metrics available")

@app.get("/predict")
async def get_prediction():
    """Get queue size prediction"""
    if api.model is None:
        raise HTTPException(status_code=503, detail="AI model not available. Train the model first.")
    
    try:
        # Get current metrics
        current_metrics = api.get_latest_metrics()
        
        if not current_metrics:
            raise HTTPException(status_code=404, detail="No current metrics available")
        
        # Prepare features for prediction
        features = [
            current_metrics.get('total_queues', 0),
            current_metrics.get('publish_rate', 0),
            current_metrics.get('cpu_usage', 0),
            current_metrics.get('memory_usage_percent', 0),
            datetime.now().hour,
            datetime.now().weekday(),
            1 if (9 <= datetime.now().hour <= 17 and datetime.now().weekday() < 5) else 0
        ]
        
        # Scale features and make prediction
        features_scaled = api.scaler.transform([features])
        prediction = api.model.predict(features_scaled)[0]
        
        # Calculate confidence (simplified)
        confidence = min(100, max(50, 100 - abs(prediction - current_metrics['total_messages']) / max(current_metrics['total_messages'], 1) * 100))
        
        return {
            "status": "success",
            "prediction": {
                "predicted_messages": round(prediction),
                "current_messages": current_metrics['total_messages'],
                "confidence_percent": round(confidence, 1),
                "prediction_time": datetime.now(timezone.utc).isoformat(),
                "model_input": {
                    "total_queues": features[0],
                    "publish_rate": features[1],
                    "cpu_usage": features[2],
                    "memory_usage_percent": features[3],
                    "hour": features[4],
                    "is_business_hour": bool(features[6])
                }
            }
        }
        
    except Exception as e:
        logger.error(f"✗ Prediction error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics/history")
async def get_metrics_history(hours: int = 24):
    """Get historical metrics"""
    if hours > 168:  # Limit to 1 week
        hours = 168
    
    try:
        query = f'''
        from(bucket: "{api.config.get('influxdb_bucket', 'metrics')}")
          |> range(start: -{hours}h)
          |> filter(fn: (r) => r._measurement == "rabbitmq_basic_metrics")
          |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
        '''
        
        query_api = api.influx_client.query_api()
        result = query_api.query_data_frame(query)
        
        if not result.empty:
            # Convert to simple format
            history = []
            for _, row in result.iterrows():
                history.append({
                    'timestamp': str(row.get('_time')),
                    'field': row.get('_field'),
                    'value': float(row.get('_value', 0))
                })
            
            return {
                "status": "success",
                "hours": hours,
                "data_points": len(history),
                "data": history
            }
        else:
            return {
                "status": "success", 
                "hours": hours,
                "data_points": 0,
                "data": []
            }
            
    except Exception as e:
        logger.error(f"✗ History error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

def main():
    """Start the API server"""
    try:
        logger.info("🚀 Starting RabbitMQ AI API server...")
        
        host = api.config.get('ai_service_host', '127.0.0.1')
        port = int(api.config.get('ai_service_port', 8080))
        
        uvicorn.run(
            app,
            host=host,
            port=port,
            log_level="info"
        )
    except Exception as e:
        logger.error(f"✗ API startup error: {e}")

if __name__ == "__main__":
    main()
EOF

# Step 3: Set permissions
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/lib/api/simple_api.py
sudo chmod +x /opt/rabbitmq-ai/lib/api/simple_api.py

# Step 4: Create systemd service for API
sudo tee /etc/systemd/system/rabbitmq-ai-api.service <<EOF
[Unit]
Description=RabbitMQ AI API Server
After=network.target rabbitmq-ai-collector.service

[Service]
Type=simple
User=rabbitmq-ai
Group=rabbitmq-ai
WorkingDirectory=/opt/rabbitmq-ai
Environment="PYTHONPATH=/opt/rabbitmq-ai/lib"
EnvironmentFile=/opt/rabbitmq-ai/config/ai_environment.env
ExecStart=/opt/rabbitmq-ai/venv/bin/python /opt/rabbitmq-ai/lib/api/simple_api.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Step 5: Enable and start API service
sudo systemctl daemon-reload
sudo systemctl enable rabbitmq-ai-api.service
sudo systemctl start rabbitmq-ai-api.service

# Step 6: Check API status
sudo systemctl status rabbitmq-ai-api.service
```

---

## 7. Testing and Validation ✅

### 7.1 Complete System Test

**What we're doing**: Testing that all components work together correctly.

```bash
echo "=== RabbitMQ AI System Test ==="

# Test 1: Check all services are running
echo "1. Checking service status..."
services=("rabbitmq-server" "influxdb" "redis" "prometheus" "rabbitmq-ai-collector" "rabbitmq-ai-api")

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "   ✓ $service: Running"
    else
        echo "   ✗ $service: Not running"
    fi
done

# Test 2: Check database connections
echo ""
echo "2. Testing database connections..."

# Test InfluxDB
if curl -s http://localhost:8086/health | grep -q "ready"; then
    echo "   ✓ InfluxDB: Connected"
else
    echo "   ✗ InfluxDB: Connection failed"
fi

# Test Redis
if redis-cli -a "AIRedisPassword2024!" ping 2>/dev/null | grep -q "PONG"; then
    echo "   ✓ Redis: Connected"
else
    echo "   ✗ Redis: Connection failed"
fi

# Test Prometheus
if curl -s http://localhost:9090/api/v1/status/config | grep -q "yaml"; then
    echo "   ✓ Prometheus: Connected"
else
    echo "   ✗ Prometheus: Connection failed"
fi

# Test 3: Check API endpoints
echo ""
echo "3. Testing AI API endpoints..."

# Test health endpoint
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    echo "   ✓ API Health: OK"
else
    echo "   ✗ API Health: Failed"
fi

# Test metrics endpoint
if curl -s http://localhost:8080/metrics/latest | grep -q "total_messages"; then
    echo "   ✓ API Metrics: OK"
else
    echo "   ✗ API Metrics: Failed"
fi

# Test prediction endpoint
if curl -s http://localhost:8080/predict | grep -q "prediction"; then
    echo "   ✓ API Predictions: OK"
else
    echo "   ✗ API Predictions: Failed (might need more training data)"
fi

# Test 4: Check logs for errors
echo ""
echo "4. Checking for errors in logs..."

error_count=$(sudo journalctl -u rabbitmq-ai-collector --since "1 hour ago" | grep -c "ERROR" || echo 0)
echo "   Collector errors in last hour: $error_count"

error_count=$(sudo journalctl -u rabbitmq-ai-api --since "1 hour ago" | grep -c "ERROR" || echo 0)
echo "   API errors in last hour: $error_count"

# Test 5: Check data collection
echo ""
echo "5. Checking data collection..."

data_points=$(curl -s "http://localhost:8080/metrics/history?hours=1" | grep -o '"data_points":[0-9]*' | cut -d: -f2 || echo 0)
echo "   Data points collected in last hour: $data_points"

echo ""
echo "=== Test Complete ==="
```

### 7.2 Interactive API Testing

**What we're doing**: Manually testing the API to see predictions in action.

```bash
echo "=== Interactive API Test ==="

# Function to make API calls with nice formatting
test_endpoint() {
    echo ""
    echo "Testing: $1"
    echo "URL: $2"
    echo "Response:"
    curl -s "$2" | python3 -m json.tool
    echo ""
}

# Test all endpoints
test_endpoint "Health Check" "http://localhost:8080/health"
test_endpoint "Latest Metrics" "http://localhost:8080/metrics/latest"
test_endpoint "Prediction" "http://localhost:8080/predict"
test_endpoint "History (last 6 hours)" "http://localhost:8080/metrics/history?hours=6"

echo "=== You can also test in your browser ==="
echo "Open these URLs in your web browser:"
echo "  Health: http://$(hostname -I | awk '{print $1}'):8080/health"
echo "  Metrics: http://$(hostname -I | awk '{print $1}'):8080/metrics/latest"
echo "  Predict: http://$(hostname -I | awk '{print $1}'):8080/predict"
echo ""
```

### 7.3 Understanding Your Results

**How to interpret the output:**

1. **Health Check Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "services": {
    "influxdb": "healthy",
    "model": "loaded"
  }
}
```
- `status: healthy` = Everything is working
- `influxdb: healthy` = Database connection is good
- `model: loaded` = AI model is ready for predictions

2. **Metrics Response:**
```json
{
  "status": "success",
  "data": {
    "total_messages": 1234,
    "total_queues": 5,
    "cpu_usage": 25.3,
    "memory_usage_percent": 45.2
  }
}
```
- Shows current state of your RabbitMQ cluster
- Numbers should match what you see in RabbitMQ management UI

3. **Prediction Response:**
```json
{
  "prediction": {
    "predicted_messages": 1456,
    "current_messages": 1234,
    "confidence_percent": 78.5
  }
}
```
- `predicted_messages` = What AI thinks will happen next
- `confidence_percent` = How sure the AI is (higher is better)

---

## 8. Troubleshooting Guide 🔧

### 8.1 Common Issues and Solutions

#### Issue 1: Services Won't Start

**Symptoms:**
```bash
sudo systemctl status rabbitmq-ai-collector
# Shows: failed (exit code 1)
```

**Solutions:**
```bash
# Check detailed logs
sudo journalctl -u rabbitmq-ai-collector -n 50

# Common fixes:
# 1. Check configuration file
sudo nano /opt/rabbitmq-ai/config/ai_environment.env

# 2. Check permissions
sudo chown -R rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai
sudo chown -R rabbitmq-ai:rabbitmq-ai /var/log/rabbitmq-ai

# 3. Test Python environment
sudo su - rabbitmq-ai
source /opt/rabbitmq-ai/venv/bin/activate
python -c "import numpy; print('OK')"
exit

# 4. Restart dependencies
sudo systemctl restart influxdb redis
```

#### Issue 2: No Data in InfluxDB

**Symptoms:**
```bash
curl http://localhost:8080/metrics/latest
# Returns: "No metrics available"
```

**Solutions:**
```bash
# 1. Check InfluxDB token
influx auth list --host http://localhost:8086

# 2. Test InfluxDB connection manually
influx bucket list --host http://localhost:8086

# 3. Check RabbitMQ credentials in config
curl -u admin:password http://localhost:15672/api/overview

# 4. Run collector manually to see errors
sudo su - rabbitmq-ai
source /opt/rabbitmq-ai/venv/bin/activate
python /opt/rabbitmq-ai/lib/collectors/simple_collector.py
exit
```

#### Issue 3: Model Training Fails

**Symptoms:**
```bash
python /opt/rabbitmq-ai/lib/predictors/simple_predictor.py
# Shows: "No data available for training"
```

**Solutions:**
```bash
# 1. Check if collector has been running long enough
sudo systemctl status rabbitmq-ai-collector

# 2. Verify data in InfluxDB
curl "http://localhost:8086/query?db=metrics&q=SHOW MEASUREMENTS"

# 3. Run collector for more time
sudo su - rabbitmq-ai
source /opt/rabbitmq-ai/venv/bin/activate
timeout 600 python /opt/rabbitmq-ai/lib/collectors/simple_collector.py
exit

# 4. Check minimum data requirements (need at least 10 data points)
```

#### Issue 4: API Returns Errors

**Symptoms:**
```bash
curl http://localhost:8080/predict
# Returns: 500 Internal Server Error
```

**Solutions:**
```bash
# 1. Check API logs
sudo journalctl -u rabbitmq-ai-api -n 20

# 2. Verify model files exist
ls -la /var/lib/rabbitmq-ai/models/

# 3. Retrain model
sudo su - rabbitmq-ai
source /opt/rabbitmq-ai/venv/bin/activate
python /opt/rabbitmq-ai/lib/predictors/simple_predictor.py
exit

# 4. Restart API service
sudo systemctl restart rabbitmq-ai-api
```

### 8.2 Performance Troubleshooting

#### System Resource Issues

```bash
# Check system resources
echo "=== System Resources ==="
echo "CPU Usage:"
top -bn1 | grep "Cpu(s)"

echo "Memory Usage:"
free -h

echo "Disk Usage:"
df -h

echo "Top processes:"
ps aux --sort=-%cpu | head -10

# Check specific AI process resource usage
echo "=== AI Process Resources ==="
ps aux | grep python | grep rabbitmq-ai
```

#### Database Performance

```bash
# Check InfluxDB performance
echo "=== InfluxDB Status ==="
curl http://localhost:8086/health
curl http://localhost:8086/debug/vars | grep -E "(queryExecutor|httpd)"

# Check Redis performance
echo "=== Redis Status ==="
redis-cli -a "AIRedisPassword2024!" info memory
redis-cli -a "AIRedisPassword2024!" info stats
```

### 8.3 Validation Commands

**Use these commands to verify everything is working:**

```bash
# Complete system validation script
cat > /tmp/validate_ai_system.sh <<'EOF'
#!/bin/bash
echo "=== RabbitMQ AI System Validation ==="

# Function to check service
check_service() {
    if systemctl is-active --quiet $1; then
        echo "✓ $1: Running"
    else
        echo "✗ $1: Not running"
        return 1
    fi
}

# Function to check URL
check_url() {
    if curl -s --max-time 5 "$2" | grep -q "$3"; then
        echo "✓ $1: OK"
    else
        echo "✗ $1: Failed"
        return 1
    fi
}

# Check all services
echo "1. Service Status:"
check_service "rabbitmq-server"
check_service "influxdb"
check_service "redis"
check_service "prometheus"
check_service "rabbitmq-ai-collector"
check_service "rabbitmq-ai-api"

echo ""
echo "2. Database Connectivity:"
check_url "InfluxDB" "http://localhost:8086/health" "ready"
check_url "Prometheus" "http://localhost:9090/api/v1/status/config" "yaml"

# Redis check
if redis-cli -a "AIRedisPassword2024!" ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis: OK"
else
    echo "✗ Redis: Failed"
fi

echo ""
echo "3. AI API Status:"
check_url "API Health" "http://localhost:8080/health" "healthy"
check_url "API Metrics" "http://localhost:8080/metrics/latest" "success"

# Check if model is available
if curl -s http://localhost:8080/predict | grep -q "prediction"; then
    echo "✓ AI Predictions: Available"
else
    echo "⚠ AI Predictions: Model needs training"
fi

echo ""
echo "4. Data Collection:"
data_points=$(curl -s "http://localhost:8080/metrics/history?hours=1" | grep -o '"data_points":[0-9]*' | cut -d: -f2 2>/dev/null || echo 0)
echo "   Data points in last hour: $data_points"

if [ "$data_points" -gt 0 ]; then
    echo "✓ Data Collection: Working"
else
    echo "⚠ Data Collection: No recent data"
fi

echo ""
echo "=== Validation Complete ==="
EOF

chmod +x /tmp/validate_ai_system.sh
/tmp/validate_ai_system.sh
```

---

## 9. Maintenance and Monitoring 📊

### 9.1 Daily Maintenance Tasks

**Create a daily maintenance script:**

```bash
# Create daily maintenance script
sudo tee /opt/rabbitmq-ai/scripts/daily_maintenance.sh <<'EOF'
#!/bin/bash
# Daily maintenance script for RabbitMQ AI system

LOG_FILE="/var/log/rabbitmq-ai/maintenance.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting daily maintenance" >> $LOG_FILE

# 1. Check disk space
DISK_USAGE=$(df /var/lib/rabbitmq-ai | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "[$DATE] WARNING: Disk usage at ${DISK_USAGE}%" >> $LOG_FILE
fi

# 2. Clean old log files (keep 7 days)
find /var/log/rabbitmq-ai -name "*.log*" -mtime +7 -delete

# 3. Check service health
for service in rabbitmq-ai-collector rabbitmq-ai-api; do
    if ! systemctl is-active --quiet $service; then
        echo "[$DATE] WARNING: $service is not running" >> $LOG_FILE
        systemctl restart $service
    fi
done

# 4. Backup model files
MODEL_DIR="/var/lib/rabbitmq-ai/models"
BACKUP_DIR="/var/lib/rabbitmq-ai/backups/$(date +%Y%m%d)"
if [ -d "$MODEL_DIR" ] && [ "$(ls -A $MODEL_DIR)" ]; then
    mkdir -p $BACKUP_DIR
    cp -r $MODEL_DIR/* $BACKUP_DIR/
    echo "[$DATE] Model files backed up to $BACKUP_DIR" >> $LOG_FILE
fi

# 5. Clean old backups (keep 30 days)
find /var/lib/rabbitmq-ai/backups -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null

echo "[$DATE] Daily maintenance completed" >> $LOG_FILE
EOF

sudo chmod +x /opt/rabbitmq-ai/scripts/daily_maintenance.sh
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/scripts/daily_maintenance.sh

# Create cron job for daily maintenance
sudo tee /etc/cron.d/rabbitmq-ai-maintenance <<EOF
# Daily maintenance for RabbitMQ AI system
0 2 * * * rabbitmq-ai /opt/rabbitmq-ai/scripts/daily_maintenance.sh
EOF
```

### 9.2 Monitoring Dashboard

**Create a simple monitoring script:**

```bash
# Create monitoring script
sudo tee /opt/rabbitmq-ai/scripts/monitor.sh <<'EOF'
#!/bin/bash
# Simple monitoring dashboard for RabbitMQ AI

clear
echo "==============================================="
echo "         RabbitMQ AI System Monitor"
echo "==============================================="
echo ""

# System Status
echo "🖥️  SYSTEM STATUS"
echo "   Date: $(date)"
echo "   Uptime: $(uptime -p)"
echo "   CPU: $(top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1)%"
echo "   Memory: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"
echo "   Disk: $(df /var/lib/rabbitmq-ai | tail -1 | awk '{print $5}')"
echo ""

# Service Status
echo "🔧 SERVICE STATUS"
for service in rabbitmq-server influxdb redis prometheus rabbitmq-ai-collector rabbitmq-ai-api; do
    if systemctl is-active --quiet $service; then
        echo "   ✅ $service"
    else
        echo "   ❌ $service"
    fi
done
echo ""

# AI Metrics
echo "🤖 AI SYSTEM STATUS"

# Check if API is responding
if curl -s --max-time 5 http://localhost:8080/health | grep -q "healthy"; then
    echo "   ✅ AI API: Healthy"
    
    # Get latest metrics
    LATEST=$(curl -s http://localhost:8080/metrics/latest)
    if echo "$LATEST" | grep -q "total_messages"; then
        MESSAGES=$(echo "$LATEST" | grep -o '"total_messages":[0-9]*' | cut -d: -f2)
        QUEUES=$(echo "$LATEST" | grep -o '"total_queues":[0-9]*' | cut -d: -f2)
        CPU=$(echo "$LATEST" | grep -o '"cpu_usage":[0-9.]*' | cut -d: -f2)
        
        echo "   📊 Messages: $MESSAGES"
        echo "   📋 Queues: $QUEUES"
        echo "   ⚡ CPU: ${CPU}%"
    fi
    
    # Check prediction capability
    if curl -s --max-time 5 http://localhost:8080/predict | grep -q "prediction"; then
        echo "   🔮 Predictions: Available"
    else
        echo "   ⚠️  Predictions: Model needs training"
    fi
else
    echo "   ❌ AI API: Not responding"
fi
echo ""

# Data Collection Stats
echo "📈 DATA COLLECTION"
DATA_POINTS=$(curl -s "http://localhost:8080/metrics/history?hours=1" | grep -o '"data_points":[0-9]*' | cut -d: -f2 2>/dev/null || echo 0)
echo "   Last hour: $DATA_POINTS data points"

# Log file sizes
echo "   Collector log: $(du -h /var/log/rabbitmq-ai/collector.log 2>/dev/null | cut -f1 || echo 'N/A')"
echo "   API log: $(du -h /var/log/rabbitmq-ai/api.log 2>/dev/null | cut -f1 || echo 'N/A')"
echo ""

echo "==============================================="
echo "Press Ctrl+C to exit, or wait 30 seconds for refresh..."
sleep 30
exec $0  # Restart script for continuous monitoring
EOF

sudo chmod +x /opt/rabbitmq-ai/scripts/monitor.sh
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/scripts/monitor.sh

echo "You can run the monitor with: /opt/rabbitmq-ai/scripts/monitor.sh"
```

### 9.3 Setting Up Alerts

**Create simple alerting:**

```bash
# Create alerting script
sudo tee /opt/rabbitmq-ai/scripts/check_alerts.sh <<'EOF'
#!/bin/bash
# Simple alerting for RabbitMQ AI system

ALERT_LOG="/var/log/rabbitmq-ai/alerts.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Function to send alert
send_alert() {
    local LEVEL=$1
    local MESSAGE=$2
    echo "[$DATE] $LEVEL: $MESSAGE" >> $ALERT_LOG
    
    # You can add email/Slack notifications here
    # Example: echo "$MESSAGE" | mail -s "RabbitMQ AI Alert" admin@company.com
}

# Check disk space
DISK_USAGE=$(df /var/lib/rabbitmq-ai | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    send_alert "CRITICAL" "Disk usage at ${DISK_USAGE}% - immediate action required"
elif [ $DISK_USAGE -gt 80 ]; then
    send_alert "WARNING" "Disk usage at ${DISK_USAGE}% - monitor closely"
fi

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [ $MEMORY_USAGE -gt 90 ]; then
    send_alert "CRITICAL" "Memory usage at ${MEMORY_USAGE}% - system may become unstable"
fi

# Check service health
for service in rabbitmq-ai-collector rabbitmq-ai-api; do
    if ! systemctl is-active --quiet $service; then
        send_alert "CRITICAL" "Service $service is not running"
    fi
done

# Check API health
if ! curl -s --max-time 10 http://localhost:8080/health | grep -q "healthy"; then
    send_alert "CRITICAL" "AI API is not responding"
fi

# Check data collection
DATA_POINTS=$(curl -s "http://localhost:8080/metrics/history?hours=1" | grep -o '"data_points":[0-9]*' | cut -d: -f2 2>/dev/null || echo 0)
if [ $DATA_POINTS -eq 0 ]; then
    send_alert "WARNING" "No data collected in the last hour"
fi
EOF

sudo chmod +x /opt/rabbitmq-ai/scripts/check_alerts.sh
sudo chown rabbitmq-ai:rabbitmq-ai /opt/rabbitmq-ai/scripts/check_alerts.sh

# Run alerts check every 15 minutes
sudo tee /etc/cron.d/rabbitmq-ai-alerts <<EOF
# Alert checking for RabbitMQ AI system
*/15 * * * * rabbitmq-ai /opt/rabbitmq-ai/scripts/check_alerts.sh
EOF
```

---

## 🎉 Congratulations!

You have successfully implemented an AI-powered RabbitMQ monitoring system! Here's what you've accomplished:

### ✅ What You've Built:
1. **Data Collection System** - Automatically gathers RabbitMQ metrics
2. **Machine Learning Model** - Predicts future queue behavior
3. **REST API** - Provides easy access to predictions and metrics
4. **Automated Services** - Everything runs automatically in the background
5. **Monitoring Tools** - Scripts to keep everything healthy

### 🔄 What Happens Now:
- Your system collects data every 30 seconds
- The AI model retrains daily with new data
- You can get predictions anytime via the API
- Services restart automatically if they fail
- Daily maintenance keeps everything clean

### 📞 Getting Help:
If you need help, check:
1. The troubleshooting section above
2. Log files in `/var/log/rabbitmq-ai/`
3. Service status with `systemctl status servicename`
4. API endpoints for real-time status

### 🚀 Next Steps:
1. Let the system collect data for a few days
2. Monitor the prediction accuracy
3. Customize the alerting for your needs
4. Explore adding more AI features

**Your AI-powered RabbitMQ system is now ready for production use!** 🎊