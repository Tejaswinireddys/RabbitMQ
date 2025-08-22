# Deployment Documentation

This directory contains comprehensive deployment guides for RabbitMQ 4.x across different platforms and scenarios.

## 📁 Contents

### 🎯 Core Deployment Guides
- **[production-deployment-guide.md](production-deployment-guide.md)** - Enterprise production deployment procedures
- **[rabbitmq-4x-rhel8-deployment.md](rabbitmq-4x-rhel8-deployment.md)** - RHEL8 VM specific deployment with static cluster configuration
- **[rabbitmq-single-node-deployment.md](rabbitmq-single-node-deployment.md)** - Single-node deployment with Docker and native options

### 📋 Manual Deployment Procedures
- **[manual-deployment-guide-updated.md](manual-deployment-guide-updated.md)** - Updated manual deployment procedures
- **[manual-deployment-steps-complete.md](manual-deployment-steps-complete.md)** - Complete step-by-step manual deployment
- **[manual-deployment-steps.md](manual-deployment-steps.md)** - Basic manual deployment steps
- **[deployment-guide.md](deployment-guide.md)** - General deployment guide

### 🔒 Specialized Deployments
- **[non-root-deployment-guide.md](non-root-deployment-guide.md)** - Deployment without root privileges
- **[offline-installation-guide.md](offline-installation-guide.md)** - Air-gapped environment deployment

## 🎯 Deployment Scenarios

### Production Enterprise Deployment
- Multi-node clusters
- High availability configuration
- Load balancer integration
- Monitoring and alerting setup

### Development/Testing
- Single-node deployments
- Docker-based setups
- Quick start configurations

### Specialized Environments
- Air-gapped networks
- Non-privileged user installations
- Platform-specific optimizations

## 🔧 Platform Support

### Supported Operating Systems
- **RHEL 8+** - Primary enterprise platform
- **CentOS 8+** - Community enterprise alternative
- **Ubuntu 20.04+** - Development and testing
- **Docker** - Containerized deployments

### Deployment Methods
- **Native Installation** - Direct OS installation
- **Docker Containers** - Containerized deployment
- **Kubernetes** - Orchestrated deployment
- **Manual Setup** - Step-by-step manual configuration

## 📋 Prerequisites

### System Requirements
- 4+ CPU cores
- 8+ GB RAM
- 50+ GB storage
- Network connectivity

### Software Dependencies
- Erlang/OTP 26+
- RabbitMQ 4.x packages
- SSL certificates (production)
- Monitoring tools

## 🚀 Quick Start Guide

### For Production Deployment:
1. Review [production-deployment-guide.md](production-deployment-guide.md)
2. Prepare infrastructure requirements
3. Follow platform-specific guide
4. Implement monitoring and backup

### For RHEL8 VM Deployment:
1. Follow [rabbitmq-4x-rhel8-deployment.md](rabbitmq-4x-rhel8-deployment.md)
2. Configure firewall and SELinux
3. Set up cluster nodes
4. Validate deployment

### For Single Node Testing:
1. Use [rabbitmq-single-node-deployment.md](rabbitmq-single-node-deployment.md)
2. Choose Docker or native installation
3. Configure basic settings
4. Test connectivity

## 🔍 Troubleshooting

### Common Issues
- Check [troubleshooting documentation](../troubleshooting/)
- Verify system requirements
- Review firewall configurations
- Validate network connectivity

### Support Resources
- Platform-specific documentation
- Community forums
- Enterprise support channels

## 📊 Post-Deployment

After successful deployment:
1. Configure [monitoring](../monitoring/)
2. Set up [backup procedures](../configuration/)
3. Plan [upgrade strategy](../upgrades/)
4. Implement [security measures](../../configs/templates/)