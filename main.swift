import Cocoa
import CoreGraphics
import ApplicationServices
import ServiceManagement

// MARK: - Constants & Key Codes
private let kUserDefaultsKey = "savedCustomButtonMappings_v2"

// MARK: - Data Model
struct ButtonMapping: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var buttonNumber: Int64
    var keyCode: UInt16
    var modifierFlags: UInt64
    var displayString: String
}

// MARK: - Helper to Convert KeyCode to Human Readable String
func keyString(for keyCode: UInt16, characters: String?) -> String {
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

// MARK: - Configuration Manager
class ConfigManager {
    static let shared = ConfigManager()

    var isEnabled: Bool = true
    var isRecordingMouse: Bool = false
    var onButtonRecorded: ((Int64) -> Void)?
    private var isInitialized = false

    var mappings: [ButtonMapping] = [] {
        didSet {
            guard isInitialized else { return }
            saveMappings()
            AppDelegate.shared?.rebuildMenu()
            SettingsWindowController.shared?.reloadMappingsList()
        }
    }

    init() {
        loadMappings()
        isInitialized = true
    }

    func loadMappings() {
        if let data = UserDefaults.standard.data(forKey: kUserDefaultsKey),
           let loaded = try? JSONDecoder().decode([ButtonMapping].self, from: data) {
            self.mappings = loaded
            return
        }

        // Default initial mapping: Button 4 -> Cmd + ` (Next window of current app)
        self.mappings = [
            ButtonMapping(
                buttonNumber: 4,
                keyCode: 0x32,
                modifierFlags: CGEventFlags.maskCommand.rawValue,
                displayString: "⌘ `"
            )
        ]
    }

    func saveMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: kUserDefaultsKey)
        }
    }

    func addOrUpdateMapping(_ mapping: ButtonMapping) {
        if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
            mappings[index] = mapping
        } else if let index = mappings.firstIndex(where: { $0.buttonNumber == mapping.buttonNumber }) {
            // Replace mapping for same button
            mappings[index] = mapping
        } else {
            mappings.append(mapping)
        }
    }

    func removeMapping(id: String) {
        mappings.removeAll(where: { $0.id == id })
    }
}

// MARK: - Key Simulation
func sendKeystroke(virtualKey: CGKeyCode, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState) ?? CGEventSource(stateID: .combinedSessionState)

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
        return
    }

    keyDown.flags = flags
    keyUp.flags = flags

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}

// MARK: - Event Tap Manager
class EventTapManager {
    static let shared = EventTapManager()

    private(set) var tap: CFMachPort?
    private(set) var source: CFRunLoopSource?
    private(set) var isListening: Bool = false

    func updateTap() {
        let isTrusted = AXIsProcessTrusted()
        if tap == nil && isTrusted {
            installTap()
        } else if !isTrusted && tap != nil {
            removeTap()
        }
    }

