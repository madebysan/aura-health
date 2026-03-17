import SwiftUI
import SwiftData
import Charts

struct BiomarkersView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Biomarker.testDate, order: .reverse)
    private var biomarkers: [Biomarker]

    @Query private var labSessions: [LabSession]

    @State private var searchText = ""
    @State private var statusFilter: BiomarkerStatus?
    @State private var showingAddSheet = false
    @State private var showingLabImport = false
    @State private var selectedBiomarker: Biomarker?
    @State private var selectedSnapshotIndex = -1  // -1 = "All", 0+ = specific lab date
    @State private var showOlderMarkers = false
    @State private var showingLabNotes = false

    @State private var claudeService = ClaudeService()

    // MARK: - Snapshot Data

    /// All unique lab dates, newest first
    private var labDates: [Date] {
        let cal = Calendar.current
        let dates = Set(biomarkers.map { cal.startOfDay(for: $0.testDate) })
        return dates.sorted(by: >)
    }

    /// Whether "All" is selected (no specific snapshot)
    private var isShowingAll: Bool { selectedSnapshotIndex == -1 }

    /// The currently selected snapshot date
    private var selectedDate: Date? {
        guard !isShowingAll, !labDates.isEmpty else { return nil }
        let idx = min(selectedSnapshotIndex, labDates.count - 1)
        return labDates[idx]
    }

    /// Biomarkers from the selected snapshot date (all markers when showing "All")
    private var snapshotBiomarkers: Set<String> {
        if isShowingAll { return Set(biomarkers.map(\.marker)) }
        guard let date = selectedDate else { return [] }
        let cal = Calendar.current
        return Set(biomarkers.filter { cal.isDate($0.testDate, inSameDayAs: date) }.map(\.marker))
    }

    /// Lab session for the currently selected date
    private var currentLabSession: LabSession? {
        guard let date = selectedDate else { return nil }
        let cal = Calendar.current
        return labSessions.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    /// Find or create a lab session for a date
    private func labSession(for date: Date) -> LabSession {
        let cal = Calendar.current
        if let existing = labSessions.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            return existing
        }
        let session = LabSession(date: cal.startOfDay(for: date))
        modelContext.insert(session)
        return session
    }

    /// Whether the most recent lab is older than 3 months
    private var labsAreStale: Bool {
        guard let newest = labDates.first else { return false }
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        return newest < threeMonthsAgo
    }

    /// Latest value for each marker, respecting search & status filters
    private var groupedByMarker: [(marker: String, latest: Biomarker, history: [Biomarker])] {
        let filtered = biomarkers.filter { bio in
            let matchesSearch = searchText.isEmpty || bio.marker.localizedCaseInsensitiveContains(searchText)
            let matchesStatus = statusFilter == nil || bio.status == statusFilter
            return matchesSearch && matchesStatus
        }
        let grouped = Dictionary(grouping: filtered, by: \.marker)
        return grouped.map { marker, items in
            let sorted = items.sorted { $0.testDate > $1.testDate }
            return (marker: marker, latest: sorted[0], history: sorted)
        }
        .sorted { $0.marker < $1.marker }
    }

    /// Markers grouped by body system
    private var groupedBySystem: [(system: BodySystem, markers: [(marker: String, latest: Biomarker, history: [Biomarker])])] {
        let systemGrouped = Dictionary(grouping: groupedByMarker) { group in
            BiomarkerReference.system(for: group.marker)
        }
        return BodySystem.allCases.compactMap { system in
            guard let markers = systemGrouped[system], !markers.isEmpty else { return nil }
            return (system: system, markers: markers)
        }
    }

    /// Markers from the selected snapshot, grouped by system
    private var snapshotGroupedBySystem: [(system: BodySystem, markers: [(marker: String, latest: Biomarker, history: [Biomarker])])] {
        groupedBySystem.compactMap { systemGroup in
            let filtered = systemGroup.markers.filter { snapshotBiomarkers.contains($0.marker) }
            guard !filtered.isEmpty else { return nil }
            return (system: systemGroup.system, markers: filtered)
        }
    }

    /// Markers NOT in the selected snapshot, grouped by system
    private var olderGroupedBySystem: [(system: BodySystem, markers: [(marker: String, latest: Biomarker, history: [Biomarker])])] {
        groupedBySystem.compactMap { systemGroup in
            let filtered = systemGroup.markers.filter { !snapshotBiomarkers.contains($0.marker) }
            guard !filtered.isEmpty else { return nil }
            return (system: systemGroup.system, markers: filtered)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if biomarkers.isEmpty {
                    VStack(spacing: 12) {
                        EmptyStateView(
                            icon: "drop.fill",
                            title: "No Biomarkers",
                            message: "Upload a lab report in Chat to import biomarkers automatically, or add them manually.",
                            actionLabel: "Upload Lab Results in Chat",
                            action: { NotificationCenter.default.post(name: .switchToChat, object: nil) }
                        )
                        Button("Add Manually") { showingAddSheet = true }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    // Stale labs banner
                    if labsAreStale {
                        staleBanner
                    }

                    // Snapshot date picker
                    snapshotPicker

                    // Lab session notes card
                    if !isShowingAll, let date = selectedDate {
                        labNotesCard(for: date)
                    }

                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                        TextField("Search biomarkers", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    // Status summary bar
                    statusSummaryBar
                        .staggeredAppearance(index: 0)

                    // Filters
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterPill(label: "All", isActive: statusFilter == nil) {
                                withAnimation(AppAnimation.viewSwitch) { statusFilter = nil }
                            }
                            FilterPill(label: "Normal", isActive: statusFilter == .normal) {
                                withAnimation(AppAnimation.viewSwitch) { statusFilter = .normal }
                            }
                            FilterPill(label: "Borderline", isActive: statusFilter == .borderline) {
                                withAnimation(AppAnimation.viewSwitch) { statusFilter = .borderline }
                            }
                            FilterPill(label: "Abnormal", isActive: statusFilter == .abnormal) {
                                withAnimation(AppAnimation.viewSwitch) { statusFilter = .abnormal }
                            }
                        }
                    }

                    if isShowingAll {
                        // All biomarkers — latest value per marker, no fading
                        ForEach(groupedBySystem, id: \.system) { systemGroup in
                            biomarkerSystemSection(systemGroup, isFaded: false)
                        }
                    } else {
                        // Snapshot biomarkers (from selected lab date)
                        ForEach(snapshotGroupedBySystem, id: \.system) { systemGroup in
                            biomarkerSystemSection(systemGroup, isFaded: false)
                        }

                        // Older biomarkers (not in selected snapshot)
                        if !olderGroupedBySystem.isEmpty {
                            if showOlderMarkers {
                                Divider()
                                    .padding(.vertical, 4)

                                HStack {
                                    Text("Older Results")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button {
                                        withAnimation(AppAnimation.viewSwitch) {
                                            showOlderMarkers = false
                                        }
                                    } label: {
                                        Text("Hide")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 4)

                                ForEach(olderGroupedBySystem, id: \.system) { systemGroup in
                                    biomarkerSystemSection(systemGroup, isFaded: true)
                                }
                            } else {
                                let olderCount = olderGroupedBySystem.reduce(0) { $0 + $1.markers.count }
                                Button {
                                    withAnimation(AppAnimation.expand) {
                                        showOlderMarkers = true
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 14))
                                        Text("Show \(olderCount) older biomarkers")
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("Biomarkers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Manually", systemImage: "plus")
                    }
                    Button {
                        showingLabImport = true
                    } label: {
                        Label("Import from Lab Report", systemImage: "doc.text.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddBiomarkerSheet()
        }
        .sheet(isPresented: $showingLabImport) {
            LabImportSheet(claudeService: claudeService)
        }
        .sheet(item: $selectedBiomarker) { biomarker in
            BiomarkerDetailSheet(marker: biomarker.marker, biomarkers: biomarkers)
        }
        .onChange(of: selectedSnapshotIndex) {
            showOlderMarkers = false
        }
    }

    // MARK: - Biomarker System Section

    private func biomarkerSystemSection(
        _ systemGroup: (system: BodySystem, markers: [(marker: String, latest: Biomarker, history: [Biomarker])]),
        isFaded: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemGroup.system.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(systemGroup.system.swiftColor)
                Text(systemGroup.system.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(systemGroup.markers, id: \.marker) { group in
                Button {
                    selectedBiomarker = group.latest
                } label: {
                    BiomarkerCardView(
                        biomarker: group.latest,
                        historyCount: group.history.count,
                        isFaded: isFaded
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        for bio in group.history {
                            modelContext.delete(bio)
                        }
                    } label: {
                        Label("Delete All \(group.marker) Records", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Stale Banner

    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Labs may be outdated")
                    .font(.subheadline.weight(.medium))
                Text("Your most recent results are over 3 months old. Consider scheduling a follow-up with your doctor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Snapshot Picker

    private var snapshotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterPill(label: "Latest", isActive: isShowingAll) {
                    withAnimation(AppAnimation.viewSwitch) { selectedSnapshotIndex = -1 }
                }

                ForEach(Array(labDates.enumerated()), id: \.element) { index, date in
                    let cal = Calendar.current
                    let session = labSessions.first { cal.isDate($0.date, inSameDayAs: date) }
                    let label = if let name = session?.name, !name.isEmpty {
                        name
                    } else {
                        date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits))
                    }
                    FilterPill(
                        label: label,
                        isActive: index == selectedSnapshotIndex
                    ) {
                        withAnimation(AppAnimation.viewSwitch) { selectedSnapshotIndex = index }
                    }
                }
            }
        }
    }

    // MARK: - Lab Notes Card

    private func labNotesCard(for date: Date) -> some View {
        let session = currentLabSession
        let hasContent = session != nil && (!session!.name.isEmpty || !session!.notes.isEmpty)

        return Button {
            showingLabNotes = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: hasContent ? "note.text" : "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundStyle(hasContent ? .primary : .tertiary)
                    .frame(width: 20)

                if hasContent, let session {
                    VStack(alignment: .leading, spacing: 2) {
                        if !session.name.isEmpty {
                            Text(session.name)
                                .font(.subheadline.weight(.medium))
                        }
                        if !session.notes.isEmpty {
                            Text(session.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Text("Add lab notes")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingLabNotes) {
            LabNotesSheet(date: date, labSession: labSession(for: date))
        }
    }

    // MARK: - Status Summary

    private var statusSummaryBar: some View {
        let counts = statusCounts
        let total = counts.normal + counts.borderline + counts.abnormal
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 8) {
                GeometryReader { geo in
                    let width = geo.size.width
                    HStack(spacing: 2) {
                        if counts.normal > 0 {
                            statusSegment(count: counts.normal, total: total, width: width, color: AppColors.statusGreen, label: "Normal")
                        }
                        if counts.borderline > 0 {
                            statusSegment(count: counts.borderline, total: total, width: width, color: AppColors.statusOrange, label: "Borderline")
                        }
                        if counts.abnormal > 0 {
                            statusSegment(count: counts.abnormal, total: total, width: width, color: AppColors.statusRed, label: "Abnormal")
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                HStack(spacing: 12) {
                    if counts.normal > 0 {
                        statusLegendItem(count: counts.normal, label: "Normal", color: AppColors.statusGreen)
                    }
                    if counts.borderline > 0 {
                        statusLegendItem(count: counts.borderline, label: "Borderline", color: AppColors.statusOrange)
                    }
                    if counts.abnormal > 0 {
                        statusLegendItem(count: counts.abnormal, label: "Abnormal", color: AppColors.statusRed)
                    }
                    Spacer()
                    Text("\(total) markers")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        )
    }

    private func statusLegendItem(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusSegment(count: Int, total: Int, width: CGFloat, color: Color, label: String) -> some View {
        let segmentCount = [statusCounts.normal > 0, statusCounts.borderline > 0, statusCounts.abnormal > 0].filter(\.self).count
        let spacing = CGFloat(segmentCount - 1) * 2
        let segmentWidth = max(40, (width - spacing) * CGFloat(count) / CGFloat(total))

        return Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: segmentWidth, height: 14)
            .background(color.opacity(0.7))
    }

    private var statusCounts: (normal: Int, borderline: Int, abnormal: Int) {
        let latest = groupedByMarker.map(\.latest)
        return (
            normal: latest.filter { $0.status == .normal }.count,
            borderline: latest.filter { $0.status == .borderline }.count,
            abnormal: latest.filter { $0.status == .abnormal }.count
        )
    }
}

// MARK: - Biomarker Card

struct BiomarkerCardView: View {
    let biomarker: Biomarker
    let historyCount: Int
    var isFaded: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.biomarkerColor(biomarker.status))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(biomarker.marker)
                    .font(.subheadline.weight(.medium))
                Text(biomarker.testDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            StatusBadge(label: biomarker.status.displayName, color: AppColors.biomarkerColor(biomarker.status))

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: biomarker.value == biomarker.value.rounded() ? "%.0f" : "%.1f", biomarker.value))
                    .font(.body.monospacedDigit().bold())
                Text(biomarker.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: 12, cornerRadius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverCard()
        .opacity(isFaded ? 0.4 : 1.0)
    }
}

// MARK: - Add Biomarker Sheet

struct AddBiomarkerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var marker = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var refMin = ""
    @State private var refMax = ""
    @State private var lab = ""
    @State private var testDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Marker Name", text: $marker)
                    DatePicker("Test Date", selection: $testDate, displayedComponents: .date)
                    TextField("Lab", text: $lab)
                }
                Section("Result") {
                    HStack {
                        TextField("Value", text: $value)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("Unit", text: $unit)
                    }
                }
                Section("Reference Range") {
                    HStack {
                        TextField("Min", text: $refMin)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("-").foregroundStyle(.tertiary)
                        TextField("Max", text: $refMax)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Biomarker")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(marker.isEmpty || value.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }

    private func save() {
        guard let val = Double(value) else { return }
        modelContext.insert(Biomarker(testDate: testDate, marker: marker, value: val,
            unit: unit, refMin: Double(refMin), refMax: Double(refMax), lab: lab, notes: notes))
        dismiss()
    }
}

// MARK: - Detail Sheet

struct BiomarkerDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let marker: String
    let biomarkers: [Biomarker]

    @State private var selectedDate: Date?

    private var history: [Biomarker] {
        biomarkers.filter { $0.marker == marker }.sorted { $0.testDate > $1.testDate }
    }

    private var latest: Biomarker? { history.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let latest {
                        // Value + status
                        VStack(spacing: 6) {
                            Text(String(format: "%.1f", latest.value))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .contentTransition(.numericText())

                            Text(latest.unit)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            StatusBadge(label: latest.status.displayName, color: AppColors.biomarkerColor(latest.status))
                        }
                        .padding(.vertical, 8)

                        // Range bar
                        if latest.refMin != nil && latest.refMax != nil {
                            rangeBar(for: latest)
                                .cardStyle()
                        }

                        // Trend chart
                        if history.count > 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Trend")
                                    .font(.headline)

                                Chart(history.reversed(), id: \.id) { bio in
                                    LineMark(
                                        x: .value("Date", bio.testDate),
                                        y: .value("Value", bio.value)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(Color.secondary.opacity(0.5))
                                    .lineStyle(StrokeStyle(lineWidth: 2))

                                    PointMark(
                                        x: .value("Date", bio.testDate),
                                        y: .value("Value", bio.value)
                                    )
                                    .foregroundStyle(AppColors.biomarkerColor(bio.status))
                                    .symbolSize(40)

                                    if let selectedDate,
                                       Calendar.current.isDate(bio.testDate, inSameDayAs: selectedDate) {
                                        RuleMark(x: .value("Date", bio.testDate))
                                            .foregroundStyle(Color.secondary.opacity(0.3))
                                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                            .annotation(position: .top, spacing: 6) {
                                                VStack(spacing: 2) {
                                                    Text(String(format: "%.1f", bio.value) + " " + bio.unit)
                                                        .font(.caption.weight(.semibold))
                                                    Text(bio.testDate, format: .dateTime.month(.abbreviated).day().year())
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6))
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                                            }
                                    }
                                }
                                .chartXSelection(value: $selectedDate)
                                .frame(height: 160)
                            }
                            .cardStyle()
                        }

                        // Educational info
                        if let info = BiomarkerReference.info(for: marker) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("About This Marker")
                                    .font(.headline)

                                Text(info.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 6) {
                                    Label {
                                        Text("**Why it matters:** \(info.whyItMatters)")
                                            .font(.subheadline)
                                    } icon: {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                    }

                                    if latest.status != .normal {
                                        Label {
                                            Text("**What to do:** \(info.ifOutOfRange)")
                                                .font(.subheadline)
                                        } icon: {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .foregroundStyle(.blue)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                            .cardStyle()
                        }

                        // Chat about this marker
                        Button {
                            // Post notification with marker context so chat can pre-fill
                            let context = "Tell me about my \(marker) level of \(String(format: "%.1f", latest.value)) \(latest.unit). Is this good? What should I know?"
                            NotificationCenter.default.post(name: .switchToChat, object: context)
                            dismiss()
                        } label: {
                            Label("Chat about this", systemImage: "bubble.left.fill")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        // History
                        VStack(alignment: .leading, spacing: 10) {
                            Text("History")
                                .font(.headline)

                            ForEach(history, id: \.id) { bio in
                                HStack {
                                    Text(bio.testDate, format: .dateTime.month(.abbreviated).day().year())
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "%.1f", bio.value))
                                        .font(.subheadline.monospacedDigit().bold())
                                    Text(bio.unit)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Circle()
                                        .fill(AppColors.biomarkerColor(bio.status))
                                        .frame(width: 7, height: 7)
                                }
                                if bio.id != history.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .cardStyle()
                    }
                }
                .padding()
            }
            .navigationTitle(marker)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
    }

    private func rangeBar(for biomarker: Biomarker) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = geo.size.width
                let min = biomarker.refMin!
                let max = biomarker.refMax!
                let range = max - min
                let extendedMin = min - range * 0.3
                let extendedMax = max + range * 0.3
                let fullRange = extendedMax - extendedMin
                let normalStart = CGFloat((min - extendedMin) / fullRange) * width
                let normalWidth = CGFloat(range / fullRange) * width
                let valueX = CGFloat((biomarker.value - extendedMin) / fullRange) * width

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusRed.opacity(0.5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusGreen.opacity(0.55))
                        .frame(width: normalWidth)
                        .offset(x: normalStart)

                    Circle()
                        .fill(AppColors.biomarkerColor(biomarker.status))
                        .shadow(color: AppColors.biomarkerColor(biomarker.status).opacity(0.4), radius: 4)
                        .frame(width: 14, height: 14)
                        .offset(x: Swift.max(0, Swift.min(valueX - 7, width - 14)))
                }
            }
            .frame(height: 14)

            HStack {
                Text(String(format: "%.1f", biomarker.refMin!))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("Ref Range")
                    .font(.caption2).foregroundStyle(.quaternary)
                Spacer()
                Text(String(format: "%.1f", biomarker.refMax!))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Lab Notes Sheet

struct LabNotesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @Bindable var labSession: LabSession
    @State private var editedDate: Date

    init(date: Date, labSession: LabSession) {
        self.date = date
        self.labSession = labSession
        self._editedDate = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $editedDate, displayedComponents: .date)
                }

                Section("Lab Name") {
                    TextField("e.g. Quest Diagnostics, Annual Checkup", text: $labSession.name)
                }

                Section("Notes") {
                    TextField("Context, doctor notes, fasting status...", text: $labSession.notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Lab Notes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        updateDateIfNeeded()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func updateDateIfNeeded() {
        let cal = Calendar.current
        guard !cal.isDate(editedDate, inSameDayAs: date) else { return }

        // Update the lab session date
        let newDate = cal.startOfDay(for: editedDate)
        labSession.date = newDate

        // Update all biomarkers from the original date to the new date
        let descriptor = FetchDescriptor<Biomarker>()
        guard let biomarkers = try? modelContext.fetch(descriptor) else { return }
        for biomarker in biomarkers where cal.isDate(biomarker.testDate, inSameDayAs: date) {
            biomarker.testDate = newDate
        }
        try? modelContext.save()
    }
}
