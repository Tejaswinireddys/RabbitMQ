# Redis 8.2.2 High Availability Cluster Deployment

## Three-Node Redis Cluster with Sentinel

### Overview

This deployment provides a highly available Redis cluster with automatic failover using Redis Sentinel.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        REDIS HA ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐           │
│    │     NODE 1      │  │     NODE 2      │  │     NODE 3      │           │
│    │   (Master)      │  │   (Replica)     │  │   (Replica)     │           │
│    │                 │  │                 │  │                 │           │
│    │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │           │
│    │ │   Redis     │ │  │ │   Redis     │ │  │ │   Redis     │ │           │
│    │ │   :6379     │ │  │ │   :6379     │ │  │ │   :6379     │ │           │
│    │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │           │
│    │        │        │  │        │        │  │        │        │           │
│    │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌─────────────┐ │           │
│    │ │  Sentinel   │ │  │ │  Sentinel   │ │  │ │  Sentinel   │ │           │
│    │ │   :26379    │ │  │ │   :26379    │ │  │ │   :26379    │ │           │
│    │ └─────────────┘ │  │ └─────────────┘ │  │ └─────────────┘ │           │
│    └────────┬────────┘  └────────┬────────┘  └────────┬────────┘           │
│             │                    │                    │                     │
│             └────────────────────┼────────────────────┘                     │
│                                  │                                          │
│                         Sentinel Quorum                                     │
│                        (2 of 3 required)                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Specifications

| Component | Details |
|-----------|---------|
| Redis Version | 8.2.2 |
| Nodes | 3 (1 Master + 2 Replicas) |
| Sentinels | 3 (1 per node) |
| Redis Port | 6379 |
| Sentinel Port | 26379 |
| User | `redis` (non-root) |
| Install Path | `/opt/cached/current` |
| Data Path | `/opt/cached/current/data` |
| Log Path | `/opt/cached/current/logs` |

### Directory Structure

```
/opt/cached/
├── current/                    # Symlink to active version
│   ├── bin/                    # Redis binaries
│   │   ├── redis-server
│   │   ├── redis-cli
│   │   ├── redis-sentinel
│   │   └── redis-benchmark
│   ├── conf/                   # Configuration files
│   │   ├── redis.conf
│   │   └── sentinel.conf
│   ├── data/                   # Redis data (RDB/AOF)
│   ├── logs/                   # Log files
│   │   ├── redis.log
│   │   └── sentinel.log
│   ├── run/                    # PID files
│   │   ├── redis.pid
│   │   └── sentinel.pid
│   └── scripts/                # Management scripts
└── redis-8.2.2/                # Actual installation
```

### Quick Start

```bash
# 1. Create redis user and directories (as root)
sudo ./scripts/01-setup-user.sh

# 2. Install Redis (as root, runs as redis user)
sudo ./scripts/02-install-redis.sh

# 3. Configure and start (as redis user)
sudo -u redis ./scripts/03-configure-node.sh <node-number> <master-ip>
sudo -u redis ./scripts/04-start-services.sh
```

### Node Configuration

| Node | Role | IP Address | Redis Port | Sentinel Port |
|------|------|------------|------------|---------------|
| node1 | Master | 10.0.1.1 | 6379 | 26379 |
| node2 | Replica | 10.0.1.2 | 6379 | 26379 |
| node3 | Replica | 10.0.1.3 | 6379 | 26379 |

### Failover Behavior

- Sentinel quorum: 2 (majority of 3)
- Down-after-milliseconds: 5000 (5 seconds)
- Failover timeout: 60000 (60 seconds)
- Automatic failover when master is unreachable

### Documentation

- [Architecture Details](./architecture/README.md)
- [Installation Guide](./docs/installation.md)
- [Operations Guide](./docs/operations.md)
- [Troubleshooting](./docs/troubleshooting.md)

### File Index

```
redis-cluster-deployment/
├── README.md                           # This file
├── architecture/
│   └── README.md                       # Detailed architecture
├── configs/
│   ├── redis/
│   │   ├── redis-common.conf           # Common Redis config
│   │   ├── redis-master.conf           # Master-specific config
│   │   └── redis-replica.conf          # Replica-specific config
│   └── sentinel/
│       └── sentinel.conf               # Sentinel configuration
├── scripts/
│   ├── 01-setup-user.sh                # Create redis user
│   ├── 02-install-redis.sh             # Install Redis binaries
│   ├── 03-configure-node.sh            # Configure node
│   ├── 04-start-services.sh            # Start Redis & Sentinel
│   ├── 05-stop-services.sh             # Stop services
│   ├── health-check.sh                 # Health check script
│   ├── failover.sh                     # Manual failover
│   └── backup.sh                       # Backup script
├── systemd/
│   ├── redis.service                   # Redis systemd unit
│   └── redis-sentinel.service          # Sentinel systemd unit
├── docs/
│   ├── installation.md                 # Installation guide
│   ├── operations.md                   # Operations guide
│   └── troubleshooting.md              # Troubleshooting guide
└── templates/
    └── redis-env.sh                    # Environment template
```
