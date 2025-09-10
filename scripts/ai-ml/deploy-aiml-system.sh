#!/bin/bash

# RabbitMQ AI/ML System Deployment Script
# This script deploys the complete AI/ML operations system for RabbitMQ

set -e

# Configuration
NAMESPACE="${NAMESPACE:-rabbitmq-aiml}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
ML_NAMESPACE="${ML_NAMESPACE:-ml-pipeline}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-grafana}"

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

# Check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is required but not installed"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "kubectl is available and connected to cluster"
}

# Check if helm is available
check_helm() {
    if ! command -v helm &> /dev/null; then
        log_error "helm is required but not installed"
        exit 1
    fi
    
    log_success "helm is available"
}

# Create namespaces
create_namespaces() {
    log_message "Creating namespaces..."
    
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $ML_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $GRAFANA_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Namespaces created successfully"
}

# Install monitoring stack
install_monitoring_stack() {
    log_message "Installing monitoring stack..."
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    
    # Install Prometheus
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace $MONITORING_NAMESPACE \
        --set grafana.adminPassword=admin123 \
        --set prometheus.prometheusSpec.retention=30d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
        --wait
    
    # Install InfluxDB
    helm upgrade --install influxdb bitnami/influxdb \
        --namespace $MONITORING_NAMESPACE \
        --set auth.enabled=true \
        --set auth.admin.password=admin123 \
        --set persistence.enabled=true \
        --set persistence.size=20Gi \
        --wait
    
    # Install Elasticsearch
    helm upgrade --install elasticsearch bitnami/elasticsearch \
        --namespace $MONITORING_NAMESPACE \
        --set replicas=3 \
        --set persistence.enabled=true \
        --set persistence.size=50Gi \
        --wait
    
    log_success "Monitoring stack installed successfully"
}

# Install data pipeline
install_data_pipeline() {
    log_message "Installing data pipeline..."
    
    # Install Apache Kafka
    helm upgrade --install kafka bitnami/kafka \
        --namespace $NAMESPACE \
        --set replicaCount=3 \
        --set persistence.enabled=true \
        --set persistence.size=20Gi \
        --set zookeeper.persistence.enabled=true \
        --set zookeeper.persistence.size=10Gi \
        --wait
    
    # Install Apache Spark
    helm upgrade --install spark bitnami/spark \
        --namespace $NAMESPACE \
        --set master.replicaCount=1 \
        --set worker.replicaCount=2 \
        --set persistence.enabled=true \
        --set persistence.size=20Gi \
        --wait
    
    log_success "Data pipeline installed successfully"
}

# Install ML platform
install_ml_platform() {
    log_message "Installing ML platform..."
    
    # Install Kubeflow
    kubectl apply -k "github.com/kubeflow/manifests/example?ref=v1.8.0"
    
    # Wait for Kubeflow to be ready
    log_message "Waiting for Kubeflow to be ready..."
    kubectl wait --for=condition=ready pod -l app=centraldashboard -n kubeflow --timeout=600s
    
    # Install MLflow
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mlflow
  namespace: $ML_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mlflow
  template:
    metadata:
      labels:
        app: mlflow
    spec:
      containers:
      - name: mlflow
        image: python:3.11-slim
        command: ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
        ports:
        - containerPort: 5000
        env:
        - name: MLFLOW_BACKEND_STORE_URI
          value: "sqlite:///mlflow.db"
        - name: MLFLOW_DEFAULT_ARTIFACT_ROOT
          value: "/mlflow/artifacts"
        volumeMounts:
        - name: mlflow-storage
          mountPath: /mlflow
      volumes:
      - name: mlflow-storage
        persistentVolumeClaim:
          claimName: mlflow-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mlflow
  namespace: $ML_NAMESPACE
spec:
  selector:
    app: mlflow
  ports:
  - port: 5000
    targetPort: 5000
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mlflow-pvc
  namespace: $ML_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
    
    # Wait for MLflow to be ready
    kubectl wait --for=condition=ready pod -l app=mlflow -n $ML_NAMESPACE --timeout=300s
    
    log_success "ML platform installed successfully"
}

