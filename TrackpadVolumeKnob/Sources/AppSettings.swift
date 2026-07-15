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
            DefaultsKey.brightnessModifier: BrightnessModifier.none.rawValue
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
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApplication.shared.appearance = nil
        case .light:  NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
