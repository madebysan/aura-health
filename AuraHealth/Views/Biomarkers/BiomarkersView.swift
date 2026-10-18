import SwiftUI
import SwiftData
import Charts

struct BiomarkersView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Biomarker.testDate, order: .reverse)
    private var biomarkers: [Biomarker]

    @Query private var labSessions: [LabSession]

    @State private var searchText = ""
    @State private var flaggedOnly = false
    @State private var showingAddSheet = false
    @State private var showingLabImport = false
    @State private var selectedBiomarker: Biomarker?
    @State private var selectedSnapshotIndex = -1  // -1 = latest per marker, 0+ = specific lab date
    @State private var showOlderMarkers = false
    @State private var showingLabNotes = false

    @State private var aiService = AIService()

    /// One list row: the reading shown for the selected session and the one before it.
    struct MarkerRow: Identifiable {
        let marker: String
        let shown: Biomarker
        let previous: Biomarker?
        let history: [Biomarker]
        var id: String { marker }
    }

    // MARK: - Snapshot Data

    /// All unique lab dates, newest first
    private var labDates: [Date] {
        let cal = Calendar.current
        let dates = Set(biomarkers.map { cal.startOfDay(for: $0.testDate) })
        return dates.sorted(by: >)
    }

    private var isShowingAll: Bool { selectedSnapshotIndex == -1 }

    private var selectedDate: Date? {
        guard !isShowingAll, !labDates.isEmpty else { return nil }
        return labDates[min(selectedSnapshotIndex, labDates.count - 1)]
    }

    private var currentLabSession: LabSession? {
        guard let date = selectedDate else { return nil }
        let cal = Calendar.current
        return labSessions.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    private func labSession(for date: Date) -> LabSession {
        let cal = Calendar.current
        if let existing = labSessions.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            return existing
        }
        let session = LabSession(date: cal.startOfDay(for: date))
        modelContext.insert(session)
        return session
    }

    private var labsAreStale: Bool {
        guard let newest = labDates.first else { return false }
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        return newest < threeMonthsAgo
    }

    private var historyByMarker: [String: [Biomarker]] {
        Dictionary(grouping: biomarkers, by: \.marker).mapValues { $0.sorted { $0.testDate > $1.testDate } }
    }

    /// Rows for the selected session (or the latest reading of every marker),
    /// before search and the flagged filter.
    private var sessionRows: [MarkerRow] {
        let cal = Calendar.current
        return historyByMarker.compactMap { marker, history in
            if let date = selectedDate {
                guard let index = history.firstIndex(where: { cal.isDate($0.testDate, inSameDayAs: date) }) else { return nil }
                return MarkerRow(marker: marker, shown: history[index], previous: history.indices.contains(index + 1) ? history[index + 1] : nil, history: history)
            }
            return MarkerRow(marker: marker, shown: history[0], previous: history.count > 1 ? history[1] : nil, history: history)
        }
        .sorted { $0.marker < $1.marker }
    }

    /// Markers without a reading in the selected session, showing their latest value.
    private var olderRows: [MarkerRow] {
        guard selectedDate != nil else { return [] }
        let inSession = Set(sessionRows.map(\.marker))
        return historyByMarker
            .filter { !inSession.contains($0.key) }
            .map { MarkerRow(marker: $0.key, shown: $0.value[0], previous: $0.value.count > 1 ? $0.value[1] : nil, history: $0.value) }
            .sorted { $0.marker < $1.marker }
    }

    private func applyFilters(_ rows: [MarkerRow]) -> [MarkerRow] {
        rows.filter { row in
            (searchText.isEmpty || row.marker.localizedCaseInsensitiveContains(searchText))
                && (!flaggedOnly || row.shown.status == .borderline || row.shown.status == .abnormal)
        }
    }

    private func groupedBySystem(_ rows: [MarkerRow]) -> [(system: BodySystem, rows: [MarkerRow])] {
        let grouped = Dictionary(grouping: rows) { BiomarkerReference.system(for: $0.marker) }
        return BodySystem.allCases.compactMap { system in
            guard let rows = grouped[system], !rows.isEmpty else { return nil }
            return (system: system, rows: rows)
        }
    }

    private var flaggedCount: Int {
        sessionRows.filter { $0.shown.status == .borderline || $0.shown.status == .abnormal }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if biomarkers.isEmpty {
                    VStack(spacing: 12) {
                        EmptyStateView(
                            icon: "drop",
                            title: "No Biomarkers",
                            message: "Upload a lab report in Chat to import biomarkers automatically, or add them manually.",
                            actionLabel: "Upload Lab Results in Chat",
                            action: { NotificationCenter.default.post(name: .switchToChat, object: nil) }
                        )
                        Button("Add Manually") { showingAddSheet = true }
                            .font(Notebook.mono(.footnote))
                            .underline()
                            .foregroundStyle(Notebook.inkSecondary)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    Text(headerKicker)
                        .kicker()
                        .padding(.bottom, 10)

                    snapshotPicker

                    if labsAreStale {
                        NoteLine(text: "Your most recent results are over 3 months old. Consider scheduling a follow-up with your doctor.", tag: "Labs")
                    }

                    statusSummary

                    if !isShowingAll, let date = selectedDate {
                        labNotesRow(for: date)
                    }

                    toolsRow

                    let visible = applyFilters(sessionRows)
                    if visible.isEmpty {
                        Text(searchText.isEmpty ? "No flagged markers in this session." : "No markers match “\(searchText)”.")
                            .font(Notebook.mono(.footnote))
                            .foregroundStyle(Notebook.inkSecondary)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(groupedBySystem(visible), id: \.system) { group in
                            systemSection(group, isFaded: false)
                        }
                    }

                    // Markers not measured in the selected session
                    let older = applyFilters(olderRows)
                    if !older.isEmpty {
                        if showOlderMarkers {
                            NotebookSectionHeader(title: "Not in this session", trailing: "\(older.count)")
                            ForEach(groupedBySystem(older), id: \.system) { group in
                                systemSection(group, isFaded: true)
                            }
                            Button("Hide older results") {
                                withAnimation(AppAnimation.viewSwitch) { showOlderMarkers = false }
                            }
                            .font(Notebook.mono(.footnote))
                            .underline()
                            .foregroundStyle(Notebook.inkSecondary)
                            .frame(minHeight: 44)
                        } else {
                            Button {
                                withAnimation(AppAnimation.expand) { showOlderMarkers = true }
                            } label: {
                                Text("Show \(older.count) markers not in this session")
                                    .font(Notebook.mono(.footnote))
                                    .underline()
                                    .foregroundStyle(Notebook.inkSecondary)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
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
                .accessibilityLabel("Add or Import Biomarker")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddBiomarkerSheet()
        }
        .sheet(isPresented: $showingLabImport) {
            LabImportSheet(aiService: aiService)
        }
        .sheet(item: $selectedBiomarker) { biomarker in
            BiomarkerDetailSheet(marker: biomarker.marker, biomarkers: biomarkers, focusDate: biomarker.testDate)
        }
        .onChange(of: selectedSnapshotIndex) {
            showOlderMarkers = false
        }
    }

    private var headerKicker: String {
        let labs = Set(biomarkers.map(\.lab).filter { !$0.isEmpty })
        let markers = Set(biomarkers.map(\.marker)).count
        let source = labs.count == 1 ? labs.first! : "\(labDates.count) sessions"
        return "\(source) · \(markers) markers"
    }

    // MARK: - System Section

    private func systemSection(_ group: (system: BodySystem, rows: [MarkerRow]), isFaded: Bool) -> some View {
        let flagged = group.rows.filter { $0.shown.status == .borderline || $0.shown.status == .abnormal }.count
        return VStack(alignment: .leading, spacing: 0) {
            NotebookSectionHeader(
                title: group.system.rawValue,
                trailing: flagged > 0 ? "\(flagged) flagged" : "\(group.rows.count)",
                trailingColor: flagged > 0 ? Notebook.signal : Notebook.inkSecondary
            )
            ForEach(group.rows) { row in
                Button {
                    selectedBiomarker = row.shown
                } label: {
                    BiomarkerCardView(biomarker: row.shown, previous: row.previous, historyCount: row.history.count, isFaded: isFaded)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        for bio in row.history {
                            modelContext.delete(bio)
                        }
                    } label: {
                        Label("Delete All \(row.marker) Records", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Snapshot Picker

    private var snapshotPicker: some View {
        UnderlineTabs(options: [-1] + Array(labDates.indices), selection: $selectedSnapshotIndex) { index in
            guard index >= 0 else { return "Latest" }
            let date = labDates[index]
            let cal = Calendar.current
            if let name = labSessions.first(where: { cal.isDate($0.date, inSameDayAs: date) })?.name, !name.isEmpty {
                return name
            }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        let rows = sessionRows
        let normal = rows.filter { $0.shown.status == .normal }.count
        let borderline = rows.filter { $0.shown.status == .borderline }.count
        let abnormal = rows.filter { $0.shown.status == .abnormal }.count
        let clearlyOut = rows.contains { $0.shown.status == .abnormal && !$0.shown.isMarginallyOutOfRange }
        let severity: (Biomarker) -> Int = { $0.status == .abnormal ? 2 : $0.status == .borderline ? 1 : 0 }
        let ordered = rows.map(\.shown).sorted { severity($0) < severity($1) }

        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Latest results").kicker()
            BigNumber(value: "\(normal)", suffix: "/\(rows.count) in range")

            HStack(spacing: 3) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, bio in
                    Rectangle()
                        .fill(bio.status == .normal ? Notebook.ink.opacity(0.2) : AppColors.biomarkerColor(bio))
                        .frame(height: 18)
                }
            }
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { legendItems(normal: normal, borderline: borderline, abnormal: abnormal, clearlyOut: clearlyOut) }
                VStack(alignment: .leading, spacing: 4) { legendItems(normal: normal, borderline: borderline, abnormal: abnormal, clearlyOut: clearlyOut) }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func legendItems(normal: Int, borderline: Int, abnormal: Int, clearlyOut: Bool) -> some View {
        legendItem(count: normal, label: "in range", color: Notebook.ink.opacity(0.25))
        legendItem(count: borderline, label: "near limit", color: Notebook.near)
        legendItem(count: abnormal, label: "out of range", color: clearlyOut ? Notebook.signal : Notebook.near)
    }

    private func legendItem(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
            Text("\(count)").foregroundStyle(Notebook.ink)
            Text(label).foregroundStyle(Notebook.inkSecondary)
        }
        .font(Notebook.mono(.caption))
    }

    // MARK: - Search and Filter

    private var toolsRow: some View {
        // Side by side when they fit; stacked at large text sizes
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                searchField
                flaggedButton(fixed: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                searchField
                flaggedButton(fixed: false)
            }
        }
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote)
                .foregroundStyle(Notebook.inkTertiary)
                .accessibilityHidden(true)
            TextField("Search markers", text: $searchText)
                .font(Notebook.mono(.subheadline))
                .textFieldStyle(.plain)
                .submitLabel(.search)
        }
        .frame(minHeight: 44)
        .ruled()
    }

    private func flaggedButton(fixed: Bool) -> some View {
        Button {
            withAnimation(AppAnimation.viewSwitch) { flaggedOnly.toggle() }
        } label: {
            Text("Flagged only (\(flaggedCount))")
                .font(Notebook.mono(.caption))
                .underline(true, pattern: .solid)
                .fontWeight(flaggedOnly ? .semibold : .regular)
                .foregroundStyle(flaggedOnly ? Notebook.ink : Notebook.inkSecondary)
                .fixedSize(horizontal: fixed, vertical: false)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(flaggedOnly ? .isSelected : [])
    }

    // MARK: - Lab Notes

    private func labNotesRow(for date: Date) -> some View {
        let session = currentLabSession
        let name = session?.name ?? ""
        let notes = session?.notes ?? ""
        let hasContent = !name.isEmpty || !notes.isEmpty

        return Button {
            showingLabNotes = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Notes").kicker()
                VStack(alignment: .leading, spacing: 2) {
                    if hasContent {
                        if !name.isEmpty {
                            Text(name).font(.subheadline.weight(.medium)).foregroundStyle(Notebook.ink)
                        }
                        if !notes.isEmpty {
                            Text(notes).font(.footnote).foregroundStyle(Notebook.inkSecondary).lineLimit(2)
                        }
                    } else {
                        Text("Add notes for this session").font(.subheadline).foregroundStyle(Notebook.inkSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Notebook.inkTertiary)
            }
            .padding(.vertical, 14)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingLabNotes) {
            LabNotesSheet(date: date, labSession: labSession(for: date))
        }
    }
}

// MARK: - Biomarker Row

/// One lab result: name, status word and previous value; the mono value; and
/// an inline range bar. Stacks at accessibility text sizes.
struct BiomarkerCardView: View {
    let biomarker: Biomarker
    var previous: Biomarker?
    let historyCount: Int
    var isFaded: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    nameBlock
                    valueBlock(alignment: .leading)
                    rangeBlock
                }
            } else {
                HStack(spacing: 14) {
                    nameBlock.frame(maxWidth: .infinity, alignment: .leading)
                    valueBlock(alignment: .trailing)
                    rangeBlock.frame(width: 72)
                }
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        .contentShape(Rectangle())
        .opacity(isFaded ? 0.5 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    private var statusText: String {
        switch biomarker.status {
        case .abnormal: biomarker.rangePosition == .below ? "↓ below range" : "↑ above range"
        default: biomarker.statusLabel.lowercased()
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(biomarker.marker)
                .font(.callout.weight(.medium))
                .foregroundStyle(Notebook.ink)
            HStack(spacing: 0) {
                StatusWord(text: statusText, color: AppColors.biomarkerWordColor(biomarker))
                if let previous {
                    StatusWord(text: " · was \(AppFormat.number(previous.value))")
                }
            }
        }
    }

    private func valueBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(AppFormat.number(biomarker.value))
                .font(Notebook.mono(.title3, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Notebook.ink)
            Text(biomarker.unit)
                .font(Notebook.mono(.caption2))
                .foregroundStyle(Notebook.inkSecondary)
        }
    }

    @ViewBuilder
    private var rangeBlock: some View {
        if biomarker.lowerLimit != nil || biomarker.upperLimit != nil {
            MiniRangeBar(value: biomarker.value, low: biomarker.lowerLimit, high: biomarker.upperLimit, color: AppColors.biomarkerColor(biomarker))
        } else {
            Color.clear.frame(height: 18)
        }
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
    /// The session the user tapped; defaults to the latest reading.
    var focusDate: Date?

    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .largeTitle) private var heroValueSize: CGFloat = 52

    private var history: [Biomarker] {
        biomarkers.filter { $0.marker == marker }.sorted { $0.testDate > $1.testDate }
    }

    private var focused: Biomarker? {
        if let focusDate, let match = history.first(where: { Calendar.current.isDate($0.testDate, inSameDayAs: focusDate) }) {
            return match
        }
        return history.first
    }

    /// "Improving since April" when the oldest reading was outside the range
    /// and later readings moved back toward it.
    private var trendTitle: String {
        guard history.count > 1, let oldest = history.last, let newest = history.first else { return "Across sessions" }
        let towardRange: Bool
        if let high = oldest.upperLimit, oldest.value > high { towardRange = newest.value < oldest.value }
        else if let low = oldest.lowerLimit, oldest.value < low { towardRange = newest.value > oldest.value }
        else { towardRange = false }
        return towardRange ? "Improving since \(oldest.testDate.formatted(.dateTime.month(.wide)))" : "Across sessions"
    }

    private func statusText(_ bio: Biomarker) -> String {
        switch bio.status {
        case .abnormal: bio.rangePosition == .below ? "↓ below range" : "↑ above range"
        default: bio.statusLabel.lowercased()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let latest = focused {
                        // Value + status
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppFormat.number(latest.value))
                                .font(.system(size: heroValueSize, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(Notebook.ink)
                                .contentTransition(.numericText())
                            Text("\(latest.unit) · \(latest.testDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(Notebook.mono(.footnote))
                                .foregroundStyle(Notebook.inkSecondary)
                            StatusWord(text: statusText(latest), color: AppColors.biomarkerWordColor(latest))
                                .padding(.top, 6)
                        }
                        .notebookBlock()

                        // Range bar
                        if latest.lowerLimit != nil || latest.upperLimit != nil {
                            ReferenceRangeBar(
                                value: latest.value,
                                low: latest.lowerLimit,
                                high: latest.upperLimit,
                                valueColor: AppColors.biomarkerColor(latest),
                                unit: latest.unit
                            )
                            .notebookBlock()
                        }

                        // Trend chart
                        if history.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(trendTitle).kicker()
                                trendChart(latest: latest)
                            }
                            .notebookBlock()
                        }

                        // History
                        VStack(alignment: .leading, spacing: 0) {
                            Text("History").kicker().padding(.bottom, 8)
                            ForEach(history, id: \.id) { bio in
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Text(bio.testDate, format: .dateTime.month(.abbreviated).day().year())
                                        Spacer()
                                        Text("\(AppFormat.number(bio.value)) \(bio.unit)")
                                        Text(statusText(bio))
                                            .foregroundStyle(AppColors.biomarkerWordColor(bio))
                                            .frame(minWidth: 110, alignment: .trailing)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bio.testDate, format: .dateTime.month(.abbreviated).day().year())
                                        Text("\(AppFormat.number(bio.value)) \(bio.unit) · \(statusText(bio))")
                                            .foregroundStyle(AppColors.biomarkerWordColor(bio))
                                    }
                                }
                                .font(Notebook.mono(.subheadline))
                                .foregroundStyle(Notebook.ink)
                                .padding(.vertical, 9)
                                .accessibilityElement(children: .combine)
                                if bio.id != history.last?.id {
                                    Rectangle().fill(Notebook.rule).frame(height: 1)
                                }
                            }
                        }
                        .notebookBlock()

                        // Educational info
                        if let info = BiomarkerReference.info(for: marker) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("About this marker").kicker()
                                Text(info.description)
                                    .font(.subheadline)
                                    .foregroundStyle(Notebook.ink)
                                Text("Why it matters: \(info.whyItMatters)")
                                    .font(.subheadline)
                                    .foregroundStyle(Notebook.inkSecondary)
                                if latest.status != .normal {
                                    Text("Questions to discuss: \(info.ifOutOfRange)")
                                        .font(.subheadline)
                                        .foregroundStyle(Notebook.inkSecondary)
                                }
                            }
                            .notebookBlock()
                        }

                        Text("Educational context only. Reference ranges vary by laboratory and individual; consult a qualified healthcare professional before making medical decisions.")
                            .font(Notebook.mono(.caption2))
                            .foregroundStyle(Notebook.inkSecondary)
                            .padding(.top, 16)

                        // Chat about this marker
                        Button {
                            let context = "Tell me about my \(marker) level of \(AppFormat.number(latest.value)) \(latest.unit). Is this good? What should I know?"
                            NotificationCenter.default.post(name: .switchToChat, object: context)
                            dismiss()
                        } label: {
                            Label("Chat about this", systemImage: "bubble.left")
                        }
                        .buttonStyle(NotebookSecondaryButtonStyle())
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Notebook.paperRaised.ignoresSafeArea())
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

    private func trendChart(latest: Biomarker) -> some View {
        Chart {
            if let high = latest.upperLimit {
                RectangleMark(
                    yStart: .value("Low", latest.lowerLimit ?? 0),
                    yEnd: .value("High", high)
                )
                .foregroundStyle(Notebook.band.opacity(0.5))
            }

            ForEach(history.reversed(), id: \.id) { bio in
                LineMark(
                    x: .value("Date", bio.testDate),
                    y: .value("Value", bio.value)
                )
                .foregroundStyle(Notebook.ink)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(
                    x: .value("Date", bio.testDate),
                    y: .value("Value", bio.value)
                )
                .foregroundStyle(AppColors.biomarkerColor(bio))
                .symbol(.square)
                .symbolSize(44)

                if let selectedDate, Calendar.current.isDate(bio.testDate, inSameDayAs: selectedDate) {
                    RuleMark(x: .value("Date", bio.testDate))
                        .foregroundStyle(Notebook.inkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, spacing: 6) {
                            Text("\(AppFormat.number(bio.value)) \(bio.unit)")
                                .font(Notebook.mono(.caption, weight: .medium))
                                .foregroundStyle(Notebook.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Notebook.paperRaised)
                                .overlay(Rectangle().stroke(Notebook.rule, lineWidth: 1))
                        }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 28))
        .chartXAxis {
            AxisMarks(values: history.map(\.testDate)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Notebook.mono(.caption2))
                    .foregroundStyle(Notebook.inkSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Notebook.rule)
                AxisValueLabel().font(Notebook.mono(.caption2)).foregroundStyle(Notebook.inkSecondary)
            }
        }
        .frame(height: 160)
        .accessibilityLabel("\(marker) trend")
        .accessibilityValue(ChartSummary.trend(points: history.map { ($0.testDate, $0.value) }, unit: latest.unit))
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
