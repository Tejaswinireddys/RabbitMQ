#!/usr/bin/env python3
"""
RabbitMQ Performance Prediction Model
This script implements machine learning models for predicting RabbitMQ performance metrics.
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import StandardScaler, PolynomialFeatures
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
import joblib
import logging
from typing import Dict, List, Tuple, Optional
import json
import requests
from datetime import datetime, timedelta
import warnings
warnings.filterwarnings('ignore')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PerformancePredictor:
    """
    Performance prediction system for RabbitMQ clusters using machine learning.
    """
    
    def __init__(self, prediction_horizon: int = 24):
        """
        Initialize the performance predictor.
        
        Args:
            prediction_horizon: Number of hours to predict ahead
        """
        self.prediction_horizon = prediction_horizon
        self.models = {}
        self.scalers = {}
        self.feature_engineering = {}
        self.is_trained = False
        
        # Define target metrics to predict
        self.target_metrics = [
            'memory_usage', 'cpu_usage', 'queue_depth',
            'connection_count', 'message_rate', 'error_rate'
        ]
        
        # Define feature columns
        self.feature_columns = [
            'memory_usage', 'disk_usage', 'connection_count',
            'channel_count', 'queue_depth', 'message_rate',
            'cpu_usage', 'network_io', 'error_rate',
            'consumer_count', 'exchange_count', 'vhost_count',
            'hour_of_day', 'day_of_week', 'is_weekend'
        ]
        
    def prepare_features(self, data: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare features for training and prediction.
        
        Args:
            data: DataFrame containing RabbitMQ metrics
            
        Returns:
            DataFrame with prepared features
        """
        try:
            # Create a copy to avoid modifying original data
            features = data.copy()
            
            # Add time-based features
            if 'timestamp' in features.columns:
                features['timestamp'] = pd.to_datetime(features['timestamp'])
                features['hour_of_day'] = features['timestamp'].dt.hour
                features['day_of_week'] = features['timestamp'].dt.dayofweek
                features['is_weekend'] = features['timestamp'].dt.dayofweek.isin([5, 6]).astype(int)
            else:
                # Generate synthetic time features if timestamp not available
                features['hour_of_day'] = np.random.randint(0, 24, len(features))
                features['day_of_week'] = np.random.randint(0, 7, len(features))
                features['is_weekend'] = (features['day_of_week'] >= 5).astype(int)
            
            # Add lag features for time series prediction
            for metric in self.target_metrics:
                if metric in features.columns:
                    for lag in [1, 2, 3, 6, 12, 24]:  # 1h, 2h, 3h, 6h, 12h, 24h lags
                        features[f'{metric}_lag_{lag}'] = features[metric].shift(lag)
            
            # Add rolling statistics
            for metric in self.target_metrics:
                if metric in features.columns:
                    features[f'{metric}_rolling_mean_3h'] = features[metric].rolling(window=3).mean()
                    features[f'{metric}_rolling_std_3h'] = features[metric].rolling(window=3).std()
                    features[f'{metric}_rolling_mean_24h'] = features[metric].rolling(window=24).mean()
                    features[f'{metric}_rolling_std_24h'] = features[metric].rolling(window=24).std()
            
            # Add interaction features
            if 'memory_usage' in features.columns and 'cpu_usage' in features.columns:
                features['memory_cpu_interaction'] = features['memory_usage'] * features['cpu_usage']
            
            if 'connection_count' in features.columns and 'message_rate' in features.columns:
                features['connection_message_interaction'] = features['connection_count'] * features['message_rate']
            
            # Fill missing values
            features = features.fillna(features.median())
            
            # Handle infinite values
            features = features.replace([np.inf, -np.inf], np.nan)
            features = features.fillna(features.median())
            
            return features
            
        except Exception as e:
            logger.error(f"Error preparing features: {e}")
            raise
    
    def train_model(self, metric_name: str, features: pd.DataFrame, target: pd.Series) -> Dict:
        """
        Train a prediction model for a specific metric.
        
        Args:
            metric_name: Name of the metric to predict
            features: Feature matrix
            target: Target values
            
        Returns:
            Training results dictionary
        """
        try:
            logger.info(f"Training model for {metric_name}...")
            
            # Remove rows with missing target values
            valid_indices = ~target.isna()
            X = features[valid_indices]
            y = target[valid_indices]
            
            if len(X) == 0:
                raise ValueError(f"No valid data for {metric_name}")
            
            # Split data for validation
            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42
            )
            
            # Scale features
            scaler = StandardScaler()
            X_train_scaled = scaler.fit_transform(X_train)
            X_test_scaled = scaler.transform(X_test)
            
            # Train multiple models and select the best one
            models = {
                'random_forest': RandomForestRegressor(
                    n_estimators=100,
                    max_depth=10,
                    random_state=42
                ),
                'gradient_boosting': GradientBoostingRegressor(
                    n_estimators=100,
                    max_depth=6,
                    random_state=42
                ),
                'linear_regression': LinearRegression()
            }
            
            best_model = None
            best_score = -np.inf
            best_model_name = None
            
            for model_name, model in models.items():
                # Train model
                model.fit(X_train_scaled, y_train)
                
                # Evaluate model
                y_pred = model.predict(X_test_scaled)
                score = r2_score(y_test, y_pred)
                
                logger.info(f"{model_name} R² score: {score:.4f}")
                
                if score > best_score:
                    best_score = score
                    best_model = model
                    best_model_name = model_name
            
            # Store the best model
            self.models[metric_name] = best_model
            self.scalers[metric_name] = scaler
            
            # Calculate additional metrics
            y_pred = best_model.predict(X_test_scaled)
            mse = mean_squared_error(y_test, y_pred)
            mae = mean_absolute_error(y_test, y_pred)
            
            # Cross-validation score
            cv_scores = cross_val_score(best_model, X_train_scaled, y_train, cv=5)
            
            logger.info(f"Best model for {metric_name}: {best_model_name}")
            logger.info(f"R² score: {best_score:.4f}")
            logger.info(f"MSE: {mse:.4f}")
            logger.info(f"MAE: {mae:.4f}")
            logger.info(f"CV score: {cv_scores.mean():.4f} (+/- {cv_scores.std() * 2:.4f})")
            
            return {
                'metric': metric_name,
                'model_name': best_model_name,
                'r2_score': float(best_score),
                'mse': float(mse),
                'mae': float(mae),
                'cv_score_mean': float(cv_scores.mean()),
                'cv_score_std': float(cv_scores.std())
            }
            
        except Exception as e:
            logger.error(f"Error training model for {metric_name}: {e}")
            return {
                'metric': metric_name,
                'status': 'error',
                'error': str(e)
            }
    
    def train_all_models(self, historical_data: pd.DataFrame) -> Dict:
        """
        Train prediction models for all target metrics.
        
        Args:
            historical_data: Historical RabbitMQ metrics data
            
        Returns:
            Training results dictionary
        """
        try:
            logger.info("Starting performance prediction model training...")
            
            # Prepare features
            features = self.prepare_features(historical_data)
            
            # Ensure we have all required columns
            missing_columns = set(self.feature_columns) - set(features.columns)
            if missing_columns:
                logger.warning(f"Missing columns: {missing_columns}")
                # Add missing columns with default values
                for col in missing_columns:
                    features[col] = 0
            
            # Select feature columns
            feature_matrix = features[self.feature_columns]
            
            # Train models for each target metric
            training_results = {}
            for metric in self.target_metrics:
                if metric in historical_data.columns:
                    result = self.train_model(metric, feature_matrix, historical_data[metric])
                    training_results[metric] = result
                else:
                    logger.warning(f"Target metric {metric} not found in data")
            
            self.is_trained = True
            
            logger.info("Performance prediction model training completed!")
            
            return {
                'status': 'success',
                'trained_models': list(training_results.keys()),
                'results': training_results
            }
            
        except Exception as e:
            logger.error(f"Training failed: {e}")
            return {
                'status': 'error',
                'error': str(e)
            }
    
    def predict(self, current_data: pd.DataFrame, hours_ahead: int = None) -> Dict:
        """
        Predict future performance metrics.
        
        Args:
            current_data: Current RabbitMQ metrics data
            hours_ahead: Number of hours to predict ahead
            
        Returns:
            Prediction results dictionary
        """
        if not self.is_trained:
            raise ValueError("Models must be trained first")
        
        if hours_ahead is None:
            hours_ahead = self.prediction_horizon
        
        try:
            # Prepare features
            features = self.prepare_features(current_data)
            
            # Ensure we have all required columns
            missing_columns = set(self.feature_columns) - set(features.columns)
            for col in missing_columns:
                features[col] = 0
            
            # Select feature columns
            feature_matrix = features[self.feature_columns]
            
            # Make predictions for each metric
            predictions = {}
            for metric in self.target_metrics:
                if metric in self.models:
                    # Scale features
                    scaled_features = self.scalers[metric].transform(feature_matrix)
                    
                    # Make prediction
                    prediction = self.models[metric].predict(scaled_features)
                    predictions[metric] = float(prediction[0])
                else:
                    logger.warning(f"No model available for {metric}")
            
            # Add prediction metadata
            results = {
                'timestamp': datetime.now().isoformat(),
                'prediction_horizon_hours': hours_ahead,
                'predictions': predictions,
                'confidence_scores': self._calculate_confidence_scores(predictions),
                'recommendations': self._generate_recommendations(predictions)
            }
            
            return results
            
        except Exception as e:
            logger.error(f"Prediction failed: {e}")
            return {
                'status': 'error',
                'error': str(e)
            }
    
    def _calculate_confidence_scores(self, predictions: Dict) -> Dict:
        """
        Calculate confidence scores for predictions.
        
        Args:
            predictions: Dictionary of predictions
            
        Returns:
            Dictionary of confidence scores
        """
        confidence_scores = {}
        
        for metric, value in predictions.items():
            # Simple confidence calculation based on value ranges
            if metric == 'memory_usage':
                # Higher confidence for values in normal range (0.3-0.7)
                if 0.3 <= value <= 0.7:
                    confidence = 0.9
                elif 0.1 <= value <= 0.9:
                    confidence = 0.7
                else:
                    confidence = 0.5
            elif metric == 'cpu_usage':
                if 0.2 <= value <= 0.8:
                    confidence = 0.9
                elif 0.1 <= value <= 0.9:
                    confidence = 0.7
                else:
                    confidence = 0.5
            elif metric == 'queue_depth':
                if 100 <= value <= 10000:
                    confidence = 0.9
                elif 10 <= value <= 100000:
                    confidence = 0.7
                else:
                    confidence = 0.5
            else:
                confidence = 0.8  # Default confidence
            
            confidence_scores[metric] = confidence
        
        return confidence_scores
    
    def _generate_recommendations(self, predictions: Dict) -> List[str]:
        """
        Generate recommendations based on predictions.
        
        Args:
            predictions: Dictionary of predictions
            
        Returns:
            List of recommendations
        """
        recommendations = []
        
        # Memory usage recommendations
        if predictions.get('memory_usage', 0) > 0.8:
            recommendations.append("High memory usage predicted. Consider scaling memory or optimizing queue configurations.")
        
        # CPU usage recommendations
        if predictions.get('cpu_usage', 0) > 0.8:
            recommendations.append("High CPU usage predicted. Consider scaling CPU resources or optimizing message processing.")
        
        # Queue depth recommendations
        if predictions.get('queue_depth', 0) > 10000:
            recommendations.append("High queue depth predicted. Consider adding consumers or scaling nodes.")
        
        # Connection count recommendations
        if predictions.get('connection_count', 0) > 1000:
            recommendations.append("High connection count predicted. Monitor for connection leaks or consider connection pooling.")
        
        # Error rate recommendations
        if predictions.get('error_rate', 0) > 0.05:
            recommendations.append("High error rate predicted. Investigate potential issues and consider implementing retry mechanisms.")
        
        # Message rate recommendations
        if predictions.get('message_rate', 0) > 1000:
            recommendations.append("High message rate predicted. Ensure adequate resources and consider load balancing.")
        
        return recommendations
    
    def save_models(self, filepath: str) -> bool:
        """
        Save all trained models to disk.
        
        Args:
            filepath: Path to save the models
            
        Returns:
            True if successful, False otherwise
        """
        try:
            model_data = {
                'models': self.models,
                'scalers': self.scalers,
                'target_metrics': self.target_metrics,
                'feature_columns': self.feature_columns,
                'prediction_horizon': self.prediction_horizon,
                'is_trained': self.is_trained
            }
            
            joblib.dump(model_data, filepath)
            logger.info(f"Models saved to {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to save models: {e}")
            return False
    
    def load_models(self, filepath: str) -> bool:
        """
        Load trained models from disk.
        
        Args:
            filepath: Path to load the models from
            
        Returns:
            True if successful, False otherwise
        """
        try:
            model_data = joblib.load(filepath)
            
            self.models = model_data['models']
            self.scalers = model_data['scalers']
            self.target_metrics = model_data['target_metrics']
            self.feature_columns = model_data['feature_columns']
            self.prediction_horizon = model_data['prediction_horizon']
            self.is_trained = model_data['is_trained']
            
            logger.info(f"Models loaded from {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load models: {e}")
            return False

