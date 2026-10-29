import IOKit

/// What closing the lid will do.
enum Lid {

    /// What happens if the lid closes now, while LidKeeper is active.
    enum Outcome {
        /// macOS won't start lid sleep, or sleep is off system-wide.
        case staysAwake
        /// macOS starts lid sleep, but our `PreventSystemSleep` assertion
        /// turns it into dark wake: the screen goes off, the Mac keeps running.
        case screenOffKeepsRunning
        /// On battery macOS ignores that assertion, so the Mac sleeps.
        case sleepsOnBattery
        /// The assertion isn't held, so the Mac sleeps.
        case sleeps

        var title: String {
            switch self {
            case .staysAwake: return "Closing the lid won't sleep this Mac"
            case .screenOffKeepsRunning: return "Closing the lid turns off the screen; this Mac keeps running"
            case .sleepsOnBattery: return "\u{26A0}\u{FE0E} On battery, closing the lid will sleep this Mac"
            case .sleeps: return "\u{26A0}\u{FE0E} Closing the lid will sleep this Mac"
            }
        }
    }

    /// Combines what macOS reports with the power source.
    ///
    /// macOS's lid flag only says whether closing the lid starts lid sleep;
    /// it doesn't count assertions. On AC power `PreventSystemSleep` turns
    /// that sleep into dark wake (`pmset -g log` shows "Entering DarkWake
    /// state due to 'Clamshell Sleep'"). On battery macOS ignores the
    /// assertion, as Apple documents, and the Mac really sleeps.
    ///
    /// On battery the flag can't be trusted: with our assertion held it can
    /// read "No" while closing the lid still sleeps the Mac ("Entering Sleep
    /// state due to 'Clamshell Sleep' … Using Batt"). Only turning sleep off
    /// system-wide keeps a closed Mac running there, so that's all we ask.
    static func outcome(closingCausesSleep: Bool, sleepDisabled: Bool,
                        isOnACPower: Bool, holdsSystemSleepAssertion: Bool) -> Outcome {
        if sleepDisabled { return .staysAwake }
        guard isOnACPower else { return .sleepsOnBattery }
        guard closingCausesSleep else { return .staysAwake }
        return holdsSystemSleepAssertion ? .screenOffKeepsRunning : .sleeps
    }

    /// Whether closing the lid would start lid sleep right now, as macOS
    /// itself reports it, or `nil` on Macs without a lid. Other settings or
    /// software can turn lid sleep off, so we ask instead of guessing.
    static var closingCausesSleep: Bool? { rootDomainFlag("AppleClamshellCausesSleep") }

    /// Whether sleep is turned off system-wide (`pmset disablesleep`), in
    /// which case not even a closed lid sleeps.
    static var sleepDisabled: Bool { rootDomainFlag("SleepDisabled") ?? false }

    private static func rootDomainFlag(_ key: String) -> Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return nil }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(
            rootDomain, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return value as? Bool
    }
}
