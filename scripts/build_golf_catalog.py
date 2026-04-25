#!/usr/bin/env python3
"""Build the bundled golf course catalog from open data sources.

The output schema matches FoundationModel/Resources/golf_courses.json.

Data sources:
- OpenGolfAPI US GeoJSON: https://github.com/opengolfapi/data (ODbL 1.0)
- OpenStreetMap / Overpass Canada extraction: leisure=golf_course (ODbL 1.0)
"""

from __future__ import annotations

import argparse
import gzip
import json
import urllib.parse
import urllib.request
from pathlib import Path


OPEN_GOLF_US_GEOJSON = (
    "https://raw.githubusercontent.com/opengolfapi/data/main/opengolfapi-us.geojson.gz"
)
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
CANADA_GOLF_QUERY = """
[out:json][timeout:180];
area["ISO3166-1"="CA"][admin_level=2]->.canada;
(
  node["leisure"="golf_course"](area.canada);
  way["leisure"="golf_course"](area.canada);
  relation["leisure"="golf_course"](area.canada);
);
out center tags;
"""


def read_url(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=240) as response:
        return response.read()


def coordinate_from_geometry(geometry: dict) -> tuple[float, float] | None:
    if geometry.get("type") == "Point":
        lon, lat = geometry["coordinates"]
        return float(lat), float(lon)
    if geometry.get("type") == "Polygon":
        ring = geometry["coordinates"][0]
        if not ring:
            return None
        lon = sum(point[0] for point in ring) / len(ring)
        lat = sum(point[1] for point in ring) / len(ring)
        return float(lat), float(lon)
    if geometry.get("type") == "MultiPolygon":
        rings = [ring for polygon in geometry["coordinates"] for ring in polygon if ring]
        points = [point for ring in rings for point in ring]
        if not points:
            return None
        lon = sum(point[0] for point in points) / len(points)
        lat = sum(point[1] for point in points) / len(points)
        return float(lat), float(lon)
    return None


def boundary_from_geometry(geometry: dict) -> list[dict] | None:
    if geometry.get("type") != "Polygon":
        return None
    ring = geometry["coordinates"][0][:80]
    return [{"latitude": float(lat), "longitude": float(lon)} for lon, lat in ring]


def normalize_open_golf_course(feature: dict) -> dict | None:
    props = feature.get("properties", {})
    geometry = feature.get("geometry", {})
    coordinate = coordinate_from_geometry(geometry)
    if coordinate is None:
        return None

    lat, lon = coordinate
    course_id = str(props.get("id") or props.get("course_id") or props.get("name"))
    name = props.get("name") or props.get("course_name")
    if not course_id or not name:
        return None

    return {
        "id": f"opengolf-us-{course_id}",
        "name": name,
        "country": "US",
        "region": props.get("state") or props.get("region") or "",
        "city": props.get("city") or "",
        "address": props.get("address") or "",
        "latitude": lat,
        "longitude": lon,
        "boundary": boundary_from_geometry(geometry),
        "holes": [],
        "attribution": "Contains data from OpenGolfAPI (opengolfapi.org), ODbL 1.0.",
    }


def normalize_osm_course(element: dict) -> dict | None:
    tags = element.get("tags", {})
    name = tags.get("name")
    if not name:
        return None

    center = element.get("center")
    if center:
        lat, lon = float(center["lat"]), float(center["lon"])
    elif "lat" in element and "lon" in element:
        lat, lon = float(element["lat"]), float(element["lon"])
    else:
        geometry = element.get("geometry") or []
        if not geometry:
            return None
        lat = sum(point["lat"] for point in geometry) / len(geometry)
        lon = sum(point["lon"] for point in geometry) / len(geometry)

    street = " ".join(
        part
        for part in [tags.get("addr:housenumber", ""), tags.get("addr:street", "")]
        if part
    )
    address = ", ".join(
        part
        for part in [street, tags.get("addr:city", ""), tags.get("addr:province", "")]
        if part
    )
    boundary = None
    if element.get("geometry"):
        boundary = [
            {"latitude": float(point["lat"]), "longitude": float(point["lon"])}
            for point in element["geometry"][:80]
        ]

    return {
        "id": f"osm-ca-{element['type']}-{element['id']}",
        "name": name,
        "country": "CA",
        "region": tags.get("addr:province") or tags.get("addr:state") or "",
        "city": tags.get("addr:city") or "",
        "address": address,
        "latitude": lat,
        "longitude": lon,
        "boundary": boundary,
        "holes": [],
        "attribution": "Contains information from OpenStreetMap, ODbL 1.0.",
    }


def load_us_courses(limit: int | None) -> list[dict]:
    raw = gzip.decompress(read_url(OPEN_GOLF_US_GEOJSON))
    data = json.loads(raw)
    courses = []
    for feature in data.get("features", []):
        course = normalize_open_golf_course(feature)
        if course:
            courses.append(course)
        if limit and len(courses) >= limit:
            break
    return courses


def load_canada_courses(limit: int | None) -> list[dict]:
    body = urllib.parse.urlencode({"data": CANADA_GOLF_QUERY}).encode()
    request = urllib.request.Request(
        OVERPASS_URL,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "FoundationModelGolfDemo/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        data = json.loads(response.read())
    courses = []
    for element in data.get("elements", []):
        course = normalize_osm_course(element)
        if course:
            courses.append(course)
        if limit and len(courses) >= limit:
            break
    return courses


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="FoundationModel/Resources/golf_courses.json")
    parser.add_argument("--limit-us", type=int, default=None)
    parser.add_argument("--limit-ca", type=int, default=None)
    parser.add_argument("--skip-us", action="store_true")
    parser.add_argument("--skip-ca", action="store_true")
    args = parser.parse_args()

    courses: list[dict] = []
    if not args.skip_us:
        courses.extend(load_us_courses(args.limit_us))
    if not args.skip_ca:
        courses.extend(load_canada_courses(args.limit_ca))

    catalog = {
        "schemaVersion": 1,
        "attribution": [
            "Contains data from OpenGolfAPI (opengolfapi.org), ODbL 1.0.",
            "Contains information from OpenStreetMap, ODbL 1.0.",
        ],
        "courses": courses,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(courses)} courses to {output}")


if __name__ == "__main__":
    main()
