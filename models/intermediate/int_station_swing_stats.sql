with daily_swing as (

    select * from {{ ref('int_station_daily_swing') }}

),

station_swing_stats as (

    select
        station_id,
        max(day_swing) as max_daily_swing,
        avg(day_swing) as avg_daily_swing,
        count(distinct event_date) as days_observed

    from daily_swing
    group by station_id

)

select * from station_swing_stats