# RabbitMQ Three-Node Cluster & Horizontal Scaling - Visio Architecture Guide

## 🎯 Overview

This document provides detailed guidance for creating a comprehensive Visio architecture diagram for RabbitMQ three-node cluster with horizontal scaling capabilities, including meaningful icons, data flows, and component relationships.

## 📋 Diagram Components & Icons

### 1. Infrastructure Layer Components

#### 1.1 Load Balancer Tier
```
Component: External Load Balancer
Visio Icon: Network Equipment > Load Balancer
Description: HAProxy/NGINX/AWS ALB
Data Flow: Bidirectional arrows to RabbitMQ nodes
Color Scheme: Blue (#0066CC)
```

#### 1.2 RabbitMQ Cluster Nodes
```
Component: RabbitMQ Node 1 (Primary)
Visio Icon: Servers > Application Server
Description: rabbit@node1
Data Flow: Inter-node communication, client connections
Color Scheme: Green (#00AA44)

Component: RabbitMQ Node 2 (Secondary)
Visio Icon: Servers > Application Server  
Description: rabbit@node2
Data Flow: Inter-node communication, client connections
Color Scheme: Green (#00AA44)

Component: RabbitMQ Node 3 (Secondary)
Visio Icon: Servers > Application Server
Description: rabbit@node3
Data Flow: Inter-node communication, client connections
Color Scheme: Green (#00AA44)
```

#### 1.3 Storage Layer
```
Component: Shared Storage/NFS
Visio Icon: Storage > Database Server
Description: Persistent message storage
Data Flow: Read/Write operations from all nodes
Color Scheme: Orange (#FF8800)

Component: Local Node Storage
Visio Icon: Storage > Hard Disk
Description: Mnesia database per node
Data Flow: Node-specific data operations
Color Scheme: Orange (#FF8800)
```

### 2. Application Layer Components

#### 2.1 Producer Applications
```
Component: Microservice Producer 1
Visio Icon: Cloud > Azure Service
Description: Order Processing Service
Data Flow: Publish messages to exchanges
Color Scheme: Purple (#8A2BE2)

Component: Microservice Producer 2
Visio Icon: Cloud > Azure Service
Description: Payment Processing Service
Data Flow: Publish messages to exchanges
Color Scheme: Purple (#8A2BE2)

Component: Batch Job Producer
Visio Icon: Process > Scheduled Task
Description: ETL/Data Processing Jobs
Data Flow: Bulk message publishing
Color Scheme: Purple (#8A2BE2)
```

#### 2.2 Consumer Applications
```
Component: Consumer Service 1
Visio Icon: Cloud > Azure Function
Description: Email Notification Service
Data Flow: Consume messages from queues
Color Scheme: Teal (#008B8B)

Component: Consumer Service 2
Visio Icon: Cloud > Azure Function
Description: Inventory Update Service
Data Flow: Consume messages from queues
Color Scheme: Teal (#008B8B)

Component: Consumer Service 3
Visio Icon: Cloud > Azure Function
Description: Analytics Processing Service
Data Flow: Consume messages from queues
Color Scheme: Teal (#008B8B)
```

### 3. Monitoring & Management Layer

#### 3.1 Monitoring Components
```
Component: Prometheus Server
Visio Icon: Monitoring > Dashboard
Description: Metrics collection and storage
Data Flow: Scrape metrics from RabbitMQ nodes
Color Scheme: Red (#DC143C)

Component: Grafana Dashboard
Visio Icon: Monitoring > Analytics
Description: Visualization and alerting
Data Flow: Query metrics from Prometheus
Color Scheme: Red (#DC143C)

Component: RabbitMQ Management UI
Visio Icon: Web > Web Application
Description: Native management interface
Data Flow: Direct connection to cluster nodes
Color Scheme: Yellow (#FFD700)
```

