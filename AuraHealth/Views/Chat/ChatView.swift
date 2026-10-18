import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
#if os(macOS)
import AppKit
#endif

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var prefillMessage: String?

    init(prefillMessage: Binding<String?> = .constant(nil)) {
        self._prefillMessage = prefillMessage
    }

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var allConversations: [Conversation]

    /// Limit to most recent 50 conversations for display performance
    private var conversations: [Conversation] {
        Array(allConversations.prefix(50))
    }

    @State private var currentConversation: Conversation?
    @State private var inputText = ""
    @State private var aiService = AIService()
    @State private var errorMessage: String?
    @State private var showingHistory = false
    @State private var showingFilePicker = false
    @State private var attachedFileURL: URL?
    @State private var attachedFromPhotoPicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingPhotoData: Data?
    /// The attached photo's bytes, kept until sent so "Save to Vault" can store them.
    @State private var attachedPhotoData: Data?
    @State private var attachedPhotoSaved = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Returns existing conversation or creates one on demand (only called when sending)
    private func ensureConversation() -> Conversation {
        if let current = currentConversation {
            return current
        }
        let conv = Conversation()
        modelContext.insert(conv)
        currentConversation = conv
        return conv
    }

    /// For read-only access (message display) — returns current or empty
    private var displayMessages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !aiService.isReady {
                        apiKeyBanner
                    }
                    if displayMessages.isEmpty {
                        chatEmptyState
                    }
                    ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
                        ChatBubble(message: message)
                            .id(message.id)
                            .staggeredAppearance(index: index)
                    }
                    if aiService.isResponding {
                        typingIndicator
                    }
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: displayMessages.count) {
                if let last = displayMessages.last {
                    withAnimation(AppAnimation.appear) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        #else
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                inputBar
            }
        }
        #endif
        .notebookBackground()
        .navigationTitle("Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aura", let host = url.host,
                  let section = AppSection(rawValue: host) else { return .systemAction }
            NotificationCenter.default.post(name: .navigateTo, object: section)
            // Deep-link to a specific metric: aura://vitals/hrv
            if let metricRaw = url.pathComponents.first(where: { $0 != "/" }),
               let metric = MetricType(rawValue: metricRaw) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openMetricDetail, object: metric)
                }
            }
            return .handled
        })
        .toolbar {
            #if os(iOS)
            if isInputFocused {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startNewChat()
                } label: {
                    Image("ph.chat-centered-dots")
                }
                .accessibilityLabel("New Conversation")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingHistory = true
                } label: {
                    Image("ph.clock-counter-clockwise")
                }
                .accessibilityLabel("Conversation History")
            }
        }
        .sheet(isPresented: $showingHistory) {
            ConversationHistorySheet(
                conversations: conversations,
                currentConversation: currentConversation,
                onSelect: { conversation in
                    currentConversation = conversation
                    showingHistory = false
                },
                onDelete: { conversation in
                    if conversation.id == currentConversation?.id {
                        currentConversation = nil
                    }
                    modelContext.delete(conversation)
                },
                onNewChat: {
                    startNewChat()
                    showingHistory = false
                }
            )
        }
        .confirmationDialog(
            "Allow AI to change Aura data?",
            isPresented: Binding(
                get: { aiService.pendingToolApproval != nil },
                set: { isPresented in
                    if !isPresented, aiService.pendingToolApproval != nil {
                        aiService.denyPendingTool()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if aiService.pendingToolApproval?.isDestructive == true {
                Button("Allow Delete", role: .destructive) {
                    aiService.approvePendingTool()
                }
            } else {
                Button("Allow Change") {
                    aiService.approvePendingTool()
                }
            }
            Button("Don't Allow", role: .cancel) {
                aiService.denyPendingTool()
            }
        } message: {
            Text(aiService.pendingToolApproval?.summary ?? "Review this change before allowing it.")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                attachedFromPhotoPicker = false
                attachedFileURL = url
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let jpegData = jpegData(from: data) {
                    pendingPhotoData = jpegData
                    attachPhoto()
                }
                selectedPhotoItem = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            startNewChat()
        }
        .onChange(of: prefillMessage) {
            if let message = prefillMessage, !message.isEmpty {
                inputText = message
                prefillMessage = nil
                // Auto-submit: send immediately so the user gets a summary right away
                sendMessage()
            }
        }
        .onDisappear {
            aiService.denyPendingTool()
        }
    }

    private func startNewChat() {
        currentConversation = nil
        inputText = ""
        errorMessage = nil
    }

    /// Photos attach straight away; saving one to the Vault is a separate tap on the attachment.
    private func attachPhoto() {
        guard let data = pendingPhotoData else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard (try? data.write(to: tempURL)) != nil else { return }

        attachedFromPhotoPicker = true
        attachedFileURL = tempURL
        attachedPhotoData = data
        attachedPhotoSaved = false
        pendingPhotoData = nil
    }

    private func savePhotoToVault() {
        guard let data = attachedPhotoData, let tempURL = attachedFileURL else { return }
        do {
            let conversationTitle = currentConversation?.title
            let photoTitle: String
            if let title = conversationTitle, title != "New Chat" {
                photoTitle = "Photo – \(title)"
            } else {
                photoTitle = "Photo \(Date().formatted(.dateTime.month().day().year().hour().minute()))"
            }
            let doc = VaultDocument(
                title: photoTitle,
                fileName: tempURL.lastPathComponent,
                fileType: .image,
                mimeType: "image/jpeg",
                fileData: data,
                fileSize: data.count,
                tags: ["chat-attachment", "photo"],
                notes: "Attached via Chat"
            )
            modelContext.insert(doc)
        }
        attachedPhotoSaved = true
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isResponding
    }

    private func errorBanner(_ message: String) -> some View {
        NoteLine(text: message, tag: "Error")
    }

    private func jpegData(from data: Data) -> Data? {
        #if os(iOS)
        UIImage(data: data)?.jpegData(compressionQuality: 0.85)
        #elseif os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        return nil
        #endif
    }

    // MARK: - API Key Banner

    /// The one "AI is off" message; it opens Settings.
    private var apiKeyBanner: some View {
        Button {
            NotificationCenter.default.post(name: .navigateTo, object: AppSection.settings)
        } label: {
            HStack {
                Text("Set up AI to start chatting")
                    .font(.subheadline)
                    .foregroundStyle(Notebook.ink)
                Spacer()
                Text("Settings")
                    .font(Notebook.mono(.caption))
                    .foregroundStyle(Notebook.inkSecondary)
                Image("ph.caret-right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Notebook.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Settings")
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recent threads, so past conversations are one tap away
            let recent = conversations.filter { !$0.messages.isEmpty }.prefix(3)
            if !recent.isEmpty {
                NotebookSectionHeader(title: "Recent", trailing: "\(conversations.filter { !$0.messages.isEmpty }.count)")
                ForEach(Array(recent)) { conversation in
                    recentRow(conversation)
                }
            }

            NotebookSectionHeader(title: "Try asking")

            suggestionRow("What biomarkers are out of range?")
            suggestionRow("How are my vitals this week?")
            suggestionRow("Log my weight at 175 lbs")

            Text("Aura provides educational information, not diagnosis or medical advice.")
                .font(.footnote)
                .foregroundStyle(Notebook.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentRow(_ conversation: Conversation) -> some View {
        Button {
            currentConversation = conversation
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Notebook.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(conversation.messages.count) messages · \(conversation.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(Notebook.mono(.caption))
                        .foregroundStyle(Notebook.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("ph.caret-right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Notebook.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this conversation")
    }

    private func suggestionRow(_ text: String) -> some View {
        Button {
            inputText = text
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Notebook.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image("ph.arrow-down-left")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Notebook.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .ruled()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Puts this question in the message field")
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Attachment preview
            if let fileURL = attachedFileURL {
                HStack(spacing: 10) {
                    Text("Attached").kicker()
                    Text(fileURL.lastPathComponent)
                        .font(Notebook.mono(.caption))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Notebook.ink)
                    Spacer(minLength: 4)
                    if attachedFromPhotoPicker {
                        if attachedPhotoSaved {
                            Text("In Vault")
                                .font(Notebook.mono(.caption))
                                .foregroundStyle(Notebook.inkSecondary)
                        } else {
                            Button("Save to Vault") { savePhotoToVault() }
                                .font(Notebook.mono(.caption))
                                .underline()
                                .foregroundStyle(Notebook.inkSecondary)
                                .buttonStyle(.plain)
                                .frame(minHeight: 44)
                        }
                    }
                    Button {
                        attachedFileURL = nil
                        attachedPhotoData = nil
                    } label: {
                        Image("ph.x")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Notebook.inkSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove Attachment")
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .ruled()
            }

            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Photo Library", image: "ph.image")
                    }
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Files", image: "ph.file-text")
                    }
                } label: {
                    Image("ph.paperclip")
                        .font(.body.weight(.medium))
                        .foregroundStyle(aiService.isReady ? Notebook.ink : Notebook.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .disabled(!aiService.isReady)
                .accessibilityLabel("Attach File")

                Group {
                    if aiService.isReady {
                        TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                            .focused($isInputFocused)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Notebook.ink)
                            .lineLimit(1...4)
                    } else {
                        Text("Ask about your health data...")
                            .foregroundStyle(Notebook.inkTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHint("Set up AI in Settings first")
                    }
                }
                .font(.body)
                // The composer stays usable at the largest sizes; messages scale fully
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Notebook.paperRaised, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Notebook.rule, lineWidth: 1))

                Button { sendMessage() } label: {
                    Image("ph.arrow-up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Notebook.paper)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Notebook.ink : Notebook.emptyBox, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .disabled(!canSend)
                .accessibilityLabel("Send Message")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Notebook.paper)
        .ruled(.top)
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Aura").kicker()
            if reduceMotion {
                Text("writing…").kicker()
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Notebook.inkSecondary)
                            .frame(width: 5, height: 5)
                            .offset(y: aiService.isResponding ? -2 : 0)
                            .animation(
                                .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                                value: aiService.isResponding
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aura is writing a reply")
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !aiService.isResponding else { return }

        let conversation = ensureConversation()
        let displayText = attachedFileURL != nil
            ? "\(text)\n📎 \(attachedFileURL!.lastPathComponent)"
            : text
        conversation.addMessage(role: .user, content: displayText)

        // Auto-title from first message
        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(50))
        }

        // Pass file to service before clearing
        aiService.pendingFileURL = attachedFileURL

        // Files save to the Vault on send; photos only when "Save to Vault" was tapped
        if let fileURL = attachedFileURL, !attachedFromPhotoPicker {
            saveToVault(url: fileURL)
        }

        inputText = ""
        attachedFileURL = nil
        attachedFromPhotoPicker = false
        attachedPhotoData = nil
        attachedPhotoSaved = false
        errorMessage = nil

        aiService.isResponding = true
        Task {
            defer { aiService.isResponding = false }
            guard aiService.isReady else {
                errorMessage = "Finish AI provider setup and consent in Settings before chatting."
                return
            }
            do {
                let response = try await aiService.sendMessage(
                    conversationHistory: conversation.messages,
                    context: modelContext
                )
                conversation.addMessage(role: .assistant, content: response)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Save to Vault

    private func saveToVault(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return }

        let ext = url.pathExtension.lowercased()
        let fileType: VaultFileType = switch ext {
        case "pdf": .pdf
        case "jpg", "jpeg", "png", "heic", "gif", "webp": .image
        case "txt", "md", "csv", "rtf": .text
        case "mp4", "mov", "m4v": .video
        default: .text
        }

        let mimeType: String = switch ext {
        case "pdf": "application/pdf"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "txt": "text/plain"
        default: "application/octet-stream"
        }

        var tags = ["chat-attachment"]
        if fileType == .pdf { tags.append("lab-report") }

        let doc = VaultDocument(
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            fileType: fileType,
            mimeType: mimeType,
            fileData: data,
            fileSize: data.count,
            tags: tags,
            notes: "Attached via Chat"
        )
        modelContext.insert(doc)
    }
}

// MARK: - Chat Bubble

/// One entry in the transcript. Aura's replies read as plain prose on the
/// page; your own messages sit on raised paper, aligned right.
struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            Text("\(isUser ? "You" : "Aura") · \(message.timestamp.formatted(.dateTime.hour().minute()))")
                .kicker()

            Group {
                if isUser {
                    Text(message.content)
                } else if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attributed)
                } else {
                    Text(message.content)
                }
            }
            .font(.body)
            .lineSpacing(3)
            .foregroundStyle(Notebook.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, isUser ? 14 : 0)
            .padding(.vertical, isUser ? 10 : 0)
            .background {
                if isUser {
                    RoundedRectangle(cornerRadius: 16).fill(Notebook.paperRaised)
                    RoundedRectangle(cornerRadius: 16).stroke(Notebook.rule, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.leading, isUser ? 48 : 0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Conversation History Sheet

struct ConversationHistorySheet: View {
    let conversations: [Conversation]
    let currentConversation: Conversation?
    let onSelect: (Conversation) -> Void
    let onDelete: (Conversation) -> Void
    let onNewChat: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var nonEmptyConversations: [Conversation] {
        conversations.filter { !$0.messages.isEmpty }
    }

    private var groupedConversations: [(String, [Conversation])] {
        let calendar = Calendar.current
        let now = Date()

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var thisMonth: [Conversation] = []
        var older: [Conversation] = []

        for conv in nonEmptyConversations {
            if calendar.isDateInToday(conv.updatedAt) {
                today.append(conv)
            } else if calendar.isDateInYesterday(conv.updatedAt) {
                yesterday.append(conv)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), conv.updatedAt >= weekAgo {
                thisWeek.append(conv)
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now), conv.updatedAt >= monthAgo {
                thisMonth.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [(String, [Conversation])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !thisMonth.isEmpty { groups.append(("This Month", thisMonth)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    var body: some View {
        NavigationStack {
            Group {
                if nonEmptyConversations.isEmpty {
                    VStack(spacing: 12) {
                        Image("ph.chats")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(Notebook.inkTertiary)
                            .accessibilityHidden(true)
                        Text("No conversations yet")
                            .font(.subheadline)
                            .foregroundStyle(Notebook.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedConversations, id: \.0) { group, convos in
                            Section {
                                ForEach(convos) { conversation in
                                    ConversationRow(
                                        conversation: conversation,
                                        isActive: conversation.id == currentConversation?.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelect(conversation)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onDelete(conversation)
                                        } label: {
                                            Label("Delete", image: "ph.trash")
                                        }
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(Notebook.rule)
                                }
                            } header: {
                                Text(group).kicker()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Notebook.paperRaised.ignoresSafeArea())
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onNewChat()
                    } label: {
                        Image("ph.chat-centered-dots")
                    }
                    .accessibilityLabel("New Conversation")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 480, minHeight: 400, idealHeight: 540)
        #endif
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let isActive: Bool

    private var messageCount: Int {
        conversation.messages.count
    }

    private var preview: String {
        if let lastMessage = conversation.messages.last {
            return String(lastMessage.content.prefix(80))
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(Notebook.ink)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !preview.isEmpty {
                Text(preview)
                    .font(.footnote)
                    .foregroundStyle(Notebook.inkSecondary)
                    .lineLimit(2)
            }

            Text("\(conversation.updatedAt.formatted(.dateTime.month(.abbreviated).day())) · \(messageCount) msgs" + (isActive ? " · open now" : ""))
                .font(Notebook.mono(.caption2, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Notebook.ink : Notebook.inkSecondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
