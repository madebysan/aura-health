import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VaultView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \VaultDocument.uploadedAt, order: .reverse)
    private var documents: [VaultDocument]

    @State private var isUnlocked = false
    @State private var passwordInput = ""
    @State private var showingSetup = false
    @State private var showingUpload = false
    @State private var selectedDocument: VaultDocument?
    @State private var errorMessage = ""
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        Group {
            if !KeychainService.hasVaultPassword {
                setupPrompt
            } else if !isUnlocked {
                passwordGate
            } else {
                vaultContent
            }
        }
        .navigationTitle("Vault")
        .sheet(isPresented: $showingSetup) {
            VaultSetupSheet(isUnlocked: $isUnlocked)
        }
    }

    // MARK: - Setup

    private var setupPrompt: some View {
        EmptyStateView(
            icon: "lock.shield.fill",
            title: "Secure Vault",
            message: "Set a master password to protect your sensitive health documents.",
            actionLabel: "Set Up Vault",
            action: { showingSetup = true }
        )
    }

    // MARK: - Password Gate

    private var passwordGate: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Vault Locked")
                    .font(.title3.weight(.medium))
                Text("Enter your master password")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 8) {
                SecureField("Master Password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { unlock() }
                    .offset(x: shakeOffset)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppColors.statusRed)
                }
            }

            Button("Unlock") { unlock() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(passwordInput.isEmpty)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func unlock() {
        if KeychainService.verifyVaultPassword(passwordInput) {
            withAnimation(AppAnimation.expand) {
                isUnlocked = true
            }
            errorMessage = ""
        } else {
            errorMessage = "Incorrect password"
            passwordInput = ""
            // Shake animation
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                shakeOffset = -10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                    shakeOffset = 10
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                    shakeOffset = 0
                }
            }
        }
    }

    // MARK: - Content

    private var vaultContent: some View {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280))], spacing: 12) {
                    ForEach(Array(documents.enumerated()), id: \.element.id) { index, doc in
                        DocumentCard(document: doc)
                            .onTapGesture { selectedDocument = doc }
                            .staggeredAppearance(index: index)
                    }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUpload = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(AppAnimation.collapse) {
                        isUnlocked = false
                        passwordInput = ""
                    }
                } label: {
                    Image(systemName: "lock.fill")
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

// MARK: - Vault Setup

struct VaultSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isUnlocked: Bool

    @State private var password = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirm)
                }
                if !error.isEmpty {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Set Vault Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(password.isEmpty || confirm.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 200)
        #endif
    }

    private func save() {
        guard password == confirm else { error = "Passwords don't match"; return }
        guard password.count >= 4 else { error = "Minimum 4 characters"; return }
        if KeychainService.saveVaultPassword(password) {
            isUnlocked = true
            dismiss()
        } else {
            error = "Failed to save password"
        }
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
                    } else {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Select File", systemImage: "doc.badge.plus")
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
            .navigationTitle("Upload Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedFileURL == nil || title.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.pdf, .image, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    selectedFileURL = url
                    if title.isEmpty {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private func save() {
        guard let url = selectedFileURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try? Data(contentsOf: url)
        let size = data?.count ?? 0
        let type = fileType(for: url)
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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
    let document: VaultDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: document.fileType.iconName)
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 4) {
                        Text(document.title)
                            .font(.title3.weight(.medium))
                        Text(document.fileName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !document.notes.isEmpty {
                        Text(document.notes)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                    }
                }
                .padding()
            }
            .navigationTitle("Document")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }
}
