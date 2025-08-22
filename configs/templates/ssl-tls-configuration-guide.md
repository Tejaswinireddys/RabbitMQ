# RabbitMQ 4.1.x SSL/TLS Configuration Guide

## Overview
This guide provides comprehensive SSL/TLS configuration for RabbitMQ 4.1.x clusters, covering certificate generation, configuration, and best practices for secure communication.

## SSL/TLS Architecture

### Communication Channels
1. **Client to RabbitMQ** - AMQP over SSL (port 5671)
2. **Management Interface** - HTTPS (port 15671)
3. **Inter-node Communication** - Erlang distribution over SSL
4. **Plugin Communication** - Various plugins over SSL

## Certificate Requirements

### Certificate Types Needed
1. **CA Certificate** - Certificate Authority for signing
2. **Server Certificates** - One per RabbitMQ node
3. **Client Certificates** - For client authentication (optional)
4. **Peer Certificates** - For inter-node communication

### Certificate Attributes
- **Key Size**: 2048-bit RSA minimum, 4096-bit recommended
- **Hash Algorithm**: SHA-256 or higher
- **Validity Period**: 1-2 years maximum
- **Subject Alternative Names**: Include all node hostnames/IPs

## Certificate Generation

### Method 1: Using OpenSSL (Manual)

#### Step 1: Create CA Certificate
```bash
#!/bin/bash
# File: create-ca-certificate.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
CA_DIR="$CERT_DIR/ca"
DAYS_VALID=365

echo "=== Creating RabbitMQ CA Certificate ==="

# Create certificate directories
sudo mkdir -p $CA_DIR
sudo mkdir -p $CERT_DIR/{server,client}

# Create CA private key
sudo openssl genrsa -out $CA_DIR/ca-key.pem 4096

# Create CA certificate
sudo openssl req -new -x509 -days $DAYS_VALID -key $CA_DIR/ca-key.pem -out $CA_DIR/ca-cert.pem \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT Department/CN=RabbitMQ-CA"

echo "CA certificate created: $CA_DIR/ca-cert.pem"
```

#### Step 2: Create Server Certificates
```bash
#!/bin/bash
# File: create-server-certificates.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
CA_DIR="$CERT_DIR/ca"
SERVER_DIR="$CERT_DIR/server"
DAYS_VALID=365

# Get node information
read -p "Enter number of nodes: " NODE_COUNT
declare -a NODE_HOSTNAMES
declare -a NODE_IPS

for ((i=1; i<=NODE_COUNT; i++)); do
    read -p "Enter hostname for node $i: " hostname
    read -p "Enter IP address for node $i: " ip
    NODE_HOSTNAMES[$i]=$hostname
    NODE_IPS[$i]=$ip
done

echo "=== Creating Server Certificates ==="

for ((i=1; i<=NODE_COUNT; i++)); do
    NODE_NAME="${NODE_HOSTNAMES[$i]}"
    NODE_IP="${NODE_IPS[$i]}"
    
    echo "Creating certificate for node: $NODE_NAME ($NODE_IP)"
    
    # Create server private key
    sudo openssl genrsa -out $SERVER_DIR/$NODE_NAME-key.pem 4096
    
    # Create certificate signing request
    sudo openssl req -new -key $SERVER_DIR/$NODE_NAME-key.pem -out $SERVER_DIR/$NODE_NAME.csr \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=IT Department/CN=$NODE_NAME"
    
    # Create certificate extensions
    sudo tee $SERVER_DIR/$NODE_NAME.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $NODE_NAME
DNS.2 = localhost
IP.1 = $NODE_IP
IP.2 = 127.0.0.1
EOF
    
    # Sign the certificate
    sudo openssl x509 -req -in $SERVER_DIR/$NODE_NAME.csr -CA $CA_DIR/ca-cert.pem \
        -CAkey $CA_DIR/ca-key.pem -CAcreateserial -out $SERVER_DIR/$NODE_NAME-cert.pem \
        -days $DAYS_VALID -extensions v3_req -extfile $SERVER_DIR/$NODE_NAME.ext
    
    # Clean up CSR and extension files
    sudo rm $SERVER_DIR/$NODE_NAME.csr $SERVER_DIR/$NODE_NAME.ext
    
    echo "Server certificate created for $NODE_NAME"
done

echo "All server certificates created in: $SERVER_DIR"
```

