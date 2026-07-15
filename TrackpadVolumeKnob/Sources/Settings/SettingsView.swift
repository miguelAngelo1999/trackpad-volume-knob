// SettingsView.swift — tabbed preferences window
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            GesturesTab(settings: settings)
                .tabItem { Label("Gestures", systemImage: "hand.draw") }

            AudioTab()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            AppsTab(settings: settings)
                .tabItem { Label("Apps", systemImage: "square.stack") }

            AppearanceTab(settings: settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $settings.enableMenuBarIcon)
                Toggle("Automatically check for updates", isOn: $settings.autoCheckUpdates)
            }

            Section("Debug") {
                Toggle("Enable debug logging", isOn: $settings.debugLogging)
                if settings.debugLogging {
                    Text("Debug messages are printed to Console.app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("License", value: "MIT")
                Link(
                    "Source code on GitHub",
                    destination: URL(string: "https://github.com/miguelAngelo1999/trackpad-volume-knob")!
                )
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Gestures Tab

private struct GesturesTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Volume per step")
                        Spacer()
                        Text("\(Int(settings.sensitivity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.sensitivity, in: 0.01...0.20, step: 0.01)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Degrees per step")
                        Spacer()
                        Text("\(String(format: "%.1f", settings.degreesPerStep))°")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.degreesPerStep, in: 1.0...20.0, step: 0.5)
                }
            }

            Section("Behaviour") {
                Toggle("Invert rotation direction", isOn: $settings.invertDirection)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Dead zone")
                        Spacer()
                        Text("\(String(format: "%.1f", settings.deadZoneDegrees))°")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.deadZoneDegrees, in: 0.0...10.0, step: 0.5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Acceleration")
                        Spacer()
                        Text(String(format: "%.1f×", settings.acceleration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.acceleration, in: 1.0...4.0, step: 0.1)
                    Text("Higher values make fast rotations jump more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Haptic Feedback") {
                Picker("Trackpad feedback", selection: $settings.hapticLevel) {
                    ForEach(HapticLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch settings.hapticLevel {
                    case .off:
                        Text("No trackpad feedback.")
                    case .light:
                        Text("Subtle tick on every change.")
                    case .medium:
                        Text("Snap on every change • stronger bump at 10% volume steps.")
                    case .strong:
                        Text("Strong click on every change • bump at 10% volume steps.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Fallback Mode") {
                Toggle("Require modifier key", isOn: $settings.fallbackMode)
                if settings.fallbackMode {
                    Picker("Modifier key", selection: $settings.fallbackModifier) {
                        ForEach(FallbackModifier.allCases) { mod in
                            Text(mod.rawValue).tag(mod)
                        }
                    }
                    Text("Hold this key while rotating to adjust volume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Action") {
                Picker("Rotation controls", selection: $settings.gestureTarget) {
                    ForEach(GestureTarget.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Hold modifier to switch to…", selection: $settings.brightnessModifier) {
                    ForEach(BrightnessModifier.allCases) { m in
                        Text(m == .none ? "Disabled" : "\(m.rawValue) → \(settings.gestureTarget == .volume ? "Brightness" : "Volume")")
                            .tag(m)
                    }
                }

                if settings.brightnessModifier != .none {
                    Text("Hold \(settings.brightnessModifier.rawValue) while rotating to temporarily control \(settings.gestureTarget == .volume ? "brightness" : "volume").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pinch Gesture") {
                Toggle("Enable pinch gesture", isOn: $settings.pinchEnabled)

                if settings.pinchEnabled {
                    Picker("Pinch controls", selection: $settings.pinchTarget) {
                        ForEach(PinchTarget.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Spread to increase \(settings.pinchTarget.rawValue.lowercased()), pinch to decrease.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio Tab

private struct AudioTab: View {
    var body: some View {
        Form {
            Section("Output Device") {
                Text("TrackpadVolumeKnob controls the macOS default output device.")
                    .foregroundStyle(.secondary)
                Text("This includes built-in speakers, AirPods, Bluetooth headphones, USB DACs, and anything else set as default in System Settings › Sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Volume Test") {
                VolumeTestView()
            }
        }
        .formStyle(.grouped)
    }
}

private struct VolumeTestView: View {
    @State private var volume: Double = 0.5
    private let controller = VolumeController()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test volume")
                Spacer()
                Text("\(Int(volume * 100))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $volume, in: 0...1, step: 0.01)
                .onChange(of: volume) { _, newValue in
                    controller.setVolume(Float(newValue))
                }
        }
    }
}

// MARK: - Apps Tab

private struct AppsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var newBundleID: String = ""
    @State private var showingAddField = false

    var body: some View {
        VStack(spacing: 0) {
            // Header explanation
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.slash.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pass-through Apps")
                        .font(.headline)
                    Text("Rotation gestures are ignored when these apps are frontmost, so their native rotation features (maps, image rotation, 3-D views) work uninterrupted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))

            Divider()

            // App list
            List {
                ForEach(settings.excludedBundleIDs, id: \.self) { bid in
                    AppRow(bundleID: bid,
                           isPreset: defaultExcludedBundleIDs.contains(bid)) {
                        settings.removeExclusion(bid)
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { settings.excludedBundleIDs.remove(at: $0) }
                }

                // Inline add row
                if showingAddField {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        TextField("com.example.App", text: $newBundleID)
                            .textFieldStyle(.plain)
                            .onSubmit { commitAdd() }
                        Button("Add") { commitAdd() }
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") {
                            newBundleID = ""
                            showingAddField = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    showingAddField = true
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(showingAddField)

                Spacer()

                // "Add current app" convenience button
                if let front = NSWorkspace.shared.frontmostApplication,
                   let bid = front.bundleIdentifier,
                   bid != Bundle.main.bundleIdentifier {
                    Button("Add Frontmost App") {
                        settings.addExclusion(bid)
                    }
                    .buttonStyle(.borderless)
                    .help("Add \(front.localizedName ?? bid) (\(bid))")
                }

                Spacer()

                Button("Reset to Defaults") {
                    settings.resetExclusionsToDefaults()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func commitAdd() {
        settings.addExclusion(newBundleID)
        newBundleID = ""
        showingAddField = false
    }
}

// MARK: - AppRow

private struct AppRow: View {
    let bundleID: String
    let isPreset: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    // Resolve app name and icon from the bundle ID if the app is installed.
    private var appInfo: (name: String, icon: NSImage?)? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return (name, icon)
    }

    var body: some View {
        HStack(spacing: 10) {
            // App icon if installed, otherwise generic
            if let icon = appInfo?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(appInfo?.name ?? bundleID)
                        .lineLimit(1)
                    if isPreset {
                        Text("preset")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                if appInfo != nil {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Remove button — shown on hover
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
