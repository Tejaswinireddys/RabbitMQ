#!/bin/bash

# RabbitMQ AI/ML Operations - EC2 RHEL8 Deployment Script
# This script automates the complete deployment of the AI/ML operations system on EC2 RHEL8 instances

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-10.0.1.0/24}"
PRIVATE_SUBNET_A_CIDR="${PRIVATE_SUBNET_A_CIDR:-10.0.2.0/24}"
PRIVATE_SUBNET_B_CIDR="${PRIVATE_SUBNET_B_CIDR:-10.0.3.0/24}"
PRIVATE_SUBNET_C_CIDR="${PRIVATE_SUBNET_C_CIDR:-10.0.4.0/24}"
KEY_PAIR_NAME="${KEY_PAIR_NAME:-rabbitmq-aiml-key}"
INSTANCE_TYPE_RABBITMQ="${INSTANCE_TYPE_RABBITMQ:-m5.xlarge}"
INSTANCE_TYPE_MONITORING="${INSTANCE_TYPE_MONITORING:-m5.large}"
INSTANCE_TYPE_KUBERNETES="${INSTANCE_TYPE_KUBERNETES:-m5.xlarge}"
RHEL8_AMI_ID="${RHEL8_AMI_ID:-ami-0c02fb55956c7d316}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_message "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is required but not installed"
        exit 1
    fi
    
    # Check Ansible
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible is required but not installed"
        exit 1
    fi
    
    log_success "All prerequisites are available"
}

# Create VPC and networking
create_vpc_networking() {
    log_message "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block $VPC_CIDR \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=rabbitmq-aiml-vpc}]' \
        --query 'Vpc.VpcId' \
        --output text)
    
    log_success "VPC created: $VPC_ID"
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=rabbitmq-aiml-igw}]' \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID
    
    log_success "Internet Gateway created and attached: $IGW_ID"
    
    # Create Public Subnet
    PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PUBLIC_SUBNET_CIDR \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rabbitmq-aiml-public-subnet}]' \
        --query 'Subnet.SubnetId' \
        --output text)
    
    # Create Private Subnets
    PRIVATE_SUBNET_A_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_A_CIDR \
        --availability-zone ${AWS_REGION}a \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rabbitmq-aiml-private-subnet-a}]' \
        --query 'Subnet.SubnetId' \
        --output text)
    
    PRIVATE_SUBNET_B_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_B_CIDR \
        --availability-zone ${AWS_REGION}b \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rabbitmq-aiml-private-subnet-b}]' \
        --query 'Subnet.SubnetId' \
        --output text)
    
    PRIVATE_SUBNET_C_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $PRIVATE_SUBNET_C_CIDR \
        --availability-zone ${AWS_REGION}c \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rabbitmq-aiml-private-subnet-c}]' \
        --query 'Subnet.SubnetId' \
        --output text)
    
    log_success "Subnets created: Public=$PUBLIC_SUBNET_ID, Private A=$PRIVATE_SUBNET_A_ID, Private B=$PRIVATE_SUBNET_B_ID, Private C=$PRIVATE_SUBNET_C_ID"
    
    # Create Route Table for Public Subnet
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rabbitmq-aiml-public-rt}]' \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    # Create route to Internet Gateway
    aws ec2 create-route \
        --route-table-id $PUBLIC_RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID
    
    # Associate Public Subnet with Public Route Table
    aws ec2 associate-route-table \
        --subnet-id $PUBLIC_SUBNET_ID \
        --route-table-id $PUBLIC_RT_ID
    
    log_success "Route tables created and configured"
    
    # Store IDs for later use
    echo "VPC_ID=$VPC_ID" > .aws-infrastructure
    echo "IGW_ID=$IGW_ID" >> .aws-infrastructure
    echo "PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID" >> .aws-infrastructure
    echo "PRIVATE_SUBNET_A_ID=$PRIVATE_SUBNET_A_ID" >> .aws-infrastructure
    echo "PRIVATE_SUBNET_B_ID=$PRIVATE_SUBNET_B_ID" >> .aws-infrastructure
    echo "PRIVATE_SUBNET_C_ID=$PRIVATE_SUBNET_C_ID" >> .aws-infrastructure
    echo "PUBLIC_RT_ID=$PUBLIC_RT_ID" >> .aws-infrastructure
}