#### 3.2 Security Components
```
Component: Firewall/Security Groups
Visio Icon: Security > Firewall
Description: Network security
Data Flow: Filter incoming/outgoing traffic
Color Scheme: Gray (#696969)

Component: Certificate Authority
Visio Icon: Security > Certificate
Description: TLS/SSL certificates
Data Flow: Secure communication setup
Color Scheme: Gray (#696969)
```

### 4. Horizontal Scaling Components

#### 4.1 Auto-Scaling Group
```
Component: Container Orchestration (K8s)
Visio Icon: Cloud > Container
Description: Kubernetes/Docker Swarm
Data Flow: Deploy/scale RabbitMQ instances
Color Scheme: Navy (#000080)

Component: Additional RabbitMQ Nodes
Visio Icon: Servers > Server (dashed outline)
Description: rabbit@node4, rabbit@node5...
Data Flow: Dynamic cluster joining
Color Scheme: Light Green (#90EE90)
```

---

## 🎨 Detailed Visio Diagram Layout

### Layout Structure (Top to Bottom):
```
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL CLIENTS LAYER                      │
├─────────────────────────────────────────────────────────────────┤
│                    LOAD BALANCER LAYER                         │
├─────────────────────────────────────────────────────────────────┤
│                    APPLICATION LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                    RABBITMQ CLUSTER LAYER                      │
├─────────────────────────────────────────────────────────────────┤
│                    STORAGE LAYER                               │
├─────────────────────────────────────────────────────────────────┤
│                    MONITORING & MANAGEMENT LAYER               │
└─────────────────────────────────────────────────────────────────┘
```

### Specific Component Positioning:

#### Layer 1: External Clients (Top)
```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Web Apps   │    │ Mobile Apps  │    │ Third-Party  │
│     📱       │    │     📱       │    │   Services   │
└──────────────┘    └──────────────┘    └──────────────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                           │
```

#### Layer 2: Load Balancer
```
                    ┌──────────────┐
                    │ Load Balancer│
                    │    ⚖️        │
                    │  HAProxy/    │
                    │   NGINX      │
                    └──────────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
```

#### Layer 3: Application Layer
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Producers   │    │ Load Balancer│    │ Consumers   │
│    📤       │    │     ⚖️       │    │    📥       │
│Service-A    │    │             │    │Service-X    │
│Service-B    │    │             │    │Service-Y    │
│Service-C    │    │             │    │Service-Z    │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
```

#### Layer 4: RabbitMQ Cluster (Core)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│RabbitMQ     │◄──►│RabbitMQ     │◄──►│RabbitMQ     │
│Node 1       │    │Node 2       │    │Node 3       │
│🐰 Primary   │    │🐰 Secondary │    │🐰 Secondary │
│Port: 5672   │    │Port: 5672   │    │Port: 5672   │
│Mgmt: 15672  │    │Mgmt: 15672  │    │Mgmt: 15672  │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
```

#### Layer 5: Storage Layer
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│Local Storage│    │Shared Storage│    │Backup       │
│💾 Mnesia    │    │💾 NFS/EBS   │    │💾 S3/Blob   │
│Node-specific│    │Persistent   │    │Archives     │
└─────────────┘    └─────────────┘    └─────────────┘
```

#### Layer 6: Monitoring & Management
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│Prometheus   │    │Grafana      │    │Management   │
│📊 Metrics   │    │📈 Dashboard │    │🖥️ Web UI    │
│Collection   │    │Alerting     │    │Admin Portal │
└─────────────┘    └─────────────┘    └─────────────┘
```

---

## 🔄 Data Flow Arrows & Labels

### Primary Data Flows:

#### 1. Message Publishing Flow
```
[Producer] ──AMQP Publish──► [Load Balancer] ──Round Robin──► [RabbitMQ Node]
                                    │
                                    ▼
[Exchange] ──Route by Key──► [Queue] ──Replicate──► [Other Nodes]
```

#### 2. Message Consumption Flow
```
[Consumer] ◄──AMQP Pull──── [Load Balancer] ◄──Balance Load──── [RabbitMQ Node]
                                    ▲
                                    │
[Queue] ──Deliver Message──► [Consumer Connection] ──ACK/NACK──► [Queue]
```

