# 11. Client Application Changes

## Overview

This document details the application-side changes required for the RabbitMQ migration from 3.12 to 4.1.4, including client library updates, code changes, and configuration modifications.

---

## 1. Client Library Updates

### 1.1 Recommended Versions

| Language | Library | Minimum Version | Recommended | Notes |
|----------|---------|-----------------|-------------|-------|
| Java | amqp-client | 5.18.0 | 5.22.0+ | Maven/Gradle update |
| Java | Spring AMQP | 3.0.0 | 3.2.0+ | Boot 3.x required |
| Python | pika | 1.3.0 | 1.3.2+ | pip update |
| Python | aio-pika | 9.0.0 | 9.5.0+ | Async support |
| Python | kombu | 5.3.0 | 5.4.0+ | Celery compatible |
| Node.js | amqplib | 0.10.0 | 0.10.4+ | npm update |
| .NET | RabbitMQ.Client | 6.5.0 | 7.0.0+ | NuGet update |
| Go | amqp091-go | 1.9.0 | 1.10.0+ | go mod update |
| Ruby | bunny | 2.22.0 | 2.23.0+ | gem update |
| PHP | php-amqplib | 3.5.0 | 3.7.0+ | composer update |

### 1.2 Dependency Update Examples

**Java (Maven):**
```xml
<dependency>
    <groupId>com.rabbitmq</groupId>
    <artifactId>amqp-client</artifactId>
    <version>5.22.0</version>
</dependency>
```

**Python (pip):**
```bash
pip install --upgrade pika>=1.3.2
```

**Node.js (npm):**
```bash
npm install amqplib@^0.10.4
```

**.NET (NuGet):**
```bash
dotnet add package RabbitMQ.Client --version 7.0.0
```

**Go:**
```bash
go get github.com/rabbitmq/amqp091-go@v1.10.0
```

---

## 2. Queue Declaration Changes

### 2.1 Declaring Quorum Queues

**Before (Classic Queue):**
```python
# Python - Classic queue
channel.queue_declare(queue='orders', durable=True)
```

**After (Quorum Queue):**
```python
# Python - Quorum queue
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={
        'x-queue-type': 'quorum',
        'x-quorum-initial-group-size': 3
    }
)
```

### 2.2 Language-Specific Examples

**Java:**
```java
// Before
channel.queueDeclare("orders", true, false, false, null);

// After
Map<String, Object> args = new HashMap<>();
args.put("x-queue-type", "quorum");
args.put("x-quorum-initial-group-size", 3);
args.put("x-delivery-limit", 5);
channel.queueDeclare("orders", true, false, false, args);
```

**Node.js:**
```javascript
// Before
await channel.assertQueue('orders', { durable: true });

// After
await channel.assertQueue('orders', {
    durable: true,
    arguments: {
        'x-queue-type': 'quorum',
        'x-quorum-initial-group-size': 3,
        'x-delivery-limit': 5
    }
});
```

**Go:**
```go
// Before
ch.QueueDeclare("orders", true, false, false, false, nil)

// After
args := amqp.Table{
    "x-queue-type": "quorum",
    "x-quorum-initial-group-size": 3,
    "x-delivery-limit": 5,
}
ch.QueueDeclare("orders", true, false, false, false, args)
```

**.NET:**
```csharp
// Before
channel.QueueDeclare("orders", durable: true, exclusive: false, autoDelete: false);

// After
var args = new Dictionary<string, object>
{
    { "x-queue-type", "quorum" },
    { "x-quorum-initial-group-size", 3 },
    { "x-delivery-limit", 5 }
};
channel.QueueDeclare("orders", durable: true, exclusive: false, autoDelete: false, arguments: args);
```

---

## 3. Connection Handling Changes

### 3.1 Connection Parameters