# Deploy RabbitMQ with enhanced monitoring
deploy_rabbitmq() {
    log_message "Deploying RabbitMQ with enhanced monitoring..."
    
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-monitor
  namespace: $NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rabbitmq-monitor
  template:
    metadata:
      labels:
        app: rabbitmq-monitor
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.12-management
        ports:
        - containerPort: 5672
        - containerPort: 15672
        - containerPort: 15692
        env:
        - name: RABBITMQ_DEFAULT_USER
          value: "admin"
        - name: RABBITMQ_DEFAULT_PASS
          value: "admin123"
        - name: RABBITMQ_PROMETHEUS_TCP_PORT
          value: "15692"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: rabbitmq-data
          mountPath: /var/lib/rabbitmq
      volumes:
      - name: rabbitmq-data
        persistentVolumeClaim:
          claimName: rabbitmq-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq-monitor
  namespace: $NAMESPACE
spec:
  selector:
    app: rabbitmq-monitor
  ports:
  - name: amqp
    port: 5672
    targetPort: 5672
  - name: management
    port: 15672
    targetPort: 15672
  - name: prometheus
    port: 15692
    targetPort: 15692
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rabbitmq-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF
    
    # Wait for RabbitMQ to be ready
    kubectl wait --for=condition=ready pod -l app=rabbitmq-monitor -n $NAMESPACE --timeout=300s
    
    log_success "RabbitMQ deployed successfully"
}

# Deploy AI/ML components
deploy_aiml_components() {
    log_message "Deploying AI/ML components..."
    
    # Deploy anomaly detection service
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anomaly-detection
  namespace: $ML_NAMESPACE
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
        command: ["python", "/app/anomaly_detection_model.py"]
        ports:
        - containerPort: 8080
        env:
        - name: RABBITMQ_URL
          value: "http://rabbitmq-monitor.$NAMESPACE.svc.cluster.local:15672"
        - name: RABBITMQ_USER
          value: "admin"
        - name: RABBITMQ_PASS
          value: "admin123"
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
  namespace: $ML_NAMESPACE
spec:
  selector:
    app: anomaly-detection
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: anomaly-detection-code
  namespace: $ML_NAMESPACE
data:
  anomaly_detection_model.py: |
    # Anomaly detection model code will be injected here
    print("Anomaly detection service started")
EOF
    
    # Deploy performance prediction service
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: performance-prediction
  namespace: $ML_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: performance-prediction
  template:
    metadata:
      labels:
        app: performance-prediction
    spec:
      containers:
      - name: performance-prediction
        image: python:3.11-slim
        command: ["python", "/app/performance_prediction_model.py"]
        ports:
        - containerPort: 8080
        env:
        - name: RABBITMQ_URL
          value: "http://rabbitmq-monitor.$NAMESPACE.svc.cluster.local:15672"
        - name: RABBITMQ_USER
          value: "admin"
        - name: RABBITMQ_PASS
          value: "admin123"
        volumeMounts:
        - name: app-code
          mountPath: /app
      volumes:
      - name: app-code
        configMap:
          name: performance-prediction-code
---
apiVersion: v1
kind: Service
metadata:
  name: performance-prediction
  namespace: $ML_NAMESPACE
spec:
  selector:
    app: performance-prediction
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-prediction-code
  namespace: $ML_NAMESPACE
data:
  performance_prediction_model.py: |
    # Performance prediction model code will be injected here
    print("Performance prediction service started")
EOF
    
    # Deploy decision engine
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: decision-engine
  namespace: $ML_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: decision-engine
  template:
    metadata:
      labels:
        app: decision-engine
    spec:
      containers:
      - name: decision-engine
        image: python:3.11-slim
        command: ["python", "/app/decision_engine.py"]
        ports:
        - containerPort: 8080
        env:
        - name: RABBITMQ_URL
          value: "http://rabbitmq-monitor.$NAMESPACE.svc.cluster.local:15672"
        - name: RABBITMQ_USER
          value: "admin"
        - name: RABBITMQ_PASS
          value: "admin123"
        - name: ANOMALY_DETECTION_URL
          value: "http://anomaly-detection:8080"
        - name: PERFORMANCE_PREDICTION_URL
          value: "http://performance-prediction:8080"
        volumeMounts:
        - name: app-code
          mountPath: /app
      volumes:
      - name: app-code
        configMap:
          name: decision-engine-code
---
apiVersion: v1
kind: Service
metadata:
  name: decision-engine
  namespace: $ML_NAMESPACE
spec:
  selector:
    app: decision-engine
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: decision-engine-code
  namespace: $ML_NAMESPACE
data:
  decision_engine.py: |
    # Decision engine code will be injected here
    print("Decision engine service started")
EOF
    
    # Wait for AI/ML components to be ready
    kubectl wait --for=condition=ready pod -l app=anomaly-detection -n $ML_NAMESPACE --timeout=300s
    kubectl wait --for=condition=ready pod -l app=performance-prediction -n $ML_NAMESPACE --timeout=300s
    kubectl wait --for=condition=ready pod -l app=decision-engine -n $ML_NAMESPACE --timeout=300s
    
    log_success "AI/ML components deployed successfully"
}

