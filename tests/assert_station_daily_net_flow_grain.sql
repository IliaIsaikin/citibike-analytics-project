-- tests/assert_station_daily_net_flow_grain.sql
select station_id, trip_date, count(*) as n
from {{ ref('int_station_daily_net_flow') }}
group by 1, 2
having count(*) > 1