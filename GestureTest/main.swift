// Minimal gesture test — no SwiftUI, compiles in seconds
import AppKit
import ApplicationServices

print("AXIsProcessTrusted: \(AXIsProcessTrusted())")

class GestureTestDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 300, y: 300, width: 380, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let label = NSTextField(labelWithString: "Click here, then rotate/scroll/pinch.\nOutput goes to the terminal that launched this.")
        label.frame = NSRect(x: 20, y: 50, width: 340, height: 60)
        label.alignment = .center
        window.contentView?.addSubview(label)
        window.title = "Gesture Test — rotate here"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // LOCAL: fires when this window is frontmost
        NSEvent.addLocalMonitorForEvents(matching: [.rotate, .magnify, .scrollWheel, .gesture, .beginGesture, .endGesture]) { event in
            switch event.type {
            case .rotate:      print("LOCAL ROTATE \(event.rotation)°")
            case .magnify:     print("LOCAL MAGNIFY \(event.magnification)")
            case .beginGesture: print("LOCAL BEGIN_GESTURE")
            case .endGesture:  print("LOCAL END_GESTURE")
            case .scrollWheel:
                if abs(event.scrollingDeltaY) > 0 { print("LOCAL SCROLL dy=\(event.scrollingDeltaY)") }
            default: break
            }
            return event
        }

        // GLOBAL: fires when OTHER apps are frontmost
        NSEvent.addGlobalMonitorForEvents(matching: [.rotate, .magnify, .gesture]) { event in
            if event.type == .rotate { print("GLOBAL ROTATE \(event.rotation)°") }
        }

        print("Window open. Click it, then try rotating two fingers.")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let del = GestureTestDelegate()
app.delegate = del
app.run()