# Deploy monitoring and alerting
deploy_monitoring_alerting() {
    log_message "Deploying monitoring and alerting..."
    
    # Deploy Prometheus service monitor for RabbitMQ
    kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq-monitor
  namespace: $MONITORING_NAMESPACE
spec:
  selector:
    matchLabels:
      app: rabbitmq-monitor
  endpoints:
  - port: prometheus
    path: /metrics
    interval: 30s
EOF
    
    # Deploy Grafana dashboards
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-dashboards
  namespace: $GRAFANA_NAMESPACE
data:
  rabbitmq-queue-dashboard.json: |
    # Dashboard JSON will be injected here
  rabbitmq-channels-connections-dashboard.json: |
    # Dashboard JSON will be injected here
  rabbitmq-message-flow-dashboard.json: |
    # Dashboard JSON will be injected here
  rabbitmq-system-performance-dashboard.json: |
    # Dashboard JSON will be injected here
  rabbitmq-cluster-health-dashboard.json: |
    # Dashboard JSON will be injected here
EOF
    
    log_success "Monitoring and alerting deployed successfully"
}

# Deploy auto-scaling and self-healing
deploy_autoscaling_selfhealing() {
    log_message "Deploying auto-scaling and self-healing..."
    
    # Deploy Horizontal Pod Autoscaler for RabbitMQ
    kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rabbitmq-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rabbitmq-monitor
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF
    
    # Deploy self-healing controller
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: self-healing-controller
  namespace: $ML_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: self-healing-controller
  template:
    metadata:
      labels:
        app: self-healing-controller
    spec:
      containers:
      - name: self-healing-controller
        image: python:3.11-slim
        command: ["python", "/app/self_healing.py"]
        env:
        - name: RABBITMQ_URL
          value: "http://rabbitmq-monitor.$NAMESPACE.svc.cluster.local:15672"
        - name: RABBITMQ_USER
          value: "admin"
        - name: RABBITMQ_PASS
          value: "admin123"
        - name: DECISION_ENGINE_URL
          value: "http://decision-engine:8080"
        volumeMounts:
        - name: app-code
          mountPath: /app
      volumes:
      - name: app-code
        configMap:
          name: self-healing-code
---
apiVersion: v1
kind: Service
metadata:
  name: self-healing-controller
  namespace: $ML_NAMESPACE
spec:
  selector:
    app: self-healing-controller
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: self-healing-code
  namespace: $ML_NAMESPACE
data:
  self_healing.py: |
    # Self-healing controller code will be injected here
    print("Self-healing controller started")
EOF
    
    log_success "Auto-scaling and self-healing deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_message "Verifying deployment..."
    
    # Check namespaces
    kubectl get namespaces | grep -E "($NAMESPACE|$MONITORING_NAMESPACE|$ML_NAMESPACE|$GRAFANA_NAMESPACE)"
    
    # Check pods
    kubectl get pods -n $NAMESPACE
    kubectl get pods -n $MONITORING_NAMESPACE
    kubectl get pods -n $ML_NAMESPACE
    kubectl get pods -n $GRAFANA_NAMESPACE
    
    # Check services
    kubectl get services -n $NAMESPACE
    kubectl get services -n $MONITORING_NAMESPACE
    kubectl get services -n $ML_NAMESPACE
    kubectl get services -n $GRAFANA_NAMESPACE
    
    log_success "Deployment verification completed"
}

