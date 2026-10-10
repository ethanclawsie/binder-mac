# mousebutton 🖱️⚡

An ultra-minimal, high-performance macOS menu bar utility to map any mouse button to any keyboard shortcut (e.g. `Cmd + \`` to cycle app windows).

---

### Highlights

* **Modern SwiftUI Architecture:** Built with native SwiftUI, Swift Package Manager, and `@Observable`, mirroring modern macOS utilities like `copyshelf-mac`.
* **Menu Bar GUI:** Sits cleanly in your macOS menu bar with a native mouse icon (`computermouse.fill`) and zero Dock icon clutter (`LSUIElement = true`).
* **High Performance & Zero Bloat:**
  * Entire app bundle is **~450 KB**.
  * Consumes **~8–12 MB** of RAM (compared to 50–150 MB for multi-feature utilities).
  * **0.0% CPU** idle. Subscribes strictly to auxiliary mouse clicks via `.cgSessionEventTap`, completely ignoring mouse movement, regular left/right clicks, and scrolling.
* **Fully Customizable Shortcuts:**
  * **＋ New Mapping:** Click to create a custom mapping entry.
  * **Record Mouse Button:** Press any mouse button (Side Button 3, Button 4, Button 5, Middle click, etc.).
  * **Record Shortcut:** Press any keyboard combination (e.g. `⌘ \``, `⌘ ⇧ \``, or any custom key combo with modifiers).
  * **Save Mapping:** Saves and applies the mapping immediately.
  * **Redo Mouse / Redo Keys:** Dedicated buttons to redo the mouse button click or keyboard shortcut individually.
  * **Remove:** Delete any mapping entry with one click.
  * Original mouse clicks are swallowed so browsers don't navigate back/forward in web history when you press the button.
* **Native & Safe:**
  * Modern `SMAppService` for Launch at Login.
  * Single-instance enforcement.
  * Persistent storage via `UserDefaults`.

---

### Quick Start

#### 1. Build and Run

```bash
cd ~/Development/mousebutton
make run
```
*(Look in your menu bar at the top of your screen for the mouse icon!)*

#### 2. First-Time Permission Setup

Because macOS protects global mouse and keyboard events, grant Accessibility permission when prompted:
* **System Settings > Privacy & Security > Accessibility** > enable **mousebutton**.

---

### Install Permanently to `/Applications`

To copy it to `/Applications` and launch it:

```bash
make install
```

Then simply click the menu bar icon and check **Launch at Login**!

---

### Uninstall

```bash
make uninstall
```
