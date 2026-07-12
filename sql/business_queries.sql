-- ==============================================================================
-- SQL BUSINESS QUERIES FOR SMART PUBLIC TRANSPORT DELAY ANALYTICS
-- Database Engine: SQLite / PostgreSQL Compatible
-- File Path: sql/business_queries.sql
-- Description: 50 Structured SQL Queries ranging from basic KPIs to complex 
--              analytical window functions, CTEs, and multi-table joins.
-- ==============================================================================

-- ==========================================
-- CATEGORY 1: BASIC KPIS & NETWORK METRICS (1 - 10)
-- ==========================================

-- Query 1: Total Trips Recorded in the Network Fact Table
-- Purpose: Verify total volume of data ingested into the transit fact table.
SELECT COUNT(*) AS total_trips_recorded 
FROM fact_transit_trips;

-- Query 2: Overall Network Average Delay in Minutes
-- Purpose: Get a single baseline metric for overall bus performance across the entire year.
SELECT ROUND(AVG(delay_minutes), 2) AS network_avg_delay_minutes 
FROM fact_transit_trips;

-- Query 3: Maximum Recorded Delay in the Entire Dataset
-- Purpose: Identify the absolute worst-case delay scenario captured in the records.
SELECT ROUND(MAX(delay_minutes), 2) AS max_recorded_delay_minutes 
FROM fact_transit_trips;

-- Query 4: Total On-Time Trips Count (On-Time defined as Delay <= 5.0 Minutes)
-- Purpose: Calculate the total volume of service running on or close to schedule.
SELECT COUNT(*) AS on_time_trips_count 
FROM fact_transit_trips 
WHERE delay_minutes <= 5.0;

-- Query 5: Overall Network On-Time Performance (OTP) Percentage
-- Purpose: Calculate the percentage of total trips that arrived on time.
SELECT 
    ROUND(COUNT(CASE WHEN delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*), 2) AS overall_otp_percentage
FROM fact_transit_trips;

-- Query 6: Average Delay, Maximum Delay, and OTP% Grouped by Route
-- Purpose: Identify which specific bus lines suffer from the worst overall delays.
SELECT 
    route_id,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes,
    ROUND(MAX(delay_minutes), 2) AS max_delay_minutes,
    ROUND(COUNT(CASE WHEN delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*), 2) AS route_otp_pct
FROM fact_transit_trips
GROUP BY route_id
ORDER BY avg_delay_minutes DESC;

-- Query 7: Rank Routes by Average Delay using Window Functions
-- Purpose: Apply a competitive rank to each transit line from most to least delayed.
SELECT 
    route_id,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes,
    RANK() OVER (ORDER BY AVG(delay_minutes) DESC) as delay_rank
FROM fact_transit_trips
GROUP BY route_id;

-- Query 8: Top 10 Most Delayed Individual Stops in the Network
-- Purpose: Pinpoint physical transit stop locations causing severe schedule bottlenecks.
SELECT 
    stop_id,
    COUNT(*) AS stop_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes,
    ROUND(MAX(delay_minutes), 2) AS max_delay_minutes
FROM fact_transit_trips
GROUP BY stop_id
ORDER BY avg_delay_minutes DESC
LIMIT 10;

-- Query 9: Count of Severe Delays (> 15 Minutes) per Route
-- Purpose: Identify routes with a high frequency of extreme, disruptive delays.
SELECT 
    route_id,
    COUNT(*) AS severe_delays_count
FROM fact_transit_trips
WHERE delay_minutes > 15.0
GROUP BY route_id
ORDER BY severe_delays_count DESC;

-- Query 10: Count of Unique Active Vehicles (Buses) per Sector
-- Purpose: Monitor how fleet assets are distributed geographically across city sectors.
SELECT 
    sector_id,
    COUNT(DISTINCT bus_id) AS unique_buses_active
FROM fact_transit_trips
GROUP BY sector_id
ORDER BY sector_id;


-- ==========================================
-- CATEGORY 2: TEMPORAL & TREND ANALYTICS (11 - 20)
-- ==========================================

