import SwiftUI

extension View {
    /// A short, non-blocking confirmation ("Moved to Dolly Sods") near the bottom of the screen.
    /// It is announced to VoiceOver and clears itself after a moment.
    func transientMessage(_ message: Binding<String?>) -> some View {
        modifier(TransientMessage(message: message))
    }
}

private struct TransientMessage: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .animation(.default, value: message)
            .task(id: message) {
                guard let message else {
                    return
                }
                AccessibilityNotification.Announcement(message).post()
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled {
                    self.message = nil
                }
            }
    }
}

/// The Move to… submenu for an entry: live destinations other than its topic, with archived
/// topics in their own section.
struct MoveToMenu: View {
    let destinations: TopicDestinations
    let move: (Topic) -> Void

    var body: some View {
        Menu("Move to…", systemImage: "folder") {
            ForEach(destinations.active) { topic in
                button(for: topic)
            }
            if !destinations.archived.isEmpty {
                Section("Archived") {
                    ForEach(destinations.archived) { topic in
                        button(for: topic)
                    }
                }
            }
        }
        .disabled(destinations.isEmpty)
    }

    private func button(for topic: Topic) -> some View {
        Button {
            move(topic)
        } label: {
            Label {
                Text(topic.title)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(topic.tint)
            }
        }
        .accessibilityLabel("Move to \(topic.title)")
    }
}
