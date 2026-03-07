import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @State private var currentConversation: Conversation?
    @State private var inputText = ""
    @State private var claudeService = ClaudeService()
    @State private var errorMessage: String?
    @State private var showingHistory = false

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
                .onChange(of: displayMessages.count) {
                    if let last = displayMessages.last {
                        withAnimation(AppAnimation.appear) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 10) {
                TextField("Ask about your health data...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                    .onSubmit { sendMessage() }

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
        }
        .navigationTitle("Chat")
        .toolbar {
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
            sendMessage()
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
        conversation.addMessage(role: .user, content: text)

        // Auto-title from first message
        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(50))
        }

        inputText = ""
        errorMessage = nil

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
