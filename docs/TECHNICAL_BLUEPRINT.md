# Technical Blueprint: Citi Bike Demand & Network Analysis

This document translates the project brief into a concrete dbt build plan. It is detailed for **Phase 1** (the core trip-data models we build first) and sketches **Phases 2+** at a high level, to be fleshed out as we reach them.

---

## Architecture Overview

The project follows a layered dbt structure. Each layer has a single clear responsibility, and data flows in one direction: sources → staging → intermediate → marts.

```
SOURCES
  citibike_raw.trips ............. raw trip data (loaded)
  citibike_raw.station_info ...... station capacity (Phase 3)

STAGING  (clean, typed, 1:1 with source; materialized as views)
  stg_citibike__trips ............ built
  stg_citibike__station_info ..... Phase 3

INTERMEDIATE  (reusable reshaping / aggregation logic; views)
  int_trips_enriched ............. add date parts + distance; apply validity cleanup
  int_station_departures ......... trips aggregated by START station
  int_station_arrivals ........... trips aggregated by END station

MARTS  (business-facing; materialized as tables)
  dim_stations ................... one row per station (+ capacity in Phase 3)
  fct_trips ...................... clean trip-grain fact table
  agg_station_demand ............. per-station demand, net flow, (trips-per-dock in Phase 3)
  agg_demand_by_time ............. demand by hour/day, split by rider type
  agg_routes ..................... top station-to-station corridors
```

**Design principles:**
- **Staging keeps everything** (all rows, all months) — no filtering, only typing/renaming.
- **Validity cleanup happens in the intermediate/fact layer**, so removed trips can be reported transparently.
- **Star schema** (`fct_trips` + `dim_stations`) for the trip grain, which the dashboard joins for filtering and mapping.
- **Pre-aggregated marts** (`agg_*`) so the dashboard reads ready-shaped data rather than running heavy queries.
- Models are **month-agnostic** — adding more months later requires no model changes, just more data in the source.

---

## PHASE 1 — Core Models (trip data only)

Built bottom-up so each model's dependencies exist before it. Materializations follow `dbt_project.yml`: staging/intermediate as views, marts as tables.

### 1. `int_trips_enriched` (intermediate, view)

**Purpose:** The single place where trip-level cleanup and enrichment happen. Everything downstream reads from here rather than from staging directly, so the cleanup logic lives in exactly one model.

**Grain:** one row per valid trip.

**Logic:**
- Read from `stg_citibike__trips`.
- **Apply validity cleanup** (the fact layer's filter, centralized here):
  - exclude `trip_duration_minutes < 0` (negative)
  - exclude `trip_duration_minutes < 1` (sub-1-minute)
  - exclude `trip_duration_minutes >= 120` (≥ 2 hours)
- **Add date/time parts** from `started_at`:
  - `trip_date` (date)
  - `trip_hour` (0–23)
  - `day_of_week` (name or number)
  - `is_weekend` (boolean)
- **Add `trip_distance_km`** — straight-line Haversine distance from start/end lat/lng, using the `dbt_utils.haversine_distance` macro. Descriptive feature only.

**Notes:** keep a comment documenting the cutoff rationale (ties back to the brief).

### 2. `fct_trips` (mart, table)

**Purpose:** The clean, business-facing trip fact table — the canonical "one row per valid trip" that the dashboard and rider-behavior analyses use.

**Grain:** one row per valid trip.

**Logic:**
- Read from `int_trips_enriched`.
- Select the trip-grain columns to expose: `ride_id`, `user_type`, `rideable_type`, timestamps, duration, distance, the date parts, and start/end station ids (as foreign keys to `dim_stations`).
- No further filtering (cleanup already applied upstream).

**Why separate from `int_trips_enriched`?** The intermediate model is internal plumbing (a view); `fct_trips` is the stable, materialized, documented output others depend on. Keeping them distinct is a clean convention.

### 3. `dim_stations` (mart, table)

**Purpose:** One row per station — the dimension the fact table and aggregates join to for names and coordinates. Capacity is added in Phase 3.

**Grain:** one row per unique station.

**Logic:**
- Derive the distinct set of stations from `stg_citibike__trips`, combining **both** start and end station appearances (a station may appear only as an origin or only as a destination).
- For each `station_id`: pick a representative `station_name`, `lat`, `lng` (stations occasionally have tiny coordinate variations across trips; take one consistent value, e.g. via a deduplication pattern).
- Exclude null station ids.

**Challenge to handle:** a station's name/coordinates must be resolved from potentially many trip rows. We'll union start-station and end-station records, then deduplicate to one row per `station_id`.

### 4. `int_station_departures` (intermediate, view)

**Purpose:** Trips aggregated by **start** station — the "bikes flowing out" side of net flow.

**Grain:** one row per start station.

**Logic:**
- Read from `fct_trips`.
- Group by `start_station_id`.
- Compute `departures` = count of trips, plus optional splits (e.g. departures by rider type) if useful downstream.

### 5. `int_station_arrivals` (intermediate, view)

**Purpose:** Trips aggregated by **end** station — the "bikes flowing in" side.

**Grain:** one row per end station.

**Logic:**
- Read from `fct_trips`.
- Group by `end_station_id`.
- Compute `arrivals` = count of trips.

### 6. `agg_station_demand` (mart, table)

**Purpose:** The core network-demand model — per-station departures, arrivals, total demand, and **net flow** (the imbalance signal). Trips-per-dock is added in Phase 3.

**Grain:** one row per station.

**Logic:**
- Start from `dim_stations` (so every station appears, even one-directional ones).
- Left join `int_station_departures` and `int_station_arrivals` on `station_id`.
- Coalesce nulls to 0 (a station with no arrivals should show 0, not null).
- Compute:
  - `total_trips` = departures + arrivals
  - `net_flow` = departures − arrivals (positive = net origin / bikes leave; negative = net destination / bikes pile up)
- Carry station name + coordinates for mapping.

**Validation hook:** network-wide `SUM(departures)` should ≈ `SUM(arrivals)`, and `SUM(net_flow)` ≈ 0 (conservation checks — implemented as singular tests in Phase 2).

### 7. `agg_demand_by_time` (mart, table)

**Purpose:** Demand across time, split by rider type — powers the time-pattern and member-vs-casual views.

**Grain:** one row per (date × hour × day_of_week × user_type) combination — exact grain to be finalized during build based on dashboard needs.

**Logic:**
- Read from `fct_trips`.
- Group by the time dimensions and `user_type`.
- Compute trip counts, average duration, average distance per group.

### 8. `agg_routes` (mart, table)

**Purpose:** Most popular station-to-station corridors.

**Grain:** one row per (start_station, end_station) pair.

**Logic:**
- Read from `fct_trips`.
- Group by `start_station_id`, `end_station_id`.
- Count trips per pair; keep names/coordinates for both ends for mapping.
- Optionally rank / keep top N by trip count.

---

## PHASE 1 — Build Order

1. `int_trips_enriched` — cleanup + enrichment (everything depends on it)
2. `dim_stations` — the station dimension
3. `fct_trips` — the clean fact table
4. `int_station_departures` + `int_station_arrivals`
5. `agg_station_demand` — combine into net flow
6. `agg_demand_by_time`
7. `agg_routes`

Build and verify each in BigQuery before moving on. Commit at sensible checkpoints (e.g. after the fact/dim pair, after the aggregates).

---

## PHASE 2 — Tests (high-level sketch)

Add data-quality tests to lock in correctness:

- **Generic tests (in YAML):**
  - `not_null` + `unique` on `ride_id` (fct_trips) and `station_id` (dim_stations)
  - `not_null` on key fields (timestamps, user_type)
  - `accepted_values` on `user_type` (member, casual) and `rideable_type`
  - `relationships` — fct_trips start/end station ids reference dim_stations
- **Singular tests (SQL):**
  - conservation check: network-wide departures ≈ arrivals
  - net_flow sums to ≈ 0
  - no trips in fct_trips with duration ≥ 120 min or < 1 min (cleanup enforcement)
- Add `dbt_utils` tests where useful (e.g. accepted range on duration).

---

## PHASE 3 — Capacity Integration + Python (high-level sketch)

- **Python ingestion script**: pull `station_information.json` from the GBFS feed (`requests`), parse to a table (`pandas`), load to BigQuery (`google-cloud-bigquery`) as `citibike_raw.station_info`.
- `stg_citibike__station_info` — stage/type the capacity data.
- Enrich `dim_stations` with `capacity` (join on station_id).
- Add `trips_per_dock` = total_trips / capacity to `agg_station_demand` — the demand-to-capacity headline metric.
- Handle stations present in trips but missing from the feed (and vice versa) gracefully.

---

## PHASE 4 — Looker Studio Dashboard (high-level sketch)

Connect Looker Studio to the marts. Planned views:
- **Demand map** — stations plotted by lat/lng, sized/colored by total demand (and trips-per-dock in Phase 3).
- **Net-flow / imbalance view** — stations by net_flow (net origins vs. destinations).
- **Time patterns** — demand by hour/day, split by rider type.
- **Member vs. casual** — behavioral comparison (duration, timing, casual-heavy stations).
- **Top routes** — leading corridors.

---

## PHASE 5 — Findings & Recommendations (high-level sketch)

A written deliverable translating the analysis into operational recommendations for the Operations & Network Planning stakeholder:
- Priority stations for added capacity (high demand / high trips-per-dock).
- Priority stations/corridors for rebalancing (strong net-flow imbalance).
- How member vs. casual demand patterns inform planning and conversion.
- Stated limitations (candidate signals, not confirmed strain; single-month snapshot).

---

## PHASE 6 — Polish & README (high-level sketch)

- Rewrite README: project purpose, architecture diagram, tech stack, key findings, how to run.
- Add model-level documentation (descriptions in YAML).
- Final repo tidy; ensure lineage/tests are clean.

---

## PHASE 7 — Scale Up

- Backfill additional months (April/May+) — no model changes needed; load more data and re-run.
