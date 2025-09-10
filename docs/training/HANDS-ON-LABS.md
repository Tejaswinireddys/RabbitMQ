# RabbitMQ AI/ML & MLOps - Hands-on Labs

## 🎯 **Purpose of This Document**

This document provides hands-on lab exercises for freshers to gain practical experience with our RabbitMQ AI/ML system. Each lab builds upon the previous one, gradually increasing in complexity.

## 📚 **Lab Prerequisites**

### **Required Knowledge**
- Basic Linux command line
- Python programming fundamentals
- Basic understanding of Docker and Kubernetes
- Familiarity with Git version control

### **Required Tools**
- Docker Desktop
- Kubernetes (minikube or cloud cluster)
- Python 3.8+
- Git
- VS Code or similar IDE

### **Required Accounts**
- AWS account (for cloud labs)
- GitHub account
- Docker Hub account

## 🧪 **Lab 1: RabbitMQ Basics**

### **Objective**
Set up a local RabbitMQ instance and understand basic message queuing concepts.

### **Duration**
2-3 hours

### **Steps**

#### **Step 1: Install RabbitMQ**
```bash
# Using Docker
docker run -d --name rabbitmq \
  -p 5672:5672 \
  -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3.12-management

# Verify installation
docker ps
```

#### **Step 2: Access Management Interface**
1. Open browser and go to `http://localhost:15672`
2. Login with username: `admin`, password: `admin123`
3. Explore the interface:
   - Overview tab: System information
   - Connections tab: Active connections
   - Channels tab: Active channels
   - Exchanges tab: Available exchanges
   - Queues tab: Available queues

#### **Step 3: Create a Simple Producer**
```python
# producer.py
import pika
import json
import time

def send_message():
    # Connect to RabbitMQ
    connection = pika.BlockingConnection(
        pika.ConnectionParameters('localhost')
    )
    channel = connection.channel()
    
    # Declare a queue
    channel.queue_declare(queue='hello')
    
    # Send messages
    for i in range(10):
        message = {
            'id': i,
            'timestamp': time.time(),
            'data': f'Message {i}'
        }
        
        channel.basic_publish(
            exchange='',
            routing_key='hello',
            body=json.dumps(message)
        )
        print(f"Sent: {message}")
        time.sleep(1)
    
    connection.close()

if __name__ == '__main__':
    send_message()
```

#### **Step 4: Create a Simple Consumer**
```python
# consumer.py
import pika
import json

def callback(ch, method, properties, body):
    message = json.loads(body)
    print(f"Received: {message}")
    
    # Acknowledge the message
    ch.basic_ack(delivery_tag=method.delivery_tag)

def consume_messages():
    # Connect to RabbitMQ
    connection = pika.BlockingConnection(
        pika.ConnectionParameters('localhost')
    )
    channel = connection.channel()
    
    # Declare the same queue
    channel.queue_declare(queue='hello')
    
    # Set up consumer
    channel.basic_consume(
        queue='hello',
        on_message_callback=callback
    )
    
    print("Waiting for messages. To exit press CTRL+C")
    channel.start_consuming()

if __name__ == '__main__':
    try:
        consume_messages()
    except KeyboardInterrupt:
        print("Stopped consuming messages")
```

#### **Step 5: Test the System**
1. Run the consumer: `python consumer.py`
2. In another terminal, run the producer: `python producer.py`
3. Observe messages being sent and received
4. Check the management interface for queue statistics

### **Lab 1 Assessment**
- [ ] Successfully installed RabbitMQ
- [ ] Can access management interface
- [ ] Created and ran producer script
- [ ] Created and ran consumer script
- [ ] Understands basic message flow

## 🧪 **Lab 2: RabbitMQ Clustering**

### **Objective**
Set up a RabbitMQ cluster and understand high availability concepts.

### **Duration**
3-4 hours

### **Steps**

#### **Step 1: Create Cluster Nodes**
```bash
# Create first node
docker run -d --name rabbitmq1 \
  -p 5672:5672 \
  -p 15672:15672 \
  -e RABBITMQ_ERLANG_COOKIE=secret_cookie \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3.12-management

# Create second node
docker run -d --name rabbitmq2 \
  -p 5673:5672 \
  -p 15673:15672 \
  -e RABBITMQ_ERLANG_COOKIE=secret_cookie \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3.12-management

# Create third node
docker run -d --name rabbitmq3 \
  -p 5674:5672 \
  -p 15674:15672 \
  -e RABBITMQ_ERLANG_COOKIE=secret_cookie \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3.12-management
```

