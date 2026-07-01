-- Cleanup-enforcement check:
-- fct_trips should contain only trips with duration in the range [1, 120) minutes.
-- Trips < 1 minute (false starts) and >= 120 minutes (probable docking failures)
-- are excluded upstream in int_trips_enriched. This test verifies that cleanup
-- is actually applied. See project brief for the cutoff rationale.
--
-- Passes if zero rows are returned (no trips outside the valid range).

select
    ride_id,
    trip_duration_minutes
from {{ ref('fct_trips') }}
where trip_duration_minutes < 1
   or trip_duration_minutes >= 120