# Create security groups
create_security_groups() {
    log_message "Creating security groups..."
    
    source .aws-infrastructure
    
    # RabbitMQ Security Group
    RABBITMQ_SG_ID=$(aws ec2 create-security-group \
        --group-name rabbitmq-sg \
        --description "RabbitMQ Cluster Security Group" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text)
    
    # Allow RabbitMQ ports
    aws ec2 authorize-security-group-ingress \
        --group-id $RABBITMQ_SG_ID \
        --protocol tcp \
        --port 5672 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $RABBITMQ_SG_ID \
        --protocol tcp \
        --port 15672 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $RABBITMQ_SG_ID \
        --protocol tcp \
        --port 25672 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $RABBITMQ_SG_ID \
        --protocol tcp \
        --port 4369 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $RABBITMQ_SG_ID \
        --protocol tcp \
        --port 15692 \
        --cidr $VPC_CIDR
    
    # Monitoring Security Group
    MONITORING_SG_ID=$(aws ec2 create-security-group \
        --group-name monitoring-sg \
        --description "Monitoring Stack Security Group" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text)
    
    # Allow monitoring ports
    aws ec2 authorize-security-group-ingress \
        --group-id $MONITORING_SG_ID \
        --protocol tcp \
        --port 9090 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $MONITORING_SG_ID \
        --protocol tcp \
        --port 3000 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $MONITORING_SG_ID \
        --protocol tcp \
        --port 8086 \
        --cidr $VPC_CIDR
    
    # Kubernetes Security Group
    KUBERNETES_SG_ID=$(aws ec2 create-security-group \
        --group-name kubernetes-sg \
        --description "Kubernetes Cluster Security Group" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text)
    
    # Allow Kubernetes ports
    aws ec2 authorize-security-group-ingress \
        --group-id $KUBERNETES_SG_ID \
        --protocol tcp \
        --port 6443 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $KUBERNETES_SG_ID \
        --protocol tcp \
        --port 2379-2380 \
        --cidr $VPC_CIDR
    
    aws ec2 authorize-security-group-ingress \
        --group-id $KUBERNETES_SG_ID \
        --protocol tcp \
        --port 10250 \
        --cidr $VPC_CIDR
    
    # Bastion Security Group
    BASTION_SG_ID=$(aws ec2 create-security-group \
        --group-name bastion-sg \
        --description "Bastion Host Security Group" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text)
    
    # Allow SSH from anywhere
    aws ec2 authorize-security-group-ingress \
        --group-id $BASTION_SG_ID \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    log_success "Security groups created: RabbitMQ=$RABBITMQ_SG_ID, Monitoring=$MONITORING_SG_ID, Kubernetes=$KUBERNETES_SG_ID, Bastion=$BASTION_SG_ID"
    
    # Store security group IDs
    echo "RABBITMQ_SG_ID=$RABBITMQ_SG_ID" >> .aws-infrastructure
    echo "MONITORING_SG_ID=$MONITORING_SG_ID" >> .aws-infrastructure
    echo "KUBERNETES_SG_ID=$KUBERNETES_SG_ID" >> .aws-infrastructure
    echo "BASTION_SG_ID=$BASTION_SG_ID" >> .aws-infrastructure
}