-- Query 11: Average Delay Grouped by Hour of Day (Uncovering Peak Rush Hours)
-- Purpose: Analyze the diurnal cycle of transit reliability.
SELECT 
    STRFTIME('%H', scheduled_arrival) AS hour_of_day,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Query 12: Average Delay Grouped by Day of Week
-- Purpose: Contrast weekday performance (commuter-heavy) with weekends.
-- Note: SQLite Sunday=0 to Saturday=6 or standard temporal strings.
SELECT 
    CASE CAST(STRFTIME('%w', scheduled_arrival) AS INTEGER)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_of_week,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*), 2) AS otp_percentage
FROM fact_transit_trips
GROUP BY STRFTIME('%w', scheduled_arrival)
ORDER BY STRFTIME('%w', scheduled_arrival);

-- Query 13: Average Delay and OTP% by Month (Seasonal Impact)
-- Purpose: Observe how delays evolve throughout the year (e.g., monsoon, winter).
SELECT 
    STRFTIME('%m', scheduled_arrival) AS month_num,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*), 2) AS otp_pct
FROM fact_transit_trips
GROUP BY month_num
ORDER BY month_num;

-- Query 14: Contrast Weekend vs Weekday Performance
-- Purpose: Check if schedule buffers need to vary between weekends and weekdays.
SELECT 
    h.weekend_flag,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN t.delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*), 2) AS otp_pct
FROM fact_transit_trips t
JOIN dim_holidays h ON DATE(t.scheduled_arrival) = h.date
GROUP BY h.weekend_flag;

-- Query 15: Identify the Worst Hour-Route Combination in the Network
-- Purpose: Find specific route timetables that are structurally flawed and always run late.
SELECT 
    route_id,
    STRFTIME('%H:00', scheduled_arrival) AS hour_slot,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips
GROUP BY route_id, hour_slot
HAVING COUNT(*) >= 50
ORDER BY avg_delay_minutes DESC
LIMIT 5;

-- Query 16: Rolling 7-Day Moving Average of Daily Delays
-- Purpose: Clean out daily spikes to see underlying long-term scheduling trends.
WITH DailyDelays AS (
    SELECT 
        DATE(scheduled_arrival) AS trip_date,
        AVG(delay_minutes) AS avg_delay
    FROM fact_transit_trips
    GROUP BY trip_date
)
SELECT 
    trip_date,
    ROUND(avg_delay, 2) AS daily_avg_delay,
    ROUND(AVG(avg_delay) OVER (
        ORDER BY trip_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_7day_avg_delay
FROM DailyDelays
LIMIT 30;

-- Query 17: Average Delay by Operational Shifts / Time Periods
-- Purpose: Analyze performance by shifts to help transit workforce scheduling.
SELECT 
    CASE 
        WHEN CAST(STRFTIME('%H', scheduled_arrival) AS INTEGER) BETWEEN 6 AND 9 THEN 'Morning Peak (06-09)'
        WHEN CAST(STRFTIME('%H', scheduled_arrival) AS INTEGER) BETWEEN 10 AND 15 THEN 'Midday Off-Peak (10-15)'
        WHEN CAST(STRFTIME('%H', scheduled_arrival) AS INTEGER) BETWEEN 16 AND 19 THEN 'Evening Peak (16-19)'
        WHEN CAST(STRFTIME('%H', scheduled_arrival) AS INTEGER) BETWEEN 20 AND 23 THEN 'Night Operations (20-23)'
        ELSE 'Overnight (00-05)'
    END AS shift_name,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips
GROUP BY shift_name
ORDER BY avg_delay_minutes DESC;

-- Query 18: Compare High-Heat Months vs Cold Months
-- Purpose: Quantify if high summers are more volatile than mild winters.
SELECT 
    CASE 
        WHEN STRFTIME('%m', scheduled_arrival) IN ('05', '06', '07') THEN 'Summer / High-Heat'
        WHEN STRFTIME('%m', scheduled_arrival) IN ('12', '01', '02') THEN 'Winter / Cold'
        ELSE 'Transitional Season'
    END AS climate_period,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips
GROUP BY climate_period;

-- Query 19: Find the Single Day with the Longest Average Transit Delay of the Year
-- Purpose: Identify dates of catastrophic city-wide gridlock.
SELECT 
    DATE(scheduled_arrival) AS trip_date,
    COUNT(*) AS total_trips,
    ROUND(AVG(delay_minutes), 2) AS daily_avg_delay,
    ROUND(SUM(delay_minutes), 2) AS cumulative_delay_minutes
FROM fact_transit_trips
GROUP BY trip_date
ORDER BY daily_avg_delay DESC
LIMIT 1;

-- Query 20: Monthly Delay Expansion & OTP Degradation Rate
-- Purpose: Calculate Month-over-Month changes in operational performance.
WITH MonthlyStats AS (
    SELECT 
        STRFTIME('%m', scheduled_arrival) AS month,
        AVG(delay_minutes) AS avg_delay
    FROM fact_transit_trips
    GROUP BY month
)
SELECT 
    month,
    ROUND(avg_delay, 2) AS avg_delay_minutes,
    ROUND(avg_delay - LAG(avg_delay, 1) OVER (ORDER BY month), 2) AS mom_delay_change_minutes
FROM MonthlyStats;


-- ==========================================
-- CATEGORY 3: WEATHER IMPACT ANALYTICS (21 - 30)
-- ==========================================

-- Query 21: Average Delay Under Different Classified Weather Conditions
-- Purpose: Prove statistical direct link between bad weather and late buses.
SELECT 
    w.weather_condition,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN t.delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(t.trip_id), 2) AS otp_pct
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY w.weather_condition
ORDER BY avg_delay_minutes DESC;

-- Query 22: Performance Metrics During Heavy Rain (Precipitation > 5.0mm) vs Clear Days
-- Purpose: Quantify the rain penalty on transit schedules.
SELECT 
    CASE WHEN w.rainfall > 5.0 THEN 'Heavy Rain (>5mm)' ELSE 'No/Light Rain' END AS rain_category,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN t.delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(t.trip_id), 2) AS otp_pct
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY rain_category;