def main():
    """
    Main function for training and testing the performance prediction model.
    """
    # Configuration
    MODEL_PATH = "/tmp/rabbitmq_performance_models.pkl"
    
    # Initialize predictor
    predictor = PerformancePredictor(prediction_horizon=24)
    
    # Generate synthetic historical data for demonstration
    logger.info("Generating synthetic historical data...")
    
    # Create time series data
    dates = pd.date_range(start='2024-01-01', end='2024-01-31', freq='H')
    n_samples = len(dates)
    
    # Generate synthetic metrics with realistic patterns
    np.random.seed(42)
    
    historical_data = pd.DataFrame({
        'timestamp': dates,
        'memory_usage': np.random.beta(2, 5, n_samples) + 0.1,
        'disk_usage': np.random.beta(2, 5, n_samples) + 0.1,
        'connection_count': np.random.poisson(100, n_samples),
        'channel_count': np.random.poisson(200, n_samples),
        'queue_depth': np.random.poisson(1000, n_samples),
        'message_rate': np.random.exponential(10, n_samples),
        'cpu_usage': np.random.beta(2, 5, n_samples) + 0.1,
        'network_io': np.random.exponential(1000, n_samples),
        'error_rate': np.random.beta(1, 10, n_samples),
        'consumer_count': np.random.poisson(50, n_samples),
        'exchange_count': np.random.poisson(10, n_samples),
        'vhost_count': np.random.poisson(5, n_samples)
    })
    
    # Add some realistic patterns
    historical_data['memory_usage'] += 0.1 * np.sin(2 * np.pi * historical_data.index / 24)  # Daily pattern
    historical_data['cpu_usage'] += 0.05 * np.sin(2 * np.pi * historical_data.index / 168)  # Weekly pattern
    historical_data['message_rate'] += 20 * np.sin(2 * np.pi * historical_data.index / 24)  # Daily pattern
    
    # Ensure values are within valid ranges
    historical_data['memory_usage'] = np.clip(historical_data['memory_usage'], 0, 1)
    historical_data['cpu_usage'] = np.clip(historical_data['cpu_usage'], 0, 1)
    historical_data['disk_usage'] = np.clip(historical_data['disk_usage'], 0, 1)
    historical_data['error_rate'] = np.clip(historical_data['error_rate'], 0, 1)
    
    # Train the models
    logger.info("Training performance prediction models...")
    training_results = predictor.train_all_models(historical_data)
    logger.info(f"Training results: {training_results}")
    
    # Save the models
    predictor.save_models(MODEL_PATH)
    
    # Test the models
    logger.info("Testing performance prediction...")
    test_data = historical_data.tail(1)  # Use last sample for testing
    predictions = predictor.predict(test_data)
    logger.info(f"Prediction results: {predictions}")
    
    logger.info("Performance prediction model training and testing completed!")

if __name__ == "__main__":
    main()
