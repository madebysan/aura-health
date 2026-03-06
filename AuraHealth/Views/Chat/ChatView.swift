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

    private var activeConversation: Conversation {
        if let current = currentConversation {
            return current
        }
        let conv = Conversation()
        modelContext.insert(conv)
        currentConversation = conv
        return conv
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
                        if activeConversation.messages.isEmpty {
                            chatEmptyState
                        }
                        ForEach(Array(activeConversation.messages.enumerated()), id: \.element.id) { index, message in
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
                .onChange(of: activeConversation.messages.count) {
                    if let last = activeConversation.messages.last {
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
                    currentConversation = nil
                    inputText = ""
                    errorMessage = nil
                } label: {
                    Image(systemName: "plus.bubble")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            currentConversation = nil
            inputText = ""
            errorMessage = nil
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !claudeService.isResponding
    }

    // MARK: - API Key Banner

    private var apiKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text("Add your Claude API key in Settings to enable AI chat")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.08))
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)

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
                suggestionChip("How's my sleep trend this week?")
                suggestionChip("What biomarkers are out of range?")
                suggestionChip("Summarize my health data")
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 60)
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
        guard !text.isEmpty else { return }

        activeConversation.addMessage(role: .user, content: text)
        inputText = ""
        errorMessage = nil

        Task {
            if claudeService.hasAPIKey {
                do {
                    let context = ClaudeService.buildContext(from: modelContext)
                    let response = try await claudeService.sendMessage(
                        text,
                        conversationHistory: activeConversation.messages,
                        healthContext: context
                    )
                    activeConversation.addMessage(role: .assistant, content: response)
                } catch {
                    errorMessage = error.localizedDescription
                    activeConversation.addMessage(role: .assistant, content: "Sorry, I couldn't process that. \(error.localizedDescription)")
                }
            } else {
                // Fallback without API key
                try? await Task.sleep(for: .seconds(0.5))
                activeConversation.addMessage(
                    role: .assistant,
                    content: "To enable AI responses, add your Claude API key in Settings > Integrations > Claude API."
                )
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
                Text(message.content)
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