-- Query 23: Average Delay Grouped by Visibility Bins
-- Purpose: Correlate visual range (e.g. fog, heavy rain blocks) with transit safety margins.
SELECT 
    CASE 
        WHEN w.visibility < 2.0 THEN 'Critical: Very Low Visibility (<2km)'
        WHEN w.visibility BETWEEN 2.0 AND 6.0 THEN 'Warning: Moderate Visibility (2-6km)'
        ELSE 'Normal: Good Visibility (>6km)'
    END AS visibility_range,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY visibility_range
ORDER BY avg_delay_minutes DESC;

-- Query 24: Percentage of Severe Delays (>15 mins) Occurring During Sub-Optimal Weather
-- Purpose: Identify the proportion of major delays caused by environmental factors.
WITH SevereTrips AS (
    SELECT t.trip_id, w.weather_condition
    FROM fact_transit_trips t
    JOIN dim_weather w ON t.date_time = w.timestamp
    WHERE t.delay_minutes > 15.0
)
SELECT 
    weather_condition,
    COUNT(*) AS severe_trips_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM SevereTrips), 2) AS share_of_all_severe_delays_pct
FROM SevereTrips
GROUP BY weather_condition
ORDER BY severe_trips_count DESC;

-- Query 25: Identify Routes Most Sensitive to Rain
-- Purpose: Find which bus routes experience the largest delay delta when it rains.
WITH RainPerformance AS (
    SELECT 
        t.route_id,
        AVG(CASE WHEN w.rainfall > 0.0 THEN t.delay_minutes END) AS avg_delay_wet,
        AVG(CASE WHEN w.rainfall = 0.0 THEN t.delay_minutes END) AS avg_delay_dry
    FROM fact_transit_trips t
    JOIN dim_weather w ON t.date_time = w.timestamp
    GROUP BY t.route_id
)
SELECT 
    route_id,
    ROUND(avg_delay_wet, 2) AS avg_delay_rainy_days,
    ROUND(avg_delay_dry, 2) AS avg_delay_dry_days,
    ROUND(avg_delay_wet - avg_delay_dry, 2) AS rain_penalty_minutes
