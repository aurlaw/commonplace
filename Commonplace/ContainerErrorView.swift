import SwiftUI

/// Shown instead of the app when the model container can't be created.
struct ContainerErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Couldn't open your journal",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

#Preview {
    ContainerErrorView(message: "The store could not be loaded.")
}