**Recommended Connection Settings:**
```python
import pika

# Optimized connection parameters for quorum queues
parameters = pika.ConnectionParameters(
    host='rabbitmq.example.com',
    port=5672,
    virtual_host='/',
    credentials=pika.PlainCredentials('user', 'password'),

    # Heartbeat - keep alive
    heartbeat=60,

    # Blocked connection timeout
    blocked_connection_timeout=300,

    # Connection attempts and retry
    connection_attempts=5,
    retry_delay=5,

    # Socket timeout
    socket_timeout=30,

    # TCP keepalive
    tcp_options={
        'TCP_KEEPIDLE': 60,
        'TCP_KEEPINTVL': 10,
        'TCP_KEEPCNT': 6
    }
)
```

### 3.2 Connection Retry Logic

**Python Example:**
```python
import pika
import time
from functools import wraps

class RabbitMQConnection:
    def __init__(self, hosts, port=5672, user='guest', password='guest'):
        self.hosts = hosts if isinstance(hosts, list) else [hosts]
        self.port = port
        self.credentials = pika.PlainCredentials(user, password)
        self.connection = None
        self.channel = None

    def connect(self, max_retries=5, retry_delay=5):
        """Connect with retry logic and host failover"""
        for attempt in range(max_retries):
            for host in self.hosts:
                try:
                    parameters = pika.ConnectionParameters(
                        host=host,
                        port=self.port,
                        credentials=self.credentials,
                        heartbeat=60,
                        connection_attempts=1,
                        retry_delay=0
                    )
                    self.connection = pika.BlockingConnection(parameters)
                    self.channel = self.connection.channel()
                    self.channel.confirm_delivery()
                    print(f"Connected to {host}")
                    return True
                except pika.exceptions.AMQPConnectionError as e:
                    print(f"Failed to connect to {host}: {e}")
                    continue

            print(f"Attempt {attempt + 1} failed, retrying in {retry_delay}s...")
            time.sleep(retry_delay)

        raise Exception("Failed to connect after all retries")

    def publish_with_retry(self, exchange, routing_key, body, properties=None, max_retries=3):
        """Publish with automatic reconnection"""
        for attempt in range(max_retries):
            try:
                if not self.connection or self.connection.is_closed:
                    self.connect()

                self.channel.basic_publish(
                    exchange=exchange,
                    routing_key=routing_key,
                    body=body,
                    properties=properties or pika.BasicProperties(delivery_mode=2),
                    mandatory=True
                )
                return True
            except (pika.exceptions.ChannelClosedByBroker,
                    pika.exceptions.ConnectionClosedByBroker) as e:
                print(f"Publish failed: {e}, reconnecting...")
                self.connection = None
                time.sleep(1)

        raise Exception("Failed to publish after all retries")
```

**Java Example:**
```java
public class RabbitMQConnection {
    private Connection connection;
    private Channel channel;
    private final List<String> hosts;
    private final int port;
    private final String username;
    private final String password;

    public RabbitMQConnection(List<String> hosts, int port, String username, String password) {
        this.hosts = hosts;
        this.port = port;
        this.username = username;
        this.password = password;
    }

    public void connect() throws Exception {
        ConnectionFactory factory = new ConnectionFactory();
        factory.setUsername(username);
        factory.setPassword(password);
        factory.setRequestedHeartbeat(60);
        factory.setConnectionTimeout(30000);
        factory.setAutomaticRecoveryEnabled(true);
        factory.setNetworkRecoveryInterval(5000);
        factory.setTopologyRecoveryEnabled(true);

        // Try each host
        for (String host : hosts) {
            try {
                factory.setHost(host);
                factory.setPort(port);
                connection = factory.newConnection();
                channel = connection.createChannel();
                channel.confirmSelect();
                System.out.println("Connected to " + host);
                return;
            } catch (Exception e) {
                System.out.println("Failed to connect to " + host + ": " + e.getMessage());
            }
        }
        throw new Exception("Failed to connect to any host");
    }

    public void publishWithRetry(String exchange, String routingKey, byte[] body, int maxRetries) throws Exception {
        for (int attempt = 0; attempt < maxRetries; attempt++) {
            try {
                if (connection == null || !connection.isOpen()) {
                    connect();
                }

                AMQP.BasicProperties props = new AMQP.BasicProperties.Builder()
                    .deliveryMode(2)
                    .build();

                channel.basicPublish(exchange, routingKey, true, props, body);
                channel.waitForConfirmsOrDie(5000);
                return;
            } catch (Exception e) {
                System.out.println("Publish failed: " + e.getMessage());
                connection = null;
                Thread.sleep(1000);
            }
        }
        throw new Exception("Failed to publish after " + maxRetries + " attempts");
    }
}
```