# Create EC2 instances
create_ec2_instances() {
    log_message "Creating EC2 instances..."
    
    source .aws-infrastructure
    
    # Create user data scripts
    create_user_data_scripts
    
    # Create RabbitMQ instances
    log_message "Creating RabbitMQ instances..."
    for i in {1..3}; do
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id $RHEL8_AMI_ID \
            --count 1 \
            --instance-type $INSTANCE_TYPE_RABBITMQ \
            --key-name $KEY_PAIR_NAME \
            --security-group-ids $RABBITMQ_SG_ID \
            --subnet-id $PRIVATE_SUBNET_A_ID \
            --user-data file://user-data-rabbitmq.sh \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rabbitmq-node-$i},{Key=Role,Value=rabbitmq}]" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        log_success "RabbitMQ Node $i created: $INSTANCE_ID"
    done
    
    # Create Monitoring instances
    log_message "Creating Monitoring instances..."
    for i in {1..3}; do
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id $RHEL8_AMI_ID \
            --count 1 \
            --instance-type $INSTANCE_TYPE_MONITORING \
            --key-name $KEY_PAIR_NAME \
            --security-group-ids $MONITORING_SG_ID \
            --subnet-id $PRIVATE_SUBNET_A_ID \
            --user-data file://user-data-monitoring.sh \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=monitoring-node-$i},{Key=Role,Value=monitoring}]" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        log_success "Monitoring Node $i created: $INSTANCE_ID"
    done
    
    # Create Kubernetes instances
    log_message "Creating Kubernetes instances..."
    for i in {1..3}; do
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id $RHEL8_AMI_ID \
            --count 1 \
            --instance-type $INSTANCE_TYPE_KUBERNETES \
            --key-name $KEY_PAIR_NAME \
            --security-group-ids $KUBERNETES_SG_ID \
            --subnet-id $PRIVATE_SUBNET_B_ID \
            --user-data file://user-data-kubernetes.sh \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=k8s-node-$i},{Key=Role,Value=kubernetes}]" \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        log_success "Kubernetes Node $i created: $INSTANCE_ID"
    done
    
    # Create Bastion host
    log_message "Creating Bastion host..."
    BASTION_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id $RHEL8_AMI_ID \
        --count 1 \
        --instance-type t3.medium \
        --key-name $KEY_PAIR_NAME \
        --security-group-ids $BASTION_SG_ID \
        --subnet-id $PUBLIC_SUBNET_ID \
        --associate-public-ip-address \
        --user-data file://user-data-bastion.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=bastion-host},{Key=Role,Value=bastion}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    log_success "Bastion host created: $BASTION_INSTANCE_ID"
}

