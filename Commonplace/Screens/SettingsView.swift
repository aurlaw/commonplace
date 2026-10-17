import SwiftData
import SwiftUI

/// Settings: the app lock, how long Trash keeps items, and the app version.
struct SettingsView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.modelContext) private var modelContext
    @Environment(\.referenceDate) private var referenceDate
    /// A per-device preference, not synced. Stored by raw value.
    @AppStorage(TrashRetention.storageKey) private var storedRetention =
        TrashRetention.defaultValue.rawValue
    /// A shorter retention waiting for confirmation, because applying it deletes items now.
    @State private var pendingRetention: TrashRetention?
    @State private var saveError: String?

    var body: some View {
        Form {
            lockSection
            Section {
                Picker("Keep items in Trash", selection: retentionBinding) {
                    ForEach(TrashRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
            } footer: {
                Text(
                    "Applies on this iPhone. Older items are deleted the next time "
                        + "Commonplace opens."
                )
            }
            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .alert(
            pendingPurgeTitle,
            isPresented: Binding(
                get: { pendingRetention != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRetention = nil
                    }
                }
            ),
            presenting: pendingRetention
        ) { retention in
            Button("Delete", role: .destructive) {
                storedRetention = retention.rawValue
                saveError = trash.purge(retention: retention)
            }
            // Cancel keeps the old setting.
            Button("Cancel", role: .cancel) {}
        } message: { retention in
            Text(
                "Items that have been in Trash for more than \(retention.title) will be "
                    + "deleted. This can’t be undone."
            )
        }
        .saveErrorAlert($saveError)
    }

    // MARK: Lock

    private var lockSection: some View {
        Section {
            Toggle("Require \(lockKind.name)", isOn: lockBinding)
                .disabled(appLock.availability.kind == nil)
        } footer: {
            Text(lockFooter)
        }
    }

    private var lockKind: BiometryKind {
        appLock.availability.kind ?? .faceID
    }

    /// Changing it either way authenticates first; the toggle moves only on success.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { appLock.isEnabled },
            set: { isOn in
                Task { await appLock.setEnabled(isOn) }
            }
        )
    }

    private var lockFooter: String {
        let rule = "Locks Commonplace when you open it and after you’ve been away for a minute."
        switch appLock.availability {
        case .available:
            return rule
        case .passcodeNotSet:
            let reason =
                appLock.wasTurnedOffUnavailable
                ? "The lock was turned off because this iPhone no longer has a passcode."
                : "Set a passcode for this iPhone to use the lock."
            return "\(reason) \(rule)"
        case .unavailable:
            return appLock.wasTurnedOffUnavailable
                ? "The lock was turned off because this iPhone can no longer authenticate."
                : "The lock isn’t available on this iPhone."
        }
    }

    private var retention: TrashRetention {
        TrashRetention(storedValue: storedRetention)
    }

    private var trash: TrashOperations {
        TrashOperations(context: modelContext, now: { [referenceDate] in referenceDate ?? .now })
    }

    /// Applies a longer retention at once. A shorter one that would delete items now asks
    /// first.
    private var retentionBinding: Binding<TrashRetention> {
        Binding(
            get: { retention },
            set: { newValue in
                if retention.isShortened(by: newValue), trash.purgeCount(retention: newValue) > 0 {
                    pendingRetention = newValue
                } else {
                    storedRetention = newValue.rawValue
                }
            }
        )
    }

    private var pendingPurgeTitle: String {
        let count = pendingRetention.map { trash.purgeCount(retention: $0) } ?? 0
        return count == 1 ? "Delete 1 Item Now?" : "Delete \(count) Items Now?"
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
    .sampleData()
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .sampleData()
    .preferredColorScheme(.dark)
}