#### **Step 2: Join Nodes to Cluster**
```bash
# Get IP addresses
docker inspect rabbitmq1 | grep IPAddress
docker inspect rabbitmq2 | grep IPAddress
docker inspect rabbitmq3 | grep IPAddress

# Join node 2 to node 1
docker exec rabbitmq2 rabbitmqctl stop_app
docker exec rabbitmq2 rabbitmqctl reset
docker exec rabbitmq2 rabbitmqctl join_cluster rabbit@rabbitmq1
docker exec rabbitmq2 rabbitmqctl start_app

# Join node 3 to node 1
docker exec rabbitmq3 rabbitmqctl stop_app
docker exec rabbitmq3 rabbitmqctl reset
docker exec rabbitmq3 rabbitmqctl join_cluster rabbit@rabbitmq1
docker exec rabbitmq3 rabbitmqctl start_app
```

#### **Step 3: Verify Cluster Status**
```bash
# Check cluster status
docker exec rabbitmq1 rabbitmqctl cluster_status

# Check from any node
docker exec rabbitmq2 rabbitmqctl cluster_status
docker exec rabbitmq3 rabbitmqctl cluster_status
```

#### **Step 4: Test Cluster Functionality**
```python
# cluster_test.py
import pika
import json
import time
import random

def test_cluster():
    # List of cluster nodes
    nodes = [
        {'host': 'localhost', 'port': 5672},
        {'host': 'localhost', 'port': 5673},
        {'host': 'localhost', 'port': 5674}
    ]
    
    # Try to connect to each node
    for node in nodes:
        try:
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    host=node['host'],
                    port=node['port'],
                    virtual_host='/',
                    credentials=pika.PlainCredentials('admin', 'admin123')
                )
            )
            channel = connection.channel()
            
            # Declare a queue
            channel.queue_declare(queue='cluster_test')
            
            # Send a test message
            message = {
                'node': f"{node['host']}:{node['port']}",
                'timestamp': time.time()
            }
            
            channel.basic_publish(
                exchange='',
                routing_key='cluster_test',
                body=json.dumps(message)
            )
            
            print(f"Successfully sent message via {node['host']}:{node['port']}")
            connection.close()
            
        except Exception as e:
            print(f"Failed to connect to {node['host']}:{node['port']}: {e}")

if __name__ == '__main__':
    test_cluster()
```

#### **Step 5: Test Failover**
1. Stop one node: `docker stop rabbitmq2`
2. Check cluster status: `docker exec rabbitmq1 rabbitmqctl cluster_status`
3. Send messages and verify they are still processed
4. Restart the node: `docker start rabbitmq2`
5. Verify it rejoins the cluster

### **Lab 2 Assessment**
- [ ] Successfully created 3-node cluster
- [ ] Can verify cluster status
- [ ] Understands cluster failover
- [ ] Can test cluster functionality
- [ ] Understands high availability concepts

## 🧪 **Lab 3: Monitoring Setup**

### **Objective**
Set up monitoring for RabbitMQ using Prometheus and Grafana.

### **Duration**
4-5 hours

### **Steps**

#### **Step 1: Enable Prometheus Plugin**
```bash
# Enable Prometheus plugin on RabbitMQ
docker exec rabbitmq1 rabbitmq-plugins enable rabbitmq_prometheus

# Verify plugin is enabled
docker exec rabbitmq1 rabbitmq-plugins list
```

#### **Step 2: Install Prometheus**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['host.docker.internal:15692']
    scrape_interval: 30s
    metrics_path: /metrics
```

```bash
# Run Prometheus
docker run -d --name prometheus \
  -p 9090:9090 \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus
```

#### **Step 3: Install Grafana**
```bash
# Run Grafana
docker run -d --name grafana \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin123 \
  grafana/grafana
```

#### **Step 4: Configure Grafana**
1. Open browser and go to `http://localhost:3000`
2. Login with username: `admin`, password: `admin123`
3. Add Prometheus as data source:
   - URL: `http://host.docker.internal:9090`
   - Access: Server (default)
   - Save & Test