#### Step 3: Create Client Certificates (Optional)
```bash
#!/bin/bash
# File: create-client-certificates.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
CA_DIR="$CERT_DIR/ca"
CLIENT_DIR="$CERT_DIR/client"
DAYS_VALID=365

read -p "Enter client name: " CLIENT_NAME

echo "=== Creating Client Certificate for $CLIENT_NAME ==="

# Create client private key
sudo openssl genrsa -out $CLIENT_DIR/$CLIENT_NAME-key.pem 4096

# Create certificate signing request
sudo openssl req -new -key $CLIENT_DIR/$CLIENT_NAME-key.pem -out $CLIENT_DIR/$CLIENT_NAME.csr \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT Department/CN=$CLIENT_NAME"

# Sign the certificate
sudo openssl x509 -req -in $CLIENT_DIR/$CLIENT_NAME.csr -CA $CA_DIR/ca-cert.pem \
    -CAkey $CA_DIR/ca-key.pem -CAcreateserial -out $CLIENT_DIR/$CLIENT_NAME-cert.pem \
    -days $DAYS_VALID

# Clean up CSR
sudo rm $CLIENT_DIR/$CLIENT_NAME.csr

echo "Client certificate created for $CLIENT_NAME"
```

### Method 2: Using tls-gen Tool (Recommended)
```bash
#!/bin/bash
# File: setup-tls-gen.sh

set -e

echo "=== Setting up TLS certificates using tls-gen ==="

# Clone tls-gen repository
git clone https://github.com/rabbitmq/tls-gen.git /tmp/tls-gen
cd /tmp/tls-gen/basic

# Read cluster configuration
read -p "Enter number of nodes: " NODE_COUNT
declare -a NODE_NAMES

for ((i=1; i<=NODE_COUNT; i++)); do
    read -p "Enter hostname for node $i: " hostname
    NODE_NAMES[$i]=$hostname
done

# Generate certificates
make PASSWORD="" CN=rabbitmq-ca

# Create server certificates for each node
for ((i=1; i<=NODE_COUNT; i++)); do
    NODE_NAME="${NODE_NAMES[$i]}"
    make PASSWORD="" CN=$NODE_NAME server
    
    # Copy certificates to RabbitMQ SSL directory
    sudo mkdir -p /etc/rabbitmq/ssl/$NODE_NAME
    sudo cp result/ca_certificate.pem /etc/rabbitmq/ssl/$NODE_NAME/
    sudo cp result/server_*certificate.pem /etc/rabbitmq/ssl/$NODE_NAME/
    sudo cp result/server_*key.pem /etc/rabbitmq/ssl/$NODE_NAME/
done

echo "TLS certificates generated for all nodes"
```

## RabbitMQ SSL Configuration

