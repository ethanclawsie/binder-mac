import Cocoa
import CoreGraphics
import ApplicationServices
import ServiceManagement

// MARK: - Constants & Key Codes
private let kDefaultKeyCode: CGKeyCode = 0x32 // Grave/Tilde `~` (kVK_ANSI_Grave)
private let kUserDefaultsKey = "savedButtonMappings"

// MARK: - Action Types
enum ActionType: String, CaseIterable, Codable {
    case nextWindow = "Next Window of Same App (⌘ `)"
    case prevWindow = "Previous Window of Same App (⌘ ⇧ `)"

    var description: String {
        return self.rawValue
    }
}

// MARK: - Configuration Manager (with Persistence)
class ConfigManager {
    static let shared = ConfigManager()

    var isEnabled: Bool = true
    var isRecording: Bool = false
    var onButtonRecorded: ((Int64) -> Void)?
    private var isInitialized = false

    // buttonNumber -> ActionType
    var mappings: [Int64: ActionType] = [:] {
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
        if let data = UserDefaults.standard.dictionary(forKey: kUserDefaultsKey) as? [String: String] {
            var loaded: [Int64: ActionType] = [:]
            for (btnStr, actionStr) in data {
                if let btn = Int64(btnStr), let action = ActionType(rawValue: actionStr) {
                    loaded[btn] = action
                }
            }
            if !loaded.isEmpty {
                self.mappings = loaded
                return
            }
        }
        // Defaults: Button 4 -> Next Window
        self.mappings = [
            4: .nextWindow
        ]
    }

    func saveMappings() {
        var dict: [String: String] = [:]
        for (btn, action) in mappings {
            dict[String(btn)] = action.rawValue
        }
        UserDefaults.standard.set(dict, forKey: kUserDefaultsKey)
    }

    func setMapping(button: Int64, action: ActionType) {
        mappings[button] = action
    }

