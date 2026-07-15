// AppSettings.swift — Central UserDefaults-backed settings store.
import Foundation
import AppKit
import Combine

private enum DefaultsKey {
    static let sensitivity         = "sensitivity"
    static let invertDirection     = "invertDirection"
    static let deadZoneDegrees     = "deadZoneDegrees"
    static let acceleration        = "acceleration"
    static let launchAtLogin       = "launchAtLogin"
    static let enableMenuBarIcon   = "enableMenuBarIcon"
    static let debugLogging        = "debugLogging"
    static let appearance          = "appearance"
    static let fallbackMode        = "fallbackMode"
    static let fallbackModifier    = "fallbackModifier"
    static let degreesPerStep      = "degreesPerStep"
    static let gestureTarget       = "gestureTarget"
    static let brightnessModifier  = "brightnessModifier"
    static let excludedBundleIDs   = "excludedBundleIDs"
    static let hapticLevel         = "hapticLevel"
    static let autoCheckUpdates    = "autoCheckUpdates"
}

// MARK: - Known apps that use the rotation gesture natively.
// Rotation events are passed through to these apps unchanged.
public let defaultExcludedBundleIDs: [String] = [
    "com.apple.Maps",                    // Maps — rotate to turn the map
    "com.apple.Preview",                 // Preview — rotate images/PDFs
    "com.apple.Photos",                  // Photos — rotate in editor
    "com.apple.iPhoto",                  // iPhoto (legacy)
    "com.apple.Aperture",                // Aperture (legacy)
    "com.sketchup.SketchUp",             // SketchUp — rotate 3-D models
    "com.autodesk.autocad",              // AutoCAD
    "com.adobe.Photoshop",               // Photoshop — rotate canvas
    "com.adobe.Illustrator",             // Illustrator — rotate canvas
    "com.adobe.AfterEffects",            // After Effects
    "com.adobe.LightroomClassicCC7",     // Lightroom Classic
    "com.adobe.lightroom",               // Lightroom (new)
    "com.readdle.PDFExpert-Mac",         // PDF Expert
    "com.pdfpen.pdfpen",                 // PDFpen
    "com.smileonmymac.PDFpenPro",        // PDFpenPro
    "com.pixelmator.pro",                // Pixelmator Pro
    "com.pixelmator.pixelmator",         // Pixelmator
    "com.bohemiancoding.sketch3",        // Sketch
    "com.figma.Desktop",                 // Figma
    "com.google.Chrome",                 // Chrome (maps/web apps)
    "org.mozilla.firefox",               // Firefox
    "com.apple.Safari",                  // Safari (web maps)
]

/// Haptic feedback intensity while rotating.
/// off    — silent
/// light  — subtle tick on every value change
/// medium — tick on every change + stronger bump at 10% notches
/// strong — alignment-weight tick on every change + bump at notches
public enum HapticLevel: String, CaseIterable, Identifiable {
    case off    = "Off"
    case light  = "Light"
    case medium = "Medium"
    case strong = "Strong"
    public var id: String { rawValue }
}

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    public var id: String { rawValue }
}

public enum FallbackModifier: String, CaseIterable, Identifiable {
    case fn      = "Fn"
    case control = "Control"
    case option  = "Option"
    case command = "Command"

    public var id: String { rawValue }
}

/// What the rotation gesture controls.
public enum GestureTarget: String, CaseIterable, Identifiable {
    case volume     = "Volume"
    case brightness = "Brightness"

    public var id: String { rawValue }
}

/// Which modifier key switches from volume to brightness (when gestureTarget == .volume).
public enum BrightnessModifier: String, CaseIterable, Identifiable {
    case none    = "None"
    case fn      = "Fn"
    case control = "Control"
    case option  = "Option"
    case command = "Command"

    public var id: String { rawValue }
}

@MainActor
public final class AppSettings: ObservableObject {

    public static let shared = AppSettings()