FROM RainPerformance
ORDER BY rain_penalty_minutes DESC;

-- Query 26: Impact of High Temperatures (> 35°C) on Electric/Standard Bus Delays
-- Purpose: Check if vehicle components / highway stress at extreme temperatures causes delays.
SELECT 
    CASE WHEN w.temperature > 35.0 THEN 'Extreme Heat (>35C)' ELSE 'Moderate/Cool' END AS temperature_category,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY temperature_category;

-- Query 27: Impact of High Wind Speeds (> 25 km/h) on Delays
-- Purpose: Check if high wind restrictions cause route bottlenecks.
SELECT 
    CASE WHEN w.wind_speed > 25.0 THEN 'High Wind (>25 km/h)' ELSE 'Calm/Breezy' END AS wind_category,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY wind_category;

-- Query 28: Count of Trips Operating Under Extreme Weather (Rain > 10mm OR Visibility < 1km)
-- Purpose: Assess extreme weather coverage across the transit network.
SELECT 
    t.route_id,
    COUNT(*) AS extreme_weather_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_during_extremes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
WHERE w.rainfall > 10.0 OR w.visibility < 1.0
GROUP BY t.route_id
ORDER BY extreme_weather_trips DESC;

-- Query 29: Weather Distribution During the Top 1% of Worst Network Delays
-- Purpose: Discover if extreme delays are primarily meteorological or systemic.
WITH Threshold AS (
    SELECT delay_minutes 
    FROM fact_transit_trips 
    ORDER BY delay_minutes DESC 
    LIMIT 1 OFFSET (SELECT COUNT(*) / 100 FROM fact_transit_trips)
)
SELECT 
    w.weather_condition,
    COUNT(t.trip_id) AS total_trips_in_top_1_percent,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
WHERE t.delay_minutes >= (SELECT delay_minutes FROM Threshold)
GROUP BY w.weather_condition
ORDER BY total_trips_in_top_1_percent DESC;

-- Query 30: Combined Matrix of Weather Condition and Peak Hour Impact
-- Purpose: Identify compound risk zones where both bad weather and rush hours strike together.
SELECT 
    w.weather_condition,
    CASE WHEN CAST(STRFTIME('%H', t.scheduled_arrival) AS INTEGER) BETWEEN 7 AND 9 OR 
              CAST(STRFTIME('%H', t.scheduled_arrival) AS INTEGER) BETWEEN 17 AND 19 THEN 'Rush Hour' 
         ELSE 'Off-Peak' 
    END AS peak_status,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_weather w ON t.date_time = w.timestamp
GROUP BY w.weather_condition, peak_status
ORDER BY avg_delay_minutes DESC;


-- ==========================================
-- CATEGORY 4: EVENTS & HOLIDAYS IMPACT (31 - 40)
-- ==========================================

-- Query 31: List Large Events (> 30k Crowd) and Associated Average Nearby Sector Delays
-- Purpose: Highlight active scheduling changes required when major stadium crowds exit.
SELECT 
    e.event_name,
    e.event_type,
    e.crowd_size,
    t.sector_id,
    ROUND(AVG(t.delay_minutes), 2) AS avg_transit_delay_near_event
FROM fact_transit_trips t
JOIN dim_events e ON t.date_time BETWEEN e.start_time AND e.end_time
WHERE e.crowd_size >= 30000 AND t.sector_id = 3  -- Sector 3 has core sports venue mapping
GROUP BY e.event_name, e.event_type, e.crowd_size, t.sector_id
ORDER BY avg_transit_delay_near_event DESC;