    func removeMapping(button: Int64) {
        mappings.removeValue(forKey: button)
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

// MARK: - Event Tap Manager (Mirroring CopyShelf's .cgSessionEventTap approach)
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

        // Using .cgSessionEventTap at .headInsertEventTap exactly like CopyShelf
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventCallback,
            userInfo: nil
        ) else {
            NSLog("[mousebutton] Failed to create CGEventTap. Ensure Accessibility is enabled.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = runLoopSource
        self.isListening = true
        NSLog("[mousebutton] .cgSessionEventTap successfully installed and active.")
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

    // RECORDING MODE: user clicked a button while app is listening
    if ConfigManager.shared.isRecording {
        if type == .otherMouseDown {
            DispatchQueue.main.async {
                ConfigManager.shared.onButtonRecorded?(buttonNumber)
            }
        }
        return nil // swallow event
    }

    guard ConfigManager.shared.isEnabled else {
        return Unmanaged.passUnretained(event)
    }

    // Check if this button is mapped
    guard let action = ConfigManager.shared.mappings[buttonNumber] else {
        // Pass through to other apps (e.g. CopyShelf or browser)
        return Unmanaged.passUnretained(event)
    }

    if type == .otherMouseDown {
        let currentFlags = event.flags
        let shiftHeld = currentFlags.contains(.maskShift)

        switch action {
        case .nextWindow:
            if shiftHeld {
                sendKeystroke(virtualKey: kDefaultKeyCode, flags: [.maskCommand, .maskShift])
            } else {
                sendKeystroke(virtualKey: kDefaultKeyCode, flags: [.maskCommand])
            }
        case .prevWindow:
            sendKeystroke(virtualKey: kDefaultKeyCode, flags: [.maskCommand, .maskShift])
        }
    }

    // Swallow mouse down and mouse up for mapped buttons
    return nil
}

// MARK: - Settings / Mapping Window Controller
class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    var recordButton: NSButton!
    var cancelButton: NSButton!
    var statusLabel: NSTextField!
    var permissionWarningLabel: NSTextField!
    var openSettingsButton: NSButton!
    var restartButton: NSButton!
    var actionPopup: NSPopUpButton!
    var saveButton: NSButton!
    var recordedButtonNumber: Int64?

    var localKeyMonitor: Any?
    var globalKeyMonitor: Any?
    var localMouseMonitor: Any?
    var globalMouseMonitor: Any?
    var mappingsStackView: NSStackView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "mousebutton Mappings"
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
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])

        // 1. Header (Centered)
        let header = NSTextField(labelWithString: "Configure Mouse Button")
        header.font = NSFont.boldSystemFont(ofSize: 15)
        header.alignment = .center
        mainStack.addArrangedSubview(header)
        header.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        header.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        let desc = NSTextField(labelWithString: "Click Record below, then press your mouse button to bind it.")
        desc.textColor = .secondaryLabelColor
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.alignment = .center
        mainStack.addArrangedSubview(desc)
        desc.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        desc.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // Permission warning row (hidden when trusted, Centered)
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

        // 2. Recording row (Centered)
        let recordRow = NSStackView()
        recordRow.orientation = .horizontal
        recordRow.spacing = 10
        recordRow.alignment = .centerY

        recordButton = NSButton(title: "🎙️ Record Mouse Button", target: self, action: #selector(startRecording))
        recordButton.bezelStyle = .rounded
        recordRow.addArrangedSubview(recordButton)

        cancelButton = NSButton(title: "Cancel (Esc)", target: self, action: #selector(cancelRecording))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Esc key
        cancelButton.isHidden = true
        recordRow.addArrangedSubview(cancelButton)

        mainStack.addArrangedSubview(recordRow)

        // Status Label (Centered underneath Record button)
        statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        mainStack.addArrangedSubview(statusLabel)
        statusLabel.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        statusLabel.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // 3. Action selection row (Centered)
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.alignment = .centerY

        let mapToLabel = NSTextField(labelWithString: "Map to:")
        mapToLabel.font = NSFont.systemFont(ofSize: 12)
        actionRow.addArrangedSubview(mapToLabel)

        actionPopup = NSPopUpButton()
        actionPopup.addItems(withTitles: ActionType.allCases.map { $0.description })
        actionPopup.isEnabled = false
        actionRow.addArrangedSubview(actionPopup)

        saveButton = NSButton(title: "Save Mapping", target: self, action: #selector(saveMapping))
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = false
        actionRow.addArrangedSubview(saveButton)

        mainStack.addArrangedSubview(actionRow)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        separator.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // 4. Current Mappings Header (Centered)
        let currentHeader = NSTextField(labelWithString: "Active Mappings:")
        currentHeader.font = NSFont.boldSystemFont(ofSize: 13)
        currentHeader.alignment = .center
        mainStack.addArrangedSubview(currentHeader)
        currentHeader.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        currentHeader.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true

        // Mappings container
        mappingsStackView = NSStackView()
        mappingsStackView.orientation = .vertical
        mappingsStackView.alignment = .centerX
        mappingsStackView.spacing = 8
        mappingsStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(mappingsStackView)
        mappingsStackView.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor).isActive = true
        mappingsStackView.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor).isActive = true
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

    @objc func startRecording() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        updatePermissionStatus()

        if !isTrusted {
            statusLabel.stringValue = "Grant Accessibility in System Settings, then try again."
            statusLabel.textColor = .systemRed
            return
        }

        EventTapManager.shared.updateTap()

        ConfigManager.shared.isRecording = true
        recordButton.title = "Listening..."
        recordButton.isEnabled = false
        cancelButton.isHidden = false
        statusLabel.stringValue = "👉 Click your mouse button now (or press Esc)..."
        statusLabel.textColor = .systemBlue
        saveButton.isEnabled = false
        actionPopup.isEnabled = false

        setupKeyMonitors()
        setupMouseMonitors()

        ConfigManager.shared.onButtonRecorded = { [weak self] button in
            guard let self = self else { return }
            self.finishRecording(button: button)
        }
    }

    func finishRecording(button: Int64) {
        guard ConfigManager.shared.isRecording else { return }
        removeKeyMonitors()
        removeMouseMonitors()
        ConfigManager.shared.isRecording = false
        ConfigManager.shared.onButtonRecorded = nil
        self.recordedButtonNumber = button

        self.recordButton.title = "🎙️ Record Mouse Button"
        self.recordButton.isEnabled = true
        self.cancelButton.isHidden = true
        let name = (button == 2) ? "Middle Button (Button 2)" : "Button \(button)"
        self.statusLabel.stringValue = "✅ Detected: \(name)"
        self.statusLabel.textColor = .systemGreen
        self.actionPopup.isEnabled = true
        self.saveButton.isEnabled = true
    }

    @objc func cancelRecording() {
        guard ConfigManager.shared.isRecording else { return }
        removeKeyMonitors()
        removeMouseMonitors()
        ConfigManager.shared.isRecording = false
        ConfigManager.shared.onButtonRecorded = nil
        recordButton.title = "🎙️ Record Mouse Button"
        recordButton.isEnabled = true
        cancelButton.isHidden = true
        statusLabel.stringValue = "Listening cancelled."
        statusLabel.textColor = .secondaryLabelColor
    }

    func setupKeyMonitors() {
        removeKeyMonitors()

        // Local monitor (when window has focus)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.cancelRecording()
                return nil
            }
            return event
        }

        // Global monitor (in case clicked outside before pressing Escape)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self?.cancelRecording()
                }
            }
        }
    }

    func setupMouseMonitors() {
        removeMouseMonitors()

        // Dual capture: NSEvent monitor also listens as a backup alongside the CGEventTap
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard ConfigManager.shared.isRecording else { return }
                self?.finishRecording(button: Int64(event.buttonNumber))
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                guard ConfigManager.shared.isRecording else { return }
                self?.finishRecording(button: Int64(event.buttonNumber))
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
        cancelRecording()
    }

    @objc func saveMapping() {
        guard let button = recordedButtonNumber else { return }
        let selectedIndex = actionPopup.indexOfSelectedItem
        let chosenAction = ActionType.allCases[selectedIndex]

        ConfigManager.shared.setMapping(button: button, action: chosenAction)

        statusLabel.stringValue = "Saved Button \(button)!"
        statusLabel.textColor = .secondaryLabelColor
        saveButton.isEnabled = false
        actionPopup.isEnabled = false
        recordedButtonNumber = nil

        reloadMappingsList()
    }

    func reloadMappingsList() {
        guard mappingsStackView != nil else { return }

        mappingsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if ConfigManager.shared.mappings.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No mappings configured yet.")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.alignment = .center
            mappingsStackView.addArrangedSubview(emptyLabel)
            emptyLabel.leadingAnchor.constraint(equalTo: mappingsStackView.leadingAnchor).isActive = true
            emptyLabel.trailingAnchor.constraint(equalTo: mappingsStackView.trailingAnchor).isActive = true
            return
        }

        for (button, action) in ConfigManager.shared.mappings.sorted(by: { $0.key < $1.key }) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let name = (button == 2) ? "Middle Button (Button 2)" : "Button \(button)"
            let label = NSTextField(labelWithString: "• \(name): \(action.description)")
            label.font = NSFont.systemFont(ofSize: 12)
            row.addArrangedSubview(label)

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(spacer)

            let deleteBtn = NSButton(title: "Remove", target: self, action: #selector(deleteMappingClicked(_:)))
            deleteBtn.bezelStyle = .inline
            deleteBtn.tag = Int(button)
            row.addArrangedSubview(deleteBtn)

            mappingsStackView.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: mappingsStackView.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: mappingsStackView.trailingAnchor).isActive = true
        }
    }

    @objc func deleteMappingClicked(_ sender: NSButton) {
        let button = Int64(sender.tag)
        ConfigManager.shared.removeMapping(button: button)
        reloadMappingsList()
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
        // Enforce single instance across the system
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
            for (button, action) in ConfigManager.shared.mappings.sorted(by: { $0.key < $1.key }) {
                let name = (button == 2) ? "Middle" : "Button \(button)"
                let shortcut = (action == .nextWindow) ? "⌘ `" : "⌘ ⇧ `"
                let item = NSMenuItem(title: "\(name)  →  \(action == .nextWindow ? "Next Window" : "Prev Window") (\(shortcut))", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Launch at login via modern SMAppService (matching CopyShelf)
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        // Accessibility settings
        let accessItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessItem.target = self
        menu.addItem(accessItem)

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

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
