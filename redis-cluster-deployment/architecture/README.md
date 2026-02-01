# Redis HA Cluster Architecture

## 1. Architecture Overview

### 1.1 High-Level Design

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           APPLICATION LAYER                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                      │
│   │   App Pod 1  │    │   App Pod 2  │    │   App Pod N  │                      │
│   └──────┬───────┘    └──────┬───────┘    └──────┬───────┘                      │
│          │                   │                   │                               │
│          └───────────────────┼───────────────────┘                               │
│                              │                                                   │
│                     ┌────────▼────────┐                                         │
│                     │  Redis Client   │                                         │
│                     │  (Sentinel-     │                                         │
│                     │   aware)        │                                         │
│                     └────────┬────────┘                                         │
│                              │                                                   │
└──────────────────────────────┼──────────────────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────────────────┐
│                      REDIS CLUSTER LAYER                                         │
├──────────────────────────────┼──────────────────────────────────────────────────┤
│                              │                                                   │
│     ┌────────────────────────┼────────────────────────┐                         │
│     │                        │                        │                         │
│     ▼                        ▼                        ▼                         │
│ ┌─────────┐             ┌─────────┐             ┌─────────┐                     │
│ │Sentinel │◄───────────►│Sentinel │◄───────────►│Sentinel │                     │
│ │  :26379 │   Gossip    │  :26379 │   Gossip    │  :26379 │                     │
│ └────┬────┘             └────┬────┘             └────┬────┘                     │
│      │                       │                       │                          │
│      │ Monitors              │ Monitors              │ Monitors                 │
│      ▼                       ▼                       ▼                          │
│ ┌─────────┐             ┌─────────┐             ┌─────────┐                     │
│ │  Redis  │             │  Redis  │             │  Redis  │                     │
│ │ MASTER  │────────────►│ REPLICA │◄────────────│ REPLICA │                     │
│ │  :6379  │ Replication │  :6379  │ Replication │  :6379  │                     │
│ └─────────┘             └─────────┘             └─────────┘                     │
│                                                                                  │
│   NODE 1                  NODE 2                  NODE 3                        │
│ 10.0.1.1                10.0.1.2                10.0.1.3                        │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| Redis Master | Accept writes, serve reads, replicate to replicas |
| Redis Replica | Receive replication stream, serve reads (optional) |
| Sentinel | Monitor Redis instances, perform failover, configuration provider |

---

## 2. Node Architecture

### 2.1 Single Node Layout

