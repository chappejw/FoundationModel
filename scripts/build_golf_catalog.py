#!/usr/bin/env python3
"""Build compact ODRSF-only resources for the golf map demo.

Inputs:
- FoundationModel/ODRSF_V1.0/ODRSF_v1.0.csv

Outputs:
- FoundationModel/Resources/odrsf_golf_courses.json
- FoundationModel/Resources/odrsf_facilities.json
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path


ODRSF_CSV = Path("FoundationModel/ODRSF_V1.0/ODRSF_v1.0.csv")
DEFAULT_COURSES_OUTPUT = Path("FoundationModel/Resources/odrsf_golf_courses.json")
DEFAULT_FACILITIES_OUTPUT = Path("FoundationModel/Resources/odrsf_facilities.json")

COUNTRY = "CA"
VALID_LAT_RANGE = (41.0, 84.0)
VALID_LON_RANGE = (-142.0, -52.0)
GOLF_TERMS = ("golf", "driving range")
NEARBY_AMENITY_RADIUS_MILES = 2.0
SOURCE_ATTRIBUTION = (
    "Contains information from the Open Database of Recreational and Sport Facilities "
    "(ODRSF) v1.0, Statistics Canada and contributing open data providers."
)


def clean(value: str | None) -> str:
    text = (value or "").strip()
    if not text or text in {"..", "_", "-"}:
        return ""
    return re.sub(r"\s+", " ", text)


def title_case(value: str) -> str:
    if not value:
        return ""
    return value.title().replace("'S", "'s")


def slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower())
    return normalized.strip("-") or "facility"


def valid_coordinate(row: dict[str, str]) -> tuple[float, float] | None:
    try:
        lat = float(row["Latitude"])
        lon = float(row["Longitude"])
    except (KeyError, TypeError, ValueError):
        return None

    if VALID_LAT_RANGE[0] <= lat <= VALID_LAT_RANGE[1] and VALID_LON_RANGE[0] <= lon <= VALID_LON_RANGE[1]:
        return lat, lon
    return None


def normalized_name(row: dict[str, str]) -> str:
    name = clean(row.get("Facility_Name"))
    if name:
        return title_case(name)

    facility_type = title_case(clean(row.get("ODRSF_facility_type")) or "Facility")
    place = title_case(clean(row.get("CSD_Name")) or clean(row.get("City")) or clean(row.get("Prov_Terr")) or "Canada")
    return f"{facility_type} in {place}"


def normalized_location(row: dict[str, str]) -> tuple[str, str, str]:
    municipality = title_case(clean(row.get("CSD_Name")) or clean(row.get("City")))
    province = clean(row.get("Prov_Terr")).upper()
    address = clean(row.get("Source_Format_Address"))
    return municipality, province, address


def is_golf_facility(row: dict[str, str]) -> bool:
    haystack = " ".join(
        clean(row.get(field)).lower()
        for field in ("Facility_Name", "Source_Facility_Type", "ODRSF_facility_type")
    )
    return any(term in haystack for term in GOLF_TERMS)


def facility_record(row: dict[str, str], lat: float, lon: float) -> dict:
    municipality, province, address = normalized_location(row)
    facility_type = clean(row.get("ODRSF_facility_type")) or "miscellaneous"
    provider = title_case(clean(row.get("Provider")) or "ODRSF")
    source_index = clean(row.get("Index"))
    source_type = clean(row.get("Source_Facility_Type"))
    name = normalized_name(row)

    return {
        "id": f"odrsf-{source_index or slug(f'{name}-{lat:.6f}-{lon:.6f}')}",
        "name": name,
        "facilityType": facility_type,
        "sourceFacilityType": source_type,
        "provider": provider,
        "municipality": municipality,
        "province": province,
        "country": COUNTRY,
        "address": title_case(address),
        "latitude": round(lat, 7),
        "longitude": round(lon, 7),
        "sourceIndex": source_index,
        "isGolfFacility": is_golf_facility(row),
    }


def course_record(row: dict[str, str], lat: float, lon: float) -> dict:
    facility = facility_record(row, lat, lon)
    return {
        "id": facility["id"],
        "name": facility["name"],
        "country": COUNTRY,
        "region": facility["province"],
        "city": facility["municipality"],
        "address": facility["address"],
        "latitude": facility["latitude"],
        "longitude": facility["longitude"],
        "boundary": None,
        "holes": [],
        "facilityType": facility["facilityType"],
        "sourceFacilityType": facility["sourceFacilityType"],
        "provider": facility["provider"],
        "sourceIndex": facility["sourceIndex"],
        "attribution": SOURCE_ATTRIBUTION,
    }


def dedupe_key(record: dict) -> tuple:
    return (
        record["name"].lower(),
        record.get("facilityType", "").lower(),
        record.get("municipality", record.get("city", "")).lower(),
        record.get("province", record.get("region", "")).lower(),
        round(float(record["latitude"]), 5),
        round(float(record["longitude"]), 5),
    )


def unique_records(records: list[dict]) -> list[dict]:
    unique: dict[tuple, dict] = {}
    for record in records:
        key = dedupe_key(record)
        existing = unique.get(key)
        if existing is None:
            unique[key] = record
            continue

        if not existing.get("address") and record.get("address"):
            unique[key] = record
    return list(unique.values())


def distance_miles(lhs: dict, rhs: dict) -> float:
    radius = 3_958.8
    lhs_lat = math.radians(lhs["latitude"])
    rhs_lat = math.radians(rhs["latitude"])
    delta_lat = math.radians(rhs["latitude"] - lhs["latitude"])
    delta_lon = math.radians(rhs["longitude"] - lhs["longitude"])
    a = math.sin(delta_lat / 2) ** 2 + math.cos(lhs_lat) * math.cos(rhs_lat) * math.sin(delta_lon / 2) ** 2
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def facilities_near_courses(facilities: list[dict], courses: list[dict]) -> list[dict]:
    cell_size = 0.1
    grid: dict[tuple[int, int], list[int]] = {}
    for index, facility in enumerate(facilities):
        key = (int(facility["latitude"] / cell_size), int(facility["longitude"] / cell_size))
        grid.setdefault(key, []).append(index)

    kept_indexes: set[int] = set()
    cell_radius = 2
    for course in courses:
        course_key = (int(course["latitude"] / cell_size), int(course["longitude"] / cell_size))
        for lat_offset in range(-cell_radius, cell_radius + 1):
            for lon_offset in range(-cell_radius, cell_radius + 1):
                for index in grid.get((course_key[0] + lat_offset, course_key[1] + lon_offset), []):
                    if distance_miles(course, facilities[index]) <= NEARBY_AMENITY_RADIUS_MILES:
                        kept_indexes.add(index)

    return [facilities[index] for index in sorted(kept_indexes)]


def load_odrsf(path: Path) -> tuple[list[dict], list[dict]]:
    facilities: list[dict] = []
    courses: list[dict] = []

    with path.open(newline="", encoding="latin-1") as handle:
        for row in csv.DictReader(handle):
            coordinate = valid_coordinate(row)
            if coordinate is None:
                continue

            lat, lon = coordinate
            facilities.append(facility_record(row, lat, lon))
            if is_golf_facility(row):
                courses.append(course_record(row, lat, lon))

    return unique_records(courses), unique_records(facilities)


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=ODRSF_CSV)
    parser.add_argument("--courses-output", type=Path, default=DEFAULT_COURSES_OUTPUT)
    parser.add_argument("--facilities-output", type=Path, default=DEFAULT_FACILITIES_OUTPUT)
    args = parser.parse_args()

    courses, facilities = load_odrsf(args.input)
    facilities = facilities_near_courses(facilities, courses)

    write_json(
        args.courses_output,
        {
            "schemaVersion": 2,
            "source": "ODRSF v1.0",
            "nearbyRadiusMiles": NEARBY_AMENITY_RADIUS_MILES,
            "attribution": [SOURCE_ATTRIBUTION],
            "courses": sorted(courses, key=lambda item: (item["region"], item["city"], item["name"])),
        },
    )
    write_json(
        args.facilities_output,
        {
            "schemaVersion": 1,
            "source": "ODRSF v1.0",
            "nearbyRadiusMiles": NEARBY_AMENITY_RADIUS_MILES,
            "attribution": [SOURCE_ATTRIBUTION],
            "facilities": sorted(
                facilities,
                key=lambda item: (item["province"], item["municipality"], item["facilityType"], item["name"]),
            ),
        },
    )

    print(f"Wrote {len(courses)} ODRSF golf courses to {args.courses_output}")
    print(f"Wrote {len(facilities)} ODRSF facilities to {args.facilities_output}")


if __name__ == "__main__":
    main()
