// Logger.swift — os.Logger wrapper
import OSLog
import Foundation

public enum Logger {
    private static let subsystem = "com.trackpadvolumeknob"
    private static let log = os.Logger(subsystem: subsystem, category: "app")

    public static func debug(_ message: String) {
        log.debug("🔵 \(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        log.info("ℹ️ \(message, privacy: .public)")
    }

    public static func warning(_ message: String) {
        log.warning("⚠️ \(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        log.error("🔴 \(message, privacy: .public)")
    }
}
