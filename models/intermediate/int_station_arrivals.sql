with trips as (

    select * from {{ ref('fct_trips') }}

),

arrivals as (

    select
        end_station_id as station_id,
        count(*) as arrivals,
        count(distinct case when user_type = 'member' then ride_id end) as arrivals_member,
        count(distinct case when user_type = 'casual' then ride_id end) as arrivals_casual
    from trips
    where end_station_id is not null
    group by end_station_id

)

select * from arrivals