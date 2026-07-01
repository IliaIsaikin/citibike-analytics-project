with stations as (

    select * from {{ ref('dim_stations') }}

),

departures as (

    select * from {{ ref('int_station_departures') }}

),

arrivals as (

    select * from {{ ref('int_station_arrivals') }}

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

        -- total demand (departures + arrivals)
        coalesce(d.departures, 0) + coalesce(a.arrivals, 0) as total_trips,

        -- net flow (arrivals - departures): positive = net accumulation (fills), negative = net drain (empties)
        coalesce(a.arrivals, 0) - coalesce(d.departures, 0) as net_flow,

        -- demand-to-capacity ratio: total trips per dock.
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

)

select * from combined