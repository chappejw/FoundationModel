# FoundationModel

A hands-on SwiftUI sample app demonstrating Apple’s **FoundationModels** framework and on-device AI patterns for iOS 26.

This repository now includes a complete **Golf Course Locator** example that downloads free golf course data, caches it locally in SwiftData (SQLite-backed), and lets users browse and select courses from both a map and a list.

## Features

### FoundationModels demos
- Availability checks (`SystemLanguageModel.default.availability`)
- Basic text generation (`LanguageModelSession.respond`)
- Streaming generation (`streamResponse`)
- Multi-turn chat with transcript context
- Guided generation with `@Generable` and `@Guide`
- Tool calling with custom `Tool` types
- Generation options (temperature, sampling, token limits, prewarming)

### Golf Course Locator demo
- Download golf course records for **United States** or **Canada**
- Uses free OpenStreetMap data via the Overpass API
- Persists downloaded data using **SwiftData** (`@Model`) with SQLite storage
- Cache-aware loading (reuses local data, refreshes stale data)
- Map-based selection and list-based selection
- Filters by:
  - Name
  - State / Province
  - Country
- Displays selected golf course details:
  - Name
  - Address
  - Phone number

## Free Data Source

This project uses OpenStreetMap data through the public Overpass endpoint:

- API endpoint: `https://overpass-api.de/api/interpreter`
- Tag queried: `golf=course`
- Geographic scope: country area filtered by `ISO3166-1` (`US` or `CA`)

OpenStreetMap data is free and open under the ODbL license. Availability, completeness, and tagged fields (address/phone) vary by location.

## Requirements

- Xcode 26+
- iOS 26+ device/simulator target
- Apple Intelligence-capable hardware for FoundationModels demos
- Apple Intelligence enabled in system settings for model execution

## Project Structure

- `/FoundationModel/Views` – UI demos, including `GolfCourseLocatorView.swift`
- `/FoundationModel/Services` – data download service (`OverpassGolfCourseService.swift`)
- `/FoundationModel/Models` – SwiftData models (`GolfCourse`, `GolfCourseSyncState`)

## How the Golf Cache Works

1. User selects a country dataset (US/Canada).
2. App checks local sync metadata in SwiftData.
3. If fresh cache exists, data is loaded from local SQLite-backed store.
4. If missing/stale, app downloads from Overpass and merges/upserts records.
5. Subsequent loads use local data until cache expiration.

## Running

1. Open `FoundationModel.xcodeproj` in Xcode.
2. Build and run the `FoundationModel` scheme.
3. Open **Golf Course Locator** from the demo list.
4. Tap **Download / Refresh** to fetch and cache courses.

## References

- Apple FoundationModels documentation: https://developer.apple.com/documentation/FoundationModels
- WWDC25-286: Meet the Foundation Models framework
- WWDC25-301: Deep dive into the Foundation Models framework
- WWDC25-259: Code-along: Bring on-device AI to your app
- OpenStreetMap: https://www.openstreetmap.org
- Overpass API: https://overpass-api.de
