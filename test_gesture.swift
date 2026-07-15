#!/usr/bin/env swift
// Opens a real NSWindow so the app is a proper GUI target for gesture events.
// This lets both local AND global monitors fire.
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        print("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        // Real window so we're a proper GUI app receiving events
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let label = NSTextField(labelWithString: "Rotate two fingers on the trackpad.\nWatch the terminal for output.")
        label.frame = NSRect(x: 20, y: 80, width: 360, height: 80)
        label.alignment = .center
        window.contentView?.addSubview(label)
        window.title = "Gesture Test"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Global monitor — fires when OTHER apps are front
        NSEvent.addGlobalMonitorForEvents(matching: [.rotate, .magnify, .scrollWheel, .gesture]) { event in
            self.printEvent("GLOBAL", event)
        }

        // Local monitor — fires when THIS window is front
        NSEvent.addLocalMonitorForEvents(matching: [.rotate, .magnify, .scrollWheel, .gesture]) { event in
            self.printEvent("LOCAL", event)
            return event
        }

        print("Ready — rotate/pinch/scroll on trackpad now")
    }

    func printEvent(_ source: String, _ event: NSEvent) {
        switch event.type {
        case .rotate:
            print("\(source) ROTATE \(event.rotation)° phase=\(event.phase.rawValue)")
        case .magnify:
            print("\(source) MAGNIFY \(event.magnification)")
        case .scrollWheel:
            if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                print("\(source) SCROLL dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY)")
            }
        default:
            print("\(source) type=\(event.type.rawValue)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
