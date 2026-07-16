// OnboardingView.swift — first-run and re-authorization permissions screen.
import SwiftUI

public struct OnboardingView: View {
    public var onComplete: () -> Void

    @State private var hasPermission = false
    @State private var isPolling = false

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)

                Text("Mac Trackpad Fix")
                    .font(.title2.bold())

                Text("Use rotate and pinch gestures on your trackpad to control volume and brightness.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Permission row
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
                        "Enable Mac Trackpad Fix in System Settings, then click \"Check Again\".",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            Divider()

            // Buttons
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
                // Register the app in the TCC list silently (no dialog)
                // so it appears in System Settings ready to be toggled on.
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
                hasPermission = PermissionsManager.hasAccessibilityPermission()
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
