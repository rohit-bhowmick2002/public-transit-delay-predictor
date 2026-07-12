import os
import pickle
import pandas as pd
import numpy as np
from datetime import datetime

# Import scikit-learn algorithms and metrics
from sklearn.ensemble import HistGradientBoostingRegressor, HistGradientBoostingClassifier
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score

# Custom modules
from src.preprocessing import load_and_merge_data
from src.features import engineer_features

def run_training_pipeline():
    print("--- STARTING MODEL TRAINING PIPELINE ---")
    
    # 1. Load Data
    df_raw = load_and_merge_data(limit=300000)
    
    # Add trip_id back since features needs it for lag computation
    # It is extracted in load_and_merge_data but let's make sure it's present
    # (Checking preprocessing.py shows trip_id is in the SELECT list)
    
    # 2. Feature Engineering
    df = engineer_features(df_raw)
    
    # 3. Temporal Train-Test Split (Standard Industry Best Practice)
    # Train on first 80% of dates, test on last 20% of dates
    print("Performing dynamic temporal train-test split (80% Train, 20% Test)...")
    df = df.sort_values(by='scheduled_arrival').reset_index(drop=True)
    split_idx = int(len(df) * 0.8)
    
    train_df = df.iloc[:split_idx].copy()
    test_df = df.iloc[split_idx:].copy()
    
    print(f"Train Set Shape: {train_df.shape} (Dates: {train_df['scheduled_arrival'].min()} to {train_df['scheduled_arrival'].max()})")
    print(f"Test Set Shape: {test_df.shape} (Dates: {test_df['scheduled_arrival'].min()} to {test_df['scheduled_arrival'].max()})")
    
    # Define features for training
    features_cols = [
        'stop_sequence', 'temperature', 'rainfall', 'humidity', 'wind_speed', 'visibility',
        'congestion_score', 'road_closure_flag', 'accident_report_count', 
        'holiday_flag', 'weekend_flag', 'hour', 'weekday', 'month', 'is_rush_hour', 
        'is_heavy_rain', 'is_low_visibility', 'lag_1_delay', 
        'route_encoded', 'stop_encoded', 'weather_encoded', 'traffic_encoded'
    ]
    
    X_train = train_df[features_cols]
    y_train_reg = train_df['delay_minutes']
    y_train_clf = train_df['is_delayed']
    
    X_test = test_df[features_cols]
    y_test_reg = test_df['delay_minutes']
    y_test_clf = test_df['is_delayed']
    
    # 4. Train Regression Model (HistGradientBoostingRegressor)
    print("\nTraining Regression Model (HistGradientBoostingRegressor) to predict Delay Minutes...")
    reg_model = HistGradientBoostingRegressor(max_iter=100, learning_rate=0.1, random_state=42)
    reg_model.fit(X_train, y_train_reg)
    
    # Evaluate Regressor
    y_pred_reg = reg_model.predict(X_test)
    mae = mean_absolute_error(y_test_reg, y_pred_reg)
    rmse = np.sqrt(mean_squared_error(y_test_reg, y_pred_reg))
    r2 = r2_score(y_test_reg, y_pred_reg)
    
    print("\n--- REGRESSION MODEL METRICS (TEST SET) ---")
    print(f"Mean Absolute Error (MAE): {mae:.3f} minutes")
    print(f"Root Mean Squared Error (RMSE): {rmse:.3f} minutes")
    print(f"R² Score: {r2:.3f}")
    
    # 5. Train Classification Model (HistGradientBoostingClassifier)
    print("\nTraining Classification Model (HistGradientBoostingClassifier) to predict Binary Delay (>10 mins)...")
    clf_model = HistGradientBoostingClassifier(max_iter=100, learning_rate=0.1, random_state=42)
    clf_model.fit(X_train, y_train_clf)
    
    # Evaluate Classifier
    y_pred_clf = clf_model.predict(X_test)
    y_prob_clf = clf_model.predict_proba(X_test)[:, 1]
    
    acc = accuracy_score(y_test_clf, y_pred_clf)
    prec = precision_score(y_test_clf, y_pred_clf)
    rec = recall_score(y_test_clf, y_pred_clf)
    f1 = f1_score(y_test_clf, y_pred_clf)
    auc = roc_auc_score(y_test_clf, y_prob_clf)
    
    print("\n--- CLASSIFICATION MODEL METRICS (TEST SET) ---")
    print(f"Accuracy:  {acc:.3f}")
    print(f"Precision: {prec:.3f}")
    print(f"Recall:    {rec:.3f}")
    print(f"F1 Score:  {f1:.3f}")
    print(f"ROC-AUC:   {auc:.3f}")
    
    # 6. Save Models and Metadata
    print("\nSaving trained models & metadata to models/...")
    os.makedirs("models", exist_ok=True)
    
    with open("models/regressor_model.pkl", "wb") as f:
        pickle.dump(reg_model, f)
        
    with open("models/classifier_model.pkl", "wb") as f:
        pickle.dump(clf_model, f)
        
    # Save a metadata dictionary for mapping categoricals in app/
    metadata = {
        'features': features_cols,
        'route_mapping': dict(enumerate(df_raw['route_id'].astype('category').cat.categories)),
        'stop_mapping': dict(enumerate(df_raw['stop_id'].astype('category').cat.categories)),
        'weather_mapping': dict(enumerate(df_raw['weather_condition'].astype('category').cat.categories)),
        'traffic_mapping': dict(enumerate(df_raw['traffic_level'].astype('category').cat.categories))
    }
    
    with open("models/metadata.pkl", "wb") as f:
        pickle.dump(metadata, f)
        
    print("Training pipeline finished successfully! Models saved.")
    
    # Create simple performance reports inside reports/
    with open("reports/model_report.md", "w") as f:
        f.write(f"""# Model Evaluation Report

This report summarizes the performance of the predictive modeling engine for Public Transport Delays.

## 1. Dataset Split
- **Training Set (Jan-Sep 2025)**: {len(X_train):,} rows
- **Test Set (Oct-Dec 2025)**: {len(X_test):,} rows

## 2. Regression Performance (Predicting delay in minutes)
- **Model**: HistGradientBoostingRegressor (Gradient Boosting Ensembles)
- **Mean Absolute Error (MAE)**: {mae:.3f} minutes
- **Root Mean Squared Error (RMSE)**: {rmse:.3f} minutes
- **R² Score**: {r2:.3f}

## 3. Classification Performance (Predicting Delay > 10 minutes)
- **Model**: HistGradientBoostingClassifier (Gradient Boosting Classifier)
- **Accuracy**: {acc:.3f}
- **Precision**: {prec:.3f}
- **Recall**: {rec:.3f}
- **F1 Score**: {f1:.3f}
- **ROC-AUC**: {auc:.3f}
""")
    print("Model report saved to reports/model_report.md.")

if __name__ == "__main__":
    run_training_pipeline()
