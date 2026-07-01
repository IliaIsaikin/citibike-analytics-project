-- Capacity-metric null-safety check.
-- trips_per_dock and net_flow_per_dock must be null if and only if capacity is null.
-- This validates the nullif(capacity,0) -> null-division safety chain:
--   - capacity null  => both ratios must be null (no divide-by-zero slipped through)
--   - capacity present => both ratios must be non-null
-- Passes if zero rows are returned.

select
    station_id,
    capacity,
    trips_per_dock,
    net_flow_per_dock
from {{ ref('agg_station_demand') }}
where
    -- capacity is null but a ratio somehow computed
    (capacity is null and (trips_per_dock is not null or net_flow_per_dock is not null))
    -- or capacity exists but a ratio is missing
    or (capacity is not null and (trips_per_dock is null or net_flow_per_dock is null))