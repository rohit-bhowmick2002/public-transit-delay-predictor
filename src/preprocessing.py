import pandas as pd
from src.database import execute_query

def load_and_merge_data(db_path="data/transit_data.db", limit=None):
    """
    Extracts data from SQLite using an optimized relational SQL join 
    and returns a consolidated pandas DataFrame for modeling.
    """
    print("Extracting and merging relational rows via SQL...")
    
    limit_clause = f"LIMIT {limit}" if limit else ""
    
    query = f"""
    SELECT 
        t.trip_id,
        t.route_id,
        t.bus_id,
        t.stop_id,
        t.stop_sequence,
        t.scheduled_arrival,
        t.delay_minutes,
        t.sector_id,
        w.temperature,
        w.rainfall,
        w.humidity,
        w.wind_speed,
        w.visibility,
        w.weather_condition,
        tf.traffic_level,
        tf.congestion_score,
        tf.road_closure_flag,
        tf.accident_report_count,
        h.holiday_flag,
        h.festival_name,
        h.weekend_flag
    FROM fact_transit_trips t
    JOIN dim_weather w ON t.date_time = w.timestamp
    JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
    JOIN dim_holidays h ON DATE(t.scheduled_arrival) = h.date
    ORDER BY t.scheduled_arrival ASC
    {limit_clause};
    """
    
    df = execute_query(query, db_path)
    print(f"Data successfully loaded. Shape: {df.shape}")
    return df

if __name__ == "__main__":
    df = load_and_merge_data()
    # Save a small sample to raw/ for testing/EDA purposes if needed
    df.head(1000).to_csv("data/raw/sample_transit_data.csv", index=False)
    print("Sample raw data saved to data/raw/sample_transit_data.csv.")