#### **Step 5: Create Dashboard**
```json
{
  "dashboard": {
    "title": "RabbitMQ Monitoring",
    "panels": [
      {
        "title": "Queue Messages",
        "type": "stat",
        "targets": [
          {
            "expr": "rabbitmq_queue_messages",
            "legendFormat": "Messages"
          }
        ]
      },
      {
        "title": "Message Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(rabbitmq_queue_messages_published_total[5m])",
            "legendFormat": "Published"
          },
          {
            "expr": "rate(rabbitmq_queue_messages_delivered_total[5m])",
            "legendFormat": "Delivered"
          }
        ]
      }
    ]
  }
}
```

#### **Step 6: Generate Load and Monitor**
```python
# load_generator.py
import pika
import json
import time
import threading

def generate_load():
    connection = pika.BlockingConnection(
        pika.ConnectionParameters('localhost')
    )
    channel = connection.channel()
    
    channel.queue_declare(queue='load_test')
    
    for i in range(1000):
        message = {
            'id': i,
            'timestamp': time.time(),
            'data': f'Load test message {i}'
        }
        
        channel.basic_publish(
            exchange='',
            routing_key='load_test',
            body=json.dumps(message)
        )
        
        if i % 100 == 0:
            print(f"Sent {i} messages")
        
        time.sleep(0.1)
    
    connection.close()

if __name__ == '__main__':
    generate_load()
```

### **Lab 3 Assessment**
- [ ] Successfully enabled Prometheus plugin
- [ ] Can access Prometheus metrics
- [ ] Configured Grafana with Prometheus data source
- [ ] Created basic monitoring dashboard
- [ ] Can generate load and observe metrics

## 🧪 **Lab 4: ML Model Training**

### **Objective**
Train a simple anomaly detection model for RabbitMQ metrics.

### **Duration**
5-6 hours

### **Steps**

#### **Step 1: Collect Training Data**
```python
# data_collector.py
import pika
import json
import time
import pandas as pd
from datetime import datetime

def collect_metrics():
    connection = pika.BlockingConnection(
        pika.ConnectionParameters('localhost')
    )
    channel = connection.channel()
    
    metrics = []
    
    for i in range(1000):
        # Get queue info
        method = channel.queue_declare(queue='metrics_test', passive=True)
        queue_length = method.method.message_count
        
        # Get connection count
        connection_count = len(connection.connection.channels)
        
        # Get memory usage (simulated)
        memory_usage = 0.5 + (i % 100) / 200  # Simulate memory usage
        
        # Get CPU usage (simulated)
        cpu_usage = 0.3 + (i % 50) / 100  # Simulate CPU usage
        
        metric = {
            'timestamp': datetime.now(),
            'queue_length': queue_length,
            'connection_count': connection_count,
            'memory_usage': memory_usage,
            'cpu_usage': cpu_usage
        }
        
        metrics.append(metric)
        
        # Send some messages to create activity
        if i % 10 == 0:
            for j in range(5):
                channel.basic_publish(
                    exchange='',
                    routing_key='metrics_test',
                    body=json.dumps({'id': j, 'timestamp': time.time()})
                )
        
        time.sleep(1)
    
    connection.close()
    
    # Save to CSV
    df = pd.DataFrame(metrics)
    df.to_csv('rabbitmq_metrics.csv', index=False)
    print(f"Collected {len(metrics)} metrics")

if __name__ == '__main__':
    collect_metrics()
```

#### **Step 2: Train Anomaly Detection Model**
```python
# anomaly_detection.py
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import joblib

def train_anomaly_model():
    # Load data
    df = pd.read_csv('rabbitmq_metrics.csv')
    
    # Prepare features
    features = ['queue_length', 'connection_count', 'memory_usage', 'cpu_usage']
    X = df[features]
    
    # Normalize features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Train Isolation Forest
    model = IsolationForest(
        contamination=0.1,  # 10% of data is expected to be anomalous
        random_state=42
    )
    model.fit(X_scaled)
    
    # Make predictions
    predictions = model.predict(X_scaled)
    anomaly_scores = model.decision_function(X_scaled)
    
    # Add predictions to dataframe
    df['anomaly'] = predictions
    df['anomaly_score'] = anomaly_scores
    
    # Save model and scaler
    joblib.dump(model, 'anomaly_model.pkl')
    joblib.dump(scaler, 'scaler.pkl')
    
    # Print results
    anomalies = df[df['anomaly'] == -1]
    print(f"Detected {len(anomalies)} anomalies out of {len(df)} samples")
    print(f"Anomaly rate: {len(anomalies) / len(df) * 100:.2f}%")
    
    return model, scaler

if __name__ == '__main__':
    train_anomaly_model()
```

