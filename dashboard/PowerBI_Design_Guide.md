# Power BI Dashboard Design Guide: Transit Delay Analytics

This guide provides step-by-step instructions, table relationships, and **DAX formulas (measures)** to build the companion Power BI dashboard (`TransitPerformanceDashboard.pbix`) for this project.

---

## 🔌 1. Data Connection Setup

Power BI can connect directly to your database:
* **Option A: PostgreSQL (Production)**:
  * Click **Get Data** -> **PostgreSQL Database**.
  * Input your Server address, Database name, and select **Import** or **DirectQuery**.
* **Option B: SQLite (Local Testing)**:
  * Install the **SQLite ODBC Driver** (e.g., from Christian Werner's website).
  * In Power BI, select **ODBC** as your data source, select your SQLite DSN pointing to `data/transit_data.db`, and import your tables.

---

## 📐 2. The Star Schema (Data Model Relationships)

Power BI handles analytical queries fastest when tables are structured in a **Star Schema**. In the **Model View**, set up the following relationships:

```
    ┌─────────────────┐             ┌─────────────────┐
    │   dim_weather   │             │   dim_traffic   │
    └────────┬────────┘             └────────┬────────┘
             │ (1:Many)                      │ (1:Many)
             │ (timestamp)                   │ (timestamp + sector_id)
             ▼                               ▼
    ┌─────────────────────────────────────────────────┐
    │               fact_transit_trips                │
    └────────────────────────▲────────────────────────┘
                             │ (Many:1)
                             │ (DATE(scheduled_arrival) -> date)
                             ▼
                    ┌─────────────────┐
                    │  dim_holidays   │
                    └─────────────────┘
```

* **Table Relationships Details**:
  * `dim_weather[timestamp]` (1) ─── (Many) `fact_transit_trips[date_time]` (Active)
  * `dim_holidays[date]` (1) ─── (Many) `fact_transit_trips[DATE(scheduled_arrival)]` (Active)
  * `dim_traffic[timestamp]` & `dim_traffic[sector_id]` compound keys should be linked using a merged key `timestamp_sector` in both tables, creating a `1:Many` active relationship to `fact_transit_trips`.

---

## 🧮 3. High-Impact DAX Measures

Create a dedicated table named `_Measures` in Power BI and write these **DAX formulas** to calculate corporate-level KPIs:

### KPI 1: Total Trips Ingested
```dax
Total Trips = COUNTROWS(fact_transit_trips)
```

### KPI 2: Average Delay (Minutes)
```dax
Avg Delay (Min) = AVERAGE(fact_transit_trips[delay_minutes])
```

### KPI 3: On-Time Performance (OTP) %
*On-time is defined as arrival within 5 minutes of scheduled time.*
```dax
On-Time Performance % = 
DIVIDE(
    CALCULATE(COUNTROWS(fact_transit_trips), fact_transit_trips[delay_minutes] <= 5.0),
    [Total Trips],
    0
)
```

### KPI 4: Severe Delay Count (> 15 Minutes)
```dax
Severe Delays = CALCULATE(COUNTROWS(fact_transit_trips), fact_transit_trips[delay_minutes] > 15.0)
```

### KPI 5: Severe Delay Share %
```dax
Severe Delay % = DIVIDE([Severe Delays], [Total Trips], 0)
```

### KPI 6: Total Weather-Affected Trips
```dax
Weather Affected Trips = 
CALCULATE(
    [Total Trips],
    FILTER(dim_weather, dim_weather[weather_condition] IN {"Heavy Rain", "Foggy"})
)
```

### KPI 7: Estimated Delay Financial Cost ($)
*Assumes driver overtime and extra fuel burn costs $12.50 per delay minute.*
```dax
Estimated Delay Cost = SUM(fact_transit_trips[delay_minutes]) * 12.50
```

### KPI 8: Peak vs Off-Peak Delay Multiplier
```dax
Peak Delay Multiplier = 
DIVIDE(
    CALCULATE([Avg Delay (Min)], fact_transit_trips[hour] IN {7, 8, 9, 17, 18, 19}),
    CALCULATE([Avg Delay (Min)], NOT(fact_transit_trips[hour] IN {7, 8, 9, 17, 18, 19})),
    0
)
```

---

## 🎨 4. Page-by-Page Visualizations & Layouts

To capture the attention of a director of transport, build your dashboard as a **5-page report**:

### Page 1: Executive Transit Overview
* **KPI Card Visuals**: `Total Trips`, `Avg Delay (Min)`, `On-Time Performance %`, `Estimated Delay Cost`.
* **Line Chart**: Daily cumulative delay minutes vs. scheduled performance over the year.
* **Bar Chart (Horizontal)**: Top 10 worst routes ranked by `Avg Delay (Min)`.
* **Map Visual (Folium/Pydeck equivalent in Power BI)**: Plot transit stops with bubble size representing `Avg Delay (Min)` and bubble color representing `OTP %`.

### Page 2: Environmental & Weather Analytics
* **Clustered Bar Chart**: `Avg Delay (Min)` grouped by `Weather Condition` (Clear, Light Rain, Heavy Rain, Foggy).
* **Scatter Plot**: Rainfall intensity (X-axis) vs. actual delay minutes (Y-axis) with route filter slicers.
* **Gauge Visual**: Display current average delay under the selected weather filter against the global target (Target: <= 3.0 mins).

### Page 3: City Events & Holiday Impacts
* **Comparative Bar Chart**: Average delays on event days (Sports, Concerts) vs. standard business days.
* **Table/Matrix Visual**:
  * Rows: `Event Name`, `Event Type`, `Venue Name`
  * Columns: `Crowd Size`, `Avg Delay (Min)`, `Total Trips in Sector`
* **Slicer**: Single-select filter for `Festival Name` (Diwali, Holi, Christmas, etc.).

### Page 4: Traffic & Congestion Metrics
* **Line Chart**: Congestion score (0.0 to 1.0) along X-axis vs. Average delay minutes on Y-axis.
* **Matrix Grid**: Row sectors vs. column hours of day, colored using conditional formatting (Red = High Congestion and high delays; Green = Free flow).
* **Accident Correlation Chart**: Stacked column showing accident counts and actual bus delay spikes.

### Page 5: ML Predictive Analytics
* **Table of Coefficients/Features**: Displays relative predictive weights (e.g. `lag_1_delay` = 35% weight).
* **Scenario Emulator Table**: Embeds a Python/R script visual or Power BI Parameter table to demonstrate hypothetical scenario testing.
* **Model Validation Matrix**: Confuses matrix showing actual delays vs. predicted class delays.
