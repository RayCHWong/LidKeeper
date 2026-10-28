import AppKit

// Programmatic entry point — no storyboard, no .xib.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu-bar-only app: no Dock icon, no main window.
app.setActivationPolicy(.accessory)
app.run()