#### 3. Inter-Node Communication
```
[Node 1] ◄──Cluster Heartbeat──► [Node 2] ◄──Cluster Heartbeat──► [Node 3]
    │            25672                │            25672                │
    └──────────Quorum Consensus──────┼──────────Quorum Consensus──────┘
                                    │
[Mnesia Sync] ◄──Database Replication──► [Mnesia Sync]
```

#### 4. Monitoring Data Flow
```
[RabbitMQ Nodes] ──Expose Metrics──► [Prometheus] ──Query API──► [Grafana]
       │                                    │                        │
       └──Management API──► [Management UI] │                        ▼
                                           │              [Alert Manager]
                                           ▼                        │
                              [Health Checks] ◄──Alerts──────────────┘
```

#### 5. Horizontal Scaling Flow
```
[Auto Scaler] ──Monitor Load──► [Metrics] ──Trigger Scale──► [Orchestrator]
      │                                                            │
      ▼                                                            ▼
[New Node] ──Join Cluster──► [Existing Cluster] ──Balance Load──► [Load Balancer]
```

---

## 🎨 Visio Stencils & Icon Recommendations

### Required Stencil Sets:
1. **Basic Network Diagram**
2. **Server and Storage**
3. **Cloud and Enterprise**
4. **Monitoring and Management**
5. **Security**
6. **Containers and Orchestration**

### Specific Icon Mappings:

#### Network Components:
- Load Balancer: "3D Networking > Load balancer"
- Firewall: "Security > Firewall"
- Router: "Basic Network Shapes > Router"

#### Server Components:
- RabbitMQ Nodes: "Servers > Application server"
- Database Storage: "Servers > Database server"
- Virtual Machines: "Servers > Virtual server"

#### Application Components:
- Microservices: "Cloud > Service"
- Web Applications: "Web > Web server"
- Mobile Apps: "Devices > Mobile device"

#### Monitoring Components:
- Metrics Server: "Monitoring > Server monitor"
- Dashboard: "Monitoring > Dashboard"
- Alerts: "Monitoring > Alert"

---

## 📐 Detailed Drawing Instructions

### Step 1: Create Canvas Layout
```
1. Open Visio, select "Basic Network Diagram" template
2. Set canvas size to A3 (11x17) landscape orientation
3. Create 6 horizontal swim lanes for layers
4. Add background colors for each layer:
   - External: Light Blue (#E6F3FF)
   - Load Balancer: Light Green (#E6FFE6)
   - Application: Light Purple (#F0E6FF)
   - RabbitMQ: Light Orange (#FFE6CC)
   - Storage: Light Yellow (#FFFFCC)
   - Monitoring: Light Gray (#F5F5F5)
```

### Step 2: Place Core Components
```
1. Drag RabbitMQ server icons to cluster layer
2. Position 3 nodes horizontally with equal spacing
3. Add text labels: "rabbit@node1", "rabbit@node2", "rabbit@node3"
4. Set node1 with green border (primary), others with blue border
5. Add port labels: "AMQP:5672", "Management:15672", "Cluster:25672"
```

### Step 3: Add Connection Lines
```
1. Use "Connector" tool for all data flows
2. Inter-node connections: Thick blue lines (3pt)
3. Client connections: Medium green lines (2pt)
4. Monitoring connections: Thin red lines (1pt)
5. Add arrow heads to indicate data direction
6. Label each connection with protocol/purpose
```

### Step 4: Add Load Balancer
```
1. Place load balancer icon above RabbitMQ cluster
2. Connect to all 3 RabbitMQ nodes with equal-weight lines
3. Add configuration box: "Algorithm: Round Robin"
4. Show health check connections (dashed lines)
```

### Step 5: Add Applications
```
1. Left side: Producer applications (3-4 icons)
2. Right side: Consumer applications (3-4 icons)
3. Connect producers to load balancer with "PUBLISH" labels
4. Connect consumers to load balancer with "SUBSCRIBE" labels
5. Add message flow indicators
```

