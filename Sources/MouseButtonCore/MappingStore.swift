import Foundation
import Observation

private let kMappingsKey = "savedCustomButtonMappings_v2"
private let kEnabledKey = "mousebutton_isEnabled"

@MainActor
@Observable
public final class MappingStore {
    public static let shared = MappingStore()

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: kEnabledKey)
        }
    }

    public var mappings: [ButtonMapping] = [] {
        didSet {
            saveMappings()
        }
    }

    public init() {
        if UserDefaults.standard.object(forKey: kEnabledKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: kEnabledKey)
        } else {
            self.isEnabled = true
        }

        loadMappings()
    }

    private func loadMappings() {
        if let data = UserDefaults.standard.data(forKey: kMappingsKey),
           let loaded = try? JSONDecoder().decode([ButtonMapping].self, from: data) {
            self.mappings = loaded
            return
        }

        // Default initial mapping: Button 4 -> Cmd + ` (Next window of current app)
        self.mappings = [
            ButtonMapping(
                buttonNumber: 4,
                keyCode: 0x32,
                modifierFlags: 1 << 20, // CGEventFlags.maskCommand
                displayString: "⌘ `"
            )
        ]
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: kMappingsKey)
        }
    }

    public func addOrUpdate(_ mapping: ButtonMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        } else if let index = mappings.firstIndex(where: { $0.buttonNumber == mapping.buttonNumber }) {
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
    }

    public func remove(id: String) {
        mappings.removeAll(where: { $0.id == id })
    }

    public func updateButton(id: String, newButton: Int64) {
        if let index = mappings.firstIndex(where: { $0.id == id }) {
            var updated = mappings[index]
            updated.buttonNumber = newButton
            mappings[index] = updated
        }
    }

    public func updateShortcut(id: String, keyCode: UInt16, modifierFlags: UInt64, displayString: String) {
        if let index = mappings.firstIndex(where: { $0.id == id }) {
            var updated = mappings[index]
            updated.keyCode = keyCode
            updated.modifierFlags = modifierFlags
            updated.displayString = displayString
            mappings[index] = updated
        }
    }
}
