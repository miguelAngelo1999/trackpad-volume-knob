// OnboardingView.swift — first-run and re-authorization permissions screen.
import SwiftUI

/// Fired when the polling loop detects accessibility permission was granted.
/// AppDelegate observes this and brings the window to front.
extension Notification.Name {
    public static let accessibilityPermissionGranted = Notification.Name("accessibilityPermissionGranted")
}

public struct OnboardingView: View {
    public var onComplete: () -> Void

    @State private var hasPermission = false
    @State private var isPolling = false
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {

            // MARK: Header
            VStack(spacing: 12) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)

                Text("Mac Trackpad Fix")
                    .font(.title2.bold())

                Text("Use rotate and pinch gestures on your trackpad\nto control volume and brightness.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)

            Divider()

            // MARK: Accessibility permission
            VStack(alignment: .leading, spacing: 12) {
                Text("Required Permission")
                    .font(.headline)

                PermissionRow(
                    title: "Accessibility",
                    description: "Allows Mac Trackpad Fix to observe trackpad gestures system-wide.",
                    isGranted: hasPermission
                )

                if !hasPermission {
                    Label(
                        "Enable Mac Trackpad Fix in System Settings — this window will return automatically.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            Divider()

            // MARK: Launch at login
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at login")
                        .font(.body.bold())
                    Text("Start Mac Trackpad Fix automatically when you log in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        AppSettings.shared.launchAtLogin = newValue
                    }
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 4)

            Divider()

            // MARK: Buttons
            if hasPermission {
                Button("Get Started") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .padding(24)
            } else {
                HStack(spacing: 10) {
                    Button("Open System Settings") {
                        PermissionsManager.openAccessibilitySettings()
                        startPolling()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Again") { checkPermission() }
                        .buttonStyle(.bordered)
                }
                .padding(24)
            }
        }
        .frame(width: 480)
        .onAppear {
            checkPermission()
            if !hasPermission {
                PermissionsManager.requestAccessibilityPermission(showPrompt: false)
                startPolling()
            }
        }
    }

    private func checkPermission() {
        hasPermission = PermissionsManager.hasAccessibilityPermission()
    }

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        Task {
            while !hasPermission {
                try? await Task.sleep(for: .seconds(1))
                if PermissionsManager.hasAccessibilityPermission() {
                    hasPermission = true
                    // Post notification — AppDelegate handles window focus
                    // (more reliable than NSApp.activate from within a Task)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .accessibilityPermissionGranted, object: nil)
                    }
                }
            }
            isPolling = false
        }
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 28)
                .animation(.spring(response: 0.3), value: isGranted)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.bold())
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
