-- One-time snapshot of NYC's five borough boundaries (coextensive with
-- five NY State counties), sourced from BigQuery's public
-- geo_us_boundaries dataset and copied into geo_raw.nyc_county_boundaries.
-- County boundaries are effectively permanent, so this is a static
-- reference table, not a live/refreshed source -- unlike
-- stg_citibike__station_info, this table has no update schedule.

select
    borough,
    county_geom
from {{ source('geo', 'nyc_county_boundaries') }}