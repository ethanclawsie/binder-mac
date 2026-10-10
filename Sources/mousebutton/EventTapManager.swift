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
    public var lastDetectedButton: Int64?

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var recordingCallback: ((Int64) -> Void)?
    @ObservationIgnored private var recordedButtonForMouseUp: Int64?

    public init() {
        self.isTrusted = AXIsProcessTrusted()
        updateTap()
    }

    public func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted != self.isTrusted {
            self.isTrusted = trusted
            if trusted && tap == nil {
                installTap()
            }
        }
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
        if tap == nil && isTrusted {
            installTap()
        } else if !isTrusted && tap != nil {
            removeTap()
        }
    }

    private func installTap() {
        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue)

        activeTapManager = self

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: mouseTapCallback,
            userInfo: nil
        ) else {
            NSLog("[mousebutton] Failed to create CGEventTap.")
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

    fileprivate func handle(_ type: CGEventType, buttonNumber: Int64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        // Recording mode: capture next mouse button
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

        // Consume mouse-up of recently recorded button
        if let recorded = recordedButtonForMouseUp, buttonNumber == recorded {
            if type == .otherMouseUp {
                recordedButtonForMouseUp = nil
            }
            return true
        }

        if type == .otherMouseDown {
            self.lastDetectedButton = buttonNumber
        }

        guard MappingStore.shared.isEnabled else {
            return false
        }

        guard let mapping = MappingStore.shared.lookup[buttonNumber] else {
            return false
        }

        if type == .otherMouseDown {
            sendKeystroke(
                virtualKey: CGKeyCode(mapping.keyCode),
                flags: CGEventFlags(rawValue: mapping.modifierFlags)
            )
        }

        return true
    }
}

private nonisolated(unsafe) weak var activeTapManager: EventTapManager?

private func mouseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
    let swallow = MainActor.assumeIsolated {
        activeTapManager?.handle(type, buttonNumber: buttonNumber) ?? false
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