```
┌─────────────────────────────────────────────────────────────────┐
│                         NODE (VM/Server)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  User: redis (UID: 6379)                                        │
│  Group: redis (GID: 6379)                                       │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    /opt/cached/                             │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │                                                             │ │
│  │  current -> redis-8.2.2/     (symlink)                     │ │
│  │                                                             │ │
│  │  redis-8.2.2/                                              │ │
│  │  ├── bin/                                                  │ │
│  │  │   ├── redis-server        (executable)                 │ │
│  │  │   ├── redis-cli           (executable)                 │ │
│  │  │   ├── redis-sentinel      (symlink -> redis-server)    │ │
│  │  │   └── redis-benchmark     (executable)                 │ │
│  │  │                                                         │ │
│  │  ├── conf/                                                 │ │
│  │  │   ├── redis.conf          (main config)                │ │
│  │  │   └── sentinel.conf       (sentinel config)            │ │
│  │  │                                                         │ │
│  │  ├── data/                                                 │ │
│  │  │   ├── dump.rdb            (RDB snapshot)               │ │
│  │  │   └── appendonly.aof      (AOF file)                   │ │
│  │  │                                                         │ │
│  │  ├── logs/                                                 │ │
│  │  │   ├── redis.log           (Redis logs)                 │ │
│  │  │   └── sentinel.log        (Sentinel logs)              │ │
│  │  │                                                         │ │
│  │  └── run/                                                  │ │
│  │      ├── redis.pid           (Redis PID)                  │ │
│  │      └── sentinel.pid        (Sentinel PID)               │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      PROCESSES                              │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │                                                             │ │
│  │  redis-server (PID: xxxx)                                  │ │
│  │  ├── Port: 6379                                            │ │
│  │  ├── User: redis                                           │ │
│  │  └── Config: /opt/cached/current/conf/redis.conf           │ │
│  │                                                             │ │
│  │  redis-sentinel (PID: yyyy)                                │ │
│  │  ├── Port: 26379                                           │ │
│  │  ├── User: redis                                           │ │
│  │  └── Config: /opt/cached/current/conf/sentinel.conf        │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Replication Architecture

### 3.1 Replication Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          REPLICATION FLOW                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│                            ┌─────────────┐                                      │
│                            │   CLIENT    │                                      │
│                            └──────┬──────┘                                      │
│                                   │ WRITE                                       │
│                                   ▼                                             │
│                         ┌─────────────────┐                                     │
│                         │     MASTER      │                                     │
│                         │   (Node 1)      │                                     │
│                         │                 │                                     │
│                         │  1. Execute cmd │                                     │
│                         │  2. Write AOF   │                                     │
│                         │  3. Propagate   │                                     │
│                         └────────┬────────┘                                     │
│                                  │                                              │
│                    ┌─────────────┴─────────────┐                               │
│                    │     Replication Stream    │                               │
│                    │     (Async by default)    │                               │
│                    ▼                           ▼                               │
│           ┌─────────────────┐         ┌─────────────────┐                      │
│           │    REPLICA 1    │         │    REPLICA 2    │                      │
│           │    (Node 2)     │         │    (Node 3)     │                      │
│           │                 │         │                 │                      │
│           │  1. Receive cmd │         │  1. Receive cmd │                      │
│           │  2. Execute     │         │  2. Execute     │                      │
│           │  3. Write AOF   │         │  3. Write AOF   │                      │
│           └─────────────────┘         └─────────────────┘                      │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Replication Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `repl-diskless-sync` | yes | Diskless replication for faster sync |
| `repl-diskless-sync-delay` | 5 | Delay before starting diskless sync |
| `repl-backlog-size` | 256mb | Replication backlog for partial resync |
| `repl-backlog-ttl` | 3600 | Backlog retention time |
| `min-replicas-to-write` | 1 | Minimum replicas for write to succeed |
| `min-replicas-max-lag` | 10 | Maximum replication lag in seconds |

---

## 4. Sentinel Architecture

### 4.1 Sentinel Cluster

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          SENTINEL CLUSTER                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐          │
│   │   SENTINEL 1    │     │   SENTINEL 2    │     │   SENTINEL 3    │          │
│   │   10.0.1.1      │     │   10.0.1.2      │     │   10.0.1.3      │          │
│   │   :26379        │     │   :26379        │     │   :26379        │          │
│   └────────┬────────┘     └────────┬────────┘     └────────┬────────┘          │
│            │                       │                       │                    │
│            │◄──────────────────────┼───────────────────────┤                    │
│            │      HELLO/SUBSCRIBE  │                       │                    │
│            │◄──────────────────────┼───────────────────────┘                    │
│            │                       │                                            │
│            │    Quorum = 2         │    Quorum = 2         │                    │
│            │    (2 of 3 agree)     │    (2 of 3 agree)     │                    │
│            │                       │                       │                    │
│            ▼                       ▼                       ▼                    │
│   ┌─────────────────────────────────────────────────────────────────┐          │
│   │                         MONITORED SET                            │          │
│   │                                                                  │          │
│   │   Master: mymaster                                              │          │
│   │   ├── redis://10.0.1.1:6379 (master)                           │          │
│   │   ├── redis://10.0.1.2:6379 (replica)                          │          │
│   │   └── redis://10.0.1.3:6379 (replica)                          │          │
│   │                                                                  │          │
│   └─────────────────────────────────────────────────────────────────┘          │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Sentinel Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `sentinel monitor` | mymaster 10.0.1.1 6379 2 | Master name, IP, port, quorum |
| `sentinel down-after-milliseconds` | 5000 | Time before marking as down |
| `sentinel failover-timeout` | 60000 | Failover timeout |
| `sentinel parallel-syncs` | 1 | Replicas to reconfigure at once |
| `sentinel auth-pass` | *** | Master password |

---

## 5. Failover Process

### 5.1 Failover Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           FAILOVER PROCESS                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  STEP 1: Detection                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Sentinel 1 ──► PING ──► Master ──► No Response (5s)                   │    │
│  │  Sentinel 1 marks Master as SDOWN (Subjectively Down)                  │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                           │                                     │
│                                           ▼                                     │
│  STEP 2: Confirmation                                                           │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Sentinel 1 ──► "Is master down?" ──► Sentinel 2, 3                    │    │
│  │  Quorum reached (2/3 agree): Master is ODOWN (Objectively Down)        │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                           │                                     │
│                                           ▼                                     │
│  STEP 3: Leader Election                                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Sentinels elect a leader to perform failover                          │    │
│  │  Leader = Sentinel with highest configuration epoch                     │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                           │                                     │
│                                           ▼                                     │
│  STEP 4: Replica Selection                                                      │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Leader selects best replica based on:                                 │    │
│  │  1. Replica priority (lower = preferred)                               │    │
│  │  2. Replication offset (higher = more data)                            │    │
│  │  3. Run ID (lexicographically smaller)                                 │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                           │                                     │
│                                           ▼                                     │
│  STEP 5: Promotion                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Leader sends REPLICAOF NO ONE to selected replica                     │    │
│  │  Selected replica becomes new master                                    │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                           │                                     │
│                                           ▼                                     │
│  STEP 6: Reconfiguration                                                        │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  Leader reconfigures remaining replicas to follow new master           │    │
│  │  Old master (when recovered) becomes replica of new master             │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Failover Timeline

```
T+0s     : Master becomes unreachable
T+5s     : Sentinel marks master as SDOWN
T+5-6s   : Sentinels agree, master marked ODOWN
T+6-7s   : Sentinel leader elected
T+7-8s   : Best replica selected
T+8-10s  : Replica promoted to master
T+10-15s : Other replicas reconfigured
T+15s    : Failover complete

