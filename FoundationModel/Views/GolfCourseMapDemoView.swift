import FoundationModels
import MapKit
import SwiftUI
import UIKit

struct GolfCourseMapDemoView: View {
    private let catalog = GolfCourseCatalog.load()
    private let facilityCatalog = ODRSFFacilityCatalog.load()

    @StateObject private var locationProvider = GolfLocationProvider()
    @State private var selectedCourseID = ""
    @State private var visibleCourseIDs: [String] = []
    @State private var currentHole = 1
    @State private var searchText = ""
    @State private var weatherByCourseID: [String: GolfWeatherSnapshot] = [:]
    @State private var mapSpec: ODRSFMapSpec?
    @State private var aiSummary = "Explore ODRSF golf facilities with nearby amenities ranked by distance, type, and local context."
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var selectedAmenityID: String?
    @State private var isAmenityPanelPresented = false
    @State private var activeFacilityTypes: Set<String> = []
    @State private var mapMode: ODRSFMapMode = .hybrid
    @State private var mapPosition: MapCameraPosition = .automatic

    private var allCourses: [GolfCourse] {
        catalog.courses
    }

    private var allFacilities: [ODRSFFacility] {
        facilityCatalog.facilities
    }

    private var visibleCourses: [GolfCourse] {
        let ids = visibleCourseIDs.isEmpty ? Array(allCourses.prefix(5).map(\.id)) : visibleCourseIDs
        let courses = ids.compactMap { id in allCourses.first(where: { $0.id == id }) }
        return courses.isEmpty ? Array(allCourses.prefix(5)) : courses
    }

    private var selectedCourse: GolfCourse? {
        allCourses.first { $0.id == selectedCourseID } ?? visibleCourses.first
    }

    private var rankedAmenities: [RankedAmenity] {
        guard let selectedCourse, !activeFacilityTypes.isEmpty else { return [] }
        return ODRSFMapRanker.rankedAmenities(
            around: selectedCourse,
            facilities: allFacilities,
            userLocation: locationProvider.location,
            activeTypes: activeFacilityTypes,
            selectedAmenityIDs: mapSpec?.selectedAmenityIDs ?? []
        )
    }

    private var selectedAmenity: RankedAmenity? {
        guard let selectedAmenityID else { return nil }
        return rankedAmenities.first { $0.facility.id == selectedAmenityID }
    }

    private var mapAmenities: [RankedAmenity] {
        let essentialAmenities = Array(rankedAmenities.prefix(12))
        guard let selectedAmenity else { return essentialAmenities }
        if essentialAmenities.contains(selectedAmenity) {
            return essentialAmenities
        }
        return Array(([selectedAmenity] + essentialAmenities).prefix(12))
    }

