with stations as (

    select * from {{ ref('dim_stations') }}

),

boroughs as (

    select * from {{ ref('int_station_borough') }}

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

-- Worst single-day accumulation and drain per station, from the
-- station-day grain model. peak_daily_accumulation is the single best
-- (most positive) day; peak_daily_drain is the single worst (most
-- negative) day. These can reveal risk that the monthly average hides —
-- a station balanced on average can still have one brutal day.
daily_extremes as (

    select
        station_id,
        max(net_flow) as peak_daily_accumulation,
        min(net_flow) as peak_daily_drain
    from {{ ref('int_station_daily_net_flow') }}
    group by 1

),

combined as (

    select
        s.station_id,
        s.station_name,
        s.lat,
        s.lng,
        s.capacity,
        b.borough,

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
        ) as activity_per_dock,

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
    left join boroughs b on s.station_id = b.station_id

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

        -- avg_daily_activity_per_dock: daily throughput relative to station
        -- size. Derived independently from total_station_activity /
        -- capacity / n_days rather than dividing the already-rounded
        -- activity_per_dock, to avoid compounding rounding error.
        round(
            safe_divide(c.total_station_activity, c.capacity * n.n_days),
            2
        ) as avg_daily_activity_per_dock,

        -- avg_daily_net_flow_per_dock: daily imbalance relative to
        -- station size. The recommended metric for flagging stations
        -- that drain/accumulate too much relative to their capacity.
        round(
            safe_divide(c.net_flow, c.capacity * n.n_days),
            2
        ) as avg_daily_net_flow_per_dock

    from combined c
    cross join n_days_in_window n

),

with_readable_metrics as (

    select
        f.*,

        -- avg_daily_net_flow_pct: avg_daily_net_flow_per_dock expressed
        -- as a percentage — the % of the station's total capacity
        -- gained (positive) or lost (negative) per day on average.
        round(f.avg_daily_net_flow_per_dock * 100, 1) as avg_daily_net_flow_pct,

        -- days_to_fill_or_drain: rough estimate of how many days it
        -- would take this station to go from empty to full (if
        -- avg_daily_net_flow is positive) or full to empty (if
        -- negative), at the station's current average daily net flow
        -- rate. Unsigned — pair with the sign of avg_daily_net_flow to
        -- know which direction applies. CAVEAT: assumes a constant
        -- daily rate and no rebalancing intervention — a rough
        -- operational signal, not a guaranteed timeline. Null when net
        -- flow is ~0 (no meaningful trend) or capacity is unknown.
        round(
            safe_divide(f.capacity, abs(f.avg_daily_net_flow)),
            1
        ) as days_to_fill_or_drain

    from final f

),

with_daily_extremes as (

    select
        w.*,
        e.peak_daily_accumulation,
        e.peak_daily_drain,

        -- Per-dock versions: the worst single day expressed relative to
        -- station size. A peak_daily_drain of -20 is mild for a 100-dock
        -- station but catastrophic for a 20-dock one.
        round(safe_divide(e.peak_daily_accumulation, w.capacity), 2) as peak_daily_accumulation_per_dock,
        round(safe_divide(e.peak_daily_drain, w.capacity), 2) as peak_daily_drain_per_dock

    from with_readable_metrics w
    left join daily_extremes e on w.station_id = e.station_id

)

select * from with_daily_extremes