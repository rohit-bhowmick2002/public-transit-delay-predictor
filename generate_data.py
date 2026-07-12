import os
import sqlite3
import random
from datetime import datetime, timedelta
import math
from collections import defaultdict

print("Starting 1M-Row Realistic Transit Database Generation...")

# Create directories
os.makedirs("data/raw", exist_ok=True)
os.makedirs("data/processed", exist_ok=True)
os.makedirs("sql", exist_ok=True)
os.makedirs("src", exist_ok=True)
os.makedirs("notebooks", exist_ok=True)
os.makedirs("models", exist_ok=True)
os.makedirs("app", exist_ok=True)
os.makedirs("dashboard", exist_ok=True)
os.makedirs("reports", exist_ok=True)
os.makedirs("images", exist_ok=True)

db_path = "data/transit_data.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Enable write-ahead logging for maximum performance
cursor.execute("PRAGMA journal_mode=WAL;")
cursor.execute("PRAGMA synchronous=OFF;")

# Create database tables
cursor.execute("DROP TABLE IF EXISTS dim_holidays;")
cursor.execute("DROP TABLE IF EXISTS dim_weather;")
cursor.execute("DROP TABLE IF EXISTS dim_events;")
cursor.execute("DROP TABLE IF EXISTS dim_traffic;")
cursor.execute("DROP TABLE IF EXISTS fact_transit_trips;")

# 1. Create dim_holidays
cursor.execute("""
CREATE TABLE dim_holidays (
    date TEXT PRIMARY KEY,
    holiday_flag INTEGER,
    festival_name TEXT,
    weekend_flag INTEGER
);
""")

# 2. Create dim_weather
cursor.execute("""
CREATE TABLE dim_weather (
    timestamp TEXT PRIMARY KEY,
    temperature REAL,
    rainfall REAL,
    humidity INTEGER,
    wind_speed REAL,
    visibility REAL,
    weather_condition TEXT
);
""")

# 3. Create dim_events
cursor.execute("""
CREATE TABLE dim_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_name TEXT,
    event_type TEXT,
    venue_latitude REAL,
    venue_longitude REAL,
    crowd_size INTEGER,
    start_time TEXT,
    end_time TEXT
);
""")

# 4. Create dim_traffic
cursor.execute("""
CREATE TABLE dim_traffic (
    timestamp TEXT,
    sector_id INTEGER,
    traffic_level TEXT,
    congestion_score REAL,
    road_closure_flag INTEGER,
    accident_report_count INTEGER,
    PRIMARY KEY (timestamp, sector_id)
);
""")

# 5. Create fact_transit_trips
cursor.execute("""
CREATE TABLE fact_transit_trips (
    trip_id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_time TEXT,
    route_id TEXT,
    bus_id TEXT,
    stop_id TEXT,
    stop_sequence INTEGER,
    scheduled_arrival TEXT,
    actual_arrival TEXT,
    delay_minutes REAL,
    sector_id INTEGER,
    FOREIGN KEY(date_time) REFERENCES dim_weather(timestamp),
    FOREIGN KEY(date_time, sector_id) REFERENCES dim_traffic(timestamp, sector_id)
);
""")

conn.commit()

# --- POPULATE DIMENSION TABLES ---
print("Populating dimension tables...")

start_date = datetime(2025, 1, 1)
end_date = datetime(2025, 12, 31)
total_days = (end_date - start_date).days + 1

# Generate dim_holidays
holidays_data = []
festivals = {
    "2025-01-01": "New Year's Day",
    "2025-01-26": "Republic Day",
    "2025-03-14": "Holi",
    "2025-08-15": "Independence Day",
    "2025-10-02": "Gandhi Jayanti",
    "2025-10-20": "Diwali",
    "2025-12-25": "Christmas"
}

for i in range(total_days):
    curr_date = start_date + timedelta(days=i)
    date_str = curr_date.strftime("%Y-%m-%d")
    is_weekend = 1 if curr_date.weekday() >= 5 else 0
    fest_name = festivals.get(date_str, "None")
    is_holiday = 1 if fest_name != "None" or is_weekend == 1 else 0
    holidays_data.append((date_str, is_holiday, fest_name, is_weekend))

