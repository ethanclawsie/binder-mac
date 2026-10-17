import AppKit
import CoreGraphics
import Observation

public enum RecordingTarget: Equatable {
    case none
    case newMouseTrigger
    case newKeyTrigger
    case newActionShortcut
    case redoTrigger(mappingID: String, isMouse: Bool)
    case redoAction(mappingID: String)
}

@MainActor
@Observable
public final class RecordingCoordinator {
    public static let shared = RecordingCoordinator()

    public var target: RecordingTarget = .none

    @ObservationIgnored private var localKeyMonitor: Any?

    public init() {}

    public func startRecordingMouse(_ newTarget: RecordingTarget, onRecorded: @escaping (Int64) -> Void) {
        cancel()
        self.target = newTarget
        EventTapManager.shared.startRecordingMouse { [weak self] button in
            guard let self = self else { return }
            self.cancelKeyMonitor()
            self.target = .none
            onRecorded(button)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.cancel()
                return nil
            }
            return event
        }
    }

    public func startRecordingShortcut(_ newTarget: RecordingTarget, onRecorded: @escaping (UInt16, UInt64, String) -> Void) {
        cancel()
        self.target = newTarget
        EventTapManager.shared.cancelRecordingMouse()
        var pendingModifierKeyCode: UInt16?
        var nonSingleKeyOccurred = false

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

            if event.type == .flagsChanged {
                guard let modFlag = modifierFlagForKeyCode(keyCode) else { return event }
                let cgEventFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let isPressed = cgEventFlags.contains(modFlag)

                if isPressed {
                    let otherFlags = cgEventFlags.rawValue & ~modFlag.rawValue
                    let standardMask: UInt64 = (1 << 20) | (1 << 19) | (1 << 18) | (1 << 17)
                    if (otherFlags & standardMask) == 0 && pendingModifierKeyCode == nil && !nonSingleKeyOccurred {
                        pendingModifierKeyCode = keyCode
                    } else {
                        pendingModifierKeyCode = nil
                        nonSingleKeyOccurred = true
                    }
                } else {
                    if let pending = pendingModifierKeyCode, pending == keyCode, !nonSingleKeyOccurred {
                        let display = keyString(for: keyCode, characters: nil)
                        self.cancelKeyMonitor()
                        self.target = .none
                        onRecorded(keyCode, 0, display)
                        return nil
                    }
                    pendingModifierKeyCode = nil
                    if flags.isEmpty {
                        nonSingleKeyOccurred = false
                    }
                }
                return nil
            }

            pendingModifierKeyCode = nil
            nonSingleKeyOccurred = true

            // Esc cancels recording
            if keyCode == 53 && flags.isEmpty {
                self.cancel()
                return nil
            }

            var cgFlags: CGEventFlags = []
            var displayParts: [String] = []

            if flags.contains(.control) {
                cgFlags.insert(.maskControl)
                displayParts.append("⌃")
            }
            if flags.contains(.option) {
                cgFlags.insert(.maskAlternate)
                displayParts.append("⌥")
            }
            if flags.contains(.shift) {
                cgFlags.insert(.maskShift)
                displayParts.append("⇧")
            }
            if flags.contains(.command) {
                cgFlags.insert(.maskCommand)
                displayParts.append("⌘")
            }

            let keyText = keyString(for: keyCode, characters: event.charactersIgnoringModifiers)
            displayParts.append(keyText)

            let fullDisplay = displayParts.joined(separator: " ")

            self.cancelKeyMonitor()
            self.target = .none

            onRecorded(keyCode, cgFlags.rawValue, fullDisplay)
            return nil
        }
    }

    public func cancel() {
        cancelKeyMonitor()
        EventTapManager.shared.cancelRecordingMouse()
        self.target = .none
    }

    private func cancelKeyMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