### Dynamic SSL Configuration Template
```bash
#!/bin/bash
# File: generate-ssl-config.sh

set -e

CERT_BASE_DIR="/etc/rabbitmq/ssl"
NODE_NAME=$(hostname)

echo "=== Generating SSL Configuration for $NODE_NAME ==="

# Generate SSL configuration for rabbitmq.conf
cat >> /etc/rabbitmq/rabbitmq.conf << EOF

# SSL/TLS Configuration
listeners.ssl.default = 5671
listeners.tcp = none

# SSL Options
ssl_options.cacertfile = $CERT_BASE_DIR/ca/ca-cert.pem
ssl_options.certfile = $CERT_BASE_DIR/server/$NODE_NAME-cert.pem
ssl_options.keyfile = $CERT_BASE_DIR/server/$NODE_NAME-key.pem

# SSL Security Settings
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = false
ssl_options.client_renegotiation = false
ssl_options.secure_renegotiate = true
ssl_options.honor_ecc_order = true
ssl_options.honor_cipher_order = true

# TLS Versions
ssl_options.versions.1 = tlsv1.2
ssl_options.versions.2 = tlsv1.3

# Cipher Suites (Strong Security)
ssl_options.ciphers.1 = ECDHE-ECDSA-AES256-GCM-SHA384
ssl_options.ciphers.2 = ECDHE-RSA-AES256-GCM-SHA384
ssl_options.ciphers.3 = ECDHE-ECDSA-CHACHA20-POLY1305
ssl_options.ciphers.4 = ECDHE-RSA-CHACHA20-POLY1305
ssl_options.ciphers.5 = ECDHE-ECDSA-AES128-GCM-SHA256
ssl_options.ciphers.6 = ECDHE-RSA-AES128-GCM-SHA256

# Management Interface SSL
management.ssl.port = 15671
management.ssl.cacertfile = $CERT_BASE_DIR/ca/ca-cert.pem
management.ssl.certfile = $CERT_BASE_DIR/server/$NODE_NAME-cert.pem
management.ssl.keyfile = $CERT_BASE_DIR/server/$NODE_NAME-key.pem
management.ssl.honor_cipher_order = true
management.ssl.honor_ecc_order = true
management.ssl.client_renegotiation = false
management.ssl.secure_renegotiate = true
management.ssl.versions.1 = tlsv1.2
management.ssl.versions.2 = tlsv1.3

# Inter-node SSL (Erlang Distribution)
cluster_formation.peer_discovery_backend = classic_config
EOF

echo "SSL configuration added to rabbitmq.conf"
```

### Advanced SSL Configuration (advanced.config)
```erlang
#!/bin/bash
# File: generate-advanced-ssl-config.sh

CERT_BASE_DIR="/etc/rabbitmq/ssl"
NODE_NAME=$(hostname)

cat > /etc/rabbitmq/advanced.config << EOF
[
  {rabbit, [
    %% SSL configuration
    {ssl_listeners, [5671]},
    {tcp_listeners, []},
    
    %% SSL options
    {ssl_options, [
      {cacertfile, "$CERT_BASE_DIR/ca/ca-cert.pem"},
      {certfile, "$CERT_BASE_DIR/server/$NODE_NAME-cert.pem"},
      {keyfile, "$CERT_BASE_DIR/server/$NODE_NAME-key.pem"},
      {verify, verify_peer},
      {fail_if_no_peer_cert, false},
      {client_renegotiation, false},
      {secure_renegotiate, true},
      {honor_ecc_order, true},
      {honor_cipher_order, true},
      {versions, ['tlsv1.2', 'tlsv1.3']},
      {ciphers, [
        "ECDHE-ECDSA-AES256-GCM-SHA384",
        "ECDHE-RSA-AES256-GCM-SHA384",
        "ECDHE-ECDSA-CHACHA20-POLY1305",
        "ECDHE-RSA-CHACHA20-POLY1305",
        "ECDHE-ECDSA-AES128-GCM-SHA256",
        "ECDHE-RSA-AES128-GCM-SHA256"
      ]}
    ]}
  ]},
  
  {rabbitmq_management, [
    %% Management SSL configuration
    {listener, [
      {port, 15671},
      {ssl, true},
      {ssl_opts, [
        {cacertfile, "$CERT_BASE_DIR/ca/ca-cert.pem"},
        {certfile, "$CERT_BASE_DIR/server/$NODE_NAME-cert.pem"},
        {keyfile, "$CERT_BASE_DIR/server/$NODE_NAME-key.pem"},
        {verify, verify_none},
        {versions, ['tlsv1.2', 'tlsv1.3']}
      ]}
    ]}
  ]},
  
  {kernel, [
    %% Inter-node SSL (Erlang distribution)
    {inet_dist_use_interface, {0,0,0,0}},
    {inet_dist_listen_min, 25672},
    {inet_dist_listen_max, 25672}
  ]}
].
EOF

echo "Advanced SSL configuration created"
```

