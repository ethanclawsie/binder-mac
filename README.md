# mousebutton 🖱️⚡

An ultra-minimal, high-performance macOS menu bar utility that maps mouse side buttons to macOS window switching (`Cmd + \``).

---

### Highlights

* **Menu Bar GUI:** Sits cleanly in your macOS menu bar with a native mouse icon (`computermouse.fill`), with zero Dock icon clutter (`LSUIElement = true`).
* **High Performance & Zero Bloat:**
  * Entire app bundle is **under 100 KB**.
  * Consumes **~5–8 MB** of RAM (compared to 50–150 MB for general mouse utilities).
  * **0.0% CPU** idle. Subscribes strictly to auxiliary mouse clicks, completely ignoring mouse movement, regular left/right clicks, and scrolling.
* **Interactive Button Recorder:**
  * Click **"🎙️ Record Mouse Button"** in the settings window.
  * Press your mouse button to bind it.
  * Stop or cancel recording anytime with the **"Cancel (Esc)"** button or by pressing the **Esc key** (locally or globally).
  * Choose your action from the dropdown and save!
* **Smart Window Switching:**
  * **Next Window (`Cmd + \``)** & **Previous Window (`Cmd + Shift + \``)**
  * Holding **Shift** while pressing a forward-mapped button automatically reverses cycle direction.
  * Swallows native clicks so browsers don't navigate back/forward in web history when switching windows.
* **Built-in Menu Bar Controls:**
  * **Configure Mappings…:** Opens the lightweight settings window.
  * **Enabled / Disabled toggle:** Instantly pause or resume the feature anytime.
  * **Launch at Login toggle:** One-click toggle to start automatically on macOS boot.
  * **Open Accessibility Settings:** Direct shortcut to System Settings.
  * **Quit:** Cleanly exits the app.

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
* **System Settings > Privacy & Security > Accessibility** > enable **mousebutton** (or click **Open Accessibility Settings...** in the menu bar dropdown).

---

### Install Permanently to `~/Applications`

To copy it to your Applications folder and launch it:

```bash
make install
```

Then simply click the menu bar icon and check **Launch at Login**!

---

### Uninstall

```bash
make uninstall
```
