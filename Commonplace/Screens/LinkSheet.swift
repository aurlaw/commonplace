import SwiftUI
import UIKit

/// The composer's Link sheet: a URL and the link's text, inserted as `[text](url)`.
///
/// The text starts as the selection. With nothing selected it is filled with the page's title
/// once a URL is entered, unless it has been typed in; offline it stays empty and the URL is
/// used. A clipboard URL is offered through `PasteButton`, which pastes without the system's
/// paste permission prompt.
struct LinkSheet: View {
    let selectedText: String
    let onInsert: (String, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkMetadataService) private var linkMetadataService
    @State private var urlText = ""
    @State private var text = ""
    /// Typed into by hand: the page title no longer replaces it.
    @State private var hasEditedText = false
    @State private var isFetchingTitle = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case url
        case text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $urlText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                    if UIPasteboard.general.hasURLs {
                        PasteButton(payloadType: URL.self) { urls in
                            if let url = urls.first {
                                urlText = url.absoluteString
                            }
                        }
                    }
                }
                Section {
                    TextField("Text", text: textBinding)
                        .focused($focusedField, equals: .text)
                } footer: {
                    if isFetchingTitle {
                        Text("Getting the page title…")
                    } else if selectedText.isEmpty {
                        Text("Leave empty to show the URL.")
                    }
                }
            }
            .navigationTitle("Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let url = LinkInput.url(from: urlText) {
                            onInsert(text, url)
                            dismiss()
                        }
                    }
                    .disabled(LinkInput.url(from: urlText) == nil)
                }
            }
            .task(id: urlText) {
                await fillTitle()
            }
            .onAppear {
                text = selectedText
                hasEditedText = !selectedText.isEmpty
                focusedField = .url
            }
        }
        .presentationDetents([.medium])
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: {
                text = $0
                hasEditedText = true
            }
        )
    }

    /// Debounced: the title is looked up once typing pauses.
    private func fillTitle() async {
        guard !hasEditedText, let url = LinkInput.url(from: urlText),
            url.scheme?.lowercased().hasPrefix("http") == true
        else {
            return
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else {
            return
        }
        isFetchingTitle = true
        let title = await linkMetadataService.title(for: url)
        isFetchingTitle = false
        if !Task.isCancelled, !hasEditedText, let title {
            text = title
        }
    }
}

/// Turns what was typed into the URL field into a link destination.
nonisolated enum LinkInput {
    /// `http`, `https`, or `mailto`; a bare host gets `https://`. `nil` for anything else.
    static func url(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            return nil
        }
        let candidate = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate), MarkdownBody.isAllowed(url) else {
            return nil
        }
        if url.scheme?.lowercased() != "mailto", url.host()?.contains(".") != true {
            return nil
        }
        return url
    }
}

#Preview("Link") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            LinkSheet(selectedText: "") { _, _ in }
        }
        .sampleData()
}
