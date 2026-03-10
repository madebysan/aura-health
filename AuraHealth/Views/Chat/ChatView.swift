import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @State private var currentConversation: Conversation?
    @State private var inputText = ""
    @State private var claudeService = ClaudeService()
    @State private var errorMessage: String?
    @State private var showingHistory = false
    @State private var showingFilePicker = false
    @State private var attachedFileURL: URL?
    @FocusState private var isInputFocused: Bool
    @State private var showingAPIKeyPrompt = false
    @State private var apiKeyInput = ""

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
        VStack(spacing: 0) {
            if !claudeService.hasAPIKey {
                apiKeyBanner
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if displayMessages.isEmpty {
                            chatEmptyState
                        }
                        ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
                            ChatBubble(message: message)
                                .id(message.id)
                                .staggeredAppearance(index: index)
                        }
                        if claudeService.isResponding {
                            typingIndicator
                        }
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                #if os(iOS)
                // Dismiss keyboard by dragging down on the message list
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

            Divider()

            // Attachment preview
            if let fileURL = attachedFileURL {
                HStack(spacing: 8) {
                    Image(systemName: fileURL.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        attachedFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))
            }

            // Input
            HStack(spacing: 10) {
                Button { showingFilePicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach file")
                .disabled(!claudeService.hasAPIKey)

                if claudeService.hasAPIKey {
                    TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                        .onSubmit { sendMessage() }
                } else {
                    Button {
                        showingAPIKeyPrompt = true
                    } label: {
                        Text("Add API key to start chatting...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            canSend ? Color.accentColor : Color.secondary.opacity(0.3)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            #if os(iOS)
            // Keep the input bar above the home indicator and above the keyboard
            .padding(.bottom, 4)
            .background(.bar)
            #endif
        }
        .navigationTitle("Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                    Image(systemName: "plus.bubble")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
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
        .alert("Claude API Key", isPresented: $showingAPIKeyPrompt) {
            SecureField("sk-ant-...", text: $apiKeyInput)
            Button("Save") {
                if !apiKeyInput.isEmpty {
                    KeychainService.setValue(apiKeyInput, for: "claude-api-key")
                    apiKeyInput = ""
                }
            }
            Button("Cancel", role: .cancel) {
                apiKeyInput = ""
            }
        } message: {
            Text("Enter your Claude API key to enable AI health chat.")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                attachedFileURL = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            startNewChat()
        }
    }

    private func startNewChat() {
        currentConversation = nil
        inputText = ""
        errorMessage = nil
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !claudeService.isResponding
    }

    // MARK: - API Key Banner

    private var apiKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
            Text("Add your Claude API key in Settings to enable AI chat")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 4) {
                Text("Health Assistant")
                    .font(.title3.weight(.medium))
                Text("Ask questions, log measurements, or get health insights.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            VStack(spacing: 8) {
                suggestionChip("What biomarkers are out of range?")
                suggestionChip("How are my vitals this week?")
                suggestionChip("Log my weight at 175 lbs")
            }
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .offset(y: claudeService.isResponding ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: claudeService.isResponding
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !claudeService.isResponding else { return }

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
        claudeService.pendingFileURL = attachedFileURL

        // Auto-save attachment to Vault
        if let fileURL = attachedFileURL {
            saveToVault(url: fileURL)
        }

        inputText = ""
        attachedFileURL = nil
        errorMessage = nil
        isInputFocused = true

        Task {
            if claudeService.hasAPIKey {
                do {
                    let response = try await claudeService.sendMessage(
                        conversationHistory: conversation.messages,
                        context: modelContext
                    )
                    conversation.addMessage(role: .assistant, content: response)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = "Add your Claude API key in Settings to enable AI chat."
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

struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.1), in: Circle())
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isUser ? Color.accentColor : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .foregroundStyle(isUser ? .white : .primary)

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
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
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(.tertiary)
                        Text("No conversations yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedConversations, id: \.0) { group, convos in
                            Section(group) {
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
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
                        Image(systemName: "plus.bubble")
                    }
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
        HStack(spacing: 12) {
            // Icon
            Image(systemName: isActive ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    (isActive ? Color.accentColor : Color.secondary).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(messageCount) msgs")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
