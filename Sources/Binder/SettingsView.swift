import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store = MappingStore.shared
    @Bindable var eventTap = EventTapManager.shared
    @Bindable var recorder = RecordingCoordinator.shared

    @State private var isCreatingNew = false
    @State private var triggerMode: TriggerType = .mouse
    @State private var warningMessage: String?

    // Trigger state
    @State private var draftTriggerButton: Int64?
    @State private var draftTriggerKeyCode: UInt16?
    @State private var draftTriggerFlags: UInt64?
    @State private var draftTriggerDisplay: String?

    // Target action state
    @State private var draftTargetKeyCode: UInt16?
    @State private var draftTargetFlags: UInt64?
    @State private var draftTargetDisplay: String?

    // App scope (nil = Global)
    @State private var draftAppID: String?
    @State private var draftAppName: String?
    @State private var selectedApp: String?
    @State private var isDraftPassThrough = false

    private var isIdenticalKeyMapping: Bool {
        guard !isDraftPassThrough,
              triggerMode == .key,
              let tCode = draftTriggerKeyCode,
              let aCode = draftTargetKeyCode else { return false }
        let tFlags = draftTriggerFlags ?? 0
        let aFlags = draftTargetFlags ?? 0
        return keyLookupHash(keyCode: tCode, modifierFlags: tFlags) == keyLookupHash(keyCode: aCode, modifierFlags: aFlags)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1. Header (Centered)
            VStack(spacing: 4) {
                Text("Configure Binder")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Map any mouse button or key to any keyboard shortcut.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 16)

            // Permission alert if needed
            if !eventTap.isTrusted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Accessibility permission required to detect mouse and key events.")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Open Settings") {
                        EventTapManager.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
            }

            // Warning alert if any
            if let warning = warningMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        warningMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }

            // 2. Add New Mapping Button or Form
            if !isCreatingNew {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = true
                        triggerMode = .mouse
                        resetDrafts()
                    }
                } label: {
                    Label("New Mapping", systemImage: "plus")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                newMappingCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            Divider()

            // 3. Global Mappings + App Overrides
            ScrollView {
                VStack(spacing: 8) {
                    Text("Global Mappings")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    let global = store.mappings.filter { $0.appBundleID == nil }
                    if global.isEmpty {
                        Text("No global mappings yet. Click '＋ New Mapping' above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(global) { mapping in
                            mappingRow(for: mapping)
                        }
                    }

                    let apps = store.overrideApps
                    if !apps.isEmpty {
                        appOverridesSection(apps)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // 4. Footer controls
            HStack {
                Toggle("Enabled", isOn: $store.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Spacer()

                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { LaunchAtLogin.set($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(width: 530, height: 640)
    }

    // MARK: - App Overrides Section
    @ViewBuilder
    private func appOverridesSection(_ apps: [ShortcutMapping]) -> some View {
        let current = apps.first(where: { $0.appBundleID == selectedApp }) ?? apps[0]

        Divider()
            .padding(.vertical, 6)

        HStack(spacing: 8) {
            Text("App Overrides")
                .font(.subheadline)
                .fontWeight(.semibold)

            Menu(current.appName ?? current.appBundleID ?? "") {
                ForEach(apps) { app in
                    appItem(app.appName ?? app.appBundleID ?? "", url: appURL(app.appBundleID)) {
                        selectedApp = app.appBundleID
                    }
                }
            }
            .fixedSize()
        }

        ForEach(store.mappings.filter { $0.appBundleID == current.appBundleID }) { mapping in
            mappingRow(for: mapping)
        }
    }

    // MARK: - App helpers
    private var runningApps: [NSRunningApplication] {
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != ownID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        draftAppID = id
        draftAppName = url.deletingPathExtension().lastPathComponent
    }

    private func appURL(_ bundleID: String?) -> URL? {
        bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }

    /// Menu item with the app's 16pt icon.
    private func appItem(_ name: String, url: URL?, action: @escaping () -> Void) -> some View {
        let ws = NSWorkspace.shared
        let img = url.map { ws.icon(forFile: $0.path) } ?? ws.icon(for: .application)
        img.size = NSSize(width: 16, height: 16)
        return Button(action: action) {
            Label { Text(name) } icon: { Image(nsImage: img) }
                .labelStyle(.titleAndIcon)
        }
    }

    private func resetDrafts() {
        draftTriggerButton = nil
        draftTriggerKeyCode = nil
        draftTriggerFlags = nil
        draftTriggerDisplay = nil
        draftTargetKeyCode = nil
        draftTargetFlags = nil
        draftTargetDisplay = nil
        draftAppID = nil
        draftAppName = nil
        isDraftPassThrough = false
    }

    // MARK: - New Mapping Card Form
    private var newMappingCard: some View {
        VStack(spacing: 12) {
            Text("New Shortcut Entry")
                .font(.subheadline)
                .fontWeight(.bold)

            // Trigger Type Picker
            Picker("Trigger Type", selection: $triggerMode) {
                Text("🖱️ Mouse Button").tag(TriggerType.mouse)
                Text("⌨️ Keyboard Key").tag(TriggerType.key)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .onChange(of: triggerMode) { _, _ in
                recorder.cancel()
                draftTriggerButton = nil
                draftTriggerKeyCode = nil
                draftTriggerFlags = nil
                draftTriggerDisplay = nil
            }

            // Scope: Global or a specific app
            HStack(spacing: 8) {
                Text("Applies to")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu(draftAppName ?? "All Apps (Global)") {
                    Button("All Apps (Global)") {
                        draftAppID = nil
                        draftAppName = nil
                        isDraftPassThrough = false
                    }
                    Divider()
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        appItem(app.localizedName ?? app.bundleIdentifier ?? "", url: app.bundleURL) {
                            draftAppID = app.bundleIdentifier
                            draftAppName = app.localizedName ?? app.bundleIdentifier
                        }
                    }
                    Divider()
                    Button("Choose App…") {
                        chooseApp()
                    }
                }
                .fixedSize()
            }

            // Action Mode: Shortcut vs Pass-Through (for app overrides)
            if draftAppID != nil {
                Picker("Action", selection: $isDraftPassThrough) {
                    Text("Shortcut").tag(false)
                    Text("Pass Through (Native)").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
            }

            // Trigger Row
            HStack(spacing: 12) {
                if triggerMode == .mouse {
                    Button {
                        recorder.startRecordingMouse(.newMouseTrigger) { button in
                            draftTriggerButton = button
                            draftTriggerDisplay = mouseButtonDisplayName(for: button)
                        }
                    } label: {
                        if recorder.target == .newMouseTrigger {
                            Label("Click mouse button... (Esc)", systemImage: "computermouse")
                                .foregroundStyle(.blue)
                        } else if let disp = draftTriggerDisplay {
                            Label(disp, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Record Mouse Button", systemImage: "computermouse")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button {
                        recorder.startRecordingShortcut(.newKeyTrigger) { code, flags, display in
                            draftTriggerKeyCode = code
                            draftTriggerFlags = flags
                            draftTriggerDisplay = display
                        }
                    } label: {
                        if recorder.target == .newKeyTrigger {
                            Label("Press trigger key... (Esc)", systemImage: "keyboard")
                                .foregroundStyle(.blue)
                        } else if let disp = draftTriggerDisplay {
                            Label(disp, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Record Trigger Key", systemImage: "keyboard")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if recorder.target == .newMouseTrigger || recorder.target == .newKeyTrigger {
                    Button("Cancel") {
                        recorder.cancel()
                    }
                    .controlSize(.small)
                }
            }

            // Target Shortcut Row or Pass-Through Notice
            if isDraftPassThrough {
                Text("Trigger will pass through untouched to \(draftAppName ?? "this app").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                HStack(spacing: 12) {
                    Button {
                        recorder.startRecordingShortcut(.newActionShortcut) { code, flags, display in
                            draftTargetKeyCode = code
                            draftTargetFlags = flags
                            draftTargetDisplay = display
                        }
                    } label: {
                        if recorder.target == .newActionShortcut {
                            Label("Press action keys... (Esc)", systemImage: "arrowshape.turn.up.right.fill")
                                .foregroundStyle(.blue)
                        } else if let disp = draftTargetDisplay {
                            Label(disp, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Record Target Shortcut", systemImage: "arrowshape.turn.up.right.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    if recorder.target == .newActionShortcut {
                        Button("Cancel") {
                            recorder.cancel()
                        }
                        .controlSize(.small)
                    }
                }

                // Warning if trigger matches target shortcut
                if isIdenticalKeyMapping {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Trigger and action cannot be the same shortcut.")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            // Action row (Save / Cancel)
            HStack(spacing: 14) {
                Button("Save Mapping") {
                    let hasTrigger = (triggerMode == .mouse && draftTriggerButton != nil) ||
                                     (triggerMode == .key && draftTriggerKeyCode != nil)
                    guard hasTrigger else { return }

                    if !isDraftPassThrough {
                        guard !isIdenticalKeyMapping,
                              let _ = draftTargetKeyCode,
                              let _ = draftTargetFlags,
                              let _ = draftTargetDisplay else { return }
                    }

                    let newMapping = ShortcutMapping(
                        triggerType: triggerMode,
                        triggerButton: draftTriggerButton ?? 4,
                        triggerKeyCode: draftTriggerKeyCode ?? 0,
                        triggerModifierFlags: draftTriggerFlags ?? 0,
                        triggerDisplay: draftTriggerDisplay ?? "Key",
                        targetKeyCode: isDraftPassThrough ? 0 : (draftTargetKeyCode ?? 0),
                        targetModifierFlags: isDraftPassThrough ? 0 : (draftTargetFlags ?? 0),
                        targetDisplay: isDraftPassThrough ? "Pass Through" : (draftTargetDisplay ?? ""),
                        appBundleID: draftAppID,
                        appName: draftAppName,
                        isPassThrough: isDraftPassThrough
                    )
                    store.addOrUpdate(newMapping)
                    if let app = draftAppID {
                        selectedApp = app
                    }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = false
                        resetDrafts()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    (triggerMode == .mouse && draftTriggerButton == nil) ||
                    (triggerMode == .key && draftTriggerKeyCode == nil) ||
                    (!isDraftPassThrough && (draftTargetDisplay == nil || isIdenticalKeyMapping))
                )

                Button("Cancel") {
                    recorder.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = false
                        resetDrafts()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: - Mapping Row Item
    private func mappingRow(for mapping: ShortcutMapping) -> some View {
        HStack(spacing: 10) {
            // Trigger & Target display
            HStack(spacing: 8) {
                Image(systemName: mapping.triggerType == .mouse ? "computermouse.fill" : "keyboard.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(mapping.triggerDisplay)
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                if mapping.isPassThrough {
                    Text("Pass Through")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.12))
                        )
                } else {
                    Text(mapping.targetDisplay)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
            }

            Spacer()

            // Inline Redo Trigger
            Button {
                let isMouse = mapping.triggerType == .mouse
                if recorder.target == .redoTrigger(mappingID: mapping.id, isMouse: isMouse) {
                    recorder.cancel()
                } else if isMouse {
                    recorder.startRecordingMouse(.redoTrigger(mappingID: mapping.id, isMouse: true)) { newButton in
                        warningMessage = nil
                        store.updateMouseTrigger(id: mapping.id, newButton: newButton)
                    }
                } else {
                    recorder.startRecordingShortcut(.redoTrigger(mappingID: mapping.id, isMouse: false)) { code, flags, display in
                        if !mapping.isPassThrough {
                            let tHash = keyLookupHash(keyCode: code, modifierFlags: flags)
                            let aHash = keyLookupHash(keyCode: mapping.targetKeyCode, modifierFlags: mapping.targetModifierFlags)
                            if tHash == aHash {
                                NSSound.beep()
                                warningMessage = "Trigger and action cannot be the same shortcut."
                                return
                            }
                        }
                        warningMessage = nil
                        store.updateKeyTrigger(id: mapping.id, keyCode: code, modifierFlags: flags, display: display)
                    }
                }
            } label: {
                let isMouse = mapping.triggerType == .mouse
                if recorder.target == .redoTrigger(mappingID: mapping.id, isMouse: isMouse) {
                    Text(isMouse ? "Click button... [Esc]" : "Press key... [Esc]")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                } else {
                    Text("Redo Trigger")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Inline Redo Action (only if not pass-through)
            if !mapping.isPassThrough {
                Button {
                    if recorder.target == .redoAction(mappingID: mapping.id) {
                        recorder.cancel()
                    } else {
                        recorder.startRecordingShortcut(.redoAction(mappingID: mapping.id)) { code, flags, display in
                            if mapping.triggerType == .key {
                                let tHash = keyLookupHash(keyCode: mapping.triggerKeyCode, modifierFlags: mapping.triggerModifierFlags)
                                let aHash = keyLookupHash(keyCode: code, modifierFlags: flags)
                                if tHash == aHash {
                                    NSSound.beep()
                                    warningMessage = "Trigger and action cannot be the same shortcut."
                                    return
                                }
                            }
                            warningMessage = nil
                            store.updateTargetShortcut(id: mapping.id, keyCode: code, modifierFlags: flags, display: display)
                        }
                    }
                } label: {
                    if recorder.target == .redoAction(mappingID: mapping.id) {
                        Text("Press keys... [Esc]")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    } else {
                        Text("Redo Action")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Remove button
            Button {
                withAnimation {
                    store.remove(id: mapping.id)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove mapping")
            .padding(.leading, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            (recorder.target == .redoTrigger(mappingID: mapping.id, isMouse: mapping.triggerType == .mouse) ||
                             recorder.target == .redoAction(mappingID: mapping.id))
                            ? Color.blue.opacity(0.5)
                            : Color.secondary.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
    }
}