## Inter-node SSL Configuration

### Erlang Distribution SSL Setup
```bash
#!/bin/bash
# File: setup-inter-node-ssl.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
NODE_NAME=$(hostname)

echo "=== Setting up Inter-node SSL Communication ==="

# Create inet_tls.conf for Erlang distribution
sudo tee /etc/rabbitmq/inet_tls.conf << EOF
[
  {server, [
    {certfile, "$CERT_DIR/server/$NODE_NAME-cert.pem"},
    {keyfile, "$CERT_DIR/server/$NODE_NAME-key.pem"},
    {cacertfile, "$CERT_DIR/ca/ca-cert.pem"},
    {verify, verify_peer},
    {fail_if_no_peer_cert, true},
    {secure_renegotiate, true},
    {versions, ['tlsv1.2', 'tlsv1.3']}
  ]},
  {client, [
    {certfile, "$CERT_DIR/server/$NODE_NAME-cert.pem"},
    {keyfile, "$CERT_DIR/server/$NODE_NAME-key.pem"},
    {cacertfile, "$CERT_DIR/ca/ca-cert.pem"},
    {verify, verify_peer},
    {secure_renegotiate, true},
    {versions, ['tlsv1.2', 'tlsv1.3']}
  ]}
].
EOF

# Set environment variable for Erlang distribution
echo 'export ERL_FLAGS="-proto_dist inet_tls -ssl_dist_optfile /etc/rabbitmq/inet_tls.conf"' | \
    sudo tee -a /etc/default/rabbitmq-server

echo "Inter-node SSL configuration completed"
```

## Certificate Management

### Certificate Rotation Script
```bash
#!/bin/bash
# File: rotate-certificates.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
BACKUP_DIR="/backup/rabbitmq-certs"
NODE_NAME=$(hostname)

echo "=== Certificate Rotation Process ==="

# Create backup
sudo mkdir -p $BACKUP_DIR/$(date +%Y%m%d)
sudo cp -r $CERT_DIR/* $BACKUP_DIR/$(date +%Y%m%d)/

# Generate new certificates (reuse certificate generation scripts)
echo "Generating new certificates..."
# Call certificate generation scripts here

# Test new certificates
echo "Testing new certificates..."
sudo openssl x509 -in $CERT_DIR/server/$NODE_NAME-cert.pem -text -noout

# Reload RabbitMQ configuration
echo "Reloading RabbitMQ configuration..."
sudo systemctl reload rabbitmq-server

# Verify SSL connectivity
echo "Verifying SSL connectivity..."
openssl s_client -connect localhost:5671 -CAfile $CERT_DIR/ca/ca-cert.pem

echo "Certificate rotation completed successfully"
```

### Certificate Monitoring Script
```bash
#!/bin/bash
# File: monitor-certificates.sh

CERT_DIR="/etc/rabbitmq/ssl"
WARNING_DAYS=30
CRITICAL_DAYS=7

echo "=== Certificate Expiration Monitoring ==="

check_cert_expiry() {
    local cert_file=$1
    local cert_name=$2
    
    if [ -f "$cert_file" ]; then
        expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
        expiry_epoch=$(date -d "$expiry_date" +%s)
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        echo "Certificate: $cert_name"
        echo "  Expires: $expiry_date"
        echo "  Days until expiry: $days_until_expiry"
        
        if [ $days_until_expiry -le $CRITICAL_DAYS ]; then
            echo "  Status: CRITICAL - Certificate expires in $days_until_expiry days!"
        elif [ $days_until_expiry -le $WARNING_DAYS ]; then
            echo "  Status: WARNING - Certificate expires in $days_until_expiry days"
        else
            echo "  Status: OK"
        fi
        echo
    else
        echo "Certificate not found: $cert_file"
    fi
}

# Check CA certificate
check_cert_expiry "$CERT_DIR/ca/ca-cert.pem" "CA Certificate"

# Check server certificate
check_cert_expiry "$CERT_DIR/server/$(hostname)-cert.pem" "Server Certificate"

# Check client certificates
if [ -d "$CERT_DIR/client" ]; then
    for client_cert in $CERT_DIR/client/*-cert.pem; do
        if [ -f "$client_cert" ]; then
            client_name=$(basename "$client_cert" -cert.pem)
            check_cert_expiry "$client_cert" "Client Certificate ($client_name)"
        fi
    done
fi
```

