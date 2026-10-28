import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let power = PowerAssertionManager()
    private var auto: AutoKeepAwake?
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let auto = AutoKeepAwake(power: power)
        self.auto = auto
        menuController = StatusMenuController(power: power, auto: auto)

        // Launch flags do what the matching menu items do, for scripts.
        // `--keep-awake` starts a manual keep-awake (turning Auto off) and
        // `--keep-screen-on` also holds the display.
        let args = CommandLine.arguments
        if args.contains("--keep-screen-on") { power.keepDisplayAwake = true }
        if args.contains("--keep-awake") || args.contains("--keep-screen-on") {
            auto.isOn = false
            power.activate(duration: nil)
        }

        // `--auto` turns Auto on; like the menu item, it's remembered.
        if args.contains("--auto") { auto.isOn = true }

        // `--start-at-login` registers LidKeeper to open at login, the same
        // as the menu's "Start at Login", and reports the result.
        if args.contains("--start-at-login") {
            StartAtLogin.setEnabled(true)
            let line = "LidKeeper: Start at Login is \(StartAtLogin.statusDescription)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Always release assertions so we never leave the Mac stuck awake.
        power.deactivate()
    }
}
