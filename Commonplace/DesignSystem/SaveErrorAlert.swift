import SwiftUI

extension View {
    /// Shows a failed save. `message` is the text from `ModelContext.saveOrRollback()`.
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn’t Save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        message.wrappedValue = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension View {
    /// The confirmation every permanent delete of an entry goes through. `entry` is the one
    /// waiting to be deleted; `delete` runs when the user confirms.
    func deleteEntryAlert(_ entry: Binding<Entry?>, delete: @escaping (Entry) -> Void) -> some View
    {
        alert(
            "Delete This Entry?",
            isPresented: Binding(
                get: { entry.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        entry.wrappedValue = nil
                    }
                }
            ),
            presenting: entry.wrappedValue
        ) { pending in
            Button("Delete", role: .destructive) {
                delete(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This entry and its photos will be deleted. This can’t be undone.")
        }
    }
}
