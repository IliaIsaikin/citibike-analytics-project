-- Station-day grain net flow. One row per (station_id, trip_date) that had
-- any activity. Feeds the peak/trough daily metrics in agg_station_demand —
-- these surface the single worst day a station experienced, which the
-- monthly-average metrics smooth over and can hide entirely.

with daily_departures as (

    select
        start_station_id as station_id,
        trip_date,
        count(*) as departures
    from {{ ref('fct_trips') }}
    where start_station_id is not null
    group by 1, 2

),

daily_arrivals as (

    select
        end_station_id as station_id,
        trip_date,
        count(*) as arrivals
    from {{ ref('fct_trips') }}
    where end_station_id is not null
    group by 1, 2

),

combined as (

    select
        coalesce(d.station_id, a.station_id) as station_id,
        coalesce(d.trip_date, a.trip_date) as trip_date,
        coalesce(d.departures, 0) as departures,
        coalesce(a.arrivals, 0) as arrivals,
        coalesce(a.arrivals, 0) - coalesce(d.departures, 0) as net_flow
    from daily_departures d
    full outer join daily_arrivals a
        on d.station_id = a.station_id
        and d.trip_date = a.trip_date

)

select * from combined