cursor.executemany("INSERT INTO dim_holidays VALUES (?,?,?,?)", holidays_data)
conn.commit()

# Generate dim_weather & dim_traffic (Hourly for 2025)
weather_data = []
traffic_data = []
num_sectors = 5

for i in range(total_days * 24):
    curr_hour = start_date + timedelta(hours=i)
    time_str = curr_hour.strftime("%Y-%m-%d %H:00:00")
    
    # Weather Simulation
    month = curr_hour.month
    hour = curr_hour.hour
    
    # Seasonal temperatures
    if month in [12, 1, 2]: # Winter
        base_temp = 15.0
    elif month in [3, 4, 5]: # Spring/Summer
        base_temp = 32.0
    elif month in [6, 7, 8, 9]: # Monsoon/Wet
        base_temp = 28.0
    else: # Autumn
        base_temp = 22.0
        
    temp = base_temp + 5 * math.sin(2 * math.pi * (hour - 6) / 24) + random.uniform(-3, 3)
    
    # Rainfall probability
    rain_prob = 0.45 if month in [6, 7, 8, 9] else 0.05
    rainfall = round(random.expovariate(1.0 / 3.0), 2) if random.random() < rain_prob else 0.0
    
    # Humidity
    humidity = random.randint(70, 100) if rainfall > 0 else random.randint(40, 80)
    
    # Visibility & Condition
    wind_speed = round(random.uniform(5.0, 30.0), 1)
    if rainfall > 5.0:
        visibility = round(random.uniform(1.0, 4.0), 1)
        condition = "Heavy Rain"
    elif rainfall > 0:
        visibility = round(random.uniform(4.0, 8.0), 1)
        condition = "Light Rain"
    elif temp < 10 and humidity > 85:
        visibility = round(random.uniform(0.5, 2.0), 1)
        condition = "Foggy"
    else:
        visibility = round(random.uniform(8.0, 12.0), 1)
        condition = "Clear"
        
    weather_data.append((time_str, round(temp, 1), rainfall, humidity, wind_speed, visibility, condition))
    
    # Traffic Simulation for 5 Sectors
    for sector in range(1, num_sectors + 1):
        # Peak hour calculations
        is_rush = 1 if (7 <= hour <= 9) or (17 <= hour <= 19) else 0
        is_weekend = 1 if curr_hour.weekday() >= 5 else 0
        
        base_cong = 0.6 if is_rush else 0.2
        if is_weekend:
            base_cong *= 0.6
            
        congestion = base_cong + random.uniform(0.0, 0.3)
        if rainfall > 5.0:
            congestion += 0.2
            
        congestion = min(1.0, max(0.0, round(congestion, 2)))
        
        if congestion > 0.75:
            traffic_lvl = "Heavy"
        elif congestion > 0.4:
            traffic_lvl = "Medium"
        else:
            traffic_lvl = "Low"
            
        road_closure = 1 if random.random() < 0.02 else 0
        accidents = random.randint(1, 3) if (congestion > 0.7 and random.random() < 0.2) else 0
        
        traffic_data.append((time_str, sector, traffic_lvl, congestion, road_closure, accidents))

cursor.executemany("INSERT INTO dim_weather VALUES (?,?,?,?,?,?,?)", weather_data)
cursor.executemany("INSERT INTO dim_traffic VALUES (?,?,?,?,?,?)", traffic_data)
conn.commit()

# Generate dim_events (~250 local events)
events_data = []
event_types = ["Sports Match", "Music Concert", "Political Rally", "Festival Parade", "Exhibition"]
venues = [
    ("Stadium Arena", 22.5726, 88.3639),
    ("City Concert Hall", 22.5411, 88.3432),
    ("Central Park Grounds", 22.5834, 88.4124),
    ("Exposition Center", 22.6120, 88.4320)
]