#### **Step 3: Create Prediction Service**
```python
# prediction_service.py
import joblib
import numpy as np
from flask import Flask, request, jsonify

app = Flask(__name__)

# Load model and scaler
model = joblib.load('anomaly_model.pkl')
scaler = joblib.load('scaler.pkl')

@app.route('/predict', methods=['POST'])
def predict():
    try:
        # Get input data
        data = request.json
        features = [
            data['queue_length'],
            data['connection_count'],
            data['memory_usage'],
            data['cpu_usage']
        ]
        
        # Scale features
        features_scaled = scaler.transform([features])
        
        # Make prediction
        prediction = model.predict(features_scaled)[0]
        anomaly_score = model.decision_function(features_scaled)[0]
        
        # Return result
        result = {
            'anomaly': int(prediction),
            'anomaly_score': float(anomaly_score),
            'is_anomaly': prediction == -1
        }
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

#### **Step 4: Test the Model**
```python
# test_model.py
import requests
import json

def test_anomaly_detection():
    # Test normal data
    normal_data = {
        'queue_length': 10,
        'connection_count': 5,
        'memory_usage': 0.6,
        'cpu_usage': 0.4
    }
    
    response = requests.post('http://localhost:5000/predict', json=normal_data)
    result = response.json()
    print(f"Normal data: {result}")
    
    # Test anomalous data
    anomalous_data = {
        'queue_length': 1000,
        'connection_count': 100,
        'memory_usage': 0.95,
        'cpu_usage': 0.9
    }
    
    response = requests.post('http://localhost:5000/predict', json=anomalous_data)
    result = response.json()
    print(f"Anomalous data: {result}")

if __name__ == '__main__':
    test_anomaly_detection()
```

### **Lab 4 Assessment**
- [ ] Successfully collected training data
- [ ] Trained anomaly detection model
- [ ] Created prediction service
- [ ] Can test model predictions
- [ ] Understands ML model lifecycle

## 🧪 **Lab 5: Kubernetes Deployment**

### **Objective**
Deploy RabbitMQ and ML services on Kubernetes.

### **Duration**
6-7 hours

### **Steps**

#### **Step 1: Create RabbitMQ Deployment**
```yaml
# rabbitmq-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.12-management
        ports:
        - containerPort: 5672
        - containerPort: 15672
        env:
        - name: RABBITMQ_DEFAULT_USER
          value: "admin"
        - name: RABBITMQ_DEFAULT_PASS
          value: "admin123"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-service
spec:
  selector:
    app: rabbitmq
  ports:
  - name: amqp
    port: 5672
    targetPort: 5672
  - name: management
    port: 15672
    targetPort: 15672
  type: ClusterIP
```

#### **Step 2: Create ML Service Deployment**
```yaml
# ml-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ml-service
  template:
    metadata:
      labels:
        app: ml-service
    spec:
      containers:
      - name: ml-service
        image: your-registry/ml-service:latest
        ports:
        - containerPort: 5000
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "250m"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ml-service
spec:
  selector:
    app: ml-service
  ports:
  - port: 5000
    targetPort: 5000
  type: ClusterIP
```

#### **Step 3: Deploy to Kubernetes**
```bash
# Apply deployments
kubectl apply -f rabbitmq-deployment.yaml
kubectl apply -f ml-service-deployment.yaml

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get services
```

#### **Step 4: Test the Deployment**
```python
# test_k8s_deployment.py
import requests
import time

