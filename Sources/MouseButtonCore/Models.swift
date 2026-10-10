import Foundation

public struct ButtonMapping: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var buttonNumber: Int64
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var displayString: String

    public init(
        id: String = UUID().uuidString,
        buttonNumber: Int64,
        keyCode: UInt16,
        modifierFlags: UInt64,
        displayString: String
    ) {
        self.id = id
        self.buttonNumber = buttonNumber
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.displayString = displayString
    }
}

public func mouseButtonDisplayName(for button: Int64) -> String {
    if button == 2 {
        return "Middle Button (2)"
    } else {
        return "Button \(button)"
    }
}

public func keyString(for keyCode: UInt16, characters: String?) -> String {
    switch keyCode {
    case 0x32: return "`"
    case 0x30: return "Tab"
    case 0x24: return "Return"
    case 0x31: return "Space"
    case 0x33: return "Delete"
    case 0x35: return "Esc"
    case 0x7B: return "←"
    case 0x7C: return "→"
    case 0x7D: return "↓"
    case 0x7E: return "↑"
    case 0x7A: return "F1"
    case 0x78: return "F2"
    case 0x63: return "F3"
    case 0x76: return "F4"
    case 0x60: return "F5"
    case 0x61: return "F6"
    case 0x62: return "F7"
    case 0x64: return "F8"
    case 0x65: return "F9"
    case 0x6D: return "F10"
    case 0x67: return "F11"
    case 0x6F: return "F12"
    default:
        if let chars = characters?.uppercased(), !chars.isEmpty {
            return chars
        }
        return "Key(\(keyCode))"
    }
}
