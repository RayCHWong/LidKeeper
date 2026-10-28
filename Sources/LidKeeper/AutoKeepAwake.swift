import Foundation

/// "Auto" mode: keeps the Mac awake while Claude Code is working, and lets
/// it sleep once Claude Code goes quiet or the battery gets low.
///
/// It re-checks every 15 seconds. The setting is remembered, so with
/// Start at Login it's back on after a restart.
final class AutoKeepAwake {

    /// How long to stay awake after Claude Code's last transcript write.
    /// Long thinking and slow commands don't write the transcript, so this
    /// has to cover them.
    enum QuietPeriod: Int, CaseIterable {
        case fiveMinutes = 5
        case fifteenMinutes = 15
        case oneHour = 60

        var title: String { self == .oneHour ? "1 Hour" : "\(rawValue) Minutes" }
        var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    }

    /// What Auto does when the Mac is on battery.
    enum BatteryRule: String, CaseIterable {
        case pauseBelow20
        case pauseBelow50
        case pluggedInOnly

        var title: String {
            switch self {
            case .pauseBelow20: return "Pause Below 20%"
            case .pauseBelow50: return "Pause Below 50%"
            case .pluggedInOnly: return "Only When Plugged In"
            }
        }

        /// Lowest charge that still allows keeping awake; `nil` means never on battery.
        var minimumPercent: Int? {
            switch self {
            case .pauseBelow20: return 20
            case .pauseBelow50: return 50
            case .pluggedInOnly: return nil
            }
        }
    }

    /// Why Auto is or isn't keeping the Mac awake.
    enum Decision {
        case awake(lastActivity: Date)
        case claudeQuiet
        case batteryLow(percent: Int)
        case unplugged
    }

    /// The rule itself, kept free of side effects.
    static func decide(lastActivity: Date?, now: Date, quietPeriod: QuietPeriod,
                       power: PowerSource, batteryRule: BatteryRule) -> Decision {
        guard let lastActivity, now.timeIntervalSince(lastActivity) < quietPeriod.seconds else {
            return .claudeQuiet
        }
        if !power.isOnACPower {
            guard let minimum = batteryRule.minimumPercent else { return .unplugged }
            if let percent = power.batteryPercent, percent < minimum {
                return .batteryLow(percent: percent)
            }
        }
        return .awake(lastActivity: lastActivity)
    }

    // MARK: - State

    /// The latest decision, refreshed on every check.
    private(set) var decision: Decision = .claudeQuiet

    /// Whether Auto is on. Remembered between launches.
    var isOn: Bool {
        get { defaults.bool(forKey: Keys.isOn) }
        set {
            defaults.set(newValue, forKey: Keys.isOn)
            if newValue { start() } else { stop() }
        }
    }

    var quietPeriod: QuietPeriod {
        get { QuietPeriod(rawValue: defaults.integer(forKey: Keys.quietPeriod)) ?? .fifteenMinutes }
        set { defaults.set(newValue.rawValue, forKey: Keys.quietPeriod); evaluate() }
    }

    var batteryRule: BatteryRule {
        get { defaults.string(forKey: Keys.batteryRule).flatMap(BatteryRule.init(rawValue:)) ?? .pauseBelow20 }
        set { defaults.set(newValue.rawValue, forKey: Keys.batteryRule); evaluate() }
    }

    private enum Keys {
        static let isOn = "autoMode"
        static let quietPeriod = "autoQuietPeriodMinutes"
        static let batteryRule = "autoBatteryRule"
    }

    private let power: PowerAssertionManager
    private let claude = ClaudeCodeActivity()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init(power: PowerAssertionManager) {
        self.power = power
        if isOn { start() }
    }

    // MARK: - Checking

    /// Re-checks Claude Code and the battery, then holds or releases the
    /// assertion to match. Does nothing while Auto is off.
    func evaluate() {
        guard isOn else { return }
        decision = Self.decide(lastActivity: claude.lastActivity(), now: Date(),
                               quietPeriod: quietPeriod, power: PowerSource.current(),
                               batteryRule: batteryRule)
        if case .awake = decision {
            if !power.isActive { power.activate(duration: nil) }
        } else if power.isActive {
            power.deactivate()
        }
    }

    private func start() {
        guard timer == nil else { return }
        power.deactivate() // Auto takes over from any manual keep-awake.

        // Keeps App Nap from delaying the checks; doesn't prevent sleep itself.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Watching for Claude Code activity"
        )
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    private func stop() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        decision = .claudeQuiet
        power.deactivate()
    }
}
