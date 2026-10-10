import AppKit
import SwiftUI

@main
struct MouseButtonApp: App {
    @State private var store = MappingStore.shared
    @State private var eventTap = EventTapManager.shared

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ethanclawsie.mousebutton"
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if instances.count > 1 {
            NSLog("[mousebutton] Another instance is already running (%d instances found). Exiting.", instances.count)
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("mousebutton", systemImage: store.isEnabled ? "computermouse.fill" : "computermouse") {
            Toggle("Enabled", isOn: $store.isEnabled)

            Button("Configure Keybinds…") {
                SettingsWindowManager.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            if store.mappings.isEmpty {
                Text("No buttons mapped")
            } else {
                ForEach(store.mappings.sorted(by: { $0.buttonNumber < $1.buttonNumber })) { mapping in
                    Text("\(mouseButtonDisplayName(for: mapping.buttonNumber))  →  \(mapping.displayString)")
                }
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) }
            ))

            Divider()

            Button("Quit mousebutton") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