# Create user data scripts
create_user_data_scripts() {
    log_message "Creating user data scripts..."
    
    # RabbitMQ user data
    cat > user-data-rabbitmq.sh << 'EOF'
#!/bin/bash
# RabbitMQ Node User Data

# Update system
dnf update -y

# Install required packages
dnf install -y python3 python3-pip git wget curl vim htop

# Configure hostname
hostnamectl set-hostname rabbitmq-node-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Configure timezone
timedatectl set-timezone UTC

# Install EPEL repository
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

# Configure firewall
firewall-cmd --permanent --add-port=5672/tcp
firewall-cmd --permanent --add-port=15672/tcp
firewall-cmd --permanent --add-port=25672/tcp
firewall-cmd --permanent --add-port=4369/tcp
firewall-cmd --permanent --add-port=15692/tcp
firewall-cmd --reload

# Create rabbitmq user
useradd -m -s /bin/bash rabbitmq

# Configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Install RabbitMQ
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-erlang/script.rpm.sh | bash

dnf install -y erlang rabbitmq-server

# Enable and start RabbitMQ
systemctl enable rabbitmq-server
systemctl start rabbitmq-server

# Install management plugin
rabbitmq-plugins enable rabbitmq_management
rabbitmq-plugins enable rabbitmq_prometheus

# Create admin user
rabbitmqctl add_user admin admin123
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# Configure RabbitMQ
cat > /etc/rabbitmq/rabbitmq.conf << 'RABBITMQ_EOF'
# Network configuration
listeners.tcp.default = 5672
management.tcp.port = 15672
management.tcp.ip = 0.0.0.0

# Prometheus configuration
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0

# Memory configuration
vm_memory_high_watermark.relative = 0.6
vm_memory_high_watermark_paging_ratio = 0.5

# Disk configuration
disk_free_limit.relative = 2.0

# Logging configuration
log.console = true
log.console.level = info
log.file = true
log.file.level = info
log.file.rotation.date = $D0
log.file.rotation.size = 0
RABBITMQ_EOF

# Restart RabbitMQ
systemctl restart rabbitmq-server

# Install Node Exporter
useradd --no-create-home --shell /bin/false node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xzf node_exporter-1.6.1.linux-amd64.tar.gz
cp node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Create systemd service for Node Exporter
cat > /etc/systemd/system/node_exporter.service << 'NODE_EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
NODE_EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Configure logrotate
cat > /etc/logrotate.d/rabbitmq << 'LOGROTATE_EOF'
/var/log/rabbitmq/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 rabbitmq rabbitmq
    postrotate
        /bin/kill -USR1 $(cat /var/run/rabbitmq/rabbitmq.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
LOGROTATE_EOF
EOF

    # Monitoring user data
    cat > user-data-monitoring.sh << 'EOF'
#!/bin/bash
# Monitoring Node User Data

# Update system
dnf update -y

# Install required packages
dnf install -y python3 python3-pip git wget curl vim htop

# Configure hostname
hostnamectl set-hostname monitoring-node-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Configure timezone
timedatectl set-timezone UTC

# Install EPEL repository
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

# Configure firewall
firewall-cmd --permanent --add-port=9090/tcp
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --permanent --add-port=8086/tcp
firewall-cmd --reload

# Install Prometheus
useradd --no-create-home --shell /bin/false prometheus
mkdir /etc/prometheus
mkdir /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus
chown prometheus:prometheus /var/lib/prometheus

# Download and install Prometheus
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xzf prometheus-2.45.0.linux-amd64.tar.gz
cp prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool

# Configure Prometheus
cat > /etc/prometheus/prometheus.yml << 'PROMETHEUS_EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['10.0.2.10:15692', '10.0.2.11:15692', '10.0.2.12:15692']
    scrape_interval: 30s
    metrics_path: /metrics

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['10.0.2.10:9100', '10.0.2.11:9100', '10.0.2.12:9100']
PROMETHEUS_EOF

# Create systemd service
cat > /etc/systemd/system/prometheus.service << 'PROMETHEUS_SERVICE_EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
PROMETHEUS_SERVICE_EOF

# Enable and start Prometheus
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Install Grafana
cat > /etc/yum.repos.d/grafana.repo << 'GRAFANA_REPO_EOF'
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
GRAFANA_REPO_EOF

dnf install -y grafana
systemctl enable grafana-server
systemctl start grafana-server

# Install InfluxDB
cat > /etc/yum.repos.d/influxdb.repo << 'INFLUXDB_REPO_EOF'
[influxdb]
name = InfluxDB Repository - RHEL $releasever
baseurl = https://repos.influxdata.com/rhel/$releasever/$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdb.key
INFLUXDB_REPO_EOF

dnf install -y influxdb
systemctl enable influxdb
systemctl start influxdb
EOF

    # Kubernetes user data
    cat > user-data-kubernetes.sh << 'EOF'
#!/bin/bash
# Kubernetes Node User Data

# Update system
dnf update -y

# Install required packages
dnf install -y python3 python3-pip git wget curl vim htop

# Configure hostname
hostnamectl set-hostname k8s-node-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Configure timezone
timedatectl set-timezone UTC

# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure firewall
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=10251/tcp
firewall-cmd --permanent --add-port=10252/tcp
firewall-cmd --permanent --add-port=10255/tcp
firewall-cmd --reload

# Install Docker
dnf install -y docker
systemctl enable docker
systemctl start docker

# Install Kubernetes
cat > /etc/yum.repos.d/kubernetes.repo << 'KUBERNETES_REPO_EOF'
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
KUBERNETES_REPO_EOF

dnf install -y kubelet kubeadm kubectl
systemctl enable kubelet

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Helm repositories
helm repo add stable https://charts.helm.sh/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
EOF

    # Bastion user data
    cat > user-data-bastion.sh << 'EOF'
#!/bin/bash
# Bastion Host User Data

# Update system
dnf update -y

# Install required packages
dnf install -y python3 python3-pip git wget curl vim htop

# Configure hostname
hostnamectl set-hostname bastion-host

# Configure timezone
timedatectl set-timezone UTC

# Install EPEL repository
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm

# Configure firewall
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --reload

# Configure SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Ansible
dnf install -y ansible

# Create deployment directory
mkdir -p /opt/rabbitmq-aiml
chmod 755 /opt/rabbitmq-aiml
EOF

    log_success "User data scripts created"
}

# Wait for instances to be ready
wait_for_instances() {
    log_message "Waiting for instances to be ready..."
    
    # Wait for all instances to be running
    aws ec2 wait instance-running --filters "Name=tag:Role,Values=rabbitmq,monitoring,kubernetes,bastion"
    
    log_success "All instances are running"
    
    # Get instance information
    aws ec2 describe-instances \
        --filters "Name=tag:Role,Values=rabbitmq,monitoring,kubernetes,bastion" \
        --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0],PublicIpAddress,PrivateIpAddress,State.Name]' \
        --output table
}

