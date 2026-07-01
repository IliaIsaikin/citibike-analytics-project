with enriched as (

    select * from {{ ref('int_trips_enriched') }}

),

final as (

    select
        -- primary key
        ride_id,

        -- foreign keys to dim_stations
        start_station_id,
        end_station_id,

        -- rider & bike attributes
        user_type,
        rideable_type,

        -- time
        started_at,
        ended_at,
        trip_date,
        trip_hour,
        day_of_week,
        is_weekend,

        -- measures
        trip_duration_minutes,
        trip_distance_km

    from enriched

)

select * from final