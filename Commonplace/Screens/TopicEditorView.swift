import SwiftUI

enum TopicEditorMode: Identifiable {
    case new
    case edit(Topic)

    var id: String {
        switch self {
        case .new: "new"
        case .edit: "edit"
        }
    }
}

/// The editor's working copy. Nothing in it is written back to the store in the shell.
struct TopicDraft {
    var title = ""
    var summary = ""
    var color = TopicColor.defaultColor

    init(title: String = "", summary: String = "", color: TopicColor = .defaultColor) {
        self.title = title
        self.summary = summary
        self.color = color
    }

    init(mode: TopicEditorMode) {
        if case .edit(let topic) = mode {
            title = topic.title
            summary = topic.summary
            color = topic.color
        }
    }
}

/// New / Edit Topic sheet. Visual only: Cancel and Create / Save both just dismiss.
struct TopicEditorView: View {
    let mode: TopicEditorMode

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TopicDraft
    @FocusState private var isTitleFocused: Bool

    /// - Parameter draft: Overrides the draft derived from `mode`; previews use it to show a
    ///   specific state.
    init(mode: TopicEditorMode, draft: TopicDraft? = nil) {
        self.mode = mode
        _draft = State(initialValue: draft ?? TopicDraft(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .focused($isTitleFocused)
                    TextField("Description (optional)", text: $draft.summary, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                }
                Section {
                    swatches
                } header: {
                    Text("Color")
                        .textCase(nil)
                }
            }
            .navigationTitle(isEditing ? "Edit Topic" : "New Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .onAppear {
            isTitleFocused = true
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// The eight swatches on one row; the selected one is ringed.
    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(TopicColor.allCases, id: \.self) { color in
                Button {
                    draft.color = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if color == draft.color {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(4.5)
                        .overlay {
                            Circle()
                                .strokeBorder(color.color, lineWidth: 2)
                                .opacity(color == draft.color ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(color == draft.color ? .isSelected : [])
            }
        }
    }
}

#Preview("New") {
    TopicEditorPreview(mode: .new, draft: TopicDraft(title: "Reading notes", color: .teal))
}

#Preview("New · Dark") {
    TopicEditorPreview(mode: .new, draft: TopicDraft(title: "Reading notes", color: .teal))
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    TopicEditorPreview(mode: PreviewContainer.topic("Sedona trip").map { .edit($0) } ?? .new)
}

private struct TopicEditorPreview: View {
    let mode: TopicEditorMode
    var draft: TopicDraft?

    var body: some View {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                TopicEditorView(mode: mode, draft: draft)
            }
            .sampleData()
    }
}
