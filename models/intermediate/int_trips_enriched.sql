with trips as (

    select
        t.* except (
            start_station_id, start_station_name, start_lat, start_lng,
            end_station_id, end_station_name, end_lat, end_lng
        ),

        -- Resolve station ids via the id-mapping fix, then null out any
        -- endpoint outside the NYC network (Jersey City / Hoboken).
        -- These trips are real (mostly NYC-origin trips whose bike was
        -- ridden across the river) — the out-of-network endpoint is
        -- treated the same way dockless endpoints already are: unknown,
        -- not fabricated or dropped. See TECHNICAL_BLUEPRINT.md.
        case
            when t.start_station_id like 'JC%' or t.start_station_id like 'HB%' then null
            else coalesce(start_map.canonical_station_id, t.start_station_id)
        end as start_station_id,
        case
            when t.start_station_id like 'JC%' or t.start_station_id like 'HB%' then null
            else t.start_station_name
        end as start_station_name,
        case
            when t.start_station_id like 'JC%' or t.start_station_id like 'HB%' then null
            else t.start_lat
        end as start_lat,
        case
            when t.start_station_id like 'JC%' or t.start_station_id like 'HB%' then null
            else t.start_lng
        end as start_lng,

        case
            when t.end_station_id like 'JC%' or t.end_station_id like 'HB%' then null
            else coalesce(end_map.canonical_station_id, t.end_station_id)
        end as end_station_id,
        case
            when t.end_station_id like 'JC%' or t.end_station_id like 'HB%' then null
            else t.end_station_name
        end as end_station_name,
        case
            when t.end_station_id like 'JC%' or t.end_station_id like 'HB%' then null
            else t.end_lat
        end as end_lat,
        case
            when t.end_station_id like 'JC%' or t.end_station_id like 'HB%' then null
            else t.end_lng
        end as end_lng

    from {{ ref('stg_citibike__trips') }} t
    left join {{ ref('int_station_id_mapping') }} start_map
        on t.start_station_id = start_map.station_id
    left join {{ ref('int_station_id_mapping') }} end_map
        on t.end_station_id = end_map.station_id

),

enriched as (

    select
        -- identifiers & attributes (passed through)
        ride_id,
        rideable_type,
        user_type,
        started_at,
        ended_at,
        trip_duration_minutes,
        start_station_id,
        start_station_name,
        start_lat,
        start_lng,
        end_station_id,
        end_station_name,
        end_lat,
        end_lng,

        -- date/time parts derived from started_at
        date(started_at) as trip_date,
        extract(hour from started_at) as trip_hour,
        format_date('%A', date(started_at)) as day_of_week,
        extract(dayofweek from started_at) in (1, 7) as is_weekend,

        -- round trip: started and ended at the same station.
        -- Naturally null when either station is null (dockless or
        -- out-of-network end), consistent with existing convention.
        start_station_id = end_station_id as is_round_trip,

        -- straight-line distance between start and end (descriptive feature)
        {{ dbt_utils.haversine_distance(
            'start_lat', 'start_lng',
            'end_lat', 'end_lng',
            unit='km'
        ) }} as trip_distance_km

    from trips

    -- validity cleanup (see project brief: duration profiling + fee structure)
    where trip_duration_minutes >= 1        -- drop sub-1-minute (defensive; none found)
      and trip_duration_minutes < 120       -- drop >= 2 hours (probable docking failures)
      -- negative durations are excluded by the >= 1 condition above

)

select * from enriched