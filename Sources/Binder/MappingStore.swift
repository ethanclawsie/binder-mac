import Foundation
import Observation

private let kMappingsKey = "binder_mappings"
private let kLegacyMappingsKey = "savedCustomButtonMappings_v2"
private let kEnabledKey = "binder_isEnabled"
private let kLegacyEnabledKey = "mousebutton_isEnabled"

@MainActor
@Observable
public final class MappingStore {
    public static let shared = MappingStore()

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: kEnabledKey)
        }
    }

    public private(set) var mouseLookup: [Int64: ShortcutMapping] = [:]
    public private(set) var keyLookup: [UInt64: ShortcutMapping] = [:]

    public var hasKeyMappings: Bool {
        !keyLookup.isEmpty
    }

    private var isInitialized = false

    public var mappings: [ShortcutMapping] = [] {
        didSet {
            rebuildLookup()
            saveMappings()
            if isInitialized {
                EventTapManager.shared.updateTap()
            }
        }
    }

    private func rebuildLookup() {
        var mDict: [Int64: ShortcutMapping] = [:]
        var kDict: [UInt64: ShortcutMapping] = [:]
        for m in mappings {
            if m.triggerType == .mouse {
                mDict[m.triggerButton] = m
            } else {
                let hash = keyLookupHash(keyCode: m.triggerKeyCode, modifierFlags: m.triggerModifierFlags)
                kDict[hash] = m
            }
        }
        self.mouseLookup = mDict
        self.keyLookup = kDict
    }

    public init() {
        if UserDefaults.standard.object(forKey: kEnabledKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: kEnabledKey)
        } else if UserDefaults.standard.object(forKey: kLegacyEnabledKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: kLegacyEnabledKey)
        } else {
            self.isEnabled = true
        }

        loadMappings()
        rebuildLookup()
        self.isInitialized = true
    }

    private func loadMappings() {
        let data = UserDefaults.standard.data(forKey: kMappingsKey) ?? UserDefaults.standard.data(forKey: kLegacyMappingsKey)
        if let data,
           let loaded = try? JSONDecoder().decode([ShortcutMapping].self, from: data) {
            self.mappings = loaded.filter { mapping in
                if mapping.triggerType == .key {
                    let tHash = keyLookupHash(keyCode: mapping.triggerKeyCode, modifierFlags: mapping.triggerModifierFlags)
                    let aHash = keyLookupHash(keyCode: mapping.targetKeyCode, modifierFlags: mapping.targetModifierFlags)
                    return tHash != aHash
                }
                return true
            }
            return
        }

        // Default initial mapping: Button 4 -> Cmd + ` (Next window of current app)
        self.mappings = [
            ShortcutMapping(
                triggerType: .mouse,
                triggerButton: 4,
                triggerDisplay: "Button 4",
                targetKeyCode: 0x32,
                targetModifierFlags: 1 << 20, // CGEventFlags.maskCommand
                targetDisplay: "⌘ `"
            )
        ]
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: kMappingsKey)
        }
    }

    @discardableResult
    public func addOrUpdate(_ mapping: ShortcutMapping) -> Bool {
        if mapping.triggerType == .key {
            let tHash = keyLookupHash(keyCode: mapping.triggerKeyCode, modifierFlags: mapping.triggerModifierFlags)
            let aHash = keyLookupHash(keyCode: mapping.targetKeyCode, modifierFlags: mapping.targetModifierFlags)
            if tHash == aHash {
                return false
            }
        }

        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        } else if mapping.triggerType == .mouse,
                  let index = mappings.firstIndex(where: { $0.triggerType == .mouse && $0.triggerButton == mapping.triggerButton }) {
            mappings[index] = mapping
        } else if mapping.triggerType == .key,
                  let index = mappings.firstIndex(where: { $0.triggerType == .key && $0.triggerKeyCode == mapping.triggerKeyCode && $0.triggerModifierFlags == mapping.triggerModifierFlags }) {
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
        return true
    }

    public func remove(id: String) {
        mappings.removeAll(where: { $0.id == id })
    }

    public func updateMouseTrigger(id: String, newButton: Int64) {
        if let index = mappings.firstIndex(where: { $0.id == id }) {
            var updated = mappings[index]
            updated.triggerType = .mouse
            updated.triggerButton = newButton
            updated.triggerDisplay = mouseButtonDisplayName(for: newButton)
            mappings[index] = updated
        }
    }

    @discardableResult
    public func updateKeyTrigger(id: String, keyCode: UInt16, modifierFlags: UInt64, display: String) -> Bool {
        if let index = mappings.firstIndex(where: { $0.id == id }) {
            let tHash = keyLookupHash(keyCode: keyCode, modifierFlags: modifierFlags)
            let aHash = keyLookupHash(keyCode: mappings[index].targetKeyCode, modifierFlags: mappings[index].targetModifierFlags)
            if tHash == aHash { return false }

            var updated = mappings[index]
            updated.triggerType = .key
            updated.triggerKeyCode = keyCode
            updated.triggerModifierFlags = modifierFlags
            updated.triggerDisplay = display
            mappings[index] = updated
            return true
        }
        return false
    }

    @discardableResult
    public func updateTargetShortcut(id: String, keyCode: UInt16, modifierFlags: UInt64, display: String) -> Bool {
        if let index = mappings.firstIndex(where: { $0.id == id }) {
            if mappings[index].triggerType == .key {
                let tHash = keyLookupHash(keyCode: mappings[index].triggerKeyCode, modifierFlags: mappings[index].triggerModifierFlags)
                let aHash = keyLookupHash(keyCode: keyCode, modifierFlags: modifierFlags)
                if tHash == aHash { return false }
            }

            var updated = mappings[index]
            updated.targetKeyCode = keyCode
            updated.targetModifierFlags = modifierFlags
            updated.targetDisplay = display
            mappings[index] = updated
            return true
        }
        return false
    }
}