    @Published public var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: DefaultsKey.sensitivity) }
    }
    @Published public var invertDirection: Bool {
        didSet { defaults.set(invertDirection, forKey: DefaultsKey.invertDirection) }
    }
    @Published public var deadZoneDegrees: Double {
        didSet { defaults.set(deadZoneDegrees, forKey: DefaultsKey.deadZoneDegrees) }
    }
    @Published public var acceleration: Double {
        didSet { defaults.set(acceleration, forKey: DefaultsKey.acceleration) }
    }
    @Published public var degreesPerStep: Double {
        didSet { defaults.set(degreesPerStep, forKey: DefaultsKey.degreesPerStep) }
    }
    @Published public var fallbackMode: Bool {
        didSet { defaults.set(fallbackMode, forKey: DefaultsKey.fallbackMode) }
    }
    @Published public var fallbackModifier: FallbackModifier {
        didSet { defaults.set(fallbackModifier.rawValue, forKey: DefaultsKey.fallbackModifier) }
    }
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: DefaultsKey.launchAtLogin)
            LaunchAtLoginManager.setEnabled(launchAtLogin)
        }
    }
    @Published public var enableMenuBarIcon: Bool {
        didSet { defaults.set(enableMenuBarIcon, forKey: DefaultsKey.enableMenuBarIcon) }
    }
    @Published public var debugLogging: Bool {
        didSet { defaults.set(debugLogging, forKey: DefaultsKey.debugLogging) }
    }
    @Published public var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: DefaultsKey.appearance)
            applyAppearance()
        }
    }

    /// What rotation controls: volume or brightness.
    @Published public var gestureTarget: GestureTarget {
        didSet { defaults.set(gestureTarget.rawValue, forKey: DefaultsKey.gestureTarget) }
    }

    /// Modifier key that temporarily switches to brightness while held.
    /// Set to .none to disable the hold-to-brightness feature.
    @Published public var brightnessModifier: BrightnessModifier {
        didSet { defaults.set(brightnessModifier.rawValue, forKey: DefaultsKey.brightnessModifier) }
    }

    @Published public var hapticLevel: HapticLevel {
        didSet { defaults.set(hapticLevel.rawValue, forKey: DefaultsKey.hapticLevel) }
    }

    /// Whether Sparkle auto-checks for updates (synced to Sparkle by the App target).
    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: DefaultsKey.autoCheckUpdates) }
    }

    /// Bundle IDs of apps where rotation gestures pass through untouched.
    /// Persisted as a JSON-encoded array so add/remove is trivial.
    @Published public var excludedBundleIDs: [String] {
        didSet { saveExcludedBundleIDs() }
    }

    /// Returns true if the given bundle ID should be excluded from gesture handling.
    public func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    public func addExclusion(_ bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !excludedBundleIDs.contains(id) else { return }
        excludedBundleIDs.append(id)
    }

    public func removeExclusion(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    public func resetExclusionsToDefaults() {
        excludedBundleIDs = defaultExcludedBundleIDs
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            DefaultsKey.sensitivity:        0.05,
            DefaultsKey.invertDirection:    false,
            DefaultsKey.deadZoneDegrees:    1.5,
            DefaultsKey.acceleration:       2.0,
            DefaultsKey.degreesPerStep:     5.0,
            DefaultsKey.fallbackMode:       false,
            DefaultsKey.fallbackModifier:   FallbackModifier.option.rawValue,
            DefaultsKey.launchAtLogin:      false,
            DefaultsKey.enableMenuBarIcon:  true,
            DefaultsKey.debugLogging:       false,
            DefaultsKey.appearance:         AppearanceMode.system.rawValue,
            DefaultsKey.gestureTarget:      GestureTarget.volume.rawValue,
            DefaultsKey.brightnessModifier: BrightnessModifier.none.rawValue,
            DefaultsKey.hapticLevel:        HapticLevel.medium.rawValue,
            DefaultsKey.autoCheckUpdates:   true
        ])

        sensitivity       = defaults.double(forKey: DefaultsKey.sensitivity)
        invertDirection   = defaults.bool(forKey: DefaultsKey.invertDirection)
        deadZoneDegrees   = defaults.double(forKey: DefaultsKey.deadZoneDegrees)
        acceleration      = defaults.double(forKey: DefaultsKey.acceleration)
        degreesPerStep    = defaults.double(forKey: DefaultsKey.degreesPerStep)
        fallbackMode      = defaults.bool(forKey: DefaultsKey.fallbackMode)
        fallbackModifier  = FallbackModifier(
            rawValue: defaults.string(forKey: DefaultsKey.fallbackModifier) ?? ""
        ) ?? .option
        launchAtLogin     = defaults.bool(forKey: DefaultsKey.launchAtLogin)
        enableMenuBarIcon = defaults.bool(forKey: DefaultsKey.enableMenuBarIcon)
        debugLogging      = defaults.bool(forKey: DefaultsKey.debugLogging)
        appearance        = AppearanceMode(
            rawValue: defaults.string(forKey: DefaultsKey.appearance) ?? ""
        ) ?? .system
        gestureTarget     = GestureTarget(
            rawValue: defaults.string(forKey: DefaultsKey.gestureTarget) ?? ""
        ) ?? .volume
        brightnessModifier = BrightnessModifier(
            rawValue: defaults.string(forKey: DefaultsKey.brightnessModifier) ?? ""
        ) ?? .none
        hapticLevel = HapticLevel(
            rawValue: defaults.string(forKey: DefaultsKey.hapticLevel) ?? ""
        ) ?? .medium
        autoCheckUpdates = defaults.bool(forKey: DefaultsKey.autoCheckUpdates)

        // Load excluded bundle IDs — fall back to the built-in preset on first launch.
        if let data = defaults.data(forKey: DefaultsKey.excludedBundleIDs),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            excludedBundleIDs = saved
        } else {
            excludedBundleIDs = defaultExcludedBundleIDs
        }
    }

    private func saveExcludedBundleIDs() {
        if let data = try? JSONEncoder().encode(excludedBundleIDs) {
            defaults.set(data, forKey: DefaultsKey.excludedBundleIDs)
        }
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApplication.shared.appearance = nil
        case .light:  NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
