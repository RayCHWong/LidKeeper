import Foundation

/// Turns system sleep off while LidKeeper is keeping the Mac awake, so a
/// closed lid stays awake on battery too.
///
/// Power assertions can't do this: macOS ignores `PreventSystemSleep` on
/// battery, as Apple documents (`man caffeinate`), so a closed lid really
/// sleeps. The one switch that works is `pmset disablesleep`, and that needs
/// root. `Scripts/install-helper.sh` installs a root-owned helper and a
/// sudoers rule letting this user run it — and only it — without a password;
/// this type is the client of that helper.
///
/// Because `disablesleep` is a system-wide setting rather than an assertion,
/// nothing releases it for us. We only hold it while keep-awake is on, we
/// remember that we turned it on, and we put it back on the next launch if we
/// ever exited without doing so.
final class SleepSettings {

    /// Where `install-helper.sh` puts the helper. The sudoers rule names this
    /// exact path, so both have to agree.
    static let helperPath = "/usr/local/libexec/lidkeeper-helper"

    /// Whether the helper is there and usable without a password.
    enum HelperState: Equatable {
        case notInstalled
        case ready
        /// Installed, but sudo still wants a password — usually a missing or
        /// stale `/etc/sudoers.d/lidkeeper`.
        case needsPassword
    }

    /// The user's choice: keep a closed lid awake on battery as well.
    /// Remembered between launches, like LidKeeper's other settings.
    var keepAwakeOnBattery: Bool {
        get { defaults.bool(forKey: Keys.keepAwakeOnBattery) }
        set { defaults.set(newValue, forKey: Keys.keepAwakeOnBattery) }
    }

    /// Whether sleep is off system-wide right now, as macOS reports it.
    var isSleepDisabled: Bool { Lid.sleepDisabled }

    /// Why the last helper call failed, or `nil` if it didn't. The menu shows
    /// this so a silent failure can't leave the lid sleeping unexpectedly.
    private(set) var lastError: String?

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let keepAwakeOnBattery = "keepAwakeOnBattery"
        /// Set while we have sleep turned off, so a crash is recoverable.
        static let engaged = "sleepDisabledByLidKeeper"
    }

    // MARK: - Helper state

    /// Whether the helper file is in place. Just a file check — cheap enough
    /// to ask every time the menu opens, unlike `helperState()`, which runs
    /// sudo.
    var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.helperPath)
    }

    func helperState() -> HelperState {
        guard isHelperInstalled else { return .notInstalled }
        switch runHelper("status") {
        case .success: return .ready
        case .failure: return .needsPassword
        }
    }

    /// Installs the helper, asking for an administrator password through the
    /// standard macOS prompt. Returns `true` once it's ready to use.
    @discardableResult
    func installHelper() -> Bool {
        guard let installer = bundledInstaller() else {
            lastError = "LidKeeper couldn't find install-helper.sh. Run it from the source checkout: "
                + "sudo bash Scripts/install-helper.sh install"
            return false
        }
        let helperSource = installer.deletingLastPathComponent()
            .appendingPathComponent("lidkeeper-helper").path
        let command = "/bin/sh \(shellQuoted(installer.path)) install"
            + " --user \(shellQuoted(NSUserName()))"
            + " --helper \(shellQuoted(helperSource))"

        if let problem = runAsAdministrator(command) {
            lastError = problem
            return false
        }
        if case .ready = helperState() {
            lastError = nil
            return true
        }
        lastError = "The helper was installed but sudo still asks for a password."
        return false
    }

    /// Removes the helper and its sudoers rule, turning sleep back on first.
    @discardableResult
    func uninstallHelper() -> Bool {
        guard let installer = bundledInstaller() else {
            lastError = "LidKeeper couldn't find install-helper.sh. Run it from the source checkout: "
                + "sudo bash Scripts/install-helper.sh uninstall"
            return false
        }
        defaults.set(false, forKey: Keys.engaged)
        if let problem = runAsAdministrator("/bin/sh \(shellQuoted(installer.path)) uninstall") {
            lastError = problem
            return false
        }
        lastError = nil
        return true
    }

    // MARK: - Holding the setting

    /// Turns sleep off, if the user asked for it and the helper is installed.
    /// Safe to call when it's already off.
    func beginOverride() {
        guard keepAwakeOnBattery, isHelperInstalled else { return }
        guard !isSleepDisabled else {
            defaults.set(true, forKey: Keys.engaged)
            return
        }
        apply(disabled: true)
    }

    /// Turns sleep back on, but only if we were the ones who turned it off —
    /// someone else's `pmset disablesleep` is theirs to undo.
    func endOverride() {
        guard defaults.bool(forKey: Keys.engaged) else { return }
        apply(disabled: false)
    }

    /// Called at launch: if we exited while sleep was off — a crash, a force
    /// quit, a restart — put it back.
    func recoverAtLaunch() {
        guard defaults.bool(forKey: Keys.engaged), isSleepDisabled else {
            defaults.set(false, forKey: Keys.engaged)
            return
        }
        apply(disabled: false)
    }

    private func apply(disabled: Bool) {
        switch runHelper(disabled ? "on" : "off") {
        case .success:
            defaults.set(disabled, forKey: Keys.engaged)
            lastError = nil
        case .failure(let message):
            lastError = message
        }
    }

    // MARK: - Running things

    private enum HelperResult {
        case success(String)
        case failure(String)
    }

    /// Runs the helper through sudo. `-n` means "never prompt": with the rule
    /// in place it just runs, and without it we get a clean failure instead
    /// of a process waiting on a password nobody can type.
    private func runHelper(_ verb: String) -> HelperResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", Self.helperPath, verb]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch {
            return .failure("Couldn't run the helper: \(error.localizedDescription)")
        }
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(detail.isEmpty ? "The helper exited with code \(process.terminationStatus)." : detail)
        }
        return .success(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Runs one command with the standard macOS administrator prompt.
    /// Returns `nil` on success, or a message to show the user.
    private func runAsAdministrator(_ command: String) -> String? {
        let source = "do shell script \"\(appleScriptQuoted(command))\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            return "LidKeeper couldn't build the installer command."
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return nil }

        // -128 is the user dismissing the password prompt.
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return "Cancelled." }
        let message = error[NSAppleScript.errorMessage] as? String
        return message ?? "The installer failed."
    }

    /// The installer inside the .app bundle, falling back to the source
    /// checkout for `swift run` from the repository root.
    private func bundledInstaller() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("install-helper.sh"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Scripts/install-helper.sh"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
