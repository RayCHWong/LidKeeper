import IOKit

/// What macOS says about the lid.
enum Lid {

    /// Whether closing the lid would put the Mac to sleep right now, as macOS
    /// itself reports it, or `nil` on Macs without a lid.
    ///
    /// Apple documents the lid-closed assertion as working on AC power only,
    /// and other settings or software can also keep a closed lid awake, so
    /// we ask instead of guessing.
    static var closingCausesSleep: Bool? {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return nil }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(
            rootDomain, "AppleClamshellCausesSleep" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        return value as? Bool
    }
}
