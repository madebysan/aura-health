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
            VStack(alignment: .leading, spacing: 0) {
                if documents.isEmpty {
                    EmptyStateView(
                        icon: "ph.file-text",
                        title: "No Documents",
                        message: "Upload PDFs, images, or text files to your secure vault.",
                        actionLabel: "Upload",
                        action: { showingUpload = true }
                    )
                    .padding(.top, 60)
                } else {
                    NotebookSectionHeader(title: "Documents", trailing: "\(documents.count)")

                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, doc in
                        Button {
                            selectedDocument = doc
                        } label: {
                            DocumentCard(document: doc)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(doc)
                            } label: {
                                Label("Delete", image: "ph.trash")
                            }
                        }
                        .staggeredAppearance(index: index)
                    }
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .notebookBackground()
        .navigationTitle("Vault")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUpload = true } label: {
                    Image("ph.plus")
                }
                .accessibilityLabel("Add Document")
            }
        }
        .sheet(isPresented: $showingUpload) { VaultUploadSheet() }
        .sheet(item: $selectedDocument) { doc in VaultDocumentDetail(document: doc) }
    }
}

// MARK: - Document Row

/// A hairline row: monochrome file glyph, title, then type, size and date in
/// mono. Tags follow as a quiet mono line.
struct DocumentCard: View {
    let document: VaultDocument

    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(document.fileType.iconName)
                .font(.body)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(Notebook.ink)
                .frame(width: min(glyphWidth, 40))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Notebook.ink)
                    .lineLimit(3)

                Text("\(typeLabel) · \(formattedSize) · \(document.uploadedAt.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)

                if !document.tags.isEmpty {
                    Text(document.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(Notebook.mono(.caption2))
                        .foregroundStyle(Notebook.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Image("ph.caret-right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Notebook.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .ruled()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the document details")
    }

    private var typeLabel: String {
        switch document.fileType {
        case .pdf: "PDF"
        case .image: "Image"
        case .text: "Text"
        case .video: "Video"
        }
    }

    private var formattedSize: String {
        let bytes = document.fileSize
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
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
            NotebookForm {
                Section {
                    if let url = selectedFileURL {
                        HStack {
                            Image(fileType(for: url).iconName)
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.subheadline)
                            Spacer()
                            Button("Change") { showingFilePicker = true }
                                .font(.caption)
                        }
                    } else if selectedPhotoData != nil {
                        HStack {
                            Image("ph.image")
                                .foregroundStyle(.secondary)
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
                                Label("Select File", image: "ph.file-plus")
                            }

                            Divider().frame(height: 20)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("Photo Library", image: "ph.images")
                            }
                        }
                    }
                }

                Section {
                    NotebookField("Title", text: $title)
                    NotebookField("Tags", text: $tags, prompt: "Comma separated")
                }

                Section(header: NotebookFormHeader("Notes")) {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
            }
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
            NotebookForm {
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

                Section(header: NotebookFormHeader("Details")) {
                    NotebookField("Title", text: $document.title)
                    NotebookField("Tags", text: $tagsText, prompt: "Comma separated")
                        .onChange(of: tagsText) {
                            document.tags = tagsText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                }

                Section(header: NotebookFormHeader("Notes")) {
                    TextField("Optional notes", text: $document.notes, axis: .vertical)
                        .lineLimit(3)
                }

                Section(header: NotebookFormHeader("Info")) {
                    LabeledContent("File", value: document.fileName)
                    LabeledContent("Size") {
                        Text(formattedSize)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Added", value: document.uploadedAt, format: .dateTime.month(.abbreviated).day().year())
                }
            }
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
                            preview: SharePreview(document.title, image: Image(document.fileType.iconName))
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
