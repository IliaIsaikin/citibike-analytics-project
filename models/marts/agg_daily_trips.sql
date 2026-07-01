with trips as (

    select * from {{ ref('stg_citibike__trips') }}

),

daily as (

    select
        date(started_at) as trip_date,
        count(*) as trip_count
    from trips
    group by trip_date

)

select * from daily
order by trip_date