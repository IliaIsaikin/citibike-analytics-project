-- models/intermediate/int_station_id_mapping.sql
--
-- Resolves corrupted/duplicate station_ids that appear in raw trip data
-- under a shared station_name (e.g. 7386.1 / 7386.10 are the same
-- physical station; 5303.06 / 5303.06_ are two real, distinct stations).
--
-- Ground truth for "is this id real" = whether it exists in station_info
-- (the GBFS capacity feed), not string pattern-matching.
--
-- A station_id only ever gets remapped when it shares a station_name with
-- another id AND the two are within 100m of each other. That distance
-- check exists so that a future name collision between two genuinely
-- different stations (rare, but possible once we backfill more months)
-- doesn't get silently merged just because the names match.
--
-- Output grain: one row per distinct raw station_id seen in trip data.

with trip_station_ids as (

    -- Deliberately NOT deduped here (union all, not union distinct):
    -- station_id_summary below needs to count and average over every
    -- trip occurrence, not just distinct coordinate values. See
    -- n_trip_rows note below.
    select
        start_station_id as station_id,
        start_station_name as station_name,
        start_lat as lat,
        start_lng as lng
    from {{ ref('stg_citibike__trips') }}
    where start_station_id is not null

    union all

    select
        end_station_id as station_id,
        end_station_name as station_name,
        end_lat as lat,
        end_lng as lng
    from {{ ref('stg_citibike__trips') }}
    where end_station_id is not null

),

-- Collapse to one row per id. avg(lat)/avg(lng) give a stable
-- representative point per id (defensive — today's data has identical
-- coordinates per id, but this holds even if that ever changes).
-- n_trip_rows is real trip volume per id, used as the Case 5 tiebreaker
-- below.
station_id_summary as (

    select
        station_id,
        station_name,
        avg(lat) as avg_lat,
        avg(lng) as avg_lng,
        count(*) as n_trip_rows
    from trip_station_ids
    group by 1, 2

),

-- Tag each id against the capacity feed.
tagged as (

    select
        s.station_id,
        s.station_name,
        s.avg_lat,
        s.avg_lng,
        s.n_trip_rows,
        si.station_id is not null as has_capacity_match
    from station_id_summary s
    left join {{ ref('stg_citibike__station_info') }} si
        on s.station_id = si.station_id

),

-- Roll up to station_name level: how many ids share this name, and how
-- many of them are matched to the capacity feed?
name_groups as (

    select
        station_name,
        countif(has_capacity_match) as n_matched,
        count(*) as n_ids
    from tagged
    group by 1

),

classified as (

    select
        t.*,
        g.n_matched,
        g.n_ids
    from tagged t
    inner join name_groups g using (station_name)

),

-- Pick a candidate canonical id per name group:
--   n_ids = 1                         -> no collision, id maps to itself
--   n_matched = 1, this row matched   -> this row IS canonical
--   n_matched = 1, this row is orphan -> canonical = the matched sibling
--                                        in this name group
--   n_matched = 0, n_ids > 1          -> canonical = id with the most
--                                        trip rows (deterministic
--                                        tiebreak; Stuyvesant Walk case)
--   n_matched >= 2                     -> no merge; every id maps to
--                                        itself (real, distinct stations
--                                        — Clinton St case)
canonical_pick as (

    select
        *,
        case
            when n_ids = 1 then station_id
            when n_matched = 1 and has_capacity_match then station_id
            when n_matched = 1 and not has_capacity_match then
                max(case when has_capacity_match then station_id end)
                    over (partition by station_name)
            when n_matched = 0 then first_value(station_id) over (
                partition by station_name
                order by n_trip_rows desc, station_id
            )
            else station_id  -- n_matched >= 2: leave untouched
        end as candidate_canonical_id
    from classified

),

-- Attach the candidate canonical id's own coordinates, so we can sanity
-- check distance before trusting the merge.
with_canonical_coords as (

    select
        c.*,
        canon.avg_lat as canonical_lat,
        canon.avg_lng as canonical_lng
    from canonical_pick c
    left join canonical_pick canon
        on c.station_name = canon.station_name
        and c.candidate_canonical_id = canon.station_id

),

final as (

    select
        station_id,
        station_name,
        candidate_canonical_id,
        case
            when station_id = candidate_canonical_id then station_id
            when st_distance(
                    st_geogpoint(avg_lng, avg_lat),
                    st_geogpoint(canonical_lng, canonical_lat)
                 ) <= 100
                then candidate_canonical_id
            else station_id  -- too far apart to trust — don't merge
        end as canonical_station_id

    from with_canonical_coords

)

select * from final

-- ALL ID CASES:
-- Case 1 — No name-twin, matched to capacity feed.
-- The normal, boring case. Most of the 2,344 station_ids. Nothing to fix — id maps to itself, has capacity, done.

-- Case 2 — No name-twin, NOT matched to capacity feed.
-- This is our temporal-absence case. A station_id that appears alone under its name, but isn't in the current GBFS snapshot.
-- This is exactly what a station that closed before your GBFS pull, or hasn't opened yet, looks like — 
-- a real station with no capacity data, and critically, nothing to merge it with, because it has no colliding sibling.
-- The model maps it to itself and lets capacity stay NULL, same as the existing nullif-handling.
-- It is not touched by any merge logic, because merging only ever happens between id-twins under the same name.
-- So the temporal-absence scenario is already handled — correctly — by the simple fact that
-- the model only acts when there's a collision to resolve. A lonely unmatched id is left completely alone.

-- Case 3 — Two ids, same name, exactly one matched + one orphan, and they're close together (< 100m).
-- This is the core bug — 52 of 54 collisions (e.g. 7386.1/7386.10, E 17 St & Broadway).
-- The orphan gets merged into the matched id. This is the "real fix" case.

-- Case 4 — Two ids, same name, exactly one matched + one orphan, but they're far apart (> 100m).
-- Hasn't happened yet in our current month of data (May 2026), but this is the safety net for the future: imagine a coincidence
-- where two genuinely unrelated stations end up with the same name (unlikely, but not impossible across boroughs) and
-- one of them happens to be missing from the capacity feed. Without a distance check, the model would wrongly merge
-- two real, different stations just because the name matched and one side happened to be missing from station_info.
-- Instead, it does not merge — both ids are kept separate, each mapping to itself.

-- Case 5 — Two-plus ids, same name, zero matched, but all at the same location.
-- Stuyvesant Walk & 1 Ave Loop case — neither 5854.1 nor 5854.10 is in the capacity feed, but they're at identical coordinates.
-- The model picks one of them (whichever has more trip rows, as a deterministic tiebreaker) as canonical and merges
-- the other into it. Capacity correctly stays NULL for the merged station, since neither side had real capacity data to begin with.

-- Case 6 — Two-plus ids, same name, zero matched, and NOT at the same location.
-- Theoretical case, hasn't shown up yet: two orphan ids sharing a name, but genuinely different places.
-- The distance guard catches this the same way it does in Case 4 — no merge, each id maps to itself.

-- Case 7 — Two-plus ids, same name, two or more matched.
-- Clinton St & Grand St case — 5303.06 and 5303.06_ are both real, both in the capacity feed, both with their own
-- distinct capacity (54 vs 15 docks). The model doesn't merge these at all; each keeps its own identity, as it should.