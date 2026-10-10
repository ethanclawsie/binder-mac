import AppKit
import CoreGraphics
import Observation

public enum RecordingTarget: Equatable {
    case none
    case newMouseButton
    case newShortcut
    case redoMouseButton(mappingID: String)
    case redoShortcut(mappingID: String)
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
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }

            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

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