def test_services():
    # Test ML service health
    try:
        response = requests.get('http://ml-service:5000/health')
        print(f"ML Service Health: {response.json()}")
    except Exception as e:
        print(f"ML Service Error: {e}")
    
    # Test ML service prediction
    try:
        test_data = {
            'queue_length': 50,
            'connection_count': 10,
            'memory_usage': 0.7,
            'cpu_usage': 0.5
        }
        response = requests.post('http://ml-service:5000/predict', json=test_data)
        print(f"ML Service Prediction: {response.json()}")
    except Exception as e:
        print(f"ML Service Prediction Error: {e}")

if __name__ == '__main__':
    test_services()
```

#### **Step 5: Set up Monitoring**
```yaml
# monitoring-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
  type: ClusterIP
```

### **Lab 5 Assessment**
- [ ] Successfully created Kubernetes deployments
- [ ] Can deploy RabbitMQ on Kubernetes
- [ ] Can deploy ML services on Kubernetes
- [ ] Understands Kubernetes concepts
- [ ] Can test deployed services

## 🧪 **Lab 6: MLOps Pipeline**

### **Objective**
Implement a complete MLOps pipeline for model training and deployment.

### **Duration**
8-10 hours

### **Steps**

#### **Step 1: Set up MLflow**
```python
# mlflow_training.py
import mlflow
import mlflow.sklearn
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import joblib

def train_model_with_mlflow():
    # Set MLflow tracking URI
    mlflow.set_tracking_uri("http://localhost:5000")
    
    # Start MLflow run
    with mlflow.start_run():
        # Load data
        df = pd.read_csv('rabbitmq_metrics.csv')
        
        # Prepare features
        features = ['queue_length', 'connection_count', 'memory_usage', 'cpu_usage']
        X = df[features]
        
        # Split data
        X_train, X_test = train_test_split(X, test_size=0.2, random_state=42)
        
        # Scale features
        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)
        
        # Train model
        model = IsolationForest(
            contamination=0.1,
            random_state=42
        )
        model.fit(X_train_scaled)
        
        # Evaluate model
        train_predictions = model.predict(X_train_scaled)
        test_predictions = model.predict(X_test_scaled)
        
        train_anomalies = sum(train_predictions == -1)
        test_anomalies = sum(test_predictions == -1)
        
        # Log parameters
        mlflow.log_param("contamination", 0.1)
        mlflow.log_param("random_state", 42)
        
        # Log metrics
        mlflow.log_metric("train_anomalies", train_anomalies)
        mlflow.log_metric("test_anomalies", test_anomalies)
        mlflow.log_metric("train_anomaly_rate", train_anomalies / len(X_train))
        mlflow.log_metric("test_anomaly_rate", test_anomalies / len(X_test))
        
        # Log model
        mlflow.sklearn.log_model(model, "model")
        mlflow.sklearn.log_model(scaler, "scaler")
        
        print("Model logged to MLflow")

if __name__ == '__main__':
    train_model_with_mlflow()
```

#### **Step 2: Create Model Serving**
```python
# model_serving.py
import mlflow
import mlflow.sklearn
import numpy as np
from flask import Flask, request, jsonify

app = Flask(__name__)

# Load model from MLflow
model_uri = "runs:/<run_id>/model"
scaler_uri = "runs:/<run_id>/scaler"

model = mlflow.sklearn.load_model(model_uri)
scaler = mlflow.sklearn.load_model(scaler_uri)

@app.route('/predict', methods=['POST'])
def predict():
    try:
        data = request.json
        features = [
            data['queue_length'],
            data['connection_count'],
            data['memory_usage'],
            data['cpu_usage']
        ]
        
        features_scaled = scaler.transform([features])
        prediction = model.predict(features_scaled)[0]
        anomaly_score = model.decision_function(features_scaled)[0]
        
        result = {
            'anomaly': int(prediction),
            'anomaly_score': float(anomaly_score),
            'is_anomaly': prediction == -1
        }
        
        return jsonify(result)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

#### **Step 3: Set up CI/CD Pipeline**
```yaml
# .github/workflows/ml-pipeline.yml
name: ML Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  train:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: 3.8
    
    - name: Install dependencies
      run: |
        pip install -r requirements.txt
    
    - name: Train model
      run: |
        python mlflow_training.py
    
    - name: Test model
      run: |
        python test_model.py

  deploy:
    needs: train
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
    - uses: actions/checkout@v2
    
    - name: Deploy to Kubernetes
      run: |
        kubectl apply -f k8s/
```