---

## 4. Consumer Changes

### 4.1 Handling Redelivered Messages

With quorum queues and delivery limits, consumers need to handle redelivered messages properly:

```python
def callback(ch, method, properties, body):
    try:
        # Check if this is a redelivery
        if method.redelivered:
            redelivery_count = properties.headers.get('x-delivery-count', 1) if properties.headers else 1
            print(f"Redelivery #{redelivery_count} for message")

            # If approaching delivery limit, handle specially
            if redelivery_count >= 4:  # Assuming limit is 5
                print("Near delivery limit, attempting final processing")

        # Process message
        process_message(body)

        # Acknowledge success
        ch.basic_ack(delivery_tag=method.delivery_tag)

    except TransientError as e:
        # Transient error - requeue for retry
        print(f"Transient error: {e}, requeueing")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

    except PermanentError as e:
        # Permanent error - don't requeue (will go to DLQ after limit)
        print(f"Permanent error: {e}, rejecting")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

    except Exception as e:
        # Unknown error - log and requeue
        print(f"Unknown error: {e}")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
```

### 4.2 Consumer Prefetch Tuning

```python
# Quorum queue consumer with appropriate prefetch
channel.basic_qos(prefetch_count=100)  # Adjust based on processing time

# For slow consumers
channel.basic_qos(prefetch_count=10)

# For fast consumers with low latency
channel.basic_qos(prefetch_count=250)
```

### 4.3 Single Active Consumer Pattern

```python
# Declare queue with single active consumer
channel.queue_declare(
    queue='orders',
    durable=True,
    arguments={
        'x-queue-type': 'quorum',
        'x-single-active-consumer': True  # Only one consumer active at a time
    }
)

# Consumer - will only receive messages if it's the active one
channel.basic_consume(queue='orders', on_message_callback=callback)
```

---

## 5. Publisher Confirms

### 5.1 Enabling Publisher Confirms

```python
# Python - Enable confirms
channel = connection.channel()
channel.confirm_delivery()

# Publish with mandatory flag
try:
    channel.basic_publish(
        exchange='',
        routing_key='orders',
        body=message,
        properties=pika.BasicProperties(delivery_mode=2),
        mandatory=True
    )
    print("Message confirmed")
except pika.exceptions.UnroutableError:
    print("Message could not be routed")
```

### 5.2 Handling Negative Acknowledgments

```java
// Java - Async confirms with nack handling
channel.confirmSelect();

channel.addConfirmListener(new ConfirmListener() {
    @Override
    public void handleAck(long deliveryTag, boolean multiple) {
        System.out.println("Message confirmed: " + deliveryTag);
    }

    @Override
    public void handleNack(long deliveryTag, boolean multiple) {
        System.out.println("Message rejected: " + deliveryTag);
        // Retry logic here
    }
});
```

---

## 6. Configuration Changes

### 6.1 Application Configuration Updates

**Before:**
```yaml
# application.yml
rabbitmq:
  host: rabbit-blue.example.com
  port: 5672
  username: app_user
  password: ${RABBITMQ_PASSWORD}
```

**After:**
```yaml
# application.yml
rabbitmq:
  # Multiple hosts for failover
  hosts:
    - rabbit-green-1.example.com
    - rabbit-green-2.example.com
    - rabbit-green-3.example.com
  port: 5672
  username: app_user
  password: ${RABBITMQ_PASSWORD}

  # Connection settings
  connection:
    timeout: 30000
    heartbeat: 60
    retry:
      maxAttempts: 5
      initialInterval: 1000
      multiplier: 2
      maxInterval: 10000

  # Publisher settings
  publisher:
    confirms: true
    returns: true

  # Consumer settings
  consumer:
    prefetch: 100
    acknowledgeMode: MANUAL

  # Queue defaults
  queue:
    default-type: quorum
    delivery-limit: 5
```

