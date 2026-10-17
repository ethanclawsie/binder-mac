import CoreGraphics

public let kSyntheticUserTag: Int64 = 0x53594E54 // "SYNT"

@MainActor
private let hidEventSource = CGEventSource(stateID: .privateState)

@MainActor
func sendKeyEvent(virtualKey: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
    guard let event = CGEvent(keyboardEventSource: hidEventSource, virtualKey: virtualKey, keyDown: keyDown) else {
        return
    }
    if modifierFlagForKeyCode(UInt16(virtualKey)) != nil {
        if !flags.isEmpty {
            event.flags.formUnion(flags)
        }
    } else {
        event.flags = flags
    }
    event.setIntegerValueField(.eventSourceUserData, value: kSyntheticUserTag)
    event.post(tap: .cghidEventTap)
}
