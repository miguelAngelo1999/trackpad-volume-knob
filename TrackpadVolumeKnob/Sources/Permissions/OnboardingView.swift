// OnboardingView.swift — first-run permissions onboarding screen.
import SwiftUI

public struct OnboardingView: View {
    public var onComplete: () -> Void

    @State private var hasPermission = false
    @State private var isCheckingRepeatedly = false

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)

                Text("Welcome to TrackpadVolumeKnob")
                    .font(.title2.bold())

                Text("Rotate two fingers on your trackpad to control system volume — just like turning a physical knob.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.top, 32)
            .padding(.bottom, 28)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Required Permission")
                    .font(.headline)

                PermissionRow(
                    title: "Accessibility",
                    description: "Allows TrackpadVolumeKnob to observe trackpad rotation gestures system-wide, even when other apps are in focus.",
                    isGranted: hasPermission
                )
            }
            .padding(24)

            Divider()

            HStack(spacing: 12) {
                if !hasPermission {
                    Button("Open System Settings") {
                        PermissionsManager.openAccessibilitySettings()
                        startPollingPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Again") {
                        checkPermission()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 440)
        .onAppear { checkPermission() }
    }

    private func checkPermission() {
        hasPermission = PermissionsManager.hasAccessibilityPermission()
    }

    private func startPollingPermission() {
        guard !isCheckingRepeatedly else { return }
        isCheckingRepeatedly = true

        Task {
            while !hasPermission {
                try? await Task.sleep(for: .seconds(1))
                hasPermission = PermissionsManager.hasAccessibilityPermission()
            }
            isCheckingRepeatedly = false
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
                Text(title)
                    .font(.body.bold())
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

#Preview {
    OnboardingView(onComplete: {})
}
