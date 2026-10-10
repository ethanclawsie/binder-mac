import SwiftUI

struct SettingsView: View {
    @Bindable var store = MappingStore.shared
    @Bindable var eventTap = EventTapManager.shared
    @Bindable var recorder = RecordingCoordinator.shared

    @State private var isCreatingNew = false
    @State private var draftButton: Int64?
    @State private var draftKeyCode: UInt16?
    @State private var draftFlags: UInt64?
    @State private var draftDisplay: String?

    var body: some View {
        VStack(spacing: 16) {
            // 1. Header (Centered)
            VStack(spacing: 4) {
                Text("Configure Mouse Shortcuts")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Map any mouse button to any keyboard shortcut combination.")
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
                    Text("Accessibility permission required to detect mouse buttons.")
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

            // 2. Add New Mapping Button or Form
            if !isCreatingNew {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = true
                        draftButton = nil
                        draftKeyCode = nil
                        draftFlags = nil
                        draftDisplay = nil
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

            // 3. Active Mappings Section
            VStack(spacing: 8) {
                Text("Active Mappings")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if store.mappings.isEmpty {
                    Text("No mappings configured yet. Click '＋ New Mapping' above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.mappings.sorted(by: { $0.buttonNumber < $1.buttonNumber })) { mapping in
                                mappingRow(for: mapping)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                }
            }

            // 4. Live Button Tester
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(eventTap.lastDetectedButton == nil ? Color.secondary : Color.blue)
                    .font(.caption)

                if let btn = eventTap.lastDetectedButton {
                    Text("Detected: \(mouseButtonDisplayName(for: btn))")
                        .font(.caption)
                        .fontWeight(.semibold)

                    if let mapping = store.lookup[btn] {
                        Text("➔  Triggers \(mapping.displayString)")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .fontWeight(.bold)
                    } else {
                        Text("(Unmapped)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Click any mouse button to test detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            )

            Spacer(minLength: 0)

            Divider()

            // 5. Footer controls
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
        .frame(width: 530, height: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            eventTap.checkPermission()
        }
    }

    // MARK: - New Mapping Card Form
    private var newMappingCard: some View {
        VStack(spacing: 12) {
            Text("New Shortcut Entry")
                .font(.subheadline)
                .fontWeight(.bold)

            // Mouse button row
            HStack(spacing: 12) {
                Button {
                    recorder.startRecordingMouse(.newMouseButton) { button in
                        draftButton = button
                    }
                } label: {
                    if recorder.target == .newMouseButton {
                        Label("Click mouse button... (Esc)", systemImage: "computermouse")
                            .foregroundStyle(.blue)
                    } else if let btn = draftButton {
                        Label(mouseButtonDisplayName(for: btn), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Record Mouse Button", systemImage: "computermouse")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if recorder.target == .newMouseButton {
                    Button("Cancel") {
                        recorder.cancel()
                    }
                    .controlSize(.small)
                }
            }

            // Keyboard shortcut row
            HStack(spacing: 12) {
                Button {
                    recorder.startRecordingShortcut(.newShortcut) { code, flags, display in
                        draftKeyCode = code
                        draftFlags = flags
                        draftDisplay = display
                    }
                } label: {
                    if recorder.target == .newShortcut {
                        Label("Press keys... (Esc)", systemImage: "keyboard")
                            .foregroundStyle(.blue)
                    } else if let disp = draftDisplay {
                        Label(disp, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Record Shortcut", systemImage: "keyboard")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                if recorder.target == .newShortcut {
                    Button("Cancel") {
                        recorder.cancel()
                    }
                    .controlSize(.small)
                }
            }

            // Action row (Save / Close)
            HStack(spacing: 14) {
                Button("Save Mapping") {
                    guard let btn = draftButton,
                          let code = draftKeyCode,
                          let flags = draftFlags,
                          let disp = draftDisplay else { return }

                    let newMapping = ButtonMapping(
                        buttonNumber: btn,
                        keyCode: code,
                        modifierFlags: flags,
                        displayString: disp
                    )
                    store.addOrUpdate(newMapping)

                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = false
                        draftButton = nil
                        draftKeyCode = nil
                        draftFlags = nil
                        draftDisplay = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(draftButton == nil || draftDisplay == nil)

                Button("Cancel") {
                    recorder.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreatingNew = false
                        draftButton = nil
                        draftKeyCode = nil
                        draftFlags = nil
                        draftDisplay = nil
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
    private func mappingRow(for mapping: ButtonMapping) -> some View {
        HStack(spacing: 10) {
            // Button name & Shortcut indicator
            HStack(spacing: 8) {
                Text(mouseButtonDisplayName(for: mapping.buttonNumber))
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(mapping.displayString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.08))
                    )
            }

            Spacer()

            // Inline Redo Mouse
            Button {
                if recorder.target == .redoMouseButton(mappingID: mapping.id) {
                    recorder.cancel()
                } else {
                    recorder.startRecordingMouse(.redoMouseButton(mappingID: mapping.id)) { newButton in
                        store.updateButton(id: mapping.id, newButton: newButton)
                    }
                }
            } label: {
                if recorder.target == .redoMouseButton(mappingID: mapping.id) {
                    Text("Click button... [Esc]")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                } else {
                    Text("Redo Mouse")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Inline Redo Keys
            Button {
                if recorder.target == .redoShortcut(mappingID: mapping.id) {
                    recorder.cancel()
                } else {
                    recorder.startRecordingShortcut(.redoShortcut(mappingID: mapping.id)) { code, flags, display in
                        store.updateShortcut(id: mapping.id, keyCode: code, modifierFlags: flags, displayString: display)
                    }
                }
            } label: {
                if recorder.target == .redoShortcut(mappingID: mapping.id) {
                    Text("Press keys... [Esc]")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                } else {
                    Text("Redo Keys")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

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
                            (recorder.target == .redoMouseButton(mappingID: mapping.id) ||
                             recorder.target == .redoShortcut(mappingID: mapping.id))
                            ? Color.blue.opacity(0.5)
                            : Color.secondary.opacity(0.15),
                            lineWidth: 1
                        )
                )
        )
    }
}