Total failover time: ~15 seconds (typical)
```

---

## 6. Network Architecture

### 6.1 Port Requirements

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 6379 | TCP | Inbound | Redis client connections |
| 6379 | TCP | Internal | Replication traffic |
| 26379 | TCP | Internal | Sentinel communication |
| 26379 | TCP | Inbound | Sentinel client queries |

### 6.2 Firewall Rules

```bash
# Node 1 (10.0.1.1)
iptables -A INPUT -p tcp --dport 6379 -j ACCEPT
iptables -A INPUT -p tcp --dport 26379 -j ACCEPT
iptables -A INPUT -p tcp -s 10.0.1.2 --dport 6379 -j ACCEPT
iptables -A INPUT -p tcp -s 10.0.1.3 --dport 6379 -j ACCEPT
iptables -A INPUT -p tcp -s 10.0.1.2 --dport 26379 -j ACCEPT
iptables -A INPUT -p tcp -s 10.0.1.3 --dport 26379 -j ACCEPT
```

---

## 7. Data Persistence

### 7.1 Persistence Strategy

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        PERSISTENCE ARCHITECTURE                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌────────────────────────────────────────────────────────────────────────┐   │
│   │                            REDIS SERVER                                 │   │
│   │                                                                         │   │
│   │   ┌─────────────────────────────────────────────────────────────────┐  │   │
│   │   │                         IN-MEMORY                                │  │   │
│   │   │                         DATASET                                  │  │   │
│   │   └─────────────────────────────────────────────────────────────────┘  │   │
│   │          │                                    │                        │   │
│   │          │ Every 1s                          │ Every write            │   │
│   │          ▼                                    ▼                        │   │
│   │   ┌─────────────────┐                 ┌─────────────────┐             │   │
│   │   │   RDB Snapshot  │                 │   AOF Log       │             │   │
│   │   │   (Point-in-    │                 │   (Write-ahead  │             │   │
│   │   │    time backup) │                 │    log)         │             │   │
│   │   └─────────────────┘                 └─────────────────┘             │   │
│   │          │                                    │                        │   │
│   └──────────┼────────────────────────────────────┼────────────────────────┘   │
│              │                                    │                            │
│              ▼                                    ▼                            │
│   ┌─────────────────────────────────────────────────────────────────────────┐ │
│   │                              DISK                                        │ │
│   │                                                                          │ │
│   │   /opt/cached/current/data/                                             │ │
│   │   ├── dump.rdb         (Compact, periodic)                              │ │
│   │   └── appendonly.aof   (Every write, larger)                            │ │
│   │                                                                          │ │
│   └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Persistence Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| `appendonly` | yes | Enable AOF persistence |
| `appendfsync` | everysec | Fsync every second |
| `save 900 1` | yes | RDB: save if 1 key changed in 900s |
| `save 300 10` | yes | RDB: save if 10 keys changed in 300s |
| `save 60 10000` | yes | RDB: save if 10000 keys changed in 60s |
| `aof-rewrite-percentage` | 100 | Rewrite AOF when 100% growth |
| `aof-rewrite-min-size` | 64mb | Minimum AOF size for rewrite |

---

## 8. Memory Architecture

### 8.1 Memory Allocation

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          MEMORY ARCHITECTURE                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   Total Server RAM: 16 GB (example)                                             │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐  │
│   │   Redis maxmemory: 12 GB (75% of total)                                 │  │
│   │                                                                          │  │
│   │   ┌────────────────────────────────────────────────────────────────┐    │  │
│   │   │  Data Storage                                    ~10 GB        │    │  │
│   │   ├────────────────────────────────────────────────────────────────┤    │  │
│   │   │  Replication Buffer                              ~1 GB         │    │  │
│   │   ├────────────────────────────────────────────────────────────────┤    │  │
│   │   │  Client Output Buffers                           ~512 MB       │    │  │
│   │   ├────────────────────────────────────────────────────────────────┤    │  │
│   │   │  AOF Rewrite Buffer                              ~256 MB       │    │  │
│   │   ├────────────────────────────────────────────────────────────────┤    │  │
│   │   │  Overhead (fragmentation, etc.)                  ~256 MB       │    │  │
│   │   └────────────────────────────────────────────────────────────────┘    │  │
│   │                                                                          │  │
│   └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│   ┌─────────────────────────────────────────────────────────────────────────┐  │
│   │   OS Reserved: 4 GB (25% of total)                                      │  │
│   │   ├── System processes                                                  │  │
│   │   ├── File system cache                                                 │  │
│   │   └── Sentinel process (~50 MB)                                         │  │
│   └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Eviction Policy

| Policy | Configuration | Description |
|--------|---------------|-------------|
| Default | `volatile-lru` | Evict LRU keys with expire set |
| Alternative | `allkeys-lru` | Evict any LRU keys |
| No Eviction | `noeviction` | Return error on write when full |

---

## 9. Security Architecture

### 9.1 Security Layers

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY ARCHITECTURE                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  Layer 1: Network Security                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Bind to specific interfaces (not 0.0.0.0)                            │   │
│  │  • Firewall rules (iptables/security groups)                            │   │
│  │  • Private network (no public exposure)                                  │   │
│  │  • TLS encryption (optional but recommended)                             │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Layer 2: Authentication                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Redis AUTH password (requirepass)                                    │   │
│  │  • ACL users with specific permissions                                   │   │
│  │  • Sentinel auth-pass for master authentication                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Layer 3: Authorization (ACL)                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Per-user command restrictions                                         │   │
│  │  • Key pattern restrictions                                              │   │
│  │  • Read-only users for replicas                                          │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Layer 4: Process Security                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │  • Non-root user (redis:redis)                                          │   │
│  │  • Protected mode enabled                                                │   │
│  │  • Rename dangerous commands                                             │   │
│  │  • Disable CONFIG command for non-admin                                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Capacity Planning

### 10.1 Sizing Guidelines

| Data Size | Memory | Disk | Network | Nodes |
|-----------|--------|------|---------|-------|
| < 10 GB | 16 GB | 50 GB SSD | 1 Gbps | 3 |
| 10-50 GB | 64 GB | 200 GB SSD | 10 Gbps | 3 |
| 50-200 GB | 128 GB | 500 GB NVMe | 10 Gbps | 3 |
| > 200 GB | Consider Redis Cluster mode | | | |

### 10.2 Performance Expectations

| Metric | Value | Notes |
|--------|-------|-------|
| Operations/sec | 100,000+ | Single instance |
| Latency (p99) | < 1ms | Local network |
| Replication lag | < 100ms | Normal conditions |
| Failover time | 15-30s | Sentinel managed |
