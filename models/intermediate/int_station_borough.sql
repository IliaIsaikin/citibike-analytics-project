-- models/intermediate/int_station_borough.sql

with stations as (
    select distinct
        start_station_id as station_id,
        start_lat as lat,
        start_lng as lng
    from {{ ref('int_trips_enriched') }}
    where start_station_id is not null
      and start_lat is not null
      and start_lng is not null

    union distinct

    select distinct
        end_station_id,
        end_lat,
        end_lng
    from {{ ref('int_trips_enriched') }}
    where end_station_id is not null
      and end_lat is not null
      and end_lng is not null
),

-- One representative coordinate per station_id (mirrors dim_stations'
-- own dedup approach, applied independently here to avoid depending
-- on the mart -- keeps int_station_borough correctly intermediate-only).
station_repr as (
    select
        station_id,
        avg(lat) as lat,
        avg(lng) as lng
    from stations
    group by station_id
)

select
    s.station_id,
    c.borough
from station_repr s
left join {{ ref('stg_geo__nyc_counties') }} c
    on st_contains(c.county_geom, st_geogpoint(s.lng, s.lat))