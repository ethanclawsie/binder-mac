import AppKit
import SwiftUI

@main
struct BinderApp: App {
    @State private var store = MappingStore.shared
    @State private var eventTap = EventTapManager.shared

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ethanclawsie.Binder"
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if instances.count > 1 {
            NSLog("[Binder] Another instance is already running (%d instances found). Exiting.", instances.count)
            exit(0)
        }

        _ = MappingStore.shared
        _ = EventTapManager.shared
        EventTapManager.shared.updateTap()
    }

    var body: some Scene {
        MenuBarExtra("Binder", systemImage: "button.programmable") {
            Toggle("Enabled", isOn: $store.isEnabled)

            Button("Configure Shortcuts…") {
                SettingsWindowManager.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            if store.mappings.isEmpty {
                Text("No shortcuts mapped")
            } else {
                ForEach(store.mappings) { mapping in
                    let targetText = mapping.isPassThrough ? "Pass Through" : mapping.targetDisplay
                    Text("\(mapping.triggerDisplay)  →  \(targetText)" + (mapping.appName.map { "  (\($0))" } ?? ""))
                }
            }


            Divider()

            Button("Quit Binder") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
