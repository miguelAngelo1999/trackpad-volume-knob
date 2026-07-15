// main.swift — executable entry point
// Must be named exactly "main.swift" (lowercase) so SPM treats it as the
// top-level entry point. Top-level code here runs on the main thread.
import AppKit

// Keep a strong reference — NSApplication.delegate is weak.
let _delegate = AppDelegate()
NSApplication.shared.delegate = _delegate
NSApplication.shared.run()
