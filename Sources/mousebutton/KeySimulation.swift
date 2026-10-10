import CoreGraphics

@MainActor
private let hidEventSource = CGEventSource(stateID: .hidSystemState)

@MainActor
func sendKeystroke(virtualKey: CGKeyCode, flags: CGEventFlags) {
    guard let keyDown = CGEvent(keyboardEventSource: hidEventSource, virtualKey: virtualKey, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: hidEventSource, virtualKey: virtualKey, keyDown: false) else {
        return
    }
    keyDown.flags = flags
    keyUp.flags = flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}