## SSL Testing and Validation

### SSL Connectivity Test Script
```bash
#!/bin/bash
# File: test-ssl-connectivity.sh

set -e

CERT_DIR="/etc/rabbitmq/ssl"
NODE_NAME=$(hostname)

echo "=== SSL Connectivity Testing ==="

# Test 1: OpenSSL s_client
echo "1. Testing SSL connection with OpenSSL..."
timeout 5 openssl s_client -connect localhost:5671 -CAfile $CERT_DIR/ca/ca-cert.pem \
    -cert $CERT_DIR/client/test-cert.pem -key $CERT_DIR/client/test-key.pem 2>/dev/null \
    && echo "✓ SSL connection successful" || echo "✗ SSL connection failed"

# Test 2: Management interface HTTPS
echo "2. Testing Management interface HTTPS..."
curl -k --cacert $CERT_DIR/ca/ca-cert.pem https://localhost:15671/api/overview \
    -u admin:admin123 >/dev/null 2>&1 \
    && echo "✓ Management HTTPS successful" || echo "✗ Management HTTPS failed"

# Test 3: Certificate validation
echo "3. Validating certificates..."
openssl verify -CAfile $CERT_DIR/ca/ca-cert.pem $CERT_DIR/server/$NODE_NAME-cert.pem \
    && echo "✓ Server certificate valid" || echo "✗ Server certificate invalid"

# Test 4: Cipher suite testing
echo "4. Testing cipher suites..."
nmap --script ssl-enum-ciphers -p 5671 localhost 2>/dev/null | grep -A 20 "TLS" \
    && echo "✓ Cipher suite information retrieved" || echo "✗ Cipher suite test failed"

# Test 5: Protocol version testing
echo "5. Testing TLS versions..."
for version in tls1_2 tls1_3; do
    openssl s_client -connect localhost:5671 -$version -CAfile $CERT_DIR/ca/ca-cert.pem \
        </dev/null >/dev/null 2>&1 \
        && echo "✓ $version supported" || echo "✗ $version not supported"
done

echo "SSL testing completed"
```

## Client Configuration Examples

### Java Client SSL Configuration
```java
// Java SSL configuration example
import com.rabbitmq.client.ConnectionFactory;
import com.rabbitmq.client.Connection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.TrustManagerFactory;

public class RabbitMQSSLClient {
    public static void main(String[] args) throws Exception {
        ConnectionFactory factory = new ConnectionFactory();
        factory.setHost("rabbitmq-server");
        factory.setPort(5671);
        factory.setUsername("teja");
        factory.setPassword("Teja@2024");
        
        // SSL Configuration
        SSLContext sslContext = SSLContext.getInstance("TLSv1.2");
        
        // Load trust store (CA certificate)
        TrustManagerFactory tmf = TrustManagerFactory.getInstance("SunX509");
        KeyStore trustStore = KeyStore.getInstance("JKS");
        trustStore.load(new FileInputStream("/path/to/truststore.jks"), "password".toCharArray());
        tmf.init(trustStore);
        
        // Load key store (client certificate)
        KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        keyStore.load(new FileInputStream("/path/to/client.p12"), "password".toCharArray());
        kmf.init(keyStore, "password".toCharArray());
        
        sslContext.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
        factory.useSslProtocol(sslContext);
        
        Connection connection = factory.newConnection();
        System.out.println("SSL connection established successfully!");
    }
}
```

