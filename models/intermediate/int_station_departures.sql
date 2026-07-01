with trips as (

    select * from {{ ref('fct_trips') }}

),

departures as (

    select
        start_station_id as station_id,
        count(*) as departures,
        count(distinct case when user_type = 'member' then ride_id end) as departures_member,
        count(distinct case when user_type = 'casual' then ride_id end) as departures_casual
    from trips
    where start_station_id is not null
    group by start_station_id

)

select * from departures