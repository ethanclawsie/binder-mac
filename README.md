# Binder ⚡

An ultra-minimal, high-performance macOS menu bar utility to map any mouse button or keyboard key to any keyboard shortcut (e.g. `Button 4` ➔ `Cmd + \`` to cycle app windows, `F1` ➔ `Cmd + Space`).

---

### Highlights

* **Modern SwiftUI Architecture:** Built with native SwiftUI, Swift Package Manager, and `@Observable`, mirroring modern macOS utilities like `copyshelf-mac`.
* **Menu Bar GUI:** Sits cleanly in your macOS menu bar with a programmable button icon (`button.programmable`) and zero Dock clutter (`LSUIElement = true`).
* **High Performance & Zero Bloat:**
  * Entire app bundle is **~360 KB**.
  * Consumes **~14 MB** physical RAM (compared to 100–200 MB for bloated utilities).
  * **0.0% CPU** idle. Zero allocations on hot-path keystroke simulation.
  * **Dynamic Event Tap:** Keyboard events are only tapped if keyboard mappings exist—zero overhead on normal typing.
  * **Loop Prevention:** Synthetic events are tagged to prevent recursive shortcut trigger loops.
* **Dual-Trigger Customizable Shortcuts:**
  * **＋ New Mapping:** Choose **Mouse Button** or **Keyboard Key** as the trigger.
  * **Record Trigger:** Click any mouse button (Middle Button, Button 4, Button 5) or press any key / hotkey combo.
  * **Record Target Shortcut:** Press any action keyboard combination (e.g. `⌘ \``, `⌘ Space`, or any custom combo).
  * **Validation Guard:** Prevents redundant triggers where trigger key matches action key.
  * **Save Mapping:** Saves and applies immediately.
  * **In-Place Redo Trigger / Redo Action:** Dedicated buttons to redo either side of any mapping.
  * **Remove:** Delete any mapping entry with one click.
* **Native & Safe:**
  * Modern `SMAppService` for Launch at Login.
  * Single-instance enforcement.
  * Persistent storage via `UserDefaults`.

---

### Install

#### Via Homebrew (Recommended)

```bash
brew install --cask ethanclawsie/tap/binder
```

Update anytime with:

```bash
brew upgrade --cask binder
```

---

### Manual Install / Build from Source

#### 1. Quick Local Install to `/Applications`

```bash
make install
```

#### 2. First-Time Permission Setup

Because macOS protects global mouse and keyboard events, grant Accessibility permission when prompted:
* **System Settings > Privacy & Security > Accessibility** > enable **Binder**.

Then simply click the menu bar icon and check **Launch at Login**!

---

### Uninstall

```bash
make uninstall
```
