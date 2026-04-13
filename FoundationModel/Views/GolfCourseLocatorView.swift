import SwiftUI
import SwiftData
import MapKit

@MainActor
struct GolfCourseLocatorView: View {
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel = GolfCourseLocatorViewModel()
    @State private var mapPosition: MapCameraPosition = .automatic

    var filteredCourses: [GolfCourse] {
        viewModel.allCourses.filter { course in
            let nameMatches = viewModel.nameFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || course.name.localizedCaseInsensitiveContains(viewModel.nameFilter)
            let stateMatches = viewModel.stateOrProvinceFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || course.stateOrProvince.localizedCaseInsensitiveContains(viewModel.stateOrProvinceFilter)
            let countryMatches = viewModel.countryFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || course.country.localizedCaseInsensitiveContains(viewModel.countryFilter)

            return nameMatches && stateMatches && countryMatches
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section("Dataset") {
                    Picker("Download", selection: $viewModel.selectedCountry) {
                        ForEach(GolfDatasetCountry.allCases) { country in
                            Text(country.rawValue).tag(country)
                        }
                    }

                    HStack {
                        Button("Load Cache") {
                            Task { await viewModel.loadCachedCourses(using: modelContext) }
                        }

                        Spacer()

                        Button("Download / Refresh") {
                            Task { await viewModel.downloadAndCache(using: modelContext) }
                        }
                        .disabled(viewModel.isLoading)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading golf courses...")
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Filters") {
                    TextField("Name", text: $viewModel.nameFilter)
                    TextField("State / Province", text: $viewModel.stateOrProvinceFilter)
                    TextField("Country", text: $viewModel.countryFilter)
                }
            }
            .frame(maxHeight: 300)

            Map(position: $mapPosition) {
                ForEach(filteredCourses) { course in
                    Annotation(course.name, coordinate: course.coordinate, anchor: .bottom) {
                        Button {
                            viewModel.selectedCourse = course
                            mapPosition = .region(region(center: course.coordinate))
                        } label: {
                            Image(systemName: viewModel.selectedCourse?.sourceID == course.sourceID ? "flag.circle.fill" : "flag.circle")
                                .font(.title2)
                                .foregroundStyle(viewModel.selectedCourse?.sourceID == course.sourceID ? .blue : .green)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            if let selected = viewModel.selectedCourse {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.name)
                        .font(.headline)
                    Text(selected.address.isEmpty ? "Address unavailable" : selected.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(selected.phoneNumber.isEmpty ? "Phone unavailable" : selected.phoneNumber)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }

            List(filteredCourses) { course in
                Button {
                    viewModel.selectedCourse = course
                    mapPosition = .region(region(center: course.coordinate))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name)
                            .font(.headline)
                        Text(course.stateOrProvince.isEmpty ? course.country : "\(course.stateOrProvince), \(course.country)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !course.phoneNumber.isEmpty {
                            Text(course.phoneNumber)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onAppear {
                    guard course.sourceID == filteredCourses.last?.sourceID else { return }
                    Task { await viewModel.loadNextPage(using: modelContext) }
                }
            }
            .listStyle(.plain)

            if viewModel.canLoadMore {
                ProgressView("Loading more courses...")
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Golf Course Locator")
        .task {
            await viewModel.loadFromCacheOrDownload(using: modelContext)
            updateMapForCurrentSelection()
        }
        .onChange(of: viewModel.selectedCountry) { _, _ in
            Task { await viewModel.loadFromCacheOrDownload(using: modelContext) }
        }
        .onChange(of: filteredCourses.count) { _, _ in
            updateMapForCurrentSelection()
        }
    }

    private func region(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
    }

    private func updateMapForCurrentSelection() {
        if let selected = viewModel.selectedCourse {
            mapPosition = .region(region(center: selected.coordinate))
            return
        }

        if let first = filteredCourses.first {
            mapPosition = .region(region(center: first.coordinate))
        }
    }
}

@MainActor
final class GolfCourseLocatorViewModel: ObservableObject {
    @Published var allCourses: [GolfCourse] = []
    @Published var selectedCourse: GolfCourse?
    @Published var selectedCountry: GolfDatasetCountry = .unitedStates

    @Published var nameFilter = ""
    @Published var stateOrProvinceFilter = ""
    @Published var countryFilter = ""

    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var canLoadMore = false

    private let cacheLifetimeDays = 30
    private var cacheLifetime: TimeInterval { TimeInterval(cacheLifetimeDays * 24 * 60 * 60) }
    private let pageSize = 1_000
    private var currentOffset = 0
    private let downloader = OverpassGolfCourseService()

    func loadFromCacheOrDownload(using context: ModelContext) async {
        await resetAndLoadFirstPage(using: context)

        guard let lastSync = lastSyncDate(for: selectedCountry, in: context) else {
            await downloadAndCache(using: context)
            return
        }

        if Date().timeIntervalSince(lastSync) > cacheLifetime {
            await downloadAndCache(using: context)
        } else {
            statusMessage = "Loaded cached golf course data."
        }
    }

    func resetAndLoadFirstPage(using context: ModelContext) async {
        currentOffset = 0
        allCourses = []
        selectedCourse = nil
        canLoadMore = true
        await loadNextPage(using: context)
    }

    func loadCachedCourses(using context: ModelContext) async {
        await resetAndLoadFirstPage(using: context)
    }

    func loadNextPage(using context: ModelContext) async {
        guard canLoadMore || currentOffset == 0 else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            var descriptor = FetchDescriptor<GolfCourse>(sortBy: [SortDescriptor(\GolfCourse.name)])
            descriptor.fetchOffset = currentOffset
            descriptor.fetchLimit = pageSize

            let nextPage = try context.fetch(descriptor)
            allCourses.append(contentsOf: nextPage)
            currentOffset += nextPage.count
            canLoadMore = nextPage.count == pageSize

            if selectedCourse == nil {
                selectedCourse = allCourses.first
            }

            statusMessage = "Loaded \(allCourses.count) cached golf courses."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadAndCache(using context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Downloading \(selectedCountry.rawValue) golf course data..."

        do {
            let downloadedCourses = try await downloader.downloadCourses(for: selectedCountry)
            try merge(downloadedCourses: downloadedCourses, into: context)
            statusMessage = "Downloaded and cached \(downloadedCourses.count) golf courses for \(selectedCountry.rawValue)."
            await resetAndLoadFirstPage(using: context)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func merge(downloadedCourses: [DownloadedGolfCourse], into context: ModelContext) throws {
        let countryCode = selectedCountry.isoCode
        let existingDescriptor = FetchDescriptor<GolfCourse>(
            predicate: #Predicate { $0.countryCode == countryCode }
        )
        let existingCourses = try context.fetch(existingDescriptor)
        var existingByID: [String: GolfCourse] = Dictionary(uniqueKeysWithValues: existingCourses.map { ($0.sourceID, $0) })

        for downloaded in downloadedCourses {
            if let existing = existingByID[downloaded.sourceID] {
                existing.name = downloaded.name
                existing.address = downloaded.address
                existing.phoneNumber = downloaded.phoneNumber
                existing.stateOrProvince = downloaded.stateOrProvince
                existing.country = downloaded.country
                existing.countryCode = downloaded.countryCode
                existing.latitude = downloaded.latitude
                existing.longitude = downloaded.longitude
                existing.lastUpdatedAt = .now
                existingByID.removeValue(forKey: downloaded.sourceID)
            } else {
                context.insert(
                    GolfCourse(
                        sourceID: downloaded.sourceID,
                        name: downloaded.name,
                        address: downloaded.address,
                        phoneNumber: downloaded.phoneNumber,
                        stateOrProvince: downloaded.stateOrProvince,
                        country: downloaded.country,
                        countryCode: downloaded.countryCode,
                        latitude: downloaded.latitude,
                        longitude: downloaded.longitude,
                        lastUpdatedAt: .now
                    )
                )
            }
        }

        // Remove stale entries no longer returned by the current dataset refresh.
        for stale in existingByID.values {
            context.delete(stale)
        }

        try updateSyncState(in: context)
        try context.save()
    }

    private func updateSyncState(in context: ModelContext) throws {
        let countryCode = selectedCountry.isoCode
        let descriptor = FetchDescriptor<GolfCourseSyncState>(
            predicate: #Predicate { $0.countryCode == countryCode }
        )

        if let existingState = try context.fetch(descriptor).first {
            existingState.lastSyncedAt = .now
        } else {
            context.insert(GolfCourseSyncState(countryCode: countryCode, lastSyncedAt: .now))
        }
    }

    private func lastSyncDate(for country: GolfDatasetCountry, in context: ModelContext) -> Date? {
        let countryCode = country.isoCode
        let descriptor = FetchDescriptor<GolfCourseSyncState>(
            predicate: #Predicate { $0.countryCode == countryCode }
        )
        return try? context.fetch(descriptor).first?.lastSyncedAt
    }
}

#Preview {
    NavigationStack {
        GolfCourseLocatorView()
            .modelContainer(for: [GolfCourse.self, GolfCourseSyncState.self], inMemory: true)
    }
}
