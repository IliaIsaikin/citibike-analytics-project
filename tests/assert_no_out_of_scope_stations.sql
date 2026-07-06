-- Fails if any Jersey City / Hoboken station id ever appears in the
-- fact table. These should always be nulled out in int_trips_enriched.
select *
from {{ ref('fct_trips') }}
where start_station_id like 'JC%' or start_station_id like 'HB%'
   or end_station_id like 'JC%' or end_station_id like 'HB%'