for ev_idx in range(250):
    ev_day = start_date + timedelta(days=random.randint(0, total_days - 1))
    ev_hour = random.randint(14, 19)
    ev_start = ev_day.replace(hour=ev_hour, minute=0)
    ev_end = ev_start + timedelta(hours=random.randint(3, 5))
    
    venue = random.choice(venues)
    crowd = random.randint(5000, 60000)
    ev_type = random.choice(event_types)
    ev_name = f"{venue[0]} {ev_type} {ev_idx}"
    
    events_data.append((
        ev_name, ev_type, venue[1], venue[2], crowd,
        ev_start.strftime("%Y-%m-%d %H:00:00"),
        ev_end.strftime("%Y-%m-%d %H:00:00")
    ))

cursor.executemany("""
INSERT INTO dim_events (event_name, event_type, venue_latitude, venue_longitude, crowd_size, start_time, end_time) 
VALUES (?,?,?,?,?,?,?)
""", events_data)
conn.commit()

print("Populating 1M-Row fact_transit_trips table (Highly Optimized)...")

# Cache some lookups to avoid slow database joins inside simulation loop
cursor.execute("SELECT timestamp, rainfall, visibility FROM dim_weather")
weather_lookup = {row[0]: (row[1], row[2]) for row in cursor.fetchall()}

cursor.execute("SELECT timestamp, sector_id, congestion_score, road_closure_flag FROM dim_traffic")
traffic_lookup = {}
for row in cursor.fetchall():
    traffic_lookup[(row[0], row[1])] = (row[2], row[3])

cursor.execute("SELECT date, holiday_flag FROM dim_holidays")
holiday_lookup = {row[0]: row[1] for row in cursor.fetchall()}

cursor.execute("SELECT start_time, end_time, venue_latitude, venue_longitude, crowd_size FROM dim_events")
events_list = cursor.fetchall()

# --- OPTIMIZATION: Index events by date string to avoid O(N*M) nested loops ---
events_by_date = defaultdict(list)
for ev in events_list:
    # ev[0] is start_time, ev[1] is end_time, etc.
    start_dt = datetime.strptime(ev[0], "%Y-%m-%d %H:%M:%S")
    end_dt = datetime.strptime(ev[1], "%Y-%m-%d %H:%M:%S")
    curr_dt = start_dt.date()
    while curr_dt <= end_dt.date():
        events_by_date[curr_dt.strftime("%Y-%m-%d")].append(ev)
        curr_dt += timedelta(days=1)

routes = [f"Route_{r}" for r in range(1, 21)]
bus_pool = [f"Bus_{b}" for b in range(1, 101)]
stops = [f"Stop_{s}" for s in range(1, 11)]

# Sector allocation for each route to link traffic
route_sectors = {f"Route_{r}": (r % num_sectors) + 1 for r in range(1, 21)}

# Coordinates for each stop to map events (centered around city center)
stop_coords = {}
for s_idx, stop in enumerate(stops):
    stop_coords[stop] = (22.5726 + 0.01 * s_idx, 88.3639 + 0.012 * s_idx)

trips_completed = 0
chunk_size = 5000  # 5,000 trips = 50,000 rows per insert transaction

print("Generating 100,000 trips (10 stops each = 1,000,000 records)...")

