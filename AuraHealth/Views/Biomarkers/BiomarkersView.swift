import SwiftUI
import SwiftData
import Charts

struct BiomarkersView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Biomarker.testDate, order: .reverse)
    private var biomarkers: [Biomarker]

    @State private var searchText = ""
    @State private var statusFilter: BiomarkerStatus?
    @State private var showingAddSheet = false
    @State private var showingLabImport = false
    @State private var selectedBiomarker: Biomarker?

    private var claudeService: ClaudeService { ClaudeService() }

    private var filteredBiomarkers: [Biomarker] {
        biomarkers.filter { bio in
            let matchesSearch = searchText.isEmpty || bio.marker.localizedCaseInsensitiveContains(searchText)
            let matchesStatus = statusFilter == nil || bio.status == statusFilter
            return matchesSearch && matchesStatus
        }
    }

    private var groupedByMarker: [(marker: String, latest: Biomarker, history: [Biomarker])] {
        let grouped = Dictionary(grouping: filteredBiomarkers, by: \.marker)
        return grouped.map { marker, items in
            let sorted = items.sorted { $0.testDate > $1.testDate }
            return (marker: marker, latest: sorted[0], history: sorted)
        }
        .sorted { $0.marker < $1.marker }
    }

    private var groupedBySystem: [(system: BodySystem, markers: [(marker: String, latest: Biomarker, history: [Biomarker])])] {
        let systemGrouped = Dictionary(grouping: groupedByMarker) { group in
            BiomarkerReference.system(for: group.marker)
        }
        return BodySystem.allCases.compactMap { system in
            guard let markers = systemGrouped[system], !markers.isEmpty else { return nil }
            return (system: system, markers: markers)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if groupedByMarker.isEmpty && biomarkers.isEmpty {
                    EmptyStateView(
                        icon: "cross.vial",
                        title: "No Biomarkers",
                        message: "Add lab results to track your biomarkers over time.",
                        actionLabel: "Add Biomarker",
                        action: { showingAddSheet = true }
                    )
                    .padding(.top, 40)
                } else {
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

                    // Biomarker cards grouped by body system
                    ForEach(groupedBySystem, id: \.system) { systemGroup in
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
                                BiomarkerCardView(biomarker: group.latest, historyCount: group.history.count)
                                    .onTapGesture { selectedBiomarker = group.latest }
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
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("Biomarkers")
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
    }

    // MARK: - Status Summary

    private var statusSummaryBar: some View {
        let counts = statusCounts
        let total = counts.normal + counts.borderline + counts.abnormal
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
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
            .frame(height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }

    private func statusSegment(count: Int, total: Int, width: CGFloat, color: Color, label: String) -> some View {
        let segmentCount = [statusCounts.normal > 0, statusCounts.borderline > 0, statusCounts.abnormal > 0].filter(\.self).count
        let spacing = CGFloat(segmentCount - 1) * 2
        let segmentWidth = max(40, (width - spacing) * CGFloat(count) / CGFloat(total))

        return color.opacity(0.7)
            .frame(width: segmentWidth)
            .overlay(
                Text("\(count) \(label)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            )
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

            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: biomarker.value == biomarker.value.rounded() ? "%.0f" : "%.1f", biomarker.value))
                        .font(.body.monospacedDigit().bold())
                    Text(biomarker.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                StatusBadge(label: biomarker.status.displayName, color: AppColors.biomarkerColor(biomarker.status))
            }

            if historyCount > 1 {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .cardStyle(padding: 12, cornerRadius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverCard()
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
                                    .foregroundStyle(Color.accentColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2))

                                    PointMark(
                                        x: .value("Date", bio.testDate),
                                        y: .value("Value", bio.value)
                                    )
                                    .foregroundStyle(AppColors.biomarkerColor(bio.status))
                                    .symbolSize(40)
                                }
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
                        .fill(AppColors.statusRed.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.statusGreen.opacity(0.2))
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
