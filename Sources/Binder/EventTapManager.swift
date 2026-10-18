import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
public final class EventTapManager {
    public static let shared = EventTapManager()

    public private(set) var isListening: Bool = false
    public private(set) var isRecordingMouse: Bool = false
    public private(set) var isTrusted: Bool = false

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var recordingCallback: ((Int64) -> Void)?
    @ObservationIgnored private var recordedButtonForMouseUp: Int64?

    // Mapping fired on press, keyed by trigger button / key code, so the release matches it.
    @ObservationIgnored private var heldMouse: [Int64: ShortcutMapping] = [:]
    @ObservationIgnored private var heldKeys: [UInt64: ShortcutMapping] = [:]

    public init() {
        heldMouse.reserveCapacity(4)
        heldKeys.reserveCapacity(4)
        checkPermission()
    }

    public func checkPermission() {
        self.isTrusted = AXIsProcessTrusted()
    }

    public static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    public func startRecordingMouse(onRecorded: @escaping (Int64) -> Void) {
        checkPermission()
        guard isTrusted else {
            Self.promptForAccessibility()
            return
        }
        self.isRecordingMouse = true
        self.recordingCallback = onRecorded
        self.recordedButtonForMouseUp = nil
        updateTap()
    }

    public func cancelRecordingMouse() {
        self.isRecordingMouse = false
        self.recordingCallback = nil
        self.recordedButtonForMouseUp = nil
    }

    public func updateTap() {
        checkPermission()
        if tap != nil {
            removeTap()
        }
        if isTrusted {
            installTap()
        }
    }

    private func installTap() {
        var mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue)

        if MappingStore.shared.hasKeyMappings {
            mask |= (1 << CGEventType.keyDown.rawValue) |
                    (1 << CGEventType.keyUp.rawValue) |
                    (1 << CGEventType.flagsChanged.rawValue)
        }

        activeTapManager = self

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: tapCallback,
            userInfo: nil
        ) else {
            NSLog("[Binder] Failed to create CGEventTap.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = runLoopSource
        self.isListening = true
    }

    private func removeTap() {
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        self.tap = nil
        self.source = nil
        self.isListening = false
    }

    fileprivate func handle(type: CGEventType, buttonNumber: Int64, keyCode: UInt16, flags: UInt64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        // 1. Mouse Button events
        if type == .otherMouseDown || type == .otherMouseUp {
            if isRecordingMouse {
                if type == .otherMouseDown {
                    recordedButtonForMouseUp = buttonNumber
                    isRecordingMouse = false
                    let callback = recordingCallback
                    recordingCallback = nil
                    callback?(buttonNumber)
                    return true
                }
                return false
            }

            if let recorded = recordedButtonForMouseUp, buttonNumber == recorded {
                if type == .otherMouseUp {
                    recordedButtonForMouseUp = nil
                }
                return true
            }

            if type == .otherMouseUp {
                guard let held = heldMouse.removeValue(forKey: buttonNumber) else { return false }
                send(held, keyDown: false)
                return true
            }

            guard MappingStore.shared.isEnabled,
                  let mapping = MappingStore.shared.mapping(forButton: buttonNumber) else {
                return false
            }
            if mapping.isPassThrough {
                return false
            }
            heldMouse[buttonNumber] = mapping
            send(mapping, keyDown: true)
            return true
        }

        // 2. Keyboard Key & Modifier events
        if type == .flagsChanged {
            guard let modFlag = modifierFlagForKeyCode(keyCode) else {
                return false
            }
            let isDown = CGEventFlags(rawValue: flags).contains(modFlag)
            return handleKey(keyCode, flags: flags & ~modFlag.rawValue, isDown: isDown)
        }
        if type == .keyDown || type == .keyUp {
            return handleKey(keyCode, flags: flags, isDown: type == .keyDown)
        }

        return false
    }

    private func handleKey(_ keyCode: UInt16, flags: UInt64, isDown: Bool) -> Bool {
        if !isDown {
            guard let held = heldKeys.removeValue(forKey: UInt64(keyCode)) else { return false }
            send(held, keyDown: false)
            return true
        }

        guard MappingStore.shared.isEnabled,
              RecordingCoordinator.shared.target == .none,
              let mapping = MappingStore.shared.mapping(forKeyHash: keyLookupHash(keyCode: keyCode, modifierFlags: flags)) else {
            return false
        }
        if mapping.isPassThrough {
            return false
        }
        heldKeys[UInt64(keyCode)] = mapping
        send(mapping, keyDown: true)
        return true
    }

    private func send(_ mapping: ShortcutMapping, keyDown: Bool) {
        sendKeyEvent(virtualKey: CGKeyCode(mapping.targetKeyCode), flags: CGEventFlags(rawValue: mapping.targetModifierFlags), keyDown: keyDown)
    }
}

private nonisolated(unsafe) weak var activeTapManager: EventTapManager?

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if event.getIntegerValueField(.eventSourceUserData) == kSyntheticUserTag {
        return Unmanaged.passUnretained(event)
    }

    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.rawValue

    let swallow = MainActor.assumeIsolated {
        activeTapManager?.handle(type: type, buttonNumber: buttonNumber, keyCode: keyCode, flags: flags) ?? false
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
