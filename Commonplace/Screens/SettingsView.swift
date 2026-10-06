import SwiftUI

/// How long trashed items are kept before the auto-purge.
enum TrashRetention: String, CaseIterable, Identifiable {
    case thirtyDays
    case ninetyDays
    case never

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .never: "Never"
        }
    }
}

/// Settings. The picker changes local state only in the shell; nothing is persisted.
struct SettingsView: View {
    @State private var retention = TrashRetention.thirtyDays

    var body: some View {
        Form {
            Section {
                Picker("Keep items in Trash", selection: $retention) {
                    ForEach(TrashRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
            }
            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
    }

    /// "1.0 (1)": the marketing version and build number from the app's Info.plist.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info?["CFBundleVersion"] as? String else {
            return version
        }
        return "\(version) (\(build))"
    }
}

#Preview("Light") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