### 6.2 Environment Variables

```bash
# Old configuration
export RABBITMQ_HOST=rabbit-blue.example.com
export RABBITMQ_PORT=5672

# New configuration
export RABBITMQ_HOSTS=rabbit-green-1.example.com,rabbit-green-2.example.com,rabbit-green-3.example.com
export RABBITMQ_PORT=5672
export RABBITMQ_QUEUE_TYPE=quorum
export RABBITMQ_DELIVERY_LIMIT=5
export RABBITMQ_PUBLISHER_CONFIRMS=true
```

---

## 7. Migration Checklist per Application

```markdown
## Application Migration Checklist: [Application Name]

### Pre-Migration
- [ ] Current RabbitMQ client library version documented
- [ ] Queues used by this application identified
- [ ] Queue types (classic/quorum) confirmed
- [ ] Current connection configuration documented

### Dependency Updates
- [ ] Client library updated to compatible version
- [ ] Dependency conflicts resolved
- [ ] Unit tests passing with new library

### Code Changes
- [ ] Queue declarations updated for quorum queues
- [ ] Connection retry logic implemented
- [ ] Publisher confirms enabled
- [ ] Consumer ack/nack handling reviewed
- [ ] Redelivery handling implemented

### Configuration Changes
- [ ] Connection string updated (or ready to update)
- [ ] Multiple host support added
- [ ] Timeout and heartbeat configured
- [ ] Environment variables prepared

### Testing
- [ ] Tested against green cluster in staging
- [ ] Performance baseline established
- [ ] Failover tested (node restart)
- [ ] Message flow validated end-to-end

### Deployment
- [ ] Deployment plan documented
- [ ] Rollback plan documented
- [ ] Monitoring updated for new metrics
- [ ] On-call team notified

### Post-Migration
- [ ] Verify connections to green cluster
- [ ] Verify message publishing
- [ ] Verify message consuming
- [ ] Monitor error rates
- [ ] Confirm no message loss
```

---

## 8. Troubleshooting Common Issues

### 8.1 Connection Issues

| Issue | Symptom | Resolution |
|-------|---------|------------|
| Connection refused | `ECONNREFUSED` | Check host/port, firewall |
| Auth failure | 403 ACCESS_REFUSED | Verify credentials |
| Timeout | Connection timeout | Increase timeout, check network |
| Channel closed | Channel exception | Check queue/exchange exists |

### 8.2 Queue Declaration Conflicts

```python
# Error: PRECONDITION_FAILED - inequivalent arg 'x-queue-type'

# This happens when queue exists with different type
# Solution 1: Delete and recreate (if acceptable)
channel.queue_delete(queue='orders')
channel.queue_declare(queue='orders', durable=True,
                      arguments={'x-queue-type': 'quorum'})

# Solution 2: Use different queue name during migration
channel.queue_declare(queue='orders-v2', durable=True,
                      arguments={'x-queue-type': 'quorum'})
```

### 8.3 Message Processing Failures

```python
# Handling delivery limit reached
def setup_dlq():
    # Declare dead letter exchange
    channel.exchange_declare(exchange='dlx', exchange_type='direct')

    # Declare dead letter queue
    channel.queue_declare(queue='orders.dlq', durable=True)
    channel.queue_bind(queue='orders.dlq', exchange='dlx',
                       routing_key='orders.dead')

    # Main queue with DLX
    channel.queue_declare(
        queue='orders',
        durable=True,
        arguments={
            'x-queue-type': 'quorum',
            'x-delivery-limit': 5,
            'x-dead-letter-exchange': 'dlx',
            'x-dead-letter-routing-key': 'orders.dead'
        }
    )
```

---

**Next Step**: [12-post-migration-tasks.md](./12-post-migration-tasks.md)
