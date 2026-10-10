import AppKit
import SwiftUI

@MainActor
final class SettingsWindowManager: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowManager()

    private var window: NSWindow?

    override init() {
        super.init()
    }

    func show() {
        EventTapManager.shared.checkPermission()
        EventTapManager.shared.updateTap()

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 530, height: 490),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Binder Settings"
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.contentViewController = NSHostingController(rootView: SettingsView())
            self.window = win
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        RecordingCoordinator.shared.cancel()
        window?.contentViewController = nil
        window = nil
    }
}