### Python Client SSL Configuration
```python
#!/usr/bin/env python3
# Python SSL configuration example

import pika
import ssl

# SSL context configuration
ssl_context = ssl.create_default_context(cafile="/etc/rabbitmq/ssl/ca/ca-cert.pem")
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_REQUIRED

# Client certificate (optional)
ssl_context.load_cert_chain(
    certfile="/etc/rabbitmq/ssl/client/client-cert.pem",
    keyfile="/etc/rabbitmq/ssl/client/client-key.pem"
)

# Connection parameters
credentials = pika.PlainCredentials('teja', 'Teja@2024')
ssl_options = pika.SSLOptions(ssl_context, "rabbitmq-server")

parameters = pika.ConnectionParameters(
    host='rabbitmq-server',
    port=5671,
    virtual_host='/',
    credentials=credentials,
    ssl_options=ssl_options
)

# Establish connection
connection = pika.BlockingConnection(parameters)
print("SSL connection established successfully!")
```

### Node.js Client SSL Configuration
```javascript
// Node.js SSL configuration example
const amqp = require('amqplib');
const fs = require('fs');

async function connectWithSSL() {
    const ssl_options = {
        ca: [fs.readFileSync('/etc/rabbitmq/ssl/ca/ca-cert.pem')],
        cert: fs.readFileSync('/etc/rabbitmq/ssl/client/client-cert.pem'),
        key: fs.readFileSync('/etc/rabbitmq/ssl/client/client-key.pem'),
        rejectUnauthorized: true,
        servername: 'rabbitmq-server'
    };
    
    const connection = await amqp.connect('amqps://teja:Teja@2024@rabbitmq-server:5671/', {
        ssl: ssl_options
    });
    
    console.log('SSL connection established successfully!');
    return connection;
}

connectWithSSL().catch(console.error);
```

## Security Best Practices

### Certificate Security
1. **Private Key Protection**
   - Store private keys with 600 permissions
   - Use hardware security modules (HSM) for CA keys
   - Rotate certificates regularly (annually)

2. **Certificate Validation**
   - Always verify peer certificates
   - Use certificate pinning for critical applications
   - Monitor certificate expiration

3. **Cipher Suite Selection**
   - Disable weak ciphers (RC4, DES, 3DES)
   - Prefer AEAD ciphers (GCM, ChaCha20-Poly1305)
   - Enable forward secrecy (ECDHE, DHE)

### Network Security
1. **Firewall Configuration**
   - Allow only SSL/TLS ports (5671, 15671)
   - Block plain text ports (5672, 15672)
   - Restrict access by source IP

2. **Network Segmentation**
   - Isolate RabbitMQ cluster in dedicated VLAN
   - Use bastion hosts for administrative access
   - Implement network intrusion detection

## Troubleshooting SSL Issues

### Common SSL Problems
1. **Certificate Chain Issues**
```bash
# Verify certificate chain
openssl verify -CAfile ca-cert.pem -untrusted intermediate-cert.pem server-cert.pem
```

2. **Hostname Verification Failures**
```bash
# Check certificate subject and SAN
openssl x509 -in server-cert.pem -text -noout | grep -A 5 "Subject:"
openssl x509 -in server-cert.pem -text -noout | grep -A 5 "Subject Alternative Name"
```

3. **Permission Issues**
```bash
# Fix certificate permissions
sudo chown -R rabbitmq:rabbitmq /etc/rabbitmq/ssl/
sudo chmod 600 /etc/rabbitmq/ssl/server/*-key.pem
sudo chmod 644 /etc/rabbitmq/ssl/server/*-cert.pem
sudo chmod 644 /etc/rabbitmq/ssl/ca/ca-cert.pem
```

4. **SSL Handshake Failures**
```bash
# Debug SSL handshake
openssl s_client -connect hostname:5671 -debug -msg
```

This comprehensive SSL/TLS configuration guide ensures secure, encrypted communication for RabbitMQ clusters while maintaining performance and operational simplicity.