import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct LabImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let claudeService: ClaudeService

    @State private var extractedBiomarkers: [ExtractedBiomarker] = []
    @State private var selectedMarkers: Set<String> = []
    @State private var isExtracting = false
    @State private var extractionMethod: String?
    @State private var error: String?
    @State private var showingFilePicker = false
    @State private var fileName: String?
    @State private var importedCount: Int?
    #if os(iOS)
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if isExtracting {
                    extractingView
                } else if !extractedBiomarkers.isEmpty {
                    reviewView
                } else if let count = importedCount {
                    doneView(count: count)
                } else {
                    pickFileView
                }
            }
            .navigationTitle("Import Lab Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                // Include image types so users can import a photo of a lab report on iOS too
                allowedContentTypes: [.pdf, .plainText, .jpeg, .png, .image],
                allowsMultipleSelection: false
            ) { result in
                handleFilePicked(result)
            }
            #if os(iOS)
            // Photo picker for selecting a lab report photo from the camera roll
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhotoItem) {
                guard let item = selectedPhotoItem else { return }
                handlePhotoPickerItem(item)
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 450)
        #endif
    }

    // MARK: - Pick File

    private var pickFileView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Upload a lab report to extract biomarkers automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)

            // Primary action: file picker (PDF or text)
            Button {
                showingFilePicker = true
            } label: {
                Label("Choose File (PDF or Text)", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            #if os(iOS)
            // iOS bonus: pick a photo of a lab report from the camera roll
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Choose Photo of Lab Report", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            #endif

            if !claudeService.hasAPIKey {
                Text("Local parsing will be used. Add a Claude API key in Settings for better accuracy with complex reports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Extracting

    private var extractingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Analyzing \(fileName ?? "lab report")...")
                .font(.headline)
            Text("Extracting biomarker values from the report.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(extractedBiomarkers.count) biomarkers found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let method = extractionMethod {
                        Text("via \(method)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button("Select All") {
                    selectedMarkers = Set(extractedBiomarkers.map(\.id))
                }
                .font(.caption)
                Button("Deselect All") {
                    selectedMarkers.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                ForEach(groupedBySystem, id: \.system) { group in
                    Section(group.system.rawValue) {
                        ForEach(group.markers) { marker in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedMarkers.contains(marker.id) },
                                    set: { isOn in
                                        if isOn { selectedMarkers.insert(marker.id) }
                                        else { selectedMarkers.remove(marker.id) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(marker.marker)
                                            .font(.subheadline.weight(.medium))
                                        HStack(spacing: 4) {
                                            Text(formatValue(marker.value))
                                                .font(.caption.monospacedDigit().bold())
                                            Text(marker.unit)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if let min = marker.refMin, let max = marker.refMax {
                                                Text("(\(formatValue(min))-\(formatValue(max)))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                }
                                #if os(macOS)
                                .toggleStyle(.checkbox)
                                #endif
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(selectedMarkers.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        saveSelected()
                    } label: {
                        Text("Import \(selectedMarkers.count) Biomarkers")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedMarkers.isEmpty)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    // MARK: - Done

    private func doneView(count: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Imported \(count) biomarkers")
                .font(.headline)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Grouping

    private var groupedBySystem: [(system: BodySystem, markers: [ExtractedBiomarker])] {
        let grouped = Dictionary(grouping: extractedBiomarkers) {
            BiomarkerReference.system(for: $0.marker)
        }
        return BodySystem.allCases.compactMap { system in
            guard let markers = grouped[system], !markers.isEmpty else { return nil }
            return (system: system, markers: markers)
        }
    }

    // MARK: - Actions

    #if os(iOS)
    /// Handles a photo selected from the Photos library.
    /// Writes it to a temp file then re-uses the same file extraction pipeline.
    private func handlePhotoPickerItem(_ item: PhotosPickerItem) {
        fileName = "Photo"
        isExtracting = true
        error = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    self.error = "Could not load the selected photo."
                    isExtracting = false
                    return
                }

                // Write to a temp PNG so the shared parser can read it
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lab-report-\(UUID().uuidString).png")
                try data.write(to: tempURL)

                // Run through the same local → API extraction pipeline
                let localMarkers = (try? LocalLabParser.parse(fileURL: tempURL)) ?? []
                if !localMarkers.isEmpty {
                    extractedBiomarkers = localMarkers
                    selectedMarkers = Set(localMarkers.map(\.id))
                    extractionMethod = "local parsing"
                    isExtracting = false
                    return
                }

                if claudeService.hasAPIKey {
                    let apiMarkers = try await claudeService.extractBiomarkers(from: tempURL)
                    extractedBiomarkers = apiMarkers
                    selectedMarkers = Set(apiMarkers.map(\.id))
                    extractionMethod = "Claude API"
                    isExtracting = false
                    return
                }

                self.error = "Could not extract biomarkers from this photo. Add a Claude API key in Settings for better extraction."
                isExtracting = false
            } catch {
                self.error = error.localizedDescription
                isExtracting = false
            }
        }
    }
    #endif

    private func handleFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            fileName = url.lastPathComponent
            isExtracting = true
            error = nil

            Task {
                // Step 1: Try local parsing first (free, instant)
                do {
                    let localMarkers = try LocalLabParser.parse(fileURL: url)
                    if !localMarkers.isEmpty {
                        extractedBiomarkers = localMarkers
                        selectedMarkers = Set(localMarkers.map(\.id))
                        extractionMethod = "local parsing"
                        isExtracting = false
                        return
                    }
                } catch {
                    // Local parsing failed, try API
                }

                // Step 2: Fall back to Claude API if available
                if claudeService.hasAPIKey {
                    do {
                        let apiMarkers = try await claudeService.extractBiomarkers(from: url)
                        extractedBiomarkers = apiMarkers
                        selectedMarkers = Set(apiMarkers.map(\.id))
                        extractionMethod = "Claude API"
                        isExtracting = false
                        return
                    } catch {
                        self.error = error.localizedDescription
                        isExtracting = false
                        return
                    }
                }

                // Neither worked
                self.error = "Could not extract biomarkers from this file. Try a different format or add a Claude API key in Settings for better extraction."
                isExtracting = false
            }

        case .failure(let err):
            error = err.localizedDescription
        }
    }

    private func saveSelected() {
        var count = 0
        for marker in extractedBiomarkers where selectedMarkers.contains(marker.id) {
            let cal = Calendar.current
            let date = marker.parsedDate
            let start = cal.startOfDay(for: date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!

            let descriptor = FetchDescriptor<Biomarker>(
                predicate: #Predicate { $0.testDate >= start && $0.testDate < end }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            let alreadyExists = existing.contains { $0.marker == marker.marker }

            if !alreadyExists {
                modelContext.insert(Biomarker(
                    testDate: date,
                    marker: marker.marker,
                    value: marker.value,
                    unit: marker.unit,
                    refMin: marker.refMin,
                    refMax: marker.refMax,
                    lab: marker.lab
                ))
                count += 1
            }
        }

        try? modelContext.save()
        importedCount = count
        extractedBiomarkers = []
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
