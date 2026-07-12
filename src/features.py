import pandas as pd
import numpy as np

def engineer_features(df):
    """
    Applies professional feature engineering techniques to the transit dataset.
    Features:
    - Temporal features (hour, day, weekday, rush hour)
    - Traffic-related indices
    - Weather-related indicators (extreme rain, visibility)
    - Route lag features (delay at previous stop sequence)
    """
    print("Beginning feature engineering...")
    
    # 1. Parse Scheduled Arrival to Datetime
    df['scheduled_arrival'] = pd.to_datetime(df['scheduled_arrival'])
    
    # 2. Extract Temporal Features
    df['hour'] = df['scheduled_arrival'].dt.hour
    df['day'] = df['scheduled_arrival'].dt.day
    df['weekday'] = df['scheduled_arrival'].dt.weekday
    df['month'] = df['scheduled_arrival'].dt.month
    df['is_weekend'] = (df['weekday'] >= 5).astype(int)
    
    # 3. Rush Hour Flag (07:30-09:30 and 16:30-19:30)
    # Since we have hour values, we can simplify to 7-9 and 17-19
    df['is_rush_hour'] = (((df['hour'] >= 7) & (df['hour'] <= 9)) | 
                          ((df['hour'] >= 17) & (df['hour'] <= 19))).astype(int)
    
    # 4. Weather Indicators
    df['is_heavy_rain'] = (df['rainfall'] > 5.0).astype(int)
    df['is_low_visibility'] = (df['visibility'] < 2.0).astype(int)
    
    # 5. Route Lag Features (Very powerful!)
    # Delay of the previous stop along the same trip
    print("Computing route lag features (delay at previous stop sequence)...")
    # Make sure we sort by trip_id and stop_sequence to shift correctly
    df = df.sort_values(by=['trip_id', 'stop_sequence']).reset_index(drop=True)
    df['lag_1_delay'] = df.groupby('trip_id')['delay_minutes'].shift(1).fillna(0.0)
    
    # 6. Target Variable for Classification
    df['is_delayed'] = (df['delay_minutes'] > 10.0).astype(int)
    
    # 7. Categorical Encoding (Convert high-cardinality items to integer codes for tree models)
    # We will encode route_id and stop_id as category codes
    df['route_encoded'] = df['route_id'].astype('category').cat.codes
    df['stop_encoded'] = df['stop_id'].astype('category').cat.codes
    df['weather_encoded'] = df['weather_condition'].astype('category').cat.codes
    df['traffic_encoded'] = df['traffic_level'].astype('category').cat.codes
    
    print(f"Feature engineering completed. Features shape: {df.shape}")
    return df

if __name__ == "__main__":
    from src.preprocessing import load_and_merge_data
    df = load_and_merge_data()
    # Test on a subset of 10,000 rows to make it fast for validation
    sample_df = df.head(10000)
    feature_df = engineer_features(sample_df)
    print(feature_df[['route_id', 'stop_sequence', 'delay_minutes', 'lag_1_delay', 'is_rush_hour']].head(12))
