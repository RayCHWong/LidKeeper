import AppKit

/// Owns the menu-bar status item and translates clicks into assertion changes.
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let power: PowerAssertionManager
    private let auto: AutoKeepAwake
    private let sleepSettings: SleepSettings

    /// Preset auto-release durations. `nil` means "until I turn it off".
    private let durations: [(title: String, seconds: TimeInterval?)] = [
        ("15 Minutes", 15 * 60),
        ("30 Minutes", 30 * 60),
        ("1 Hour", 60 * 60),
        ("2 Hours", 2 * 60 * 60),
        ("5 Hours", 5 * 60 * 60),
        ("Until I Turn It Off", nil),
    ]

    init(power: PowerAssertionManager, auto: AutoKeepAwake, sleepSettings: SleepSettings) {
        self.power = power
        self.auto = auto
        self.sleepSettings = sleepSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        power.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshIcon() }
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refreshIcon()
    }

    // MARK: - Menu (rebuilt each time it opens so state is always fresh)

    func menuNeedsUpdate(_ menu: NSMenu) {
        auto.evaluate()
        menu.removeAllItems()

        let header = disabledItem(statusText())
        menu.addItem(header)
        menu.addItem(.separator())

        let manualOn = power.isActive && !auto.isOn
        let toggle = item(manualOn ? "Let It Sleep" : "Keep Awake", #selector(toggleKeepAwake))
        menu.addItem(toggle)

        let timed = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (index, duration) in durations.enumerated() {
            let entry = item(duration.title, #selector(keepAwakeForDuration(_:)))
            entry.tag = index
            sub.addItem(entry)
        }
        timed.submenu = sub
        menu.addItem(timed)

        let autoItem = item("Auto: While Claude Code Works", #selector(toggleAuto))
        autoItem.state = auto.isOn ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(.separator())

        menu.addItem(autoSettingsItem())

        let display = item("Also Keep Screen On", #selector(toggleDisplay))
        display.state = power.keepDisplayAwake ? .on : .off
        menu.addItem(display)

        // Needs the root helper: on battery nothing short of turning sleep
        // off keeps a closed lid awake. See `SleepSettings`.
        let battery = item("Also Keep Awake on Battery", #selector(toggleBatteryOverride))
        battery.state = sleepSettings.keepAwakeOnBattery ? .on : .off
        menu.addItem(battery)

        let login = item("Start at Login", #selector(toggleStartAtLogin))
        login.state = StartAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        // What closing the lid will do now (see `Lid.outcome`).
        if power.isActive, let causesSleep = Lid.closingCausesSleep {
            let outcome = Lid.outcome(
                closingCausesSleep: causesSleep,
                sleepDisabled: Lid.sleepDisabled,
                isOnACPower: PowerSource.current().isOnACPower,
                holdsSystemSleepAssertion: power.holdsSystemSleepAssertion
            )
            menu.addItem(.separator())
            menu.addItem(disabledItem(outcome.title))
        }

        // A failed helper call would otherwise be invisible, and the lid
        // would sleep when the user expects it not to.
        if let problem = sleepSettings.lastError {
            menu.addItem(.separator())
            menu.addItem(disabledItem("\u{26A0}\u{FE0E} Keep Awake on Battery: \(problem)"))
        }

        menu.addItem(.separator())
        if sleepSettings.isHelperInstalled {
            menu.addItem(item("Remove the Root Helper\u{2026}", #selector(removeHelper)))
        }
        menu.addItem(item("About LidKeeper", #selector(showAbout)))

        let quit = item("Quit LidKeeper", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Auto's two choices: how long to stay awake after Claude Code goes
    /// quiet, and what to do on battery.
    private func autoSettingsItem() -> NSMenuItem {
        let settings = NSMenuItem(title: "Auto Settings", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        sub.addItem(disabledItem("Stay Awake After Claude Code Goes Quiet"))
        for period in AutoKeepAwake.QuietPeriod.allCases {
            let entry = item(period.title, #selector(chooseQuietPeriod(_:)))
            entry.tag = period.rawValue
            entry.state = auto.quietPeriod == period ? .on : .off
            sub.addItem(entry)
        }

        sub.addItem(.separator())
        sub.addItem(disabledItem("On Battery"))
        for (index, rule) in AutoKeepAwake.BatteryRule.allCases.enumerated() {
            let entry = item(rule.title, #selector(chooseBatteryRule(_:)))
            entry.tag = index
            entry.state = auto.batteryRule == rule ? .on : .off
            sub.addItem(entry)
        }

        settings.submenu = sub
        return settings
    }

    private func statusText() -> String {
        if auto.isOn {
            switch auto.decision {
            case .awake(let lastActivity):
                let quietFor = -lastActivity.timeIntervalSinceNow
                if quietFor < 60 { return "Auto — awake, Claude Code is working" }
                return "Auto — awake, Claude Code active \(Self.format(quietFor)) ago"
            case .claudeQuiet:
                return "Auto — Claude Code is quiet, sleep allowed"
            case .batteryLow(let percent):
                return "Auto — paused, battery at \(percent)%"
            case .unplugged:
                return "Auto — paused until plugged in"
            }
        }
        guard power.isActive else { return "Sleep allowed (inactive)" }
        if let remaining = power.remainingTime {
            return "Awake — \(Self.format(remaining)) left"
        }
        return "Awake — until you turn it off"
    }

    // MARK: - Actions

    @objc private func toggleKeepAwake() {
        if power.isActive && !auto.isOn {
            power.deactivate()
        } else {
            auto.isOn = false
            power.activate(duration: nil)
        }
    }

    @objc private func keepAwakeForDuration(_ sender: NSMenuItem) {
        auto.isOn = false
        power.activate(duration: durations[sender.tag].seconds)
    }

    @objc private func toggleAuto() {
        auto.isOn.toggle()
    }

    @objc private func chooseQuietPeriod(_ sender: NSMenuItem) {
        if let period = AutoKeepAwake.QuietPeriod(rawValue: sender.tag) {
            auto.quietPeriod = period
        }
    }

    @objc private func chooseBatteryRule(_ sender: NSMenuItem) {
        auto.batteryRule = AutoKeepAwake.BatteryRule.allCases[sender.tag]
    }

    @objc private func toggleDisplay() {
        power.keepDisplayAwake.toggle()
    }

    /// Turning this on needs the root helper, so the first time it explains
    /// what will be installed and then asks for an administrator password.
    @objc private func toggleBatteryOverride() {
        if sleepSettings.keepAwakeOnBattery {
            sleepSettings.keepAwakeOnBattery = false
            sleepSettings.endOverride()
            return
        }

        if sleepSettings.helperState() != .ready, !confirmHelperInstall() { return }

        sleepSettings.keepAwakeOnBattery = true
        if power.isActive { sleepSettings.beginOverride() }
        if let problem = sleepSettings.lastError, problem != "Cancelled." {
            sleepSettings.keepAwakeOnBattery = false
            showHelperError(problem)
        }
    }

    /// Explains the helper, then installs it. `false` if the user backed out
    /// or it didn't work.
    private func confirmHelperInstall() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Keep Awake on Battery needs a helper"
        alert.informativeText = """
        On battery, macOS ignores the assertion that keeps a closed lid \
        awake, so the only thing that works is turning system sleep off — \
        and that needs administrator rights.

        LidKeeper will install a small helper at \
        /usr/local/libexec/lidkeeper-helper, owned by root, plus a rule in \
        /etc/sudoers.d/lidkeeper that lets it run with three fixed \
        arguments: on, off and status. Nothing else gains administrator \
        rights, and LidKeeper only turns sleep off while Keep Awake is on.

        You can take both files away again with "Remove the Root Helper".
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Helper\u{2026}")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        guard sleepSettings.installHelper() else {
            if let problem = sleepSettings.lastError, problem != "Cancelled." {
                showHelperError(problem)
            }
            return false
        }
        return true
    }

    @objc private func removeHelper() {
        sleepSettings.keepAwakeOnBattery = false
        sleepSettings.endOverride()
        if !sleepSettings.uninstallHelper(), let problem = sleepSettings.lastError, problem != "Cancelled." {
            showHelperError(problem)
        }
    }

    private func showHelperError(_ problem: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Keep Awake on Battery isn't set up"
        alert.informativeText = problem
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func toggleStartAtLogin() {
        if let reference = StartAtLogin.setEnabled(!StartAtLogin.isEnabled) {
            showStartAtLoginError(reference: reference)
        } else if StartAtLogin.needsApproval {
            // macOS wants the user to approve the item in System Settings.
            StartAtLogin.openLoginItemsSettings()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "LidKeeper"
        alert.informativeText = """
        A tiny menu-bar app that keeps your Mac awake — even with the \
        lid closed, when it's plugged in — using Apple's public power \
        assertions. While it's active, the menu shows what closing the \
        lid will do.

        Choose "Keep Awake" to stay up indefinitely, or pick a duration. \
        Or turn on Auto to stay awake only while Claude Code is working, \
        pausing when the battery gets low.

        On battery a closed lid still sleeps, because macOS ignores those \
        assertions there. "Also Keep Awake on Battery" gets around it by \
        turning system sleep off while LidKeeper is active, using a small \
        root helper it installs once with your permission.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showStartAtLoginError(reference: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't change Start at Login"
        alert.informativeText = """
        You can change this yourself in System Settings → General → \
        Login Items. (Reference: \(reference))
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        power.deactivate()
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let symbol = power.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let label = power.isActive ? "Keep Awake is on" : "Keep Awake is off"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            // Fallback for the unlikely case the SF Symbol is unavailable.
            button.image = nil
            button.title = power.isActive ? "AWAKE" : "zzz"
        }
    }

    // MARK: - Helpers

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
