import SwiftUI

struct FloatingChatButton: View {
    @Binding var isShowingChat: Bool

    @State private var isHovering = false

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
                        .shadow(color: Color.accentColor.opacity(0.3), radius: isHovering ? 12 : 6, y: isHovering ? 4 : 2)
                )
                .scaleEffect(isHovering ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(20)
        .keyboardShortcut("k", modifiers: .command)
        .help("Open Chat (⌘K)")
    }
}