### Step 6: Add Storage Components
```
1. Below each RabbitMQ node: Local storage icon
2. Center bottom: Shared storage icon
3. Connect with dashed lines for persistence
4. Add backup storage with archive arrows
```

### Step 7: Add Monitoring Stack
```
1. Right side: Prometheus server icon
2. Above Prometheus: Grafana dashboard icon
3. Connect RabbitMQ nodes to Prometheus (metrics flow)
4. Connect Prometheus to Grafana (query flow)
5. Add management UI connected to cluster
```

### Step 8: Add Horizontal Scaling
```
1. Right edge: Container orchestration icon
2. Dashed outline boxes for potential new nodes
3. Auto-scaler component with trigger arrows
4. Show scaling decision flow
```

### Step 9: Add Labels and Legend
```
1. Title: "RabbitMQ Three-Node Cluster with Horizontal Scaling"
2. Legend box with:
   - Data flow types (colors/line styles)
   - Component categories
   - Port definitions
   - Scaling triggers
3. Add performance metrics boxes
4. Include IP address ranges
```

### Step 10: Final Formatting
```
1. Align all components using Visio alignment tools
2. Apply consistent spacing (use grid snap)
3. Add drop shadows to main components
4. Use gradient fills for layer backgrounds
5. Add border around entire diagram
6. Include creation date and version info
```

---

## 🔢 Performance Metrics Annotations

### Add Text Boxes with Key Metrics:

#### Throughput Metrics:
```
┌─────────────────────────┐
│ Performance Metrics     │
├─────────────────────────┤
│ Max Messages/sec: 50K   │
│ Concurrent Connections: │
│   - Per Node: 10K       │
│   - Total Cluster: 30K  │
│ Queue Throughput: 20K/s │
│ Memory Usage: <4GB/node │
└─────────────────────────┘
```

#### Scaling Triggers:
```
┌─────────────────────────┐
│ Auto-Scale Triggers     │
├─────────────────────────┤
│ CPU > 80% for 5min      │
│ Memory > 85%            │
│ Queue Depth > 10K msgs  │
│ Connection > 8K/node    │
│ Disk Usage > 70%        │
└─────────────────────────┘
```

#### High Availability:
```
┌─────────────────────────┐
│ HA Configuration        │
├─────────────────────────┤
│ Min Nodes: 3            │
│ Quorum Size: 2          │
│ Replication Factor: 3   │
│ Failover Time: <30s     │
│ Split-Brain: Prevented  │
└─────────────────────────┘
```

---

## 🎯 Message Flow Scenarios

### Scenario 1: Normal Operation
```
Producer → Load Balancer → Node1 → Exchange → Queue → Consumer
                        ↘ Node2   ↗        ↘      ↗
                        ↘ Node3   ↗        ↘      ↗
```

### Scenario 2: Node Failure
```
Producer → Load Balancer → [Node1 DOWN] 
                        ↘ Node2 → Exchange → Queue → Consumer
                        ↘ Node3 ↗         ↘      ↗
```

### Scenario 3: High Load Scaling
```
Producer → Load Balancer → Node1 → Exchange → Queue → Consumer
                        → Node2 ↗         ↘      ↗
                        → Node3 ↗         ↘      ↗
                        → Node4 ↗         ↘      ↗ (Auto-scaled)
                        → Node5 ↗         ↘      ↗ (Auto-scaled)
```

---

## 💾 Export Specifications

### File Formats:
- Primary: `.vsdx` (Visio format)
- PDF: High resolution for documentation
- PNG: High DPI for presentations
- SVG: Scalable for web use

### Export Settings:
- Resolution: 300 DPI minimum
- Color Mode: RGB for digital, CMYK for print
- Include metadata and layer information
- Maintain vector quality for scaling

---

This comprehensive guide provides all necessary information to create a professional, detailed Visio architecture diagram for RabbitMQ three-node cluster with horizontal scaling capabilities.