import SwiftUI
import UIKit

extension View {
    /// Puts the app lock over everything: the lock screen and the privacy cover, the one-time
    /// offer, and scene-phase tracking. Presented sheets, covers, and alerts are never
    /// dismissed on lock; the cover sits above them.
    func appLock(_ appLock: AppLock) -> some View {
        modifier(AppLockModifier(appLock: appLock))
    }
}

private struct AppLockModifier: ViewModifier {
    let appLock: AppLock

    @Environment(\.scenePhase) private var scenePhase
    @State private var lockWindow = LockWindow()
    @State private var isOffering = false

    func body(content: Content) -> some View {
        content
            // Covers the root view from the first frame, before the window can be attached.
            // The window covers what is presented above the root.
            .overlay {
                if appLock.isCovering {
                    LockScreen(appLock: appLock)
                }
            }
            .environment(appLock)
            .onChange(of: scenePhase, initial: true) { _, phase in
                appLock.sceneChanged(to: phase)
                lockWindow.update(isVisible: appLock.isCovering, appLock: appLock)
            }
            .onChange(of: appLock.isCovering) { _, isCovering in
                lockWindow.update(isVisible: isCovering, appLock: appLock)
            }
            // After the first frame, over the topics list.
            .task {
                guard appLock.shouldOffer, !appLock.isCovering else {
                    return
                }
                try? await Task.sleep(for: .milliseconds(600))
                isOffering = appLock.shouldOffer && !appLock.isCovering
            }
            .alert(
                appLock.availability.kind?.offerTitle ?? "",
                isPresented: $isOffering
            ) {
                Button("Turn On") {
                    Task { await appLock.answerOffer(turnOn: true) }
                }
                Button("Not Now", role: .cancel) {
                    Task { await appLock.answerOffer(turnOn: false) }
                }
            } message: {
                Text("You can change this anytime in Settings.")
            }
    }
}

/// A second window above everything else in the scene, including alerts, holding the lock
/// screen. A SwiftUI overlay on the root view doesn't reach sheets or full-screen covers
/// presented above it.
@Observable
private final class LockWindow {
    @ObservationIgnored private var window: UIWindow?
    /// The window that was key before the lock went up, made key again after.
    @ObservationIgnored private weak var previousKeyWindow: UIWindow?

    func update(isVisible: Bool, appLock: AppLock) {
        if isVisible {
            show(appLock)
        } else {
            hide()
        }
    }

    private func show(_ appLock: AppLock) {
        guard window?.isHidden != false else {
            return
        }
        guard let scene = Self.activeScene else {
            return
        }
        let window = window ?? Self.makeWindow(in: scene, appLock: appLock)
        self.window = window
        previousKeyWindow = scene.windows.first { $0.isKeyWindow && $0 !== window }
        window.makeKeyAndVisible()
        UIAccessibility.post(
            notification: .screenChanged, argument: window.rootViewController?.view)
    }

    private func hide() {
        guard let window, !window.isHidden else {
            return
        }
        window.isHidden = true
        previousKeyWindow?.makeKey()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive } ?? scenes.first
    }

    private static func makeWindow(in scene: UIWindowScene, appLock: AppLock) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreen(appLock: appLock))
        host.view.backgroundColor = .systemBackground
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        return window
    }
}

/// The privacy cover, and with the lock on, the lock screen. Plain and native: the app's name
/// and glyph on the system background.
struct LockScreen: View {
    let appLock: AppLock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Commonplace")
                .font(.title2.weight(.semibold))
            if appLock.isLocked {
                Text("Commonplace is locked")
                    .foregroundStyle(.secondary)
                Button("Unlock with \(appLock.availability.kind?.name ?? "Passcode")") {
                    Task { await appLock.unlock() }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .task(id: AutoUnlockKey(lock: appLock.lockCount, isActive: appLock.isSceneActive)) {
            await appLock.autoUnlockIfNeeded()
        }
    }

    private struct AutoUnlockKey: Equatable {
        let lock: Int
        let isActive: Bool
    }
}

#Preview("Locked") {
    LockScreen(appLock: PreviewContainer.lockedAppLock)
}

#Preview("Locked · Dark") {
    LockScreen(appLock: PreviewContainer.lockedAppLock)
        .preferredColorScheme(.dark)
}
