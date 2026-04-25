import FoundationModels
import MapKit
import SwiftUI

struct GolfCourseMapDemoView: View {
    private let catalog = GolfCourseCatalog.load()

    @StateObject private var locationProvider = GolfLocationProvider()
    @State private var selectedCourseID = ""
    @State private var visibleCourseIDs: [String] = []
    @State private var currentHole = 1
    @State private var searchText = ""
    @State private var weatherByCourseID: [String: GolfWeatherSnapshot] = [:]
    @State private var mapSpec: GolfMapSpec?
    @State private var aiSummary = "Generate a map spec to let the on-device model choose useful course maps and a hole highlight."
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var allCourses: [GolfCourse] {
        catalog.courses
    }

    private var visibleCourses: [GolfCourse] {
        let ids = visibleCourseIDs.isEmpty ? Array(allCourses.prefix(3).map(\.id)) : visibleCourseIDs
        let courses = ids.compactMap { id in allCourses.first(where: { $0.id == id }) }
        return courses.isEmpty ? Array(allCourses.prefix(3)) : courses
    }

    private var selectedCourse: GolfCourse? {
        allCourses.first { $0.id == selectedCourseID } ?? visibleCourses.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls

                TabView(selection: $selectedCourseID) {
                    ForEach(visibleCourses) { course in
                        GolfCourseMapCard(
                            course: course,
                            highlightedHole: currentHole,
                            weather: weatherByCourseID[course.id] ?? GolfWeatherService.fallbackWeather(for: course),
                            isSelected: course.id == selectedCourseID
                        )
                        .tag(course.id)
                        .padding(.horizontal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(minHeight: 520)

                detailsPanel
                attributionPanel
            }
            .padding(.vertical)
        }
        .navigationTitle("Golf Course Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            initializeSelectionIfNeeded()
            Task { await loadWeatherForVisibleCourses() }
        }
        .onChange(of: selectedCourseID) { _, _ in
            clampHoleToSelection()
            Task { await loadWeatherForVisibleCourses() }
        }
        .onChange(of: visibleCourseIDs) { _, _ in
            initializeSelectionIfNeeded()
            Task { await loadWeatherForVisibleCourses() }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Course Map Spec")
                .font(.headline)

            Text(aiSummary)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Search course, city, state, province, or address", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(applySearch)

                Button(action: applySearch) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Search courses")
            }

            HStack {
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
                    Label(isGenerating ? "Generating" : "Generate Spec", systemImage: "apple.intelligence")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            }

            Stepper(value: $currentHole, in: 1...18) {
                Label("Hole \(currentHole)", systemImage: "flag.checkered")
                    .font(.headline)
            }

            Label(locationProvider.statusText, systemImage: locationProvider.canUseLocation ? "location.fill" : "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let errorMessage = locationProvider.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedCourse {
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

                if let weather = weatherByCourseID[selectedCourse.id] {
                    HStack(spacing: 16) {
                        Label(weather.temperatureText, systemImage: "thermometer.medium")
                        Label(weather.windText, systemImage: "wind")
                        Text(weather.source)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                if let mapSpec, !mapSpec.annotationLabels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(mapSpec.annotationLabels, id: \.self) { label in
                                Label(label, systemImage: "tag")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var attributionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Attribution")
                .font(.headline)

            ForEach(catalog.attribution, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("The bundled file is a small demo catalog. Run scripts/build_golf_catalog.py to replace it with a normalized OpenGolfAPI plus OpenStreetMap catalog.")
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

    private func clampHoleToSelection() {
        currentHole = min(max(currentHole, 1), 18)
    }

    private func applySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            visibleCourseIDs = Array(allCourses.prefix(3).map(\.id))
            return
        }

        let matches = allCourses.filter { course in
            course.name.lowercased().contains(query)
                || course.city.lowercased().contains(query)
                || course.region.lowercased().contains(query)
                || course.country.lowercased().contains(query)
                || course.address.lowercased().contains(query)
        }

        visibleCourseIDs = Array(matches.prefix(5).map(\.id))
        aiSummary = matches.isEmpty ? "No bundled courses matched that search." : "Showing bundled courses that match \"\(searchText)\"."
    }

    private func showNearbyCourses() {
        let location = locationProvider.location
        let sorted = allCourses.sorted { lhs, rhs in
            switch (lhs.distanceMiles(from: location), rhs.distanceMiles(from: location)) {
            case let (lhs?, rhs?):
                lhs < rhs
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.name < rhs.name
            }
        }

        visibleCourseIDs = Array(sorted.prefix(5).map(\.id))
        aiSummary = location == nil
            ? "Showing demo courses while the app waits for a device location."
            : "Showing courses sorted by distance from the current device location."
    }

    private func loadWeatherForVisibleCourses() async {
        for course in visibleCourses where weatherByCourseID[course.id] == nil {
            let weather = await GolfWeatherService.currentWeather(for: course)
            weatherByCourseID[course.id] = weather
        }
    }

    private func generateMapSpec() async {
        isGenerating = true
        errorMessage = nil

        defer { isGenerating = false }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            let spec = GolfMapSpecFactory.fallbackSpec(
                for: allCourses,
                selectedCourseID: selectedCourseID,
                hole: currentHole,
                location: locationProvider.location
            )
            apply(spec)
            errorMessage = "FoundationModels is unavailable, so a local fallback spec was applied."
            return
        }

        do {
            let session = LanguageModelSession(
                tools: [
                    SearchGolfCoursesTool(courses: allCourses),
                    GetGolfCourseDetailTool(courses: allCourses),
                    GetGolfCourseWeatherTool(courses: allCourses),
                ]
            ) {
                """
                You generate safe, typed map specifications for a golf app demo.
                Use the tools to pick relevant bundled golf courses and weather.
                Return only course ids that exist in the tool results.
                Prefer a small carousel of one to three courses.
                Keep the highlighted hole between 1 and 18.
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
                Current selected course id: \(selectedCourseID)
                Current hole selector value: \(currentHole)
                Current device location: \(locationText)

                Generate a GolfMapSpec for a carousel of golf course maps. Include useful labels for tee, green, course center, wind, and current hole if appropriate.
                """,
                generating: GolfMapSpec.self
            )

            apply(result.content)
        } catch {
            let spec = GolfMapSpecFactory.fallbackSpec(
                for: allCourses,
                selectedCourseID: selectedCourseID,
                hole: currentHole,
                location: locationProvider.location
            )
            apply(spec)
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ spec: GolfMapSpec) {
        mapSpec = spec

        let validIDs = spec.selectedCourseIDs.filter { id in
            allCourses.contains { $0.id == id }
        }

        visibleCourseIDs = validIDs.isEmpty ? Array(allCourses.prefix(3).map(\.id)) : validIDs
        selectedCourseID = visibleCourseIDs.first ?? selectedCourseID
        currentHole = min(max(spec.highlightedHole, 1), 18)
        aiSummary = spec.summary

        Task { await loadWeatherForVisibleCourses() }
    }
}

private struct GolfCourseMapCard: View {
    let course: GolfCourse
    let highlightedHole: Int
    let weather: GolfWeatherSnapshot
    let isSelected: Bool

    @State private var position: MapCameraPosition

    init(course: GolfCourse, highlightedHole: Int, weather: GolfWeatherSnapshot, isSelected: Bool) {
        self.course = course
        self.highlightedHole = highlightedHole
        self.weather = weather
        self.isSelected = isSelected
        _position = State(initialValue: .region(course.mapRegion(for: highlightedHole)))
    }

    var body: some View {
        let hole = course.hole(number: highlightedHole)

        ZStack(alignment: .topLeading) {
            Map(position: $position, interactionModes: .all) {
                UserAnnotation()

                if let boundary = course.boundary, boundary.count >= 3 {
                    MapPolygon(coordinates: boundary.map(\.coordinate))
                        .foregroundStyle(.green.opacity(0.22))
                        .stroke(.green, lineWidth: 2)
                }

                if let path = hole.path, path.count >= 2 {
                    MapPolyline(coordinates: path.map(\.coordinate))
                        .stroke(.yellow, lineWidth: 4)
                }

                Marker(course.name, systemImage: "flag", coordinate: course.coordinate)
                    .tint(.green)

                if let tee = hole.tee {
                    Marker("Hole \(hole.number) tee", systemImage: "figure.golf", coordinate: tee.coordinate)
                        .tint(.blue)
                }

                if let green = hole.green {
                    Marker("Hole \(hole.number) green", systemImage: "flag.checkered", coordinate: green.coordinate)
                        .tint(.orange)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapUserLocationButton()
                MapScaleView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.headline)
                    Text("Hole \(highlightedHole)\(hole.par.map { " - Par \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GolfWeatherHUD(weather: weather)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 500)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? .green : .clear, lineWidth: 2)
        }
        .onChange(of: highlightedHole) { _, newValue in
            position = .region(course.mapRegion(for: newValue))
        }
        .onChange(of: course.id) { _, _ in
            position = .region(course.mapRegion(for: highlightedHole))
        }
    }
}

private struct GolfWeatherHUD: View {
    let weather: GolfWeatherSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Label(weather.temperatureText, systemImage: "thermometer.medium")

            HStack(spacing: 4) {
                Image(systemName: "location.north.line.fill")
                    .rotationEffect(.degrees(weather.windDirectionDegrees))
                Text(weather.windText)
            }

            Text(weather.source)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        GolfCourseMapDemoView()
    }
}
