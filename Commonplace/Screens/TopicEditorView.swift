import SwiftData
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

/// The editor's working copy, written to the store only on Create / Save.
struct TopicDraft: Equatable {
    var title = ""
    var summary = ""
    var color = TopicColor.defaultColor
    /// Whether new entries in the topic capture location by default.
    var capturesLocation = false

    init(
        title: String = "",
        summary: String = "",
        color: TopicColor = .defaultColor,
        capturesLocation: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.color = color
        self.capturesLocation = capturesLocation
    }

    init(mode: TopicEditorMode) {
        if case .edit(let topic) = mode {
            title = topic.title
            summary = topic.summary
            color = topic.color
            capturesLocation = topic.capturesLocation
        }
    }

    /// The draft as it would be stored: title and summary without surrounding whitespace.
    var trimmed: TopicDraft {
        TopicDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color,
            capturesLocation: capturesLocation
        )
    }

    /// A topic needs a title; duplicates are allowed.
    var isValid: Bool {
        !trimmed.title.isEmpty
    }

    /// Whether saving would store something different from `original`.
    func isDirty(comparedTo original: TopicDraft) -> Bool {
        trimmed != original.trimmed
    }

    /// A new, uninserted topic holding the trimmed values.
    func makeTopic() -> Topic {
        let values = trimmed
        let topic = Topic(title: values.title, summary: values.summary, color: values.color)
        topic.capturesLocation = values.capturesLocation
        return topic
    }

    /// Writes the trimmed values to an existing topic.
    func apply(to topic: Topic) {
        let values = trimmed
        topic.title = values.title
        topic.summary = values.summary
        topic.color = values.color
        topic.capturesLocation = values.capturesLocation
    }
}

/// New / Edit Topic sheet. Create inserts a topic; Save writes back to the edited one.
struct TopicEditorView: View {
    let mode: TopicEditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draft: TopicDraft
    @State private var isConfirmingDiscard = false
    @State private var saveError: String?
    @FocusState private var isTitleFocused: Bool

    /// What the sheet opened with, for detecting unsaved changes.
    private let original: TopicDraft

    /// - Parameter draft: Overrides the draft derived from `mode`; previews use it to show a
    ///   specific state.
    init(mode: TopicEditorMode, draft: TopicDraft? = nil) {
        self.mode = mode
        original = TopicDraft(mode: mode)
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
                Section {
                    // Only a preference: permission is asked when an entry first needs it.
                    Toggle("Capture location by default", isOn: $draft.capturesLocation)
                } footer: {
                    Text(
                        "New entries in this topic will include where you wrote them. "
                            + "You can turn it off for any entry."
                    )
                }
            }
            .navigationTitle(isEditing ? "Edit Topic" : "New Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog(
                        "Discard changes?",
                        isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) {
                            dismiss()
                        }
                        Button("Keep Editing", role: .cancel) {}
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        save()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!draft.isValid)
                }
            }
        }
        // With unsaved changes, swipe-down is blocked so Cancel's confirmation is the way out.
        .interactiveDismissDisabled(isDirty)
        .saveErrorAlert($saveError)
        .onAppear {
            isTitleFocused = true
        }
    }

    private var isDirty: Bool {
        draft.isDirty(comparedTo: original)
    }

    /// Dismisses on success. On failure the sheet stays open with the draft intact.
    private func save() {
        switch mode {
        case .new:
            modelContext.insert(draft.makeTopic())
        case .edit(let topic):
            draft.apply(to: topic)
        }
        saveError = modelContext.saveOrRollback()
        if saveError == nil {
            dismiss()
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
