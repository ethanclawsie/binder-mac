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

    public init() {
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
                    (1 << CGEventType.keyUp.rawValue)
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

            guard MappingStore.shared.isEnabled else {
                return false
            }

            guard let mapping = MappingStore.shared.mouseLookup[buttonNumber] else {
                return false
            }

            if type == .otherMouseDown {
                sendKeystroke(
                    virtualKey: CGKeyCode(mapping.targetKeyCode),
                    flags: CGEventFlags(rawValue: mapping.targetModifierFlags)
                )
            }

            return true
        }

        // 2. Keyboard Key events
        if type == .keyDown || type == .keyUp {
            guard MappingStore.shared.isEnabled else {
                return false
            }

            let hash = keyLookupHash(keyCode: keyCode, modifierFlags: flags)
            guard let mapping = MappingStore.shared.keyLookup[hash] else {
                return false
            }

            if type == .keyDown {
                sendKeystroke(
                    virtualKey: CGKeyCode(mapping.targetKeyCode),
                    flags: CGEventFlags(rawValue: mapping.targetModifierFlags)
                )
            }

            return true
        }

        return false
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
