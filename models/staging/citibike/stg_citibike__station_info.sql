with source as (

    select * from {{ source('citibike', 'station_info') }}

),

cleaned as (

    select
        station_id,
        station_name,

        -- capacity of 0 means inactive/unknown station, not a real dock count.
        -- Convert to null: semantically honest, and avoids divide-by-zero when
        -- computing trips_per_dock downstream.
        nullif(capacity, 0) as capacity,
        
        lat,
        lng

    from source

)

select * from cleaned