-- Query 32: Contrast Stadium Arena Event Days vs Non-Event Days for Nearby Sectors
-- Purpose: Provide quantitative proof of event impact on transit schedules.
WITH EventDays AS (
    SELECT DISTINCT DATE(start_time) AS event_date 
    FROM dim_events 
    WHERE event_name LIKE '%Stadium%'
)
SELECT 
    CASE WHEN EventDays.event_date IS NOT NULL THEN 'Stadium Event Day' ELSE 'Non-Event Day' END AS day_category,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes,
    ROUND(COUNT(CASE WHEN t.delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(t.trip_id), 2) AS otp_pct
FROM fact_transit_trips t
LEFT JOIN EventDays ON DATE(t.scheduled_arrival) = EventDays.event_date
WHERE t.sector_id = 3
GROUP BY day_category;

-- Query 33: Delay Comparison Between National Holidays and Standard Days
-- Purpose: Quantify if transit performance scales significantly on national breaks.
SELECT 
    CASE WHEN h.holiday_flag = 1 AND h.weekend_flag = 0 THEN 'Public Holiday (Weekday)' 
         WHEN h.holiday_flag = 0 AND h.weekend_flag = 0 THEN 'Standard Weekday'
         ELSE 'Weekend' 
    END AS calendar_status,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_holidays h ON DATE(t.scheduled_arrival) = h.date
GROUP BY calendar_status;

-- Query 34: Top 5 Event Types causing the Highest Scheduling Distortions
-- Purpose: Provide city planners with event-specific transport demand adjustments.
SELECT 
    e.event_type,
    COUNT(DISTINCT e.event_id) AS event_occurrences,
    ROUND(AVG(t.delay_minutes), 2) AS avg_nearby_delay_minutes
FROM fact_transit_trips t
JOIN dim_events e ON t.date_time BETWEEN e.start_time AND e.end_time
GROUP BY e.event_type
ORDER BY avg_nearby_delay_minutes DESC;

-- Query 35: Specific Delay Analysis During Major Holidays / Festival Days
-- Purpose: Analyze seasonal cultural impacts (e.g. Diwali shopping vs Christmas breaks).
SELECT 
    h.festival_name,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_holidays h ON DATE(t.scheduled_arrival) = h.date
WHERE h.festival_name != 'None'
GROUP BY h.festival_name
ORDER BY avg_delay_minutes DESC;

-- Query 36: Delay Multiplier on Routes Passing Near Event Venues on Concert Days
-- Purpose: Compare delays on "Route_1" (Concert Route) vs non-event days.
SELECT 
    CASE WHEN e.event_id IS NOT NULL THEN 'Concert Active Nearby' ELSE 'No Active Concert' END AS concert_status,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
LEFT JOIN dim_events e ON t.date_time BETWEEN e.start_time AND e.end_time 
     AND e.event_type = 'Music Concert'
WHERE t.route_id = 'Route_1'
GROUP BY concert_status;

-- Query 37: Find the Single Event Associated with the Highest Individual Delay Spikes
-- Purpose: Track the most operational catastrophic event of the year.
SELECT 
    e.event_name,
    e.event_type,
    e.crowd_size,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_during_event,
    MAX(t.delay_minutes) AS absolute_peak_delay
FROM fact_transit_trips t
JOIN dim_events e ON t.date_time BETWEEN e.start_time AND e.end_time
GROUP BY e.event_name, e.event_type, e.crowd_size
ORDER BY avg_delay_during_event DESC
LIMIT 1;

-- Query 38: Pre-Event Build-Up Congestion (2 Hours Prior to Event Start)
-- Purpose: Highlight pre-event operational planning limits for arriving fans.
SELECT 
    e.event_name,
    ROUND(AVG(t.delay_minutes), 2) AS pre_event_delay_minutes
FROM fact_transit_trips t
JOIN dim_events e ON t.scheduled_arrival BETWEEN datetime(e.start_time, '-2 hours') AND e.start_time
WHERE e.crowd_size >= 20000
GROUP BY e.event_name
ORDER BY pre_event_delay_minutes DESC
LIMIT 5;

-- Query 39: Post-Event Dissipation Congestion (2 Hours After Event End)
-- Purpose: Compare post-event evacuation clearing time to baseline travel delays.
SELECT 
    e.event_name,
    ROUND(AVG(t.delay_minutes), 2) AS post_event_delay_minutes
FROM fact_transit_trips t
JOIN dim_events e ON t.scheduled_arrival BETWEEN e.end_time AND datetime(e.end_time, '+2 hours')
WHERE e.crowd_size >= 20000
GROUP BY e.event_name
ORDER BY post_event_delay_minutes DESC
LIMIT 5;

-- Query 40: Severe Delay Count in Nearby Sectors for Events Over 15k Crowd
-- Purpose: Direct alerts of delayed buses inside critical event buffers.
SELECT 
    e.event_name,
    COUNT(CASE WHEN t.delay_minutes > 15 THEN 1 END) AS severe_delays_count
FROM fact_transit_trips t
JOIN dim_events e ON t.date_time BETWEEN e.start_time AND e.end_time
WHERE e.crowd_size > 15000
GROUP BY e.event_name
ORDER BY severe_delays_count DESC
LIMIT 5;


-- ==========================================
-- CATEGORY 5: TRAFFIC & CONGESTION ANALYTICS (41 - 45)
-- ==========================================

-- Query 41: Average Delay Grouped by Traffic Congestion Score Quintiles
-- Purpose: Highlight structural schedule collapse as traffic gridlock rises.
SELECT 
    CASE 
        WHEN tf.congestion_score < 0.2 THEN 'Quintile 1: Very Low (0-0.2)'
        WHEN tf.congestion_score BETWEEN 0.2 AND 0.4 THEN 'Quintile 2: Low (0.2-0.4)'
        WHEN tf.congestion_score BETWEEN 0.4 AND 0.6 THEN 'Quintile 3: Medium (0.4-0.6)'
        WHEN tf.congestion_score BETWEEN 0.6 AND 0.8 THEN 'Quintile 4: High (0.6-0.8)'
        ELSE 'Quintile 5: Gridlock (0.8-1.0)'
    END AS congestion_range,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
GROUP BY congestion_range
ORDER BY congestion_range;

-- Query 42: Cost-Impact of Active Road Closures on Transit Scheduling Delays
-- Purpose: Measure the minute penalty of forced bus route detours.
SELECT 
    tf.road_closure_flag,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes,
    ROUND(MAX(t.delay_minutes), 2) AS max_delay_minutes
FROM fact_transit_trips t
JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
GROUP BY tf.road_closure_flag;

-- Query 43: Relationship Between Live Road Accidents Count and Transit Delay Times
-- Purpose: Monitor how highway collisions spill over into regional bus delays.
SELECT 
    tf.accident_report_count,
    COUNT(t.trip_id) AS total_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
GROUP BY tf.accident_report_count
ORDER BY tf.accident_report_count;

-- Query 44: Extreme Delays Under Compound Gridlock (Active Closures + High Congestion > 0.8)
-- Purpose: Highlight maximum risk situations when operations fail.
SELECT 
    t.route_id,
    COUNT(t.trip_id) AS gridlock_trips,
    ROUND(AVG(t.delay_minutes), 2) AS avg_delay_minutes
FROM fact_transit_trips t
JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
WHERE tf.road_closure_flag = 1 AND tf.congestion_score > 0.8
GROUP BY t.route_id
ORDER BY avg_delay_minutes DESC;

-- Query 45: Congestion Impact on Schedule Precision by City Sector
-- Purpose: Evaluate which part of the city infrastructure is most prone to delays.
SELECT 
    t.sector_id,
    ROUND(AVG(tf.congestion_score), 2) AS avg_congestion_score,
    ROUND(AVG(t.delay_minutes), 2) AS avg_transit_delay_minutes
FROM fact_transit_trips t
JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
GROUP BY t.sector_id
ORDER BY avg_transit_delay_minutes DESC;


-- ==========================================
-- CATEGORY 6: ADVANCED WINDOW & ANALYTICAL QUERIES (46 - 50)
-- ==========================================

-- Query 46: Window Function to Calculate Stop-to-Stop Delay Propagation Along Route Sequence
-- Purpose: Track how a delay builds downstream from stop to stop (Bus Bunching check).
SELECT 
    trip_id,
    route_id,
    stop_id,
    stop_sequence,
    delay_minutes,
    LAG(delay_minutes, 1) OVER (
        PARTITION BY trip_id ORDER BY stop_sequence
    ) AS prev_stop_delay,
    ROUND(delay_minutes - LAG(delay_minutes, 1) OVER (
        PARTITION BY trip_id ORDER BY stop_sequence
    ), 2) AS delta_delay_added_at_stop
FROM fact_transit_trips
WHERE trip_id IN (1, 2, 3) -- Sample trips
ORDER BY trip_id, stop_sequence;

-- Query 47: CTE & Window Function for Cumulative Sum of Route Delay Along Stop Sequence
-- Purpose: Calculate running totals of travel disruption for a trip.
WITH TripSequence AS (
    SELECT 
        trip_id,
        route_id,
        stop_id,
        stop_sequence,
        delay_minutes
    FROM fact_transit_trips
    WHERE trip_id IN (5, 6)
)
SELECT 
    trip_id,
    route_id,
    stop_id,
    stop_sequence,
    delay_minutes,
    ROUND(SUM(delay_minutes) OVER (
        PARTITION BY trip_id ORDER BY stop_sequence 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS running_cumulative_delay_minutes
FROM TripSequence;

-- Query 48: Find Trips with "On-Time Departures" but "Delayed Terminal Arrivals"
-- Purpose: Isolate trips that started perfectly on time at Stop 1 but deteriorated by Stop 10.
WITH TripExtremes AS (
    SELECT 
        trip_id,
        route_id,
        MAX(CASE WHEN stop_sequence = 1 THEN delay_minutes END) AS start_delay,
        MAX(CASE WHEN stop_sequence = 10 THEN delay_minutes END) AS end_delay
    FROM fact_transit_trips
    GROUP BY trip_id, route_id
)
SELECT 
    route_id,
    COUNT(trip_id) AS trips_deteriorated_count,
    ROUND(AVG(end_delay - start_delay), 2) as avg_degradation_minutes
FROM TripExtremes
WHERE start_delay <= 1.0 AND end_delay > 10.0
GROUP BY route_id
ORDER BY trips_deteriorated_count DESC;

-- Query 49: NTILE Reliability Categorization (Split Routes into 4 Quartiles of OTP)
-- Purpose: Classify transit lines for high-level operations performance reporting.
WITH RouteOTP AS (
    SELECT 
        route_id,
        COUNT(CASE WHEN delay_minutes <= 5.0 THEN 1 END) * 100.0 / COUNT(*) AS otp_pct
    FROM fact_transit_trips
    GROUP BY route_id
)
SELECT 
    route_id,
    ROUND(otp_pct, 2) AS on_time_performance_pct,
    NTILE(4) OVER (ORDER BY otp_pct DESC) AS reliability_quartile -- 1 is most reliable, 4 is least
FROM RouteOTP;

-- Query 50: Create complex operational "Risk Matrix" using CTEs and Case Statements
-- Purpose: Direct dispatcher warnings of operational failure levels.
WITH ComplexMetrics AS (
    SELECT 
        t.route_id,
        AVG(t.delay_minutes) AS avg_delay,
        AVG(tf.congestion_score) AS avg_cong,
        SUM(tf.road_closure_flag) AS total_closures
    FROM fact_transit_trips t
    JOIN dim_traffic tf ON t.date_time = tf.timestamp AND t.sector_id = tf.sector_id
    GROUP BY t.route_id
)
SELECT 
    route_id,
    ROUND(avg_delay, 2) AS avg_delay_minutes,
    ROUND(avg_cong, 2) AS avg_congestion_score,
    total_closures,
    CASE 
        WHEN avg_delay > 8.0 AND avg_cong > 0.6 THEN 'CRITICAL - Schedule Overhaul Required'
        WHEN avg_delay BETWEEN 4.0 AND 8.0 AND avg_cong > 0.4 THEN 'HIGH - Needs Operational Buffers'
        WHEN avg_delay BETWEEN 2.0 AND 4.0 THEN 'MEDIUM - Standard Operation'
        ELSE 'LOW - High Reliability Line'
    END AS dispatch_action_recommendation
FROM ComplexMetrics
ORDER BY avg_delay DESC;
