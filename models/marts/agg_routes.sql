with trips as (

    select * from {{ ref('fct_trips') }}

),

stations as (

    select * from {{ ref('dim_stations') }}

),

routes as (

    select
        start_station_id,
        end_station_id,
        count(*) as trip_count,
        round(avg(trip_duration_minutes), 2) as avg_duration_minutes,
        round(avg(trip_distance_km), 2) as avg_distance_km
    from trips
    where start_station_id is not null
      and end_station_id is not null
    group by start_station_id, end_station_id

),

routes_named as (

    select
        r.start_station_id,
        s_start.station_name as start_station_name,
        s_start.lat as start_lat,
        s_start.lng as start_lng,

        r.end_station_id,
        s_end.station_name as end_station_name,
        s_end.lat as end_lat,
        s_end.lng as end_lng,

        r.trip_count,
        r.avg_duration_minutes,
        r.avg_distance_km
    from routes r
    left join stations s_start on r.start_station_id = s_start.station_id
    left join stations s_end on r.end_station_id = s_end.station_id

)

select * from routes_named
order by trip_count desc