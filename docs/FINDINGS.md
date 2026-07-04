# Findings & Recommendations: Citi Bike Network Demand & Rebalancing

**Prepared for:** VP of Operations & Network Planning
**Data window:** May 2026, NYC network (Jersey City excluded)
**Status:** Draft — in progress. Sections marked *(pending)* await additional
dashboard components not yet built.

---

## Executive Summary

This analysis examines one month of Citi Bike trip data (~4.69M trips,
2,291 stations after data-quality resolution) to identify where network
demand concentrates, where the system is directionally imbalanced, and
where imbalance is severe enough to warrant operational attention.

Three headline findings:

1. **A data quality defect was found and corrected before analysis began.**
   Roughly 53 stations had their trip history split across two corrupted
   station identifiers, fabricating large but fictitious imbalance
   signals at affected stations. All figures in this report reflect the
   corrected data. See "Data Quality Note" below.
2. **The network is broadly well-balanced, but a small number of stations
   are severely imbalanced.** The typical station's daily imbalance is
   within a fraction of a percent of its capacity; the most extreme
   stations run 25–46% of capacity in net drain or gain per day —
   roughly 3–11x beyond normal variation.
3. **A small subset of stations (~1.4% of the network) experienced at
   least one day where net drain or accumulation exceeded the station's
   entire physical capacity** — meaning these stations cannot function at
   observed demand without active, same-day rebalancing.

---

## Data Quality Note

Profiling the raw trip data revealed that ~53 physical stations were
split across two `station_id` values due to formatting defects in the
source data (a dropped trailing zero, an appended character, or a
digit substitution). One id in each pair matched Citi Bike's published
station registry; the other did not and existed only in trip data.

**Impact if left uncorrected:** trip activity for a single physical
station would be divided between two ids, fabricating large directional
imbalances. Example: E 17 St & Broadway appeared to have a net flow of
−8,719 trips/month (a severe apparent drainer) before correction; the
true, merged figure is approximately +60 (near-balanced).

**Resolution:** ids were reconciled using Citi Bike's station capacity
feed as ground truth, with a 100-meter distance safeguard to avoid
incorrectly merging genuinely distinct, co-located stations (one such
case — two separately-capacitied stations on Clinton St & Grand St —
was correctly identified and kept separate). Station capacity match
rate improved from 97.3% to 99.5% as a direct result.

*Full technical detail: `TECHNICAL_BLUEPRINT.md`, `int_station_id_mapping`.*

---

## Finding 1: Demand Concentration & Capacity Strain *(pending)*

Volume alone does not indicate strain — a busy station with ample
capacity is not a problem; a moderately busy station with few docks can
be. [Scatter analysis of daily station activity vs. daily trips-per-dock
to be inserted here once the dashboard component is finalized, including
specific candidate stations for capacity expansion.]

---

## Finding 2: Chronic Network Imbalance

Daily net flow, normalized to each station's capacity
(`avg_daily_net_flow_pct`), is tightly distributed around zero for the
large majority of the network:

| Statistic | Value |
|---|---|
| Mean | ~0.0% |
| Median | 0.0% |
| Std. deviation | ~4% |
| 5th–95th percentile range | −7% to +4% |

The top and bottom 10 stations by this measure sit far outside that
normal range — 3x to 11x beyond the 5th/95th percentile boundary — 
confirming these are genuine outliers, not an arbitrary slice of a
smooth continuum. Representative examples:

**Most severe drainers (daily net flow, % of capacity):**
- Eastern Pkwy & Kingston Ave: approx. −46%
- FDR Drive & E 35 St, Willoughby Ave & Hall St, Grove St & Broadway,
  E 33 St & Park Ave: all beyond −29%

**Most severe fillers:**
- Greenwich St & W Houston St: approx. +22%
- Ave A & E 11 St, Van Brunt St & Wolcott St: beyond +12%

**Recommended monitoring threshold:** ±10% of daily capacity. This
falls well outside normal variation (5th/95th percentile ≈ ±4–7%) while
capturing all identified outlier stations.

---

## Finding 3: Peak-Day Severity & Rebalancing Dependency

Monthly averages can mask a station's worst single day. Examining
station-day-level data:

- **~1.4% of capacity-matched stations (31 of 2,280)** had at least one
  day where net accumulation or drain exceeded the station's total
  physical capacity — evidence these stations cannot function at
  observed demand without active same-day rebalancing.
- The most extreme case, **University Pl & E 14 St**, saw a single-day
  net accumulation of 203 bikes against a 61-dock capacity (3.3x
  capacity) on May 19, 2026 — more than 4x its next-highest day (50, on
  May 25). This pattern (one dominant outlier day, well clear of the
  rest of the month) suggests an isolated demand event near Union
  Square rather than a recurring operational issue, and is presented
  here as an example of the phenomenon rather than a representative case.
- More illustrative of the sustained pattern: **W 48 St & Rockefeller
  Plaza** (57 docks, peak single-day drain of 68 — 1.2x capacity) and
  **Eastern Pkwy & Kingston Ave** (30 docks, peak single-day drain of
  44 — 1.5x capacity), both of which also appear among the chronic
  drainers in Finding 2, indicating persistent rather than one-off strain.

---

## Context: Citi Bike's Own Service Standards

Citi Bike's operating contract with NYC DOT requires 90% bike
availability, and a 2023 NYC Comptroller review treated a station
sitting completely empty or full for an hour or more as a service
failure — finding 11,600 such instances over two summer months in 2023.
This analysis measures a related but distinct signal (net flow rate
from trip data, not real-time dock occupancy); the stations flagged in
Findings 2 and 3 are presented as **stations where sustained imbalance
makes repeated empty/full conditions plausible**, consistent with the
failure mode the city's own standards are designed to catch — not as a
direct measurement of contract compliance. *(Source:
comptroller.nyc.gov, "Riding Forward," Nov 2023.)*

---

## Recommendations *(pending quantification)*

1. **Prioritize capacity review at the intersection of Findings 1 and
   3** — small-capacity stations with disproportionate daily
   trips-per-dock are the most capital-efficient expansion candidates.
   [Quantified "docks needed to de-risk" table pending.]
2. **Adopt a ±10% daily net-flow-per-capacity threshold** as a
   standing monitoring metric for the rebalancing team, informed by the
   distribution analysis in Finding 2.
3. **Treat the 31 stations in Finding 3 as a standing watch list** for
   rebalancing route prioritization, independent of their average
   monthly behavior.
4. [Recommendations on under-utilized stations as dock-removal
   candidates — pending.]

---

## Limitations

- Single-month snapshot (May 2026); no seasonal comparison possible yet.
- Station capacity reflects a current snapshot of the GBFS feed, not
  necessarily the capacity in effect during every day of the trip data
  window.
- Unmet demand (riders who found no bike or no open dock) is invisible
  in trip data; all findings describe realized, not total, demand.
- E-bike trips ending outside the dock network (a known, accepted
  asymmetry — Citi Bike does not rebalance e-bikes, per public
  statements) may cause arrivals to slightly undercount true docking
  demand at capacity-constrained stations.
- Member vs. casual behavioral analysis not yet included in this
  version of the report.

---

*Methodology detail, metric definitions, and the full station-id
resolution logic are documented in `TECHNICAL_BLUEPRINT.md`.*