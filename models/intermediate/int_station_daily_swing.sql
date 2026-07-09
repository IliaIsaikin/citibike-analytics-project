with events as (

    -- Every departure decrements the station's bike count; every arrival
    -- increments it. Trips with a null endpoint (dockless / out-of-network,
    -- see int_trips_enriched) are excluded — a null endpoint carries no
    -- information about swing at a specific station.
    select
        start_station_id as station_id,
        started_at as event_ts,
        date(started_at) as event_date,
        -1 as delta
    from {{ ref('int_trips_enriched') }}
    where start_station_id is not null

    union all

    select
        end_station_id as station_id,
        ended_at as event_ts,
        date(ended_at) as event_date,
        1 as delta
    from {{ ref('int_trips_enriched') }}
    where end_station_id is not null

),

running as (

    -- Cumulative net bike count relative to an arbitrary zero at the start
    -- of each station-day. The zero point is unknown (actual midnight
    -- occupancy isn't tracked), but the *range* this cumulative value
    -- travels through during the day is independent of that unknown
    -- baseline. See TECHNICAL_BLUEPRINT.md for the full reasoning.
    select
        station_id,
        event_date,
        event_ts,
        sum(delta) over (
            partition by station_id, event_date
            order by event_ts
            rows between unbounded preceding and current row
        ) as cumulative_net

    from events

),

daily_swing as (

    select
        station_id,
        event_date,
        max(cumulative_net) - min(cumulative_net) as day_swing

    from running
    group by station_id, event_date

)

select * from daily_swing