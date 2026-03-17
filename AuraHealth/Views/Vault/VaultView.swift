import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct VaultView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \VaultDocument.uploadedAt, order: .reverse)
    private var documents: [VaultDocument]

    @State private var showingUpload = false
    @State private var selectedDocument: VaultDocument?

    var body: some View {
        ScrollView {
            if documents.isEmpty {
                EmptyStateView(
                    icon: "doc.fill",
                    title: "No Documents",
                    message: "Upload PDFs, images, or text files to your secure vault.",
                    actionLabel: "Upload",
                    action: { showingUpload = true }
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 280))], spacing: 12) {
                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, doc in
                        DocumentCard(document: doc)
                            .onTapGesture { selectedDocument = doc }
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(doc)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .staggeredAppearance(index: index)
                    }
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .navigationTitle("Vault")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUpload = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingUpload) { VaultUploadSheet() }
        .sheet(item: $selectedDocument) { doc in VaultDocumentDetail(document: doc) }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    let document: VaultDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: document.fileType.iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(fileColor)
                    .frame(width: 36, height: 36)
                    .background(fileColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Spacer()

                Text(formattedSize)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
            }

            Text(document.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Text(document.uploadedAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !document.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(document.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle(padding: 14, cornerRadius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .hoverCard()
    }

    private var fileColor: Color {
        switch document.fileType {
        case .pdf: .red
        case .image: .blue
        case .text: .green
        case .video: .purple
        }
    }

    private var formattedSize: String {
        let bytes = document.fileSize
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - Upload Sheet

struct VaultUploadSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var tags = ""
    @State private var selectedFileURL: URL?
    @State private var selectedFileName = ""
    @State private var selectedFileSize: Int = 0
    @State private var showingFilePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var selectedPhotoName: String?

    /// Whether a file or photo has been selected
    private var hasSelection: Bool {
        selectedFileURL != nil || selectedPhotoData != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let url = selectedFileURL {
                        HStack {
                            Image(systemName: fileType(for: url).iconName)
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                            Spacer()
                            Button("Change") { showingFilePicker = true }
                                .font(.caption)
                        }
                    } else if selectedPhotoData != nil {
                        HStack {
                            Image(systemName: "photo.fill")
                                .foregroundStyle(.blue)
                            Text(selectedPhotoName ?? "Photo")
                                .font(.subheadline)
                            Spacer()
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Text("Change").font(.caption)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                showingFilePicker = true
                            } label: {
                                Label("Select File", systemImage: "doc.badge.plus")
                            }

                            Divider().frame(height: 20)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                        }
                    }
                }

                Section {
                    TextField("Title", text: $title)
                    TextField("Tags (comma separated)", text: $tags)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Upload Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasSelection || title.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .image, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    selectedFileURL = url
                    selectedPhotoData = nil
                    selectedPhotoName = nil
                    if title.isEmpty {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
            .onChange(of: selectedPhotoItem) {
                Task {
                    guard let item = selectedPhotoItem else { return }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        selectedPhotoData = data
                        selectedFileURL = nil
                        let name = "Photo \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
                        selectedPhotoName = name
                        if title.isEmpty { title = name }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func save() {
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let photoData = selectedPhotoData {
            // Save from photo library
            let fileName = (selectedPhotoName ?? "Photo") + ".jpg"
            let doc = VaultDocument(
                title: title,
                fileName: fileName,
                fileType: .image,
                mimeType: "image/jpeg",
                fileData: photoData,
                fileSize: photoData.count,
                tags: tagList,
                notes: notes
            )
            modelContext.insert(doc)
            dismiss()
            return
        }

        guard let url = selectedFileURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try? Data(contentsOf: url)
        let size = data?.count ?? 0
        let type = fileType(for: url)

        let doc = VaultDocument(
            title: title,
            fileName: url.lastPathComponent,
            fileType: type,
            mimeType: mimeType(for: url),
            fileData: data,
            fileSize: size,
            tags: tagList,
            notes: notes
        )
        modelContext.insert(doc)
        dismiss()
    }

    private func fileType(for url: URL) -> VaultFileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .pdf
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return .image
        case "txt", "md", "csv", "rtf": return .text
        case "mp4", "mov", "m4v": return .video
        default: return .text
        }
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Document Detail

struct VaultDocumentDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: VaultDocument

    @State private var tagsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Image preview
                if document.fileType == .image, let data = document.fileData {
                    #if os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Section {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        }
                    }
                    #endif
                }

                Section("Details") {
                    TextField("Title", text: $document.title)
                    TextField("Tags (comma separated)", text: $tagsText)
                        .onChange(of: tagsText) {
                            document.tags = tagsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $document.notes, axis: .vertical)
                        .lineLimit(3)
                }

                Section("Info") {
                    LabeledContent("File", value: document.fileName)
                    LabeledContent("Size") {
                        Text(formattedSize)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Added", value: document.uploadedAt, format: .dateTime.month(.abbreviated).day().year())
                }
            }
            .formStyle(.grouped)
            .navigationTitle(document.title.isEmpty ? "Document" : document.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                if let data = document.fileData {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(
                            item: data,
                            preview: SharePreview(document.title, image: Image(systemName: document.fileType.iconName))
                        )
                    }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                tagsText = document.tags.joined(separator: ", ")
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }

    private var formattedSize: String {
        let bytes = document.fileSize
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
