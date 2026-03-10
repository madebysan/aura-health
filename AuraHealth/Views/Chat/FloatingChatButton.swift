import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FloatingChatButton: View {
    @Binding var isShowingChat: Bool

    #if os(macOS)
    @State private var isHovering = false
    #endif

    var body: some View {
        Button {
            isShowingChat = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        #if os(macOS)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: isHovering ? 12 : 6, y: isHovering ? 4 : 2)
                        #else
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
                        #endif
                )
                #if os(macOS)
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                #endif
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(20)
        .keyboardShortcut("k", modifiers: .command)
        .help("Open Chat (⌘K)")
        #else
        .padding(.trailing, 20)
        .padding(.bottom, 80) // Clear the tab bar
        #endif
    }
}

// MARK: - Floating Chat Panel (macOS)

#if os(macOS)
struct FloatingChatPanel: View {
    @Binding var isShowing: Bool

    init(isShowing: Binding<Bool>) {
        self._isShowing = isShowing
    }

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

    private func ensureConversation() -> Conversation {
        if let current = currentConversation {
            return current
        }
        let conv = Conversation()
        modelContext.insert(conv)
        currentConversation = conv
        return conv
    }

    private var displayMessages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !claudeService.isResponding
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Chat")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Conversation History")

                Button {
                    startNewChat()
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat")

                Button {
                    isShowing = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close Chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if displayMessages.isEmpty {
                            panelEmptyState
                        }
                        ForEach(Array(displayMessages.enumerated()), id: \.element.id) { index, message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if claudeService.isResponding {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .fill(Color.secondary.opacity(0.4))
                                        .frame(width: 5, height: 5)
                                        .offset(y: claudeService.isResponding ? -2 : 0)
                                        .animation(
                                            .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                                            value: claudeService.isResponding
                                        )
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(12)
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

            // Attachment preview
            if let fileURL = attachedFileURL {
                HStack(spacing: 6) {
                    Image(systemName: fileURL.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text(fileURL.lastPathComponent)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        attachedFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.03))
            }

            // Input
            HStack(spacing: 8) {
                Button { showingFilePicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach file")

                TextField("Ask about your health...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .onSubmit { sendMessage() }
                    .font(.subheadline)

                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 480)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(20)
        .keyboardShortcut("k", modifiers: .command)
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .png, .jpeg, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                attachedFileURL = url
            }
        }
    }

    private var panelEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.4))

            Text("Health Assistant")
                .font(.subheadline.weight(.medium))
            Text("Ask questions or log measurements.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                panelSuggestion("What biomarkers are out of range?")
                panelSuggestion("How are my vitals this week?")
            }
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
    }

    private func panelSuggestion(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func startNewChat() {
        currentConversation = nil
        inputText = ""
        errorMessage = nil
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !claudeService.isResponding else { return }

        let conversation = ensureConversation()
        let displayText = attachedFileURL != nil
            ? "\(text)\n📎 \(attachedFileURL!.lastPathComponent)"
            : text
        conversation.addMessage(role: .user, content: displayText)

        if conversation.title == "New Chat" {
            conversation.title = String(text.prefix(50))
        }

        claudeService.pendingFileURL = attachedFileURL

        inputText = ""
        attachedFileURL = nil
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
#endif