#### **Step 4: Set up Model Monitoring**
```python
# model_monitoring.py
import requests
import time
import pandas as pd
from datetime import datetime

def monitor_model_performance():
    while True:
        try:
            # Get current metrics
            response = requests.get('http://localhost:15672/api/overview')
            data = response.json()
            
            # Prepare features
            features = {
                'queue_length': data['queue_totals']['messages'],
                'connection_count': data['object_totals']['connections'],
                'memory_usage': data['memory']['used'] / data['memory']['limit'],
                'cpu_usage': 0.5  # Simulated
            }
            
            # Get prediction
            response = requests.post('http://localhost:5000/predict', json=features)
            result = response.json()
            
            # Log monitoring data
            monitoring_data = {
                'timestamp': datetime.now(),
                'features': features,
                'prediction': result,
                'model_version': '1.0'
            }
            
            print(f"Monitoring: {monitoring_data}")
            
            # Check for anomalies
            if result['is_anomaly']:
                print(f"ALERT: Anomaly detected! Score: {result['anomaly_score']}")
            
            time.sleep(60)  # Check every minute
            
        except Exception as e:
            print(f"Monitoring error: {e}")
            time.sleep(60)

if __name__ == '__main__':
    monitor_model_performance()
```

### **Lab 6 Assessment**
- [ ] Successfully set up MLflow
- [ ] Can train models with MLflow tracking
- [ ] Can serve models from MLflow
- [ ] Understands CI/CD for ML
- [ ] Can monitor model performance

## 🎓 **Final Project**

### **Objective**
Implement a complete RabbitMQ AI/ML system with monitoring and automation.

### **Requirements**
1. Set up RabbitMQ cluster
2. Implement anomaly detection
3. Create monitoring dashboards
4. Deploy on Kubernetes
5. Implement MLOps pipeline
6. Add automated actions

### **Deliverables**
1. Working system demonstration
2. Documentation
3. Presentation
4. Code repository

### **Assessment Criteria**
- **Functionality (40%)**: System works as expected
- **Code Quality (20%)**: Clean, well-documented code
- **Documentation (20%)**: Clear documentation
- **Presentation (20%)**: Effective presentation

## 📚 **Additional Resources**

### **Documentation**
- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [MLflow Documentation](https://mlflow.org/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)

### **Books**
- "RabbitMQ in Action" by Alvaro Videla
- "Kubernetes in Action" by Marko Lukša
- "Hands-On Machine Learning" by Aurélien Géron
- "MLOps Engineering at Scale" by Carl Osipov

### **Online Courses**
- AWS Certified Solutions Architect
- Kubernetes Certified Administrator
- Machine Learning Engineer Nanodegree
- MLOps Specialization

## 🎯 **Assessment Questions**

### **Lab 1-2: RabbitMQ**
1. How does RabbitMQ ensure message delivery?
2. What are the benefits of clustering?
3. How do you handle node failures?

### **Lab 3: Monitoring**
1. What metrics are important for RabbitMQ?
2. How do you set up alerting?
3. What are the benefits of monitoring?

### **Lab 4: ML Models**
1. How do you evaluate model performance?
2. What is the difference between supervised and unsupervised learning?
3. How do you handle model drift?

### **Lab 5: Kubernetes**
1. What are the benefits of containerization?
2. How does Kubernetes manage resources?
3. How do you scale applications?

### **Lab 6: MLOps**
1. What is the ML model lifecycle?
2. How do you version models?
3. What is continuous integration for ML?

## 🎉 **Conclusion**

These hands-on labs provide practical experience with all aspects of our RabbitMQ AI/ML system. By completing these labs, freshers will gain:

- **Practical Skills**: Hands-on experience with real tools and technologies
- **Problem-Solving**: Ability to troubleshoot and debug issues
- **System Understanding**: Deep knowledge of how components work together
- **Best Practices**: Understanding of industry best practices
- **Confidence**: Ability to work with complex systems

This practical experience, combined with the theoretical knowledge from the foundation concepts and architecture explanations, will prepare freshers to contribute effectively to our team and work with modern AI/ML systems.

---

**Ready to get hands-on experience!** 🚀