# Deploy AI/ML components
deploy_aiml_components() {
    log_message "Deploying AI/ML components..."
    
    # Get bastion host IP
    BASTION_IP=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log_message "Bastion host IP: $BASTION_IP"
    
    # Create deployment script for bastion host
    cat > deploy-on-bastion.sh << 'EOF'
#!/bin/bash
# Deploy AI/ML components on bastion host

# Get private IPs
RABBITMQ_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Role,Values=rabbitmq" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PrivateIpAddress' \
    --output text)

MONITORING_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Role,Values=monitoring" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PrivateIpAddress' \
    --output text)

KUBERNETES_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Role,Values=kubernetes" "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].PrivateIpAddress' \
    --output text)

# Initialize Kubernetes cluster on first node
K8S_MASTER_IP=$(echo $KUBERNETES_IPS | awk '{print $1}')
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$K8S_MASTER_IP"

# Get join command
JOIN_COMMAND=$(ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "sudo kubeadm token create --print-join-command")

# Join worker nodes
for ip in $KUBERNETES_IPS; do
    if [ "$ip" != "$K8S_MASTER_IP" ]; then
        ssh -o StrictHostKeyChecking=no ec2-user@$ip "sudo $JOIN_COMMAND"
    fi
done

# Install Flannel network plugin
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"

# Remove taint from master node
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl taint nodes --all node-role.kubernetes.io/control-plane-"

# Install Kubeflow
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl apply -k 'github.com/kubeflow/manifests/example?ref=v1.8.0'"

# Wait for Kubeflow to be ready
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl wait --for=condition=ready pod -l app=centraldashboard -n kubeflow --timeout=600s"

# Deploy AI/ML models
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl create namespace aiml"

# Deploy anomaly detection
ssh -o StrictHostKeyChecking=no ec2-user@$K8S_MASTER_IP "kubectl apply -f - << 'YAML_EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anomaly-detection
  namespace: aiml
spec:
  replicas: 1
  selector:
    matchLabels:
      app: anomaly-detection
  template:
    metadata:
      labels:
        app: anomaly-detection
    spec:
      containers:
      - name: anomaly-detection
        image: python:3.11-slim
        command: ['python', '/app/anomaly_detection_model.py']
        ports:
        - containerPort: 8080
        env:
        - name: RABBITMQ_URL
          value: 'http://$RABBITMQ_IPS:15672'
        - name: RABBITMQ_USER
          value: 'admin'
        - name: RABBITMQ_PASS
          value: 'admin123'
        volumeMounts:
        - name: app-code
          mountPath: /app
      volumes:
      - name: app-code
        configMap:
          name: anomaly-detection-code
---
apiVersion: v1
kind: Service
metadata:
  name: anomaly-detection
  namespace: aiml
spec:
  selector:
    app: anomaly-detection
  ports:
  - port: 8080
    targetPort: 8080
YAML_EOF"

log_success "AI/ML components deployed"
EOF

    # Copy deployment script to bastion host
    scp -o StrictHostKeyChecking=no -i ~/.ssh/$KEY_PAIR_NAME.pem deploy-on-bastion.sh ec2-user@$BASTION_IP:/tmp/
    
    # Execute deployment script on bastion host
    ssh -o StrictHostKeyChecking=no -i ~/.ssh/$KEY_PAIR_NAME.pem ec2-user@$BASTION_IP "chmod +x /tmp/deploy-on-bastion.sh && /tmp/deploy-on-bastion.sh"
    
    log_success "AI/ML components deployed successfully"
}

