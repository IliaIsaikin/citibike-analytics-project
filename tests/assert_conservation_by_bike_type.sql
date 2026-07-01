-- Conservation-by-bike-type check (behavioral, tolerance-based).
--
-- Classic bikes must dock at a station to end a trip, so their departures
-- and arrivals should conserve almost perfectly (observed ~0.002% net flow).
-- E-bikes can end dockless (off-station), producing a legitimate but larger
-- asymmetry (observed ~0.19% net flow).
--
-- This test asserts each bike type's net-flow rate stays within a tolerance
-- anchored to that observed behavior. Tolerances are loose enough to survive
-- month-to-month variation, tight enough to catch a real anomaly.
--
-- Passes if zero rows are returned (no bike type exceeds its tolerance).

with departures as (

    select
        rideable_type,
        count(*) as departures
    from {{ ref('fct_trips') }}
    where start_station_id is not null
    group by rideable_type

),

arrivals as (

    select
        rideable_type,
        count(*) as arrivals
    from {{ ref('fct_trips') }}
    where end_station_id is not null
    group by rideable_type

),

net_flow_by_type as (

    select
        d.rideable_type,
        d.departures,
        a.arrivals,
        abs(d.departures - a.arrivals) as abs_net_flow,
        abs(d.departures - a.arrivals) / d.departures as net_flow_rate
    from departures d
    join arrivals a on d.rideable_type = a.rideable_type

),

violations as (

    select
        rideable_type,
        departures,
        arrivals,
        net_flow_rate
    from net_flow_by_type
    where
        (rideable_type = 'classic_bike' and net_flow_rate > 0.001)  -- 0.1% tolerance
        or
        (rideable_type = 'electric_bike' and net_flow_rate > 0.01)  -- 1% tolerance

)

select * from violations