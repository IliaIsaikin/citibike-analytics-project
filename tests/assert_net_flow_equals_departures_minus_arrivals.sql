-- Conservation arithmetic check:
-- net_flow must exactly equal departures - arrivals for every station.
-- This tests the model's math (not real-world behavior), so it must be exact.
-- The test passes if zero rows are returned (no violations).

select
    station_id,
    departures,
    arrivals,
    net_flow,
    departures - arrivals as expected_net_flow
from {{ ref('agg_station_demand') }}
where net_flow != departures - arrivals