while trips_completed < 100000:
    chunk_trips = []
    for _ in range(chunk_size):
        route = random.choice(routes)
        bus = random.choice(bus_pool)
        sector = route_sectors[route]
        
        # Pick a random scheduled departure time in 2025
        rand_hour_idx = random.randint(0, total_days * 24 - 12) # Leave buffer at end
        trip_start_time = start_date + timedelta(hours=rand_hour_idx, minutes=random.randint(0, 45))
        
        accumulated_delay = 0.0
        
        for stop_seq in range(1, 11):
            stop = stops[stop_seq - 1]
            stop_lat, stop_lon = stop_coords[stop]
            
            # Scheduled time for this stop (spaced by 15 mins)
            stop_sched = trip_start_time + timedelta(minutes=(stop_seq - 1) * 15)
            sched_time_str = stop_sched.strftime("%Y-%m-%d %H:%M:00")
            sched_hour_str = stop_sched.strftime("%Y-%m-%d %H:00:00")
            date_str = stop_sched.strftime("%Y-%m-%d")
            
            # 1. Base Delay (Minutes)
            delay = random.uniform(0.1, 1.5)
            
            # 2. Weather Impact
            weather = weather_lookup.get(sched_hour_str, (0.0, 10.0))
            rain, vis = weather[0], weather[1]
            if rain > 5.0:
                delay += random.uniform(2.0, 5.0)
            elif rain > 0:
                delay += random.uniform(0.5, 1.5)
            if vis < 2.0:
                delay += random.uniform(1.5, 4.0)
                
            # 3. Traffic Impact
            traffic = traffic_lookup.get((sched_hour_str, sector), (0.2, 0))
            cong, closure = traffic[0], traffic[1]
            
            # Rush Hour check
            hour_val = stop_sched.hour
            is_rush = 1 if (7 <= hour_val <= 9) or (17 <= hour_val <= 19) else 0
            
            delay += cong * 8.0
            if is_rush:
                delay += random.uniform(1.5, 4.5)
            if closure == 1:
                delay += random.uniform(5.0, 15.0)
                
            # 4. Holiday & Festival Impact
            is_hol = holiday_lookup.get(date_str, 0)
            if is_hol == 1:
                delay -= 1.0 # Less general traffic on weekends/holidays
                
            # 5. Event Impact (Geospatial lookup - OPTIMIZED)
            day_events = events_by_date.get(date_str, [])
            for ev in day_events:
                ev_start = datetime.strptime(ev[0], "%Y-%m-%d %H:%M:%S")
                ev_end = datetime.strptime(ev[1], "%Y-%m-%d %H:%M:%S")
                
                # Check if event is active during scheduled arrival (or up to 2 hours before / 1 hour after)
                if (ev_start - timedelta(hours=2)) <= stop_sched <= (ev_end + timedelta(hours=1)):
                    ev_lat, ev_lon, crowd = ev[2], ev[3], ev[4]
                    
                    # Haversine distance
                    dlat = math.radians(ev_lat - stop_lat)
                    dlon = math.radians(ev_lon - stop_lon)
                    a = math.sin(dlat/2)**2 + math.cos(math.radians(stop_lat)) * math.cos(math.radians(ev_lat)) * math.sin(dlon/2)**2
                    dist = 2 * 6371 * math.asin(math.sqrt(a)) # KM
                    
                    if dist < 2.5: # Venue within 2.5 KM
                        event_congestion = (crowd / 10000.0) / (dist + 0.5)
                        delay += round(random.uniform(1.0, 3.5) * event_congestion, 2)
                        break # Only process nearest active event to save speed
                        
            # 6. Propagation Delay (Bus bunching/accumulation)
            if stop_seq > 1:
                accumulated_delay = 0.7 * accumulated_delay + delay
            else:
                accumulated_delay = delay
                
            final_delay = max(0.0, round(accumulated_delay, 2))
            
            # Actual arrival time
            actual_arrival = stop_sched + timedelta(minutes=final_delay)
            actual_time_str = actual_arrival.strftime("%Y-%m-%d %H:%M:%S")
            
            chunk_trips.append((
                sched_hour_str, route, bus, stop, stop_seq, sched_time_str, actual_time_str, final_delay, sector
            ))
            
    cursor.executemany("""
    INSERT INTO fact_transit_trips (date_time, route_id, bus_id, stop_id, stop_sequence, scheduled_arrival, actual_arrival, delay_minutes, sector_id)
    VALUES (?,?,?,?,?,?,?,?,?)
    """, chunk_trips)
    conn.commit()
    
    trips_completed += chunk_size
    print(f"Generated {trips_completed * 10} / 1,000,000 rows...")

# Build Indexes to optimize SQL queries speed
print("Building SQL Indexes for high query performance...")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_fact_date_time ON fact_transit_trips(date_time);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_fact_route_id ON fact_transit_trips(route_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_fact_stop_id ON fact_transit_trips(stop_id);")
cursor.execute("CREATE INDEX IF NOT EXISTS idx_fact_delay ON fact_transit_trips(delay_minutes);")
conn.commit()

# Print statistics
cursor.execute("SELECT COUNT(*) FROM fact_transit_trips")
total_rows = cursor.fetchone()[0]
print(f"Successfully generated database at data/transit_data.db!")
print(f"Total Rows in fact_transit_trips: {total_rows:,}")

conn.close()
print("Data Generation Completed.")
