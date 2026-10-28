import Foundation
import IOKit.ps

/// A snapshot of where the Mac's power is coming from.
struct PowerSource {

    /// True when a power adapter is connected.
    var isOnACPower: Bool

    /// Internal battery charge from 0 to 100, or `nil` on Macs without one.
    var batteryPercent: Int?

    /// Reads the current state. If it can't be read, reports AC power so
    /// nothing acts on a spurious low battery.
    static func current() -> PowerSource {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSource(isOnACPower: true, batteryPercent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] ?? []

        var percent: Int?
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            percent = current * 100 / max
        }

        return PowerSource(
            isOnACPower: providing.map { ($0 as String) == kIOPSACPowerValue } ?? true,
            batteryPercent: percent
        )
    }
}
