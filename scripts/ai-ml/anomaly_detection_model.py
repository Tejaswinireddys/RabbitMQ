#!/usr/bin/env python3
"""
RabbitMQ Anomaly Detection Model
This script implements machine learning models for detecting anomalies in RabbitMQ cluster operations.
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import logging
from typing import Dict, List, Tuple
import json
import requests
from datetime import datetime, timedelta

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RabbitMQAnomalyDetector:
    """
    Anomaly detection system for RabbitMQ clusters using machine learning.
    """
    
    def __init__(self, contamination=0.1, random_state=42):
        """
        Initialize the anomaly detector.
        
        Args:
            contamination: Expected proportion of outliers in the dataset
            random_state: Random state for reproducibility
        """
        self.contamination = contamination
        self.random_state = random_state
        self.model = IsolationForest(
            contamination=contamination,
            random_state=random_state,
            n_estimators=100
        )
        self.scaler = StandardScaler()
        self.is_trained = False
        self.feature_names = [
            'memory_usage', 'disk_usage', 'connection_count',
            'channel_count', 'queue_depth', 'message_rate',
            'cpu_usage', 'network_io', 'error_rate',
            'consumer_count', 'exchange_count', 'vhost_count'
        ]
        
    def prepare_features(self, data: pd.DataFrame) -> np.ndarray:
        """
        Prepare features for anomaly detection.
        
        Args:
            data: DataFrame containing RabbitMQ metrics
            
        Returns:
            numpy array of prepared features
        """
        try:
            # Select and validate features
            features = data[self.feature_names].copy()
            
            # Handle missing values
            features = features.fillna(features.median())
            
            # Handle infinite values
            features = features.replace([np.inf, -np.inf], np.nan)
            features = features.fillna(features.median())
            
            return features.values
            
        except KeyError as e:
            logger.error(f"Missing required features: {e}")
            raise
        except Exception as e:
            logger.error(f"Error preparing features: {e}")
            raise
    
    def train(self, historical_data: pd.DataFrame) -> Dict:
        """
        Train the anomaly detection model.
        
        Args:
            historical_data: Historical RabbitMQ metrics data
            
        Returns:
            Training results dictionary
        """
        try:
            logger.info("Starting anomaly detection model training...")
            
            # Prepare features
            features = self.prepare_features(historical_data)
            
            # Scale features
            scaled_features = self.scaler.fit_transform(features)
            
            # Train model
            self.model.fit(scaled_features)
            self.is_trained = True
            
            # Calculate training metrics
            predictions = self.model.predict(scaled_features)
            scores = self.model.score_samples(scaled_features)
            
            # Count anomalies
            anomaly_count = np.sum(predictions == -1)
            total_samples = len(predictions)
            anomaly_rate = anomaly_count / total_samples
            
            logger.info(f"Training completed. Anomaly rate: {anomaly_rate:.2%}")
            
            return {
                'status': 'success',
                'anomaly_count': int(anomaly_count),
                'total_samples': int(total_samples),
                'anomaly_rate': float(anomaly_rate),
                'contamination': self.contamination
            }
            
        except Exception as e:
            logger.error(f"Training failed: {e}")
            return {
                'status': 'error',
                'error': str(e)
            }
    
    def predict(self, current_data: pd.DataFrame) -> Dict:
        """
        Predict anomalies in current data.
        
        Args:
            current_data: Current RabbitMQ metrics data
            
        Returns:
            Prediction results dictionary
        """
        if not self.is_trained:
            raise ValueError("Model must be trained first")
        
        try:
            # Prepare features
            features = self.prepare_features(current_data)
            
            # Scale features
            scaled_features = self.scaler.transform(features)
            
            # Make predictions
            predictions = self.model.predict(scaled_features)
            scores = self.model.score_samples(scaled_features)
            
            # Convert to anomaly indicators
            anomalies = predictions == -1
            anomaly_scores = -scores  # Convert to positive scores (higher = more anomalous)
            
            # Create results
            results = {
                'timestamp': datetime.now().isoformat(),
                'anomalies_detected': int(np.sum(anomalies)),
                'total_samples': len(anomalies),
                'anomaly_rate': float(np.mean(anomalies)),
                'max_anomaly_score': float(np.max(anomaly_scores)),
                'mean_anomaly_score': float(np.mean(anomaly_scores)),
                'anomaly_details': []
            }
            
            # Add detailed anomaly information
            for i, (is_anomaly, score) in enumerate(zip(anomalies, anomaly_scores)):
                if is_anomaly:
                    anomaly_detail = {
                        'sample_index': int(i),
                        'anomaly_score': float(score),
                        'features': {
                            name: float(features[i][j]) 
                            for j, name in enumerate(self.feature_names)
                        }
                    }
                    results['anomaly_details'].append(anomaly_detail)
            
            return results
            
        except Exception as e:
            logger.error(f"Prediction failed: {e}")
            return {
                'status': 'error',
                'error': str(e)
            }
    
    def save_model(self, filepath: str) -> bool:
        """
        Save the trained model to disk.
        
        Args:
            filepath: Path to save the model
            
        Returns:
            True if successful, False otherwise
        """
        try:
            model_data = {
                'model': self.model,
                'scaler': self.scaler,
                'feature_names': self.feature_names,
                'contamination': self.contamination,
                'random_state': self.random_state,
                'is_trained': self.is_trained
            }
            
            joblib.dump(model_data, filepath)
            logger.info(f"Model saved to {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to save model: {e}")
            return False
    
    def load_model(self, filepath: str) -> bool:
        """
        Load a trained model from disk.
        
        Args:
            filepath: Path to load the model from
            
        Returns:
            True if successful, False otherwise
        """
        try:
            model_data = joblib.load(filepath)
            
            self.model = model_data['model']
            self.scaler = model_data['scaler']
            self.feature_names = model_data['feature_names']
            self.contamination = model_data['contamination']
            self.random_state = model_data['random_state']
            self.is_trained = model_data['is_trained']
            
            logger.info(f"Model loaded from {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            return False

class RabbitMQDataCollector:
    """
    Data collector for RabbitMQ metrics.
    """
    
    def __init__(self, rabbitmq_url: str, username: str, password: str):
        """
        Initialize the data collector.
        
        Args:
            rabbitmq_url: RabbitMQ management API URL
            username: RabbitMQ username
            password: RabbitMQ password
        """
        self.rabbitmq_url = rabbitmq_url
        self.auth = (username, password)
        
    def collect_metrics(self) -> Dict:
        """
        Collect current RabbitMQ metrics.
        
        Returns:
            Dictionary of current metrics
        """
        try:
            # Collect overview metrics
            overview_response = requests.get(
                f"{self.rabbitmq_url}/api/overview",
                auth=self.auth,
                timeout=10
            )
            overview_data = overview_response.json()
            
            # Collect node metrics
            nodes_response = requests.get(
                f"{self.rabbitmq_url}/api/nodes",
                auth=self.auth,
                timeout=10
            )
            nodes_data = nodes_response.json()
            
            # Collect queue metrics
            queues_response = requests.get(
                f"{self.rabbitmq_url}/api/queues",
                auth=self.auth,
                timeout=10
            )
            queues_data = queues_response.json()
            
            # Process and combine metrics
            metrics = self._process_metrics(overview_data, nodes_data, queues_data)
            
            return metrics
            
        except Exception as e:
            logger.error(f"Failed to collect metrics: {e}")
            return {}
    
    def _process_metrics(self, overview: Dict, nodes: List[Dict], queues: List[Dict]) -> Dict:
        """
        Process raw metrics into standardized format.
        
        Args:
            overview: Overview API response
            nodes: Nodes API response
            queues: Queues API response
            
        Returns:
            Processed metrics dictionary
        """
        try:
            # Calculate memory usage
            memory_used = overview.get('memory_used', 0)
            memory_limit = overview.get('memory_limit', 1)
            memory_usage = memory_used / memory_limit if memory_limit > 0 else 0
            
            # Calculate disk usage
            disk_free = overview.get('disk_free', 0)
            disk_free_limit = overview.get('disk_free_limit', 1)
            disk_usage = 1 - (disk_free / disk_free_limit) if disk_free_limit > 0 else 0
            
            # Calculate queue metrics
            total_queue_depth = sum(queue.get('messages', 0) for queue in queues)
            total_consumers = sum(queue.get('consumers', 0) for queue in queues)
            
            # Calculate error rate
            total_messages = overview.get('message_stats', {}).get('publish', 0)
            total_redelivered = overview.get('message_stats', {}).get('redeliver', 0)
            error_rate = total_redelivered / total_messages if total_messages > 0 else 0
            
            # Calculate message rate (messages per second)
            message_rate = overview.get('message_stats', {}).get('publish_details', {}).get('rate', 0)
            
            # Get node metrics
            node = nodes[0] if nodes else {}
            cpu_usage = node.get('cpu', 0) / 100.0 if node.get('cpu') else 0
            network_io = node.get('io_read_bytes', 0) + node.get('io_write_bytes', 0)
            
            processed_metrics = {
                'memory_usage': memory_usage,
                'disk_usage': disk_usage,
                'connection_count': overview.get('connections', 0),
                'channel_count': overview.get('channels', 0),
                'queue_depth': total_queue_depth,
                'message_rate': message_rate,
                'cpu_usage': cpu_usage,
                'network_io': network_io,
                'error_rate': error_rate,
                'consumer_count': total_consumers,
                'exchange_count': overview.get('exchanges', 0),
                'vhost_count': overview.get('vhosts', 0)
            }
            
            return processed_metrics
            
        except Exception as e:
            logger.error(f"Error processing metrics: {e}")
            return {}

def main():
    """
    Main function for training and testing the anomaly detection model.
    """
    # Configuration
    RABBITMQ_URL = "http://localhost:15672"
    USERNAME = "admin"
    PASSWORD = "admin123"
    MODEL_PATH = "/tmp/rabbitmq_anomaly_model.pkl"
    
    # Initialize components
    detector = RabbitMQAnomalyDetector()
    collector = RabbitMQDataCollector(RABBITMQ_URL, USERNAME, PASSWORD)
    
    # Collect historical data (in production, this would come from a database)
    logger.info("Collecting historical data...")
    historical_data = []
    
    # Simulate historical data collection
    for i in range(1000):
        metrics = collector.collect_metrics()
        if metrics:
            historical_data.append(metrics)
        else:
            # Generate synthetic data for demonstration
            synthetic_data = {
                'memory_usage': np.random.beta(2, 5),
                'disk_usage': np.random.beta(2, 5),
                'connection_count': np.random.poisson(100),
                'channel_count': np.random.poisson(200),
                'queue_depth': np.random.poisson(1000),
                'message_rate': np.random.exponential(10),
                'cpu_usage': np.random.beta(2, 5),
                'network_io': np.random.exponential(1000),
                'error_rate': np.random.beta(1, 10),
                'consumer_count': np.random.poisson(50),
                'exchange_count': np.random.poisson(10),
                'vhost_count': np.random.poisson(5)
            }
            historical_data.append(synthetic_data)
    
    # Convert to DataFrame
    df = pd.DataFrame(historical_data)
    
    # Train the model
    logger.info("Training anomaly detection model...")
    training_results = detector.train(df)
    logger.info(f"Training results: {training_results}")
    
    # Save the model
    detector.save_model(MODEL_PATH)
    
    # Test the model
    logger.info("Testing anomaly detection...")
    test_data = df.tail(10)  # Use last 10 samples for testing
    predictions = detector.predict(test_data)
    logger.info(f"Prediction results: {predictions}")
    
    # Collect real-time data and predict
    logger.info("Collecting real-time data...")
    current_metrics = collector.collect_metrics()
    if current_metrics:
        current_df = pd.DataFrame([current_metrics])
        real_time_predictions = detector.predict(current_df)
        logger.info(f"Real-time predictions: {real_time_predictions}")
    
    logger.info("Anomaly detection model training and testing completed!")

if __name__ == "__main__":
    main()
