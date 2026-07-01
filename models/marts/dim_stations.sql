with trips as (

    select * from {{ ref('int_trips_enriched') }}

),

-- gather every station appearance from the START side
start_stations as (

    select
        start_station_id as station_id,
        start_station_name as station_name,
        start_lat as lat,
        start_lng as lng
    from trips
    where start_station_id is not null

),

-- gather every station appearance from the END side
end_stations as (

    select
        end_station_id as station_id,
        end_station_name as station_name,
        end_lat as lat,
        end_lng as lng
    from trips
    where end_station_id is not null

),

-- combine both sides into one long list of station appearances
all_stations as (

    select * from start_stations
    union all
    select * from end_stations

),

-- collapse to one row per station, picking representative values
deduplicated as (

    select
        station_id,
        max(station_name) as station_name,
        avg(lat) as lat,
        avg(lng) as lng,
        count(*) as appearance_count
    from all_stations
    group by station_id

)

select * from deduplicated