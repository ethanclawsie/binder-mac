import Foundation

public enum TriggerType: String, Codable, Sendable {
    case mouse
    case key
}

public struct ShortcutMapping: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var triggerType: TriggerType

    // Trigger details
    public var triggerButton: Int64
    public var triggerKeyCode: UInt16
    public var triggerModifierFlags: UInt64
    public var triggerDisplay: String

    // Target action details
    public var targetKeyCode: UInt16
    public var targetModifierFlags: UInt64
    public var targetDisplay: String

    public init(
        id: String = UUID().uuidString,
        triggerType: TriggerType = .mouse,
        triggerButton: Int64 = 4,
        triggerKeyCode: UInt16 = 0,
        triggerModifierFlags: UInt64 = 0,
        triggerDisplay: String = "Button 4",
        targetKeyCode: UInt16,
        targetModifierFlags: UInt64,
        targetDisplay: String
    ) {
        self.id = id
        self.triggerType = triggerType
        self.triggerButton = triggerButton
        self.triggerKeyCode = triggerKeyCode
        self.triggerModifierFlags = triggerModifierFlags
        self.triggerDisplay = triggerDisplay
        self.targetKeyCode = targetKeyCode
        self.targetModifierFlags = targetModifierFlags
        self.targetDisplay = targetDisplay
    }

    enum CodingKeys: String, CodingKey {
        case id, triggerType, triggerButton, triggerKeyCode, triggerModifierFlags, triggerDisplay
        case targetKeyCode, targetModifierFlags, targetDisplay
        // Legacy keys
        case buttonNumber, keyCode, modifierFlags, displayString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString

        if let type = try container.decodeIfPresent(TriggerType.self, forKey: .triggerType) {
            self.triggerType = type
            self.triggerButton = try container.decodeIfPresent(Int64.self, forKey: .triggerButton) ?? 4
            self.triggerKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .triggerKeyCode) ?? 0
            self.triggerModifierFlags = try container.decodeIfPresent(UInt64.self, forKey: .triggerModifierFlags) ?? 0
            self.triggerDisplay = try container.decodeIfPresent(String.self, forKey: .triggerDisplay) ?? "Button 4"
            self.targetKeyCode = try container.decode(UInt16.self, forKey: .targetKeyCode)
            self.targetModifierFlags = try container.decode(UInt64.self, forKey: .targetModifierFlags)
            self.targetDisplay = try container.decode(String.self, forKey: .targetDisplay)
        } else {
            // Legacy ButtonMapping format
            self.triggerType = .mouse
            let btn = try container.decodeIfPresent(Int64.self, forKey: .buttonNumber) ?? 4
            self.triggerButton = btn
            self.triggerKeyCode = 0
            self.triggerModifierFlags = 0
            self.triggerDisplay = mouseButtonDisplayName(for: btn)
            self.targetKeyCode = try container.decode(UInt16.self, forKey: .keyCode)
            self.targetModifierFlags = try container.decode(UInt64.self, forKey: .modifierFlags)
            self.targetDisplay = try container.decode(String.self, forKey: .displayString)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(triggerType, forKey: .triggerType)
        try container.encode(triggerButton, forKey: .triggerButton)
        try container.encode(triggerKeyCode, forKey: .triggerKeyCode)
        try container.encode(triggerModifierFlags, forKey: .triggerModifierFlags)
        try container.encode(triggerDisplay, forKey: .triggerDisplay)
        try container.encode(targetKeyCode, forKey: .targetKeyCode)
        try container.encode(targetModifierFlags, forKey: .targetModifierFlags)
        try container.encode(targetDisplay, forKey: .targetDisplay)
    }
}

public typealias ButtonMapping = ShortcutMapping

public func keyLookupHash(keyCode: UInt16, modifierFlags: UInt64) -> UInt64 {
    let standardModifiersMask: UInt64 = (1 << 20) | (1 << 19) | (1 << 18) | (1 << 17)
    let masked = modifierFlags & standardModifiersMask
    return (UInt64(keyCode) << 32) | masked
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