    func installTap() {
        let mask = (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
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

    func removeTap() {
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
}

// MARK: - Event Tap Callback
func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = EventTapManager.shared.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .otherMouseDown || type == .otherMouseUp else {
        return Unmanaged.passUnretained(event)
    }

    let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

    // RECORDING MOUSE BUTTON
    if ConfigManager.shared.isRecordingMouse {
        if type == .otherMouseDown {
            DispatchQueue.main.async {
                ConfigManager.shared.onButtonRecorded?(buttonNumber)
            }
        }
        return nil
    }

    guard ConfigManager.shared.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    // Check if this button is in active mappings
    guard let mapping = ConfigManager.shared.mappings.first(where: { $0.buttonNumber == buttonNumber }) else {
        return Unmanaged.passUnretained(event) // Pass through to other apps
    }

    if type == .otherMouseDown {
        sendKeystroke(
            virtualKey: CGKeyCode(mapping.keyCode),
            flags: CGEventFlags(rawValue: mapping.modifierFlags)
        )
    }

    return nil // Swallow event
}

// MARK: - Settings / Mapping Window Controller
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    // Global warning
    var permissionWarningLabel: NSTextField!
    var openSettingsButton: NSButton!
    var restartButton: NSButton!

    // New/Edit Entry Form Card
    var formCardBox: NSBox!
    var formTitleLabel: NSTextField!
    var recordMouseBtn: NSButton!
    var cancelMouseBtn: NSButton!
    var mouseStatusLabel: NSTextField!

    var recordShortcutBtn: NSButton!
    var cancelShortcutBtn: NSButton!
    var shortcutStatusLabel: NSTextField!

    var saveEntryBtn: NSButton!
    var cancelEntryBtn: NSButton!

    var addNewButton: NSButton!
    var mappingsStackView: NSStackView!

    // Temporary working state for the form
    var editingMappingID: String?
    var draftButtonNumber: Int64?
    var draftKeyCode: UInt16?
    var draftModifierFlags: UInt64?
    var draftShortcutDisplay: String?

    // Listener monitors
    var isRecordingShortcut: Bool = false
    var localKeyMonitor: Any?
    var globalKeyMonitor: Any?
    var localMouseMonitor: Any?
    var globalMouseMonitor: Any?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "mousebutton Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self

        setupUI()
        reloadMappingsList()
        updatePermissionStatus()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        // 1. Title & Subtitle (Centered)
        let header = NSTextField(labelWithString: "Configure Mouse Shortcuts")
        header.font = NSFont.boldSystemFont(ofSize: 15)
        header.alignment = .center
        mainStack.addArrangedSubview(header)
        header.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        header.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        let desc = NSTextField(labelWithString: "Map any mouse button to any keyboard shortcut combination.")
        desc.textColor = .secondaryLabelColor
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.alignment = .center
        mainStack.addArrangedSubview(desc)
        desc.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        desc.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // Permission warning row (hidden when trusted)
        let permRow = NSStackView()
        permRow.orientation = .horizontal
        permRow.spacing = 8
        permRow.alignment = .centerY

        permissionWarningLabel = NSTextField(labelWithString: "⚠️ Accessibility required:")
        permissionWarningLabel.textColor = .systemRed
        permissionWarningLabel.font = NSFont.boldSystemFont(ofSize: 11)
        permRow.addArrangedSubview(permissionWarningLabel)

        openSettingsButton = NSButton(title: "Open Settings", target: self, action: #selector(openAccessibilitySettings))
        openSettingsButton.bezelStyle = .inline
        permRow.addArrangedSubview(openSettingsButton)

        restartButton = NSButton(title: "Restart App", target: self, action: #selector(restartApp))
        restartButton.bezelStyle = .inline
        permRow.addArrangedSubview(restartButton)

        mainStack.addArrangedSubview(permRow)

        // 2. Add New Mapping Button
        addNewButton = NSButton(title: "＋ New Mapping", target: self, action: #selector(startNewMapping))
        addNewButton.bezelStyle = .rounded
        mainStack.addArrangedSubview(addNewButton)

        // 3. Editor Card Form (Hidden until New or Edit is pressed)
        setupFormCard()
        mainStack.addArrangedSubview(formCardBox)
        formCardBox.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        formCardBox.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        separator.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // 4. Active Mappings Header
        let currentHeader = NSTextField(labelWithString: "Active Mappings")
        currentHeader.font = NSFont.boldSystemFont(ofSize: 13)
        currentHeader.alignment = .center
        mainStack.addArrangedSubview(currentHeader)
        currentHeader.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        currentHeader.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // Scroll view / Container for Mappings
        mappingsStackView = NSStackView()
        mappingsStackView.orientation = .vertical
        mappingsStackView.alignment = .centerX
        mappingsStackView.spacing = 8
        mappingsStackView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = mappingsStackView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(scrollView)
        scrollView.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        scrollView.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        // Pin document view width
        mappingsStackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor).isActive = true
        mappingsStackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor).isActive = true
    }

    func setupFormCard() {
        formCardBox = NSBox()
        formCardBox.boxType = .custom
        formCardBox.borderColor = .separatorColor
        formCardBox.borderWidth = 1
        formCardBox.cornerRadius = 8
        formCardBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        formCardBox.translatesAutoresizingMaskIntoConstraints = false
        formCardBox.isHidden = true // hidden initially

        let formStack = NSStackView()
        formStack.orientation = .vertical
        formStack.alignment = .centerX
        formStack.spacing = 10
        formStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        formStack.translatesAutoresizingMaskIntoConstraints = false

        formTitleLabel = NSTextField(labelWithString: "New Shortcut Entry")
        formTitleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        formTitleLabel.alignment = .center
        formStack.addArrangedSubview(formTitleLabel)

        // Row 1: Mouse Button
        let mouseRow = NSStackView()
        mouseRow.orientation = .horizontal
        mouseRow.spacing = 10
        mouseRow.alignment = .centerY

        recordMouseBtn = NSButton(title: "🎙️ Record Mouse Button", target: self, action: #selector(startRecordingMouseButton))
        recordMouseBtn.bezelStyle = .rounded
        mouseRow.addArrangedSubview(recordMouseBtn)

        cancelMouseBtn = NSButton(title: "Cancel (Esc)", target: self, action: #selector(cancelRecordingMouseButton))
        cancelMouseBtn.bezelStyle = .rounded
        cancelMouseBtn.isHidden = true
        mouseRow.addArrangedSubview(cancelMouseBtn)

        mouseStatusLabel = NSTextField(labelWithString: "No button set")
        mouseStatusLabel.font = NSFont.systemFont(ofSize: 12)
        mouseStatusLabel.textColor = .secondaryLabelColor
        mouseRow.addArrangedSubview(mouseStatusLabel)

        formStack.addArrangedSubview(mouseRow)

        // Row 2: Keystroke Shortcut
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 10
        shortcutRow.alignment = .centerY

        recordShortcutBtn = NSButton(title: "⌨️ Record Shortcut", target: self, action: #selector(startRecordingShortcut))
        recordShortcutBtn.bezelStyle = .rounded
        shortcutRow.addArrangedSubview(recordShortcutBtn)

        cancelShortcutBtn = NSButton(title: "Cancel (Esc)", target: self, action: #selector(cancelShortcutRecording))
        cancelShortcutBtn.bezelStyle = .rounded
        cancelShortcutBtn.isHidden = true
        shortcutRow.addArrangedSubview(cancelShortcutBtn)

        shortcutStatusLabel = NSTextField(labelWithString: "No shortcut set")
        shortcutStatusLabel.font = NSFont.systemFont(ofSize: 12)
        shortcutStatusLabel.textColor = .secondaryLabelColor
        shortcutRow.addArrangedSubview(shortcutStatusLabel)

        formStack.addArrangedSubview(shortcutRow)

        // Row 3: Action Buttons (Save & Cancel)
        let actionsRow = NSStackView()
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 12
        actionsRow.alignment = .centerY

        saveEntryBtn = NSButton(title: "Save Mapping", target: self, action: #selector(saveCurrentFormEntry))
        saveEntryBtn.bezelStyle = .rounded
        saveEntryBtn.isEnabled = false
        actionsRow.addArrangedSubview(saveEntryBtn)

        cancelEntryBtn = NSButton(title: "Close Editor", target: self, action: #selector(closeFormEditor))
        cancelEntryBtn.bezelStyle = .rounded
        actionsRow.addArrangedSubview(cancelEntryBtn)

        formStack.addArrangedSubview(actionsRow)

        formCardBox.contentView = formStack
    }

    // MARK: - Form Actions
    @objc func startNewMapping() {
        editingMappingID = nil
        draftButtonNumber = nil
        draftKeyCode = nil
        draftModifierFlags = nil
        draftShortcutDisplay = nil

        formTitleLabel.stringValue = "New Shortcut Entry"
        mouseStatusLabel.stringValue = "Click 'Record Mouse Button'"
        mouseStatusLabel.textColor = .secondaryLabelColor
        shortcutStatusLabel.stringValue = "Click 'Record Shortcut'"
        shortcutStatusLabel.textColor = .secondaryLabelColor

        saveEntryBtn.isEnabled = false
        formCardBox.isHidden = false
        addNewButton.isHidden = true
    }

    @objc func closeFormEditor() {
        cancelRecordingMouseButton()
        cancelShortcutRecording()
        formCardBox.isHidden = true
        addNewButton.isHidden = false
    }

    func openEditor(for mapping: ButtonMapping) {
        editingMappingID = mapping.id
        draftButtonNumber = mapping.buttonNumber
        draftKeyCode = mapping.keyCode
        draftModifierFlags = mapping.modifierFlags
        draftShortcutDisplay = mapping.displayString

        let name = (mapping.buttonNumber == 2) ? "Middle Button (2)" : "Button \(mapping.buttonNumber)"
        formTitleLabel.stringValue = "Editing: \(name)  ➔  \(mapping.displayString)"
        mouseStatusLabel.stringValue = "✅ \(name)"
        mouseStatusLabel.textColor = .systemGreen
        shortcutStatusLabel.stringValue = "✅ \(mapping.displayString)"
        shortcutStatusLabel.textColor = .systemGreen

        saveEntryBtn.isEnabled = true
        formCardBox.isHidden = false
        addNewButton.isHidden = true
    }

    func updateSaveButtonState() {
        let hasButton = (draftButtonNumber != nil)
        let hasShortcut = (draftKeyCode != nil && draftShortcutDisplay != nil)
        saveEntryBtn.isEnabled = hasButton && hasShortcut
    }

    @objc func saveCurrentFormEntry() {
        guard let btn = draftButtonNumber,
              let code = draftKeyCode,
              let flags = draftModifierFlags,
              let display = draftShortcutDisplay else { return }

        let mapping = ButtonMapping(
            id: editingMappingID ?? UUID().uuidString,
            buttonNumber: btn,
            keyCode: code,
            modifierFlags: flags,
            displayString: display
        )

        ConfigManager.shared.addOrUpdateMapping(mapping)
        closeFormEditor()
    }

    // MARK: - Mouse Button Recording
    @objc func startRecordingMouseButton() {
        cancelShortcutRecording()

        let options = ["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            updatePermissionStatus()
            return
        }

        EventTapManager.shared.updateTap()

        ConfigManager.shared.isRecordingMouse = true
        recordMouseBtn.title = "Listening..."
        recordMouseBtn.isEnabled = false
        cancelMouseBtn.isHidden = false
        mouseStatusLabel.stringValue = "👉 Click mouse button (Esc cancels)..."
        mouseStatusLabel.textColor = .systemBlue

        setupKeyEscMonitorForMouse()
        setupMouseMonitors()

        ConfigManager.shared.onButtonRecorded = { [weak self] button in
            guard let self = self else { return }
            self.finishRecordingMouseButton(button: button)
        }
    }

    func finishRecordingMouseButton(button: Int64) {
        removeKeyMonitors()
        removeMouseMonitors()
        ConfigManager.shared.isRecordingMouse = false
        ConfigManager.shared.onButtonRecorded = nil
        self.draftButtonNumber = button

        let name = (button == 2) ? "Middle Button (2)" : "Button \(button)"
        self.recordMouseBtn.title = "🎙️ Record Mouse Button"
        self.recordMouseBtn.isEnabled = true
        self.cancelMouseBtn.isHidden = true
        self.mouseStatusLabel.stringValue = "✅ \(name)"
        self.mouseStatusLabel.textColor = .systemGreen

        updateSaveButtonState()
    }

    @objc func cancelRecordingMouseButton() {
        guard ConfigManager.shared.isRecordingMouse else { return }
        removeKeyMonitors()
        removeMouseMonitors()
        ConfigManager.shared.isRecordingMouse = false
        ConfigManager.shared.onButtonRecorded = nil
        recordMouseBtn.title = "🎙️ Record Mouse Button"
        recordMouseBtn.isEnabled = true
        cancelMouseBtn.isHidden = true
        if let btn = draftButtonNumber {
            let name = (btn == 2) ? "Middle Button (2)" : "Button \(btn)"
            mouseStatusLabel.stringValue = "✅ \(name)"
            mouseStatusLabel.textColor = .systemGreen
        } else {
            mouseStatusLabel.stringValue = "No button set"
            mouseStatusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Keyboard Shortcut Recording
    @objc func startRecordingShortcut() {
        cancelRecordingMouseButton()

        isRecordingShortcut = true
        recordShortcutBtn.title = "Press keys..."
        recordShortcutBtn.isEnabled = false
        cancelShortcutBtn.isHidden = false
        shortcutStatusLabel.stringValue = "👉 Press shortcut keys (e.g. ⌘ `)..."
        shortcutStatusLabel.textColor = .systemBlue

        setupShortcutKeyMonitor()
    }

    func setupShortcutKeyMonitor() {
        removeKeyMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isRecordingShortcut else { return event }

            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

            // If user pressed Esc alone without modifiers, cancel recording
            if keyCode == 53 && flags.isEmpty {
                self.cancelShortcutRecording()
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

            self.finishShortcutRecording(keyCode: keyCode, modifierFlags: cgFlags.rawValue, displayString: fullDisplay)
            return nil
        }
    }

    func finishShortcutRecording(keyCode: UInt16, modifierFlags: UInt64, displayString: String) {
        removeKeyMonitors()
        isRecordingShortcut = false

        self.draftKeyCode = keyCode
        self.draftModifierFlags = modifierFlags
        self.draftShortcutDisplay = displayString

        self.recordShortcutBtn.title = "⌨️ Record Shortcut"
        self.recordShortcutBtn.isEnabled = true
        self.cancelShortcutBtn.isHidden = true
        self.shortcutStatusLabel.stringValue = "✅ \(displayString)"
        self.shortcutStatusLabel.textColor = .systemGreen

        updateSaveButtonState()
    }

    @objc func cancelShortcutRecording() {
        guard isRecordingShortcut else { return }
        removeKeyMonitors()
        isRecordingShortcut = false
        recordShortcutBtn.title = "⌨️ Record Shortcut"
        recordShortcutBtn.isEnabled = true
        cancelShortcutBtn.isHidden = true

        if let display = draftShortcutDisplay {
            shortcutStatusLabel.stringValue = "✅ \(display)"
            shortcutStatusLabel.textColor = .systemGreen
        } else {
            shortcutStatusLabel.stringValue = "No shortcut set"
            shortcutStatusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Monitors
    func setupKeyEscMonitorForMouse() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelRecordingMouseButton()
                return nil
            }
            return event
        }
    }

    func setupMouseMonitors() {
        removeMouseMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard ConfigManager.shared.isRecordingMouse else { return }
                self?.finishRecordingMouseButton(button: Int64(event.buttonNumber))
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard ConfigManager.shared.isRecordingMouse else { return }
                self?.finishRecordingMouseButton(button: Int64(event.buttonNumber))
            }
            return nil
        }
    }

    func removeKeyMonitors() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }

    func removeMouseMonitors() {
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        cancelRecordingMouseButton()
        cancelShortcutRecording()
    }

    // MARK: - Mappings List View
    func reloadMappingsList() {
        guard mappingsStackView != nil else { return }

        mappingsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if ConfigManager.shared.mappings.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No mappings configured yet. Click '＋ New Mapping' above.")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.alignment = .center
            mappingsStackView.addArrangedSubview(emptyLabel)
            emptyLabel.leadingAnchor.constraint(equalTo: mappingsStackView.leadingAnchor).isActive = true
            emptyLabel.trailingAnchor.constraint(equalTo: mappingsStackView.trailingAnchor).isActive = true
            return
        }

        for mapping in ConfigManager.shared.mappings.sorted(by: { $0.buttonNumber < $1.buttonNumber }) {
            let cardBox = NSBox()
            cardBox.boxType = .custom
            cardBox.borderColor = .separatorColor
            cardBox.borderWidth = 1
            cardBox.cornerRadius = 6
            cardBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
            cardBox.translatesAutoresizingMaskIntoConstraints = false

            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            row.translatesAutoresizingMaskIntoConstraints = false

            let btnName = (mapping.buttonNumber == 2) ? "Middle Button (2)" : "Button \(mapping.buttonNumber)"
            let label = NSTextField(labelWithString: "• \(btnName)  ➔  \(mapping.displayString)")
            label.font = NSFont.boldSystemFont(ofSize: 12)
            row.addArrangedSubview(label)

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)

            // Redo Button option
            let redoBtn = NSButton(title: "Edit / Redo", target: self, action: #selector(editMappingClicked(_:)))
            redoBtn.bezelStyle = .inline
            redoBtn.identifier = NSUserInterfaceItemIdentifier(mapping.id)
            row.addArrangedSubview(redoBtn)

            // Delete button
            let deleteBtn = NSButton(title: "Remove", target: self, action: #selector(deleteMappingClicked(_:)))
            deleteBtn.bezelStyle = .inline
            deleteBtn.identifier = NSUserInterfaceItemIdentifier(mapping.id)
            row.addArrangedSubview(deleteBtn)

            cardBox.contentView = row
            mappingsStackView.addArrangedSubview(cardBox)

            cardBox.leadingAnchor.constraint(equalTo: mappingsStackView.leadingAnchor).isActive = true
            cardBox.trailingAnchor.constraint(equalTo: mappingsStackView.trailingAnchor).isActive = true
        }
    }

    @objc func editMappingClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let mapping = ConfigManager.shared.mappings.first(where: { $0.id == id }) else { return }
        openEditor(for: mapping)
    }

    @objc func deleteMappingClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        ConfigManager.shared.removeMapping(id: id)
    }

    func updatePermissionStatus() {
        let trusted = AXIsProcessTrusted()
        permissionWarningLabel.isHidden = trusted
        openSettingsButton.isHidden = trusted
        restartButton.isHidden = trusted
        if trusted {
            EventTapManager.shared.updateTap()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updatePermissionStatus()
    }

    @objc func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updatePermissionStatus()
    }
}

// MARK: - App Delegate (Menu Bar GUI)
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var enabledMenuItem: NSMenuItem!
    var launchAtLoginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ethanclawsie.mousebutton"
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if instances.count > 1 {
            NSLog("[mousebutton] Another instance is already running (%d instances found). Exiting.", instances.count)
            NSApp.terminate(nil)
            return
        }

        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        EventTapManager.shared.updateTap()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "mousebutton") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "🖱️"
            }
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Title
        let titleItem = NSMenuItem(title: "mousebutton", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let font = NSFont.boldSystemFont(ofSize: 13) as NSFont? {
            titleItem.attributedTitle = NSAttributedString(string: "mousebutton", attributes: [.font: font])
        }
        menu.addItem(titleItem)

        // Enabled toggle
        enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledMenuItem.target = self
        enabledMenuItem.state = ConfigManager.shared.isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Map Button / Configure option
        let configItem = NSMenuItem(title: "Configure Mappings…", action: #selector(openConfigWindow), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(NSMenuItem.separator())

        // Current active mappings display
        if ConfigManager.shared.mappings.isEmpty {
            let item = NSMenuItem(title: "No buttons mapped", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for mapping in ConfigManager.shared.mappings.sorted(by: { $0.buttonNumber < $1.buttonNumber }) {
                let name = (mapping.buttonNumber == 2) ? "Middle" : "Button \(mapping.buttonNumber)"
                let item = NSMenuItem(title: "\(name)  →  \(mapping.displayString)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Launch at login via modern SMAppService
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit mousebutton", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func openConfigWindow() {
        if SettingsWindowController.shared == nil {
            SettingsWindowController.shared = SettingsWindowController()
        }
        SettingsWindowController.shared?.showWindow()
    }

    @objc func toggleEnabled() {
        ConfigManager.shared.isEnabled.toggle()
        enabledMenuItem.state = ConfigManager.shared.isEnabled ? .on : .off
        if let button = statusItem.button {
            button.appearsDisabled = !ConfigManager.shared.isEnabled
        }
    }

    func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    @objc func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            launchAtLoginMenuItem.state = .off
        } else {
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } catch {
                NSLog("[mousebutton] Failed to register launch at login: %@", error.localizedDescription)
            }
            launchAtLoginMenuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