    private var activeFacilityTypeLabel: String {
        if activeFacilityTypes.isEmpty {
            return "No amenities"
        }
        return "\(activeFacilityTypes.count) visible"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controls
                courseCarousel
                mapPanel
                detailsPanel
                attributionPanel
            }
            .padding(.vertical)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground).opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("ODRSF Golf Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initializeSelectionIfNeeded()
            updateMapCamera(animated: false)
            Task { await loadWeatherForVisibleCourses() }
        }
        .onChange(of: selectedCourseID) { _, _ in
            selectedAmenityID = nil
            clampHoleToSelection()
            updateMapCamera(animated: true)
            Task { await loadWeatherForVisibleCourses() }
        }
        .onChange(of: visibleCourseIDs) { _, _ in
            initializeSelectionIfNeeded()
            updateMapCamera(animated: true)
            Task { await loadWeatherForVisibleCourses() }
        }
        .onChange(of: activeFacilityTypes) { _, _ in
            selectedAmenityID = nil
            updateMapCamera(animated: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ODRSF Course Intelligence")
                        .font(.title3.bold())
                    Text(aiSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(spacing: 10) {
                TextField("Search course, city, province, provider, or address", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(applySearch)

                Button(action: applySearch) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Search courses")
            }

            HStack(spacing: 10) {
                Button {
                    locationProvider.requestLocation()
                    showNearbyCourses()
                } label: {
                    Label("Nearby", systemImage: "location")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await generateMapSpec() }
                } label: {
                    Label(isGenerating ? "Generating" : "AI Rank", systemImage: "apple.intelligence")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            }

            Label(locationProvider.statusText, systemImage: locationProvider.canUseLocation ? "location.fill" : "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage = locationProvider.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }

    private var courseCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Courses")
                    .font(.headline)
                Spacer()
                Text("\(allCourses.count) ODRSF golf facilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(visibleCourses) { course in
                        CourseSummaryCard(
                            course: course,
                            weather: weatherByCourseID[course.id] ?? GolfWeatherService.fallbackWeather(for: course),
                            isSelected: course.id == selectedCourseID,
                            userLocation: locationProvider.location,
                            amenityCount: selectedCourseID == course.id ? rankedAmenities.count : nil
                        )
                        .onTapGesture {
                            selectCourse(course)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                Map(position: $mapPosition, interactionModes: .all) {
                    UserAnnotation()

                    if let selectedCourse {
                        let hole = selectedCourse.hole(number: currentHole)

                        if let path = hole.path, path.count >= 2 {
                            MapPolyline(coordinates: path.map(\.coordinate))
                                .stroke(.yellow, lineWidth: 4)
                        }

                        Annotation(selectedCourse.name, coordinate: selectedCourse.coordinate) {
                            CoursePin()
                                .shadow(radius: 10, y: 5)
                        }

                        if let tee = hole.tee {
                            Marker("AI tee preview", systemImage: "figure.golf", coordinate: tee.coordinate)
                                .tint(.blue)
                        }

                        if let green = hole.green {
                            Marker("AI green preview", systemImage: "flag.checkered", coordinate: green.coordinate)
                                .tint(.orange)
                        }
                    }

                    ForEach(mapAmenities) { amenity in
                        Annotation(amenity.facility.name, coordinate: amenity.facility.coordinate) {
                            AmenityPin(
                                amenity: amenity,
                                isSelected: amenity.id == selectedAmenityID
                            )
                            .onTapGesture {
                                selectAmenity(amenity)
                            }
                        }
                    }
                }
                .mapStyle(mapMode.style)
                .mapControls {
                    MapCompass()
                    MapUserLocationButton()
                    MapScaleView()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }

                if let selectedAmenity {
                    AmenityCalloutCard(amenity: selectedAmenity) {
                        withAnimation(.snappy) {
                            selectedAmenityID = nil
                        }
                    }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if isAmenityPanelPresented {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) {
                                isAmenityPanelPresented = false
                            }
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        mapStyleButton
                        amenityButton
                    }

                    if isAmenityPanelPresented {
                        amenityPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            }
            .frame(height: 520)
            .padding(.horizontal)
            .animation(.snappy, value: selectedAmenityID)
            .animation(.snappy, value: isAmenityPanelPresented)
            .animation(.smooth, value: mapAmenities.map(\.id))
        }
    }

    private var mapStyleButton: some View {
        Menu {
            Picker("Map Style", selection: $mapMode) {
                ForEach(ODRSFMapMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
        } label: {
            Label(mapMode.title, systemImage: mapMode.symbolName)
                .font(.caption.bold())
                .labelStyle(.iconOnly)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
        .accessibilityLabel("Map style")
        .accessibilityValue(mapMode.title)
    }

    private var amenityButton: some View {
        Button {
            withAnimation(.snappy) {
                isAmenityPanelPresented.toggle()
            }
        } label: {
            Label("Amenities", systemImage: "checklist")
                .font(.caption.bold())
                .frame(height: 42)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
        .accessibilityValue(activeFacilityTypeLabel)
    }

    private var amenityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Amenities")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        activeFacilityTypes = Set(ODRSFFacilityType.allCases.map(\.rawValue))
                    }
                } label: {
                    Text("All")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ODRSFFacilityType.allCases) { type in
                        AmenityToggleRow(
                            type: type,
                            isSelected: activeFacilityTypes.contains(type.rawValue)
                        ) {
                            withAnimation(.snappy) {
                                toggle(type)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 310)

            Text(activeFacilityTypeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedCourse {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedCourse.name)
                            .font(.title3.bold())

                        Label(selectedCourse.displayLocation, systemImage: "mappin.and.ellipse")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if !selectedCourse.address.isEmpty {
                            Text(selectedCourse.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(selectedCourse.displayType.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.green.opacity(0.14), in: Capsule())

                        if let distance = selectedCourse.distanceMiles(from: locationProvider.location) {
                            Text(String(format: "%.1f mi from you", distance))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let weather = weatherByCourseID[selectedCourse.id] {
                    HStack(spacing: 16) {
                        Label(weather.temperatureText, systemImage: "thermometer.medium")
                        Label(weather.windText, systemImage: "wind")
                        Text(weather.source)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                holePreviewControls

                if !rankedAmenities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top Amenity Picks")
                            .font(.subheadline.bold())

                        ForEach(rankedAmenities.prefix(5)) { amenity in
                            Button {
                                selectAmenity(amenity)
                            } label: {
                                AmenityRow(amenity: amenity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var holePreviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $currentHole, in: 1...18) {
                Label("AI hole preview \(currentHole)", systemImage: "flag.checkered")
                    .font(.headline)
            }

            Label("Synthetic hole previews are generated because ODRSF provides facility points, not hole geometry.", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var attributionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Attribution")
                .font(.headline)

            ForEach(Array(Set(catalog.attribution + facilityCatalog.attribution)).sorted(), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("ODRSF supplies facility points and categories; course boundaries and hole layouts are not included in this datasource.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func initializeSelectionIfNeeded() {
        if selectedCourseID.isEmpty || !visibleCourses.contains(where: { $0.id == selectedCourseID }) {
            selectedCourseID = visibleCourses.first?.id ?? allCourses.first?.id ?? ""
        }
    }

    private func selectCourse(_ course: GolfCourse) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy) {
            selectedCourseID = course.id
        }
    }

    private func selectAmenity(_ amenity: RankedAmenity) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.snappy) {
            selectedAmenityID = amenity.id
            mapPosition = .region(MKCoordinateRegion(
                center: amenity.facility.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            ))
        }
    }

    private func clampHoleToSelection() {
        currentHole = min(max(currentHole, 1), 18)
    }

    private func toggle(_ type: ODRSFFacilityType) {
        if activeFacilityTypes.contains(type.rawValue) {
            activeFacilityTypes.remove(type.rawValue)
        } else {
            activeFacilityTypes.insert(type.rawValue)
        }
    }

    private func applySearch() {
        let matches = ODRSFMapRanker.courses(
            matching: searchText,
            courses: allCourses,
            userLocation: locationProvider.location
        )

        visibleCourseIDs = Array(matches.map(\.id))
        aiSummary = matches.isEmpty
            ? "No ODRSF golf facilities matched that search."
            : "Showing ODRSF golf facilities that match \"\(searchText)\"."
    }

    private func showNearbyCourses() {
        let location = locationProvider.location
        let sorted = ODRSFMapRanker.courses(matching: "", courses: allCourses, userLocation: location)
        visibleCourseIDs = Array(sorted.map(\.id))
        aiSummary = location == nil
            ? "Showing ODRSF courses while the app waits for a device location."
            : "Showing ODRSF courses sorted by distance from your current location."
    }

    private func loadWeatherForVisibleCourses() async {
        for course in visibleCourses where weatherByCourseID[course.id] == nil {
            let weather = await GolfWeatherService.currentWeather(for: course)
            weatherByCourseID[course.id] = weather
        }
    }

    private func updateMapCamera(animated: Bool) {
        guard let selectedCourse else { return }
        let ranked = ODRSFMapRanker.rankedAmenities(
            around: selectedCourse,
            facilities: allFacilities,
            userLocation: locationProvider.location,
            activeTypes: activeFacilityTypes.isEmpty ? ["__none__"] : activeFacilityTypes,
            selectedAmenityIDs: mapSpec?.selectedAmenityIDs ?? [],
            limit: 12
        )
        let region = ODRSFMapRanker.region(for: selectedCourse, amenities: ranked)
        let update = {
            mapPosition = .region(region)
        }

        if animated {
            withAnimation(.smooth(duration: 0.55), update)
        } else {
            update()
        }
    }

    private func generateMapSpec() async {
        isGenerating = true
        errorMessage = nil

        defer { isGenerating = false }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            let spec = ODRSFMapRanker.fallbackSpec(
                for: allCourses,
                facilities: allFacilities,
                selectedCourseID: selectedCourseID,
                searchText: searchText,
                hole: currentHole,
                userLocation: locationProvider.location,
                activeTypes: activeFacilityTypes
            )
            apply(spec)
            errorMessage = "Local ODRSF ranking applied."
            return
        }

        do {
            let session = LanguageModelSession(
                tools: [
                    SearchODRSFCoursesTool(courses: allCourses),
                    FindNearbyODRSFAmenitiesTool(courses: allCourses, facilities: allFacilities),
                    RankODRSFMapCandidatesTool(courses: allCourses, facilities: allFacilities),
                ]
            ) {
                """
                You generate professional, safe, typed MapKit specifications for a golf app.
                Use only the ODRSF tools. Never invent course or amenity ids.
                Prefer one to three ODRSF golf courses and up to twelve diverse nearby amenities.
                Treat ODRSF courses as point data; synthetic hole previews are available but not real course geometry.
                Prefer hybrid map style for golf context unless map or satellite is clearly better.
                """
            }

            let locationText: String
            if let location = locationProvider.location {
                locationText = "\(location.coordinate.latitude), \(location.coordinate.longitude)"
            } else {
                locationText = "unknown"
            }

            let result = try await session.respond(
                to: """
                Search text: \(searchText.isEmpty ? "none" : searchText)
                Current selected ODRSF course id: \(selectedCourseID)
                Current synthetic hole preview value: \(currentHole)
                Current device location: \(locationText)
                Active facility filters: \(activeFacilityTypes.isEmpty ? "none" : activeFacilityTypes.sorted().joined(separator: ", "))

                Generate an ODRSFMapSpec for a premium golf course map with nearby amenity pins, useful ranking labels, and a polished one-sentence summary.
                """,
                generating: ODRSFMapSpec.self
            )

            apply(result.content)
        } catch {
            let spec = ODRSFMapRanker.fallbackSpec(
                for: allCourses,
                facilities: allFacilities,
                selectedCourseID: selectedCourseID,
                searchText: searchText,
                hole: currentHole,
                userLocation: locationProvider.location,
                activeTypes: activeFacilityTypes
            )
            apply(spec)
            errorMessage = "Local ODRSF ranking applied."
        }
    }

    private func apply(_ spec: ODRSFMapSpec) {
        mapSpec = spec

        let validIDs = spec.selectedCourseIDs.filter { id in
            allCourses.contains { $0.id == id }
        }

        withAnimation(.snappy) {
            visibleCourseIDs = validIDs.isEmpty ? Array(allCourses.prefix(5).map(\.id)) : validIDs
            selectedCourseID = visibleCourseIDs.first ?? selectedCourseID
            currentHole = min(max(spec.highlightedHole, 1), 18)
            activeFacilityTypes = Set(spec.activeFacilityTypes.filter { id in
                ODRSFFacilityType(rawValue: id) != nil
            })
            mapMode = ODRSFMapMode(rawValue: spec.mapStyle.lowercased()) ?? .hybrid
            selectedAmenityID = spec.selectedAmenityIDs.first
            aiSummary = spec.summary
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: spec.latitude, longitude: spec.longitude),
                span: MKCoordinateSpan(latitudeDelta: spec.latitudeDelta, longitudeDelta: spec.longitudeDelta)
            ))
        }

        Task { await loadWeatherForVisibleCourses() }
    }
}

private enum ODRSFMapMode: String, CaseIterable, Identifiable {
    case map
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: "Map"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var symbolName: String {
        switch self {
        case .map: "map"
        case .satellite: "globe.americas"
        case .hybrid: "map.fill"
        }
    }

    var style: MapStyle {
        switch self {
        case .map:
            .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite:
            .imagery(elevation: .realistic)
        case .hybrid:
            .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }
}

private struct CourseSummaryCard: View {
    let course: GolfCourse
    let weather: GolfWeatherSnapshot
    let isSelected: Bool
    let userLocation: CLLocation?
    let amenityCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "flag.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .secondary)

                Spacer()

                if let distance = course.distanceMiles(from: userLocation) {
                    Text(String(format: "%.1f mi", distance))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Text(course.name)
                .font(.headline)
                .lineLimit(2)
                .frame(minHeight: 44, alignment: .topLeading)

            Label(course.displayLocation, systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(weather.windText, systemImage: "wind")
                if let amenityCount {
                    Label("\(amenityCount)", systemImage: "mappin")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 238, height: 178)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .green : .white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .shadow(color: .black.opacity(isSelected ? 0.14 : 0.06), radius: isSelected ? 16 : 8, y: 8)
        .animation(.snappy, value: isSelected)
    }
}

private struct CoursePin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.green.opacity(0.18))
                .frame(width: 54, height: 54)
            Circle()
                .fill(.green.gradient)
                .frame(width: 36, height: 36)
            Image(systemName: "figure.golf")
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

private struct AmenityPin: View {
    let amenity: RankedAmenity
    let isSelected: Bool

    private var type: ODRSFFacilityType {
        ODRSFFacilityType(rawValue: amenity.facility.facilityType) ?? .miscellaneous
    }

    var body: some View {
        VStack(spacing: 1) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(type.tint.gradient)
                    .frame(width: isSelected ? 36 : 24, height: isSelected ? 36 : 24)

                Image(systemName: type.symbolName)
                    .font(isSelected ? .subheadline : .system(size: 11, weight: .bold))
                    .foregroundStyle(.white)

                if amenity.rank <= 5 || isSelected {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(type.tint, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }

            if isSelected {
                Text(amenity.facility.displayType)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isSelected ? 1.12 : 1)
        .shadow(color: type.tint.opacity(isSelected ? 0.35 : 0.16), radius: isSelected ? 12 : 4, y: 4)
        .animation(.bouncy(duration: 0.35), value: isSelected)
    }
}

private struct AmenityCalloutCard: View {
    let amenity: RankedAmenity
    let onClose: () -> Void

    private var type: ODRSFFacilityType {
        ODRSFFacilityType(rawValue: amenity.facility.facilityType) ?? .miscellaneous
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(amenity.facility.name, systemImage: type.symbolName)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("#\(amenity.rank)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(type.tint.opacity(0.18), in: Capsule())

                Text(amenity.facility.displayType)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())

                Text(String(format: "%.1f mi from course", amenity.distanceFromCourseMiles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let userDistance = amenity.distanceFromUserMiles {
                Label(String(format: "%.1f mi from you", userDistance), systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(amenity.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !amenity.facility.address.isEmpty {
                Text(amenity.facility.address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text([amenity.facility.provider, amenity.facility.displayLocation].filter { !$0.isEmpty }.joined(separator: " - "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

private struct AmenityToggleRow: View {
    let type: ODRSFFacilityType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? type.tint : Color(.systemBackground).opacity(0.92))
                        .frame(width: 18, height: 18)

                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? type.tint : Color.primary.opacity(0.75), lineWidth: 1.6)
                        .frame(width: 18, height: 18)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)

                Image(systemName: type.symbolName)
                    .font(.caption)
                    .foregroundStyle(type.tint)
                    .frame(width: 18)

                Text(type.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AmenityRow: View {
    let amenity: RankedAmenity

    private var type: ODRSFFacilityType {
        ODRSFFacilityType(rawValue: amenity.facility.facilityType) ?? .miscellaneous
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(amenity.rank)")
                .font(.caption.bold())
                .foregroundStyle(type.tint)
                .frame(width: 34, alignment: .leading)

            Image(systemName: type.symbolName)
                .foregroundStyle(type.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(amenity.facility.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(amenity.facility.displayType) - \(String(format: "%.1f mi from course", amenity.distanceFromCourseMiles))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        GolfCourseMapDemoView()
    }
}
