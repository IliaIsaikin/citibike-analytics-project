with trips as (

    select * from {{ ref('stg_citibike__trips') }}

),

enriched as (

    select
        -- identifiers & attributes (passed through)
        ride_id,
        rideable_type,
        user_type,
        started_at,
        ended_at,
        trip_duration_minutes,
        start_station_id,
        start_station_name,
        start_lat,
        start_lng,
        end_station_id,
        end_station_name,
        end_lat,
        end_lng,

        -- date/time parts derived from started_at
        date(started_at) as trip_date,
        extract(hour from started_at) as trip_hour,
        format_date('%A', date(started_at)) as day_of_week,
        extract(dayofweek from started_at) in (1, 7) as is_weekend,

        -- round trip: started and ended at the same station
        start_station_id = end_station_id as is_round_trip,

        -- straight-line distance between start and end (descriptive feature)
        {{ dbt_utils.haversine_distance(
            'start_lat', 'start_lng',
            'end_lat', 'end_lng',
            unit='km'
        ) }} as trip_distance_km

    from trips

    -- validity cleanup (see project brief: duration profiling + fee structure)
    where trip_duration_minutes >= 1        -- drop sub-1-minute (defensive; none found)
      and trip_duration_minutes < 120       -- drop >= 2 hours (probable docking failures)
      -- negative durations are excluded by the >= 1 condition above

)

select * from enriched