with source as (

    select * from {{ source('citibike', 'trips') }}

),

renamed as (

    select
        -- identifiers
        ride_id,
        rideable_type,
        member_casual as user_type,

        -- timestamps (cast from string to timestamp)
        cast(started_at as timestamp) as started_at,
        cast(ended_at as timestamp) as ended_at,

        -- derived: trip duration in minutes
        timestamp_diff(
            cast(ended_at as timestamp),
            cast(started_at as timestamp),
            second
        ) / 60.0 as trip_duration_minutes,

        -- start station
        start_station_id,
        start_station_name,
        cast(start_lat as float64) as start_lat,
        cast(start_lng as float64) as start_lng,

        -- end station
        end_station_id,
        end_station_name,
        cast(end_lat as float64) as end_lat,
        cast(end_lng as float64) as end_lng

    from source

)

select * from renamed