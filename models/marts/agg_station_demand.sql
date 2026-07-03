with stations as (

    select * from {{ ref('dim_stations') }}

),

departures as (

    select * from {{ ref('int_station_departures') }}

),

arrivals as (

    select * from {{ ref('int_station_arrivals') }}

),

-- Number of distinct trip dates currently loaded. Computed dynamically
-- (not hardcoded) so avg_daily_* metrics stay correct automatically as
-- more months are backfilled in Phase 7 — this is the fix for the
-- temporal-denominator issue flagged in the original project handoff.
n_days_in_window as (

    select count(distinct trip_date) as n_days
    from {{ ref('fct_trips') }}

),

combined as (

    select
        s.station_id,
        s.station_name,
        s.lat,
        s.lng,
        s.capacity,

        -- departures (coalesce nulls to 0 for one-directional stations)
        coalesce(d.departures, 0) as departures,
        coalesce(d.departures_member, 0) as departures_member,
        coalesce(d.departures_casual, 0) as departures_casual,

        -- arrivals
        coalesce(a.arrivals, 0) as arrivals,
        coalesce(a.arrivals_member, 0) as arrivals_member,
        coalesce(a.arrivals_casual, 0) as arrivals_casual,

        -- total_station_activity: departures + arrivals at this station.
        -- Deliberately NOT named "total_trips" — it is NOT a trip count.
        -- Each trip contributes one departure at its start station and
        -- one arrival at its end station, so this measures dock-level
        -- activity in either direction (bike-touches at this specific
        -- dock), not distinct trips. This is the correct measure for
        -- capacity/strain purposes, since dock stress comes from both
        -- departures (bike availability) and arrivals (dock availability).
        -- IMPORTANT: do not SUM() this column across stations to get a
        -- network-wide trip count — it would double-count every trip
        -- (~9.36M vs. the real ~4.685M trips). Use fct_trips for
        -- network-level trip counts instead.
        coalesce(d.departures, 0) + coalesce(a.arrivals, 0) as total_station_activity,

        -- net flow (arrivals - departures): positive = net accumulation (fills), negative = net drain (empties)
        coalesce(a.arrivals, 0) - coalesce(d.departures, 0) as net_flow,

        -- demand-to-capacity ratio: station activity per dock.
        -- Null when capacity is unknown (unmatched or inactive stations).
        round(
            (coalesce(d.departures, 0) + coalesce(a.arrivals, 0)) / s.capacity,
            1
        ) as trips_per_dock,

        -- net-flow-to-capacity ratio: net accumulation per dock.
        -- Positive = fills relative to size, negative = drains relative to size.
        -- Null when capacity is unknown (unmatched or inactive stations).
        round(
            (coalesce(a.arrivals, 0) - coalesce(d.departures, 0)) / s.capacity,
            1
        ) as net_flow_per_dock

    from stations s
    left join departures d on s.station_id = d.station_id
    left join arrivals a on s.station_id = a.station_id

),

final as (

    select
        c.*,
        n.n_days,

        -- avg_daily_station_activity: station activity (departures +
        -- arrivals) per day. Easier to reason about than a monthly
        -- total, and stable in meaning as more months are backfilled
        -- (a monthly total's meaning silently drifts as the window
        -- grows; a daily average doesn't). Same double-counting caveat
        -- as total_station_activity applies if summed across stations.
        round(c.total_station_activity / n.n_days, 1) as avg_daily_station_activity,

        -- avg_daily_net_flow: net bikes gained/lost per day. Positive =
        -- station accumulates roughly this many bikes/day on average;
        -- negative = station drains roughly this many bikes/day.
        round(c.net_flow / n.n_days, 1) as avg_daily_net_flow,

        -- avg_daily_trips_per_dock: daily throughput relative to station
        -- size. Derived independently from total_station_activity /
        -- capacity / n_days rather than dividing the already-rounded
        -- trips_per_dock, to avoid compounding rounding error.
        round(
            safe_divide(c.total_station_activity, c.capacity * n.n_days),
            2
        ) as avg_daily_trips_per_dock,

        -- avg_daily_net_flow_per_dock: daily imbalance relative to
        -- station size. This is the metric most useful for flagging
        -- stations that drain/accumulate too much relative to their
        -- capacity — a distribution/threshold analysis on this column
        -- is a good candidate for the Findings write-up.
        round(
            safe_divide(c.net_flow, c.capacity * n.n_days),
            2
        ) as avg_daily_net_flow_per_dock

    from combined c
    cross join n_days_in_window n

)

select * from final