# Display access information
display_access_info() {
    log_message "Displaying access information..."
    
    # Get instance information
    BASTION_IP=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=bastion-host" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    RABBITMQ_IPS=$(aws ec2 describe-instances \
        --filters "Name=tag:Role,Values=rabbitmq" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].PrivateIpAddress' \
        --output text)
    
    MONITORING_IPS=$(aws ec2 describe-instances \
        --filters "Name=tag:Role,Values=monitoring" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].PrivateIpAddress' \
        --output text)
    
    KUBERNETES_IPS=$(aws ec2 describe-instances \
        --filters "Name=tag:Role,Values=kubernetes" "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].PrivateIpAddress' \
        --output text)
    
    echo ""
    echo "🎉 RabbitMQ AI/ML System Deployment Completed!"
    echo "=============================================="
    echo ""
    echo "📊 Access Information:"
    echo "  • Bastion Host: ssh -i ~/.ssh/$KEY_PAIR_NAME.pem ec2-user@$BASTION_IP"
    echo "  • RabbitMQ Management: http://$(echo $RABBITMQ_IPS | awk '{print $1}'):15672 (admin/admin123)"
    echo "  • Grafana: http://$(echo $MONITORING_IPS | awk '{print $1}'):3000 (admin/admin123)"
    echo "  • Prometheus: http://$(echo $MONITORING_IPS | awk '{print $1}'):9090"
    echo "  • Kubernetes Master: $(echo $KUBERNETES_IPS | awk '{print $1}'):6443"
    echo ""
    echo "🔧 Port Forwarding Commands (via Bastion):"
    echo "  • RabbitMQ: ssh -i ~/.ssh/$KEY_PAIR_NAME.pem -L 15672:$(echo $RABBITMQ_IPS | awk '{print $1}'):15672 ec2-user@$BASTION_IP"
    echo "  • Grafana: ssh -i ~/.ssh/$KEY_PAIR_NAME.pem -L 3000:$(echo $MONITORING_IPS | awk '{print $1}'):3000 ec2-user@$BASTION_IP"
    echo "  • Prometheus: ssh -i ~/.ssh/$KEY_PAIR_NAME.pem -L 9090:$(echo $MONITORING_IPS | awk '{print $1}'):9090 ec2-user@$BASTION_IP"
    echo ""
    echo "📈 Monitoring Dashboards:"
    echo "  • Queue Performance: http://localhost:3000/d/queue-performance"
    echo "  • Channels & Connections: http://localhost:3000/d/channels-connections"
    echo "  • Message Flow: http://localhost:3000/d/message-flow"
    echo "  • System Performance: http://localhost:3000/d/system-performance"
    echo "  • Cluster Health: http://localhost:3000/d/cluster-health"
    echo ""
    echo "🤖 AI/ML Services:"
    echo "  • Anomaly Detection: http://$(echo $KUBERNETES_IPS | awk '{print $1}'):8080 (anomaly-detection service)"
    echo "  • Performance Prediction: http://$(echo $KUBERNETES_IPS | awk '{print $1}'):8080 (performance-prediction service)"
    echo "  • Decision Engine: http://$(echo $KUBERNETES_IPS | awk '{print $1}'):8080 (decision-engine service)"
    echo ""
    echo "🚀 Next Steps:"
    echo "  1. Set up port forwarding for the services you want to access"
    echo "  2. Import Grafana dashboards from configs/dashboards/"
    echo "  3. Configure alerting rules in Prometheus"
    echo "  4. Train ML models with historical data"
    echo "  5. Test the AI/ML automation system"
    echo ""
}

# Cleanup function
cleanup() {
    log_message "Cleaning up temporary files..."
    rm -f user-data-*.sh deploy-on-bastion.sh
    log_success "Cleanup completed"
}

# Main deployment function
main() {
    echo "🚀 RabbitMQ AI/ML System - EC2 RHEL8 Deployment"
    echo "================================================"
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --key-pair)
                KEY_PAIR_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --region REGION           AWS region (default: us-east-1)"
                echo "  --key-pair KEY_PAIR       EC2 key pair name (default: rabbitmq-aiml-key)"
                echo "  --help                    Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  AWS_REGION, KEY_PAIR_NAME, VPC_CIDR, etc."
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    create_vpc_networking
    create_security_groups
    create_ec2_instances
    wait_for_instances
    deploy_aiml_components
    display_access_info
    cleanup
    
    log_success "RabbitMQ AI/ML system deployment on EC2 RHEL8 completed successfully!"
}

# Run main function
main "$@"