# Display access information
display_access_info() {
    log_message "Displaying access information..."
    
    echo ""
    echo "🎉 RabbitMQ AI/ML System Deployment Completed!"
    echo "=============================================="
    echo ""
    echo "📊 Access Information:"
    echo "  • RabbitMQ Management: http://localhost:15672 (admin/admin123)"
    echo "  • Grafana: http://localhost:3000 (admin/admin123)"
    echo "  • Prometheus: http://localhost:9090"
    echo "  • MLflow: http://localhost:5000"
    echo "  • Kubeflow: http://localhost:8080"
    echo ""
    echo "🔧 Port Forwarding Commands:"
    echo "  • RabbitMQ: kubectl port-forward -n $NAMESPACE svc/rabbitmq-monitor 15672:15672"
    echo "  • Grafana: kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-grafana 3000:80"
    echo "  • Prometheus: kubectl port-forward -n $MONITORING_NAMESPACE svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo "  • MLflow: kubectl port-forward -n $ML_NAMESPACE svc/mlflow 5000:5000"
    echo ""
    echo "📈 Monitoring Dashboards:"
    echo "  • Queue Performance: http://localhost:3000/d/queue-performance"
    echo "  • Channels & Connections: http://localhost:3000/d/channels-connections"
    echo "  • Message Flow: http://localhost:3000/d/message-flow"
    echo "  • System Performance: http://localhost:3000/d/system-performance"
    echo "  • Cluster Health: http://localhost:3000/d/cluster-health"
    echo ""
    echo "🤖 AI/ML Services:"
    echo "  • Anomaly Detection: http://localhost:8080 (anomaly-detection service)"
    echo "  • Performance Prediction: http://localhost:8080 (performance-prediction service)"
    echo "  • Decision Engine: http://localhost:8080 (decision-engine service)"
    echo ""
    echo "🚀 Next Steps:"
    echo "  1. Set up port forwarding for the services you want to access"
    echo "  2. Import Grafana dashboards from configs/dashboards/"
    echo "  3. Configure alerting rules in Prometheus"
    echo "  4. Train ML models with historical data"
    echo "  5. Test the AI/ML automation system"
    echo ""
}

# Main deployment function
main() {
    echo "🚀 RabbitMQ AI/ML System Deployment"
    echo "===================================="
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --monitoring-namespace)
                MONITORING_NAMESPACE="$2"
                shift 2
                ;;
            --ml-namespace)
                ML_NAMESPACE="$2"
                shift 2
                ;;
            --grafana-namespace)
                GRAFANA_NAMESPACE="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --namespace NAMESPACE           RabbitMQ namespace (default: rabbitmq-aiml)"
                echo "  --monitoring-namespace NAMESPACE Monitoring namespace (default: monitoring)"
                echo "  --ml-namespace NAMESPACE       ML namespace (default: ml-pipeline)"
                echo "  --grafana-namespace NAMESPACE  Grafana namespace (default: grafana)"
                echo "  --help                         Show this help message"
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
    check_kubectl
    check_helm
    create_namespaces
    install_monitoring_stack
    install_data_pipeline
    install_ml_platform
    deploy_rabbitmq
    deploy_aiml_components
    deploy_monitoring_alerting
    deploy_autoscaling_selfhealing
    verify_deployment
    display_access_info
    
    log_success "RabbitMQ AI/ML system deployment completed successfully!"
}

# Run main function
main "$@"
