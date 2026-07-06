# NYC Citi Bike Analytics — Operations & Network Demand

An analytics engineering project analyzing ~4.7M NYC Citi Bike trips to surface
station-level demand, network imbalance, and demand-relative-to-capacity — the
signals an operations and network-planning team uses to prioritize rebalancing
and capacity decisions.

**Stack:** dbt Core (Fusion) · Google BigQuery · Python · Looker Studio · Git

---

## Overview

Citi Bike publishes monthly trip data and a live station-information feed. This
project builds an end-to-end pipeline that ingests both, models them into a
tested analytical warehouse, and exposes operational metrics for network planning.

The analysis is framed around three operational questions:

- **Where is demand concentrated?** — trip volume by station, time, and rider type.
- **Where is the network imbalanced?** — net flow (arrivals − departures) per
  station, identifying which stations drain (empty out) and which fill up.
- **Where is demand high relative to capacity?** — demand and imbalance normalized
  by each station's dock count, distinguishing stations that are merely *busy*
  from those that are genuinely *strained*.

## Architecture

```
Citi Bike trip data (CSV, ~4.7M rows)  ─┐
                                        ├─►  BigQuery (raw)  ─►  dbt  ─►  Looker Studio
GBFS station-information feed (API)  ───┘        ▲
                                                 │
                              Python ingestion (requests → pandas → BigQuery)
```

**Data flow:**
1. **Trip data** is loaded to GCS and then to BigQuery as raw strings (ELT: load first, cast in dbt).
2. **Station capacity** is fetched from the live GBFS feed by a Python script and
   loaded to BigQuery (see [`scripts/load_station_info.py`](scripts/load_station_info.py)).
3. **dbt** transforms raw data through staging → intermediate → marts layers.
4. **Looker Studio** connects to the marts for dashboarding.

## dbt Models

The project follows a layered dbt structure:

**Staging** (`models/staging/`) — light typing and cleaning, one model per source:
- `stg_citibike__trips` — types trips, renames fields, derives trip duration.
- `stg_citibike__station_info` — types capacity data; converts capacity 0 (inactive
  stations) to NULL to keep the raw signal honest and avoid divide-by-zero downstream.

**Intermediate** (`models/intermediate/`) — reusable business logic:
- `int_station_id_mapping` — resolves corrupted/duplicate station_ids in raw trip data (formatting artifacts) 
  to a single canonical id per physical station, using the capacity feed as ground truth.
- `int_trips_enriched` — applies station_id resolution and trip-validity cleanup, and derives features 
  (trip date/hour, weekend flag, round-trip flag, Haversine distance).
- `int_station_departures` / `int_station_arrivals` — per-station trip counts with
  member/casual splits.

**Marts** (`models/marts/`) — analysis-ready outputs:
- `fct_trips` — clean trip fact table (grain: one row per trip).
- `dim_stations` — station dimension enriched with dock capacity from the GBFS feed.
- `agg_station_demand` — per-station departures, arrivals, net flow, and
  capacity-normalized metrics (`activity_per_dock`, `net_flow_per_dock`).
- `agg_demand_by_time` — demand by day-of-week, hour, and rider type.
- `agg_routes` — station-to-station corridors.
- `agg_daily_trips` — daily trip volume.

## Key Metrics

| Metric | Definition | Operational meaning |
|---|---|---|
| `net_flow` | arrivals − departures | Positive = station fills (net destination); negative = station drains (net origin). Signals rebalancing need. |
| `activity_per_dock` | total activity / capacity | Throughput pressure per dock. Distinguishes busy-but-large from busy-and-small stations. |
| `net_flow_per_dock` | net flow / capacity | Imbalance severity relative to station size — a −45 net flow is far more acute at a 20-dock station than a 100-dock one. |

## Data Modeling Decisions

A few deliberate choices, documented in [`docs/`](docs/):

- **Trip-duration cutoff:** trips ≥ 2 hours are excluded as probable docking
  failures (~0.2% of trips), based on distribution profiling and Citi Bike's
  pricing structure.
- **Haversine distance** is treated as a descriptive feature, not a validity
  filter (it can't capture round trips or actual routes).
- **Capacity join key:** the GBFS feed's `short_name` (not its internal
  `station_id`) matches the trip data's station id — verified by inspection, achieving a 99.5% station match rate 
  after resolving ~53 corrupted duplicate station_ids in the raw trip data (see int_station_id_mapping).
- **Raw layer preserves all rows;** cleanup and derivation happen in dbt, keeping
  the pipeline auditable.

## Testing

The pipeline includes >30 dbt tests:

- **Generic tests:** primary-key uniqueness/not-null, referential integrity
  (fact → dimension), accepted values (rider type, bike type), aggregate-grain
  integrity.
- **Singular tests:** net-flow arithmetic (`net_flow = arrivals − departures`),
  conservation by bike type (classic bikes conserve tightly; e-bikes carry a known
  dockless asymmetry), trip-duration bounds, and capacity-metric null-safety.

## Repository Structure

```
├── models/
│   ├── staging/        # typing & cleaning
│   ├── intermediate/   # reusable business logic
│   └── marts/          # analysis-ready outputs
├── scripts/
│   └── load_station_info.py   # Python GBFS capacity ingestion
├── tests/              # singular (custom) dbt tests
├── docs/               # project brief & technical blueprint
├── dbt_project.yml
├── packages.yml        # dbt package dependencies
└── requirements.txt    # Python dependencies
```

## Running the Project

**Prerequisites:** dbt (Fusion), a BigQuery project with credentials, Python 3.12+.

```bash
# 1. Install dbt packages
dbt deps

# 2. (Optional) Refresh station capacity from the live GBFS feed
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
export GOOGLE_APPLICATION_CREDENTIALS=~/.dbt/your-keyfile.json
python scripts/load_station_info.py

# 3. Build and test the dbt project
dbt build
```

## Data Sources

- **Trip data:** [Citi Bike System Data](https://citibikenyc.com/system-data)
- **Station capacity:** [GBFS station_information feed](https://gbfs.citibikenyc.com/gbfs/en/station_information.json)

---

*Analytics engineering portfolio project. Data reflects NYC stations for a single
month (May 2026); metrics are totals over that window.*