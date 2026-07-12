# Model Evaluation Report

This report summarizes the performance of the predictive modeling engine for Public Transport Delays.

## 1. Dataset Split
- **Training Set (Jan-Sep 2025)**: 240,000 rows
- **Test Set (Oct-Dec 2025)**: 60,000 rows

## 2. Regression Performance (Predicting delay in minutes)
- **Model**: HistGradientBoostingRegressor (Gradient Boosting Ensembles)
- **Mean Absolute Error (MAE)**: 1.947 minutes
- **Root Mean Squared Error (RMSE)**: 3.399 minutes
- **R² Score**: 0.848

## 3. Classification Performance (Predicting Delay > 10 minutes)
- **Model**: HistGradientBoostingClassifier (Gradient Boosting Classifier)
- **Accuracy**: 0.898
- **Precision**: 0.922
- **Recall**: 0.889
- **F1 Score**: 0.905
- **ROC-AUC**: 0.962
