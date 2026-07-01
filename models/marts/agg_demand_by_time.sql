with trips as (

    select * from {{ ref('fct_trips') }}

),

demand_by_time as (

    select
        day_of_week,
        trip_hour,
        is_weekend,
        user_type,

        -- volume
        count(*) as trip_count,

        -- behavioral measures
        round(avg(trip_duration_minutes), 2) as avg_duration_minutes,
        round(avg(trip_distance_km), 2) as avg_distance_km

    from trips
    group by
        day_of_week,
        trip_hour,
        is_weekend,
        user_type

)

select * from demand_by_time