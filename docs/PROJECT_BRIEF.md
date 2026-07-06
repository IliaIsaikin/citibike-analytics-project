# Project Brief: Citi Bike Demand & Network Opportunity Analysis

## Overview

This project analyzes NYC Citi Bike trip data to **diagnose network performance** — understanding **where ridership demand is concentrated and imbalanced across the station network**, where demand runs high relative to capacity, and **how member and casual riders differ** in their usage. The goal is to surface data-grounded signals and operational recommendations that help Citi Bike decide where to invest in station capacity, where to focus rebalancing effort, and how to think about its two rider segments.

The project is built as a scalable, maintainable analytics framework (modular dbt models, tested transformations, a reporting layer, and a written findings deliverable) rather than a one-off analysis — reflecting how a performance-diagnosis pipeline would be built and maintained in practice.

---

## Stakeholder

**Primary:** VP of Operations & Network Planning, Citi Bike (Lyft)

This person owns capital-intensive, hard-to-reverse decisions — where to add stations, where to expand dock capacity, and how to allocate and rebalance bikes across the network. They need demand evidence to prioritize where the next investment goes.

**Secondary:** Director of Membership & Growth

This person owns the conversion funnel (turning casual riders into annual members). The rider-behavior layer of this analysis informs where and to whom conversion efforts could be targeted.

---

## Business Problem

Citi Bike's station network has highly uneven demand. Some stations are oversubscribed — bikes run out or docks fill up at peak times, creating lost rides and rider frustration — while others are underused. The Operations team needs to know **where demand concentrates, where the network is directionally imbalanced, and where demand is high relative to a station's capacity**, so they can prioritize where to expand.

A key analytical nuance shapes this work: **trip volume measures realized demand, not strain.** A busy station is not necessarily a problem if it already has the dock capacity to absorb that demand. To distinguish "busy but well-provisioned" from "busy relative to its size," this project normalizes demand against station capacity where possible. The trip data alone cannot reveal *unmet* demand (riders who found no bike or no open dock), so the analysis identifies **candidate** stations for capacity review rather than confirmed problem sites.

Layered on top is a **rider-segment question**: members and casual riders behave differently, and understanding those differences informs both network planning (who is driving demand where) and membership conversion strategy.

---

## Core Business Questions

**Primary (Operations / Growth):**
> Where is ridership demand concentrated and imbalanced across the station network, and where is demand high relative to capacity — implying priority locations for expansion or rebalancing?

**Secondary (Rider Behavior):**
> How do member and casual riders differ in when, where, and how they ride, and what does that imply for demand patterns and conversion targeting?

### Supporting sub-questions

Network & demand:
- Which stations have the highest trip volume (as origin, as destination, and total)?
- Which station-to-station routes (corridors) are most popular?
- Which stations show the greatest directional imbalance (net origins vs. net destinations)?
- Where is demand highest **relative to dock capacity** (trips per dock)?
- How does demand shift by hour of day and day of week?

Rider behavior:
- How do member vs. casual riders split overall and by station?
- How do trip duration and timing patterns differ between the two groups (commuter vs. leisure signals)?
- Which stations are "casual-heavy" (potential conversion-targeting locations)?
- How does bike-type preference (classic vs. electric) differ by rider type?

---

## Key Metrics

**Demand & network:**
- Trips per station — as origin, as destination, and total
- Net flow per station (departures − arrivals) — the imbalance signal
- Top N station-to-station routes by trip count
- **Trips per dock (demand-to-capacity ratio)** — headline normalized metric
- Demand by hour-of-day and day-of-week, per station / zone
- Trip volume by geographic area (lat/lng based)

**Rider behavior:**
- Trip count and share by rider type (member vs. casual)
- Average / median trip duration by rider type
- Trips by hour-of-day and day-of-week, split by rider type
- Weekend vs. weekday ratio by rider type
- Casual share of trips per station (casual-heavy station identification)
- Electric vs. classic bike mix by rider type

**Validation / integrity metrics:**
- Total trips reconciled against known source total (~4.69M)
- Network-wide departures ≈ arrivals (conservation check)
- Net flows sum to ≈ zero across the network (conservation check)

---

## Conceptual Model

The grain of the raw data is a **single trip**. Each trip carries a rider type, start/end timestamp, start/end station (id, name, lat/lng), and bike type.

The analysis aggregates trips along three dimensions:
- **Station** (the analytical spine): trips are rolled up by start station and by end station, then combined to compute net flow and joined to capacity for trips-per-dock.
- **Time**: hour-of-day and day-of-week breakdowns reveal demand rhythms and directional rush-hour flows.
- **Rider type**: every demand view can be split by member vs. casual.

Station-pairs form a **route** dimension for corridor analysis. Station capacity (from a second data source) enables the demand-to-capacity normalization.

---

## Data Sources

1. **Citi Bike trip data (loaded)** — May 2026 monthly trip CSVs from the official Citi Bike System Data release, loaded into BigQuery (`citibike_raw.trips`, ~4.69M rows). New-format schema: ride_id, rideable_type, started_at, ended_at, start/end station id & name, start/end lat/lng, member_casual. NYC-originating trips only (the Jersey City origin file is excluded at ingestion); a small number of NYC-origin trips end at a Hoboken/Jersey City station (309 trips, ~0.0066%) — these are retained, with the out-of-network endpoint treated as unknown, consistent with dockless-ending handling. See TECHNICAL_BLUEPRINT.md.

2. **Citi Bike GBFS `station_information` feed (to be added)** — the live public feed at `https://gbfs.citibikenyc.com/gbfs/en/station_information.json`, providing each station's **capacity** (total docks), name, and coordinates. No authentication required. Used to compute the trips-per-dock ratio.

---

## Scope & Assumptions

**In scope:**
- One month of trip data (June 2026) as a demand snapshot.
- Station-level demand, net-flow imbalance, route/corridor analysis.
- Demand-to-capacity normalization using current station capacity.
- Member vs. casual behavioral comparison across time, duration, location, and bike type.

**Assumptions:**
- Trip volume is treated as a proxy for demand.
- Current station capacity (from the live feed) is a reasonable approximation of capacity during the trip window; minor mismatches may exist where stations were resized or added.
- Trips with missing station identifiers (~0.25% of rows) are excluded from station-level analyses but retained for time-based and rider-type analyses.
- Rider behavior is inferred at the aggregate/station level, not per individual — the data is anonymized per-trip with no cross-trip rider tracking.

**Trip-validity cleanup (applied in the fact layer, not staging):**
- **Negative durations excluded** — physically impossible (end before start). Duration profiling found none, confirming source-side cleaning.
- **Sub-1-minute durations excluded** — defensive filter for false starts / redock tests. Profiling found none.
- **Durations ≥ 2 hours excluded** as probable docking failures or lost/abandoned bikes. Justification: duration profiling showed 99.8% of trips fall under 2 hours, and the per-minute overage fee structure (fees begin at 30–45 min and accrue until the bike docks) makes genuinely longer single rides economically implausible. The excluded set is ~0.2% of trips.
- Cleanup is applied only in the business-facing fact table; staging retains all rows, so the volume and rationale of removed trips can be reported transparently.

**Limitations (stated honestly):**
- The analysis identifies **candidate** demand hotspots and imbalances, not confirmed capacity strain.
- *Unmet* demand (riders who found no available bike or no open dock) is invisible in trip data.
- A single month cannot reveal seasonality; conclusions are snapshot-specific. (Additional months may be backfilled in a later phase to enable seasonal comparison.)
- Trip distance is computed as straight-line (Haversine) distance between start and end coordinates; it is used as a descriptive analytical feature only, not as a validity filter, since it cannot capture actual ride paths or round trips.
- **Station identity required resolution before analysis.** Profiling revealed that ~53 of the raw dataset's distinct station_id values were corrupted duplicates — formatting artifacts (e.g. a dropped trailing zero, an appended character) that split a single physical station across two ids in the raw trip data. Left unresolved, this would fabricate large but fictitious net-flow imbalances at affected stations. Ids were reconciled using the station capacity feed as ground truth, with a coordinate-distance safeguard to avoid incorrectly merging genuinely distinct stations that happen to share a name. See TECHNICAL_BLUEPRINT.md for the full resolution logic. All net-flow and demand figures in this analysis reflect corrected station identities.
- **A small number of NYC-origin trips cross into New Jersey.** 309 trips (~0.0066%) depart from an NYC station but end at a Hoboken or Jersey City station (54 distinct raw ids across the two systems, resolving to 53 canonical stations after id-mapping). Rather than discarding these trips (which would also discard their legitimate NYC-side departure data), the out-of-network endpoint is set to unknown/null — the same treatment already applied to dockless trip endings. This affects end_station_id/end_station_name/end_lat/end_lng only; the trip itself, its duration, and its NYC-side departure are retained.

---

## Out of Scope

- **Historical real-time dock availability** (how full/empty stations were during the data window). This would require continuously archiving the GBFS `station_status` feed over time — a separate data-engineering effort, not part of this project.
- **Per-rider longitudinal tracking** (following an individual rider across trips) — not possible with anonymized per-trip data.
- **Multi-month / seasonal trend analysis** — single-month snapshot only.
- **Revenue, pricing, or cost modeling.**
- **Predictive modeling / forecasting** — this project is descriptive and diagnostic, not predictive.
- **Trips originating in Jersey City** — excluded at ingestion to keep the scope to the NYC network. (Note: a small number of NYC-origin trips ending in Jersey City/Hoboken are retained with the endpoint nulled — see Limitations.)

---

## Validation Approach

- Reconcile total trip count against the known source total (~4.69M rows).
- Confirm the member/casual split is plausible (Citi Bike is heavily member-skewed).
- Check duration distributions for invalid values (negative or implausibly long trips) and define handling.
- Verify hour-of-day demand patterns match intuition (commute peaks).
- Apply conservation checks: network-wide departures ≈ arrivals, and net flows sum to ≈ zero.
- Face-validity check: top-demand stations should be recognizable major hubs.

---

## Deliverables

- **A tested dbt transformation pipeline** (staging → intermediate → marts) modeling station demand, net-flow imbalance, routes, time patterns, and rider-type behavior.
- **A network-performance dashboard** (Looker Studio) for diagnosing demand and imbalance across the station network.
- **A written Findings & Recommendations summary** translating the analysis into operational recommendations for the Operations & Network Planning stakeholder — e.g. which stations are priority candidates for added capacity or rebalancing focus, and how member/casual demand patterns inform those decisions. This is the deliverable that turns the technical pipeline into actionable analysis.

## What This Project Informs

- **Operations:** where to prioritize new stations, added dock capacity, and rebalancing effort — focused on stations with high demand relative to capacity and strong directional imbalance, and on diagnosing system-health/performance signals.
- **Membership/Growth:** which stations and rider segments represent the strongest casual-to-member conversion opportunities.
