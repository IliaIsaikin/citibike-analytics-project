"""
Fetch Citi Bike station information from the GBFS feed, transform it into a
clean table, and load it into BigQuery as citibike_raw.station_info.

The `capacity` field is total dock capacity per station (static), used to
normalize demand (trips-per-dock). Join key to trip data is `short_name`
(loaded here as `station_id`).
"""

import requests
import pandas as pd
import pandas_gbq

GBFS_URL = "https://gbfs.citibikenyc.com/gbfs/en/station_information.json"

# BigQuery destination
PROJECT_ID = "sincere-strata-500023-j8"
DESTINATION_TABLE = "citibike_raw.station_info"


def fetch_station_info(url):
    """Make an HTTP GET request to the GBFS feed and return the parsed JSON."""
    print(f"Fetching: {url}")
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.json()


def transform(data):
    """Extract the fields we need into a clean pandas DataFrame."""
    stations = data["data"]["stations"]

    records = []
    for s in stations:
        records.append({
            "station_id": s.get("short_name"),   # maps to trip data's station_id
            "station_name": s.get("name"),
            "capacity": s.get("capacity"),
            "lat": s.get("lat"),
            "lng": s.get("lon"),                 # feed uses "lon", we standardize to "lng"
        })

    df = pd.DataFrame(records)
    return df


def load_to_bigquery(df):
    """Load the DataFrame into BigQuery, replacing the table each run."""
    print(f"\nLoading {len(df)} rows to {PROJECT_ID}.{DESTINATION_TABLE} ...")
    pandas_gbq.to_gbq(
        df,
        destination_table=DESTINATION_TABLE,
        project_id=PROJECT_ID,
        if_exists="replace",   # overwrite the table on each run (idempotent)
    )
    print("Load complete.")


def main():
    data = fetch_station_info(GBFS_URL)
    df = transform(data)
    print(f"Transformed {len(df)} rows.")
    load_to_bigquery(df)


if __name__ == "__main__":
    main()