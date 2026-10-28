import Foundation
import IOKit.pwr_mgt

/// Holds macOS power-management assertions that keep the Mac awake.
///
/// While active it holds two sleep assertions together:
/// - `PreventSystemSleep` is what keeps a closed lid awake. Apple documents
///   it as working on AC power only (`man caffeinate`), and other things can
///   affect lid sleep too, so the menu shows what macOS actually reports
///   (see `Lid`).
/// - `PreventUserIdleSystemSleep` stops idle sleep, and is documented to
///   work on battery as well (with the lid open).
///
/// A third, independent assertion (`PreventUserIdleDisplaySleep`) keeps
/// the display awake when the lid is open. It is toggled separately.
final class PowerAssertionManager {

    // MARK: - Observable state

    /// True while the Mac is being kept awake.
    private(set) var isActive = false

    /// When `true`, also prevents the display from sleeping (lid open).
    var keepDisplayAwake = false {
        didSet {
            guard keepDisplayAwake != oldValue else { return }
            if isActive {
                if keepDisplayAwake { create(kIOPMAssertionTypePreventUserIdleDisplaySleep, &displayAssertionID) }
                else { release(&displayAssertionID) }
            }
            onStateChange?()
        }
    }

    /// Fired on every state transition so the UI can refresh.
    var onStateChange: (() -> Void)?

    /// Time left before an automatic release, or `nil` for "until turned off".
    var remainingTime: TimeInterval? {
        guard let date = autoReleaseDate else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    // MARK: - Private

    private var systemAssertionID = IOPMAssertionID(0)
    private var idleAssertionID = IOPMAssertionID(0)
    private var displayAssertionID = IOPMAssertionID(0)
    private var autoReleaseTimer: Timer?
    private var autoReleaseDate: Date?

    /// Human-readable reason shown in `pmset -g assertions`.
    private let reason = "LidKeeper is keeping this Mac awake" as CFString

    // MARK: - Lifecycle

    /// Start keeping the Mac awake. Pass `duration` (seconds) to auto-release,
    /// or `nil` to stay awake until explicitly turned off.
    func activate(duration: TimeInterval? = nil) {
        releaseAllAssertions()
        cancelTimer()

        create(kIOPMAssertionTypePreventSystemSleep, &systemAssertionID)
        create(kIOPMAssertionTypePreventUserIdleSystemSleep, &idleAssertionID)
        if keepDisplayAwake { create(kIOPMAssertionTypePreventUserIdleDisplaySleep, &displayAssertionID) }

        isActive = systemAssertionID != IOPMAssertionID(0) || idleAssertionID != IOPMAssertionID(0)

        if isActive, let duration {
            autoReleaseDate = Date().addingTimeInterval(duration)
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.deactivate()
            }
            RunLoop.main.add(timer, forMode: .common)
            autoReleaseTimer = timer
        } else {
            autoReleaseDate = nil
        }

        onStateChange?()
    }

    /// Release every assertion and return the Mac to normal sleep behaviour.
    func deactivate() {
        cancelTimer()
        releaseAllAssertions()
        if isActive {
            isActive = false
            onStateChange?()
        }
    }

    // MARK: - Assertion helpers

    private func create(_ type: String, _ id: inout IOPMAssertionID) {
        guard id == IOPMAssertionID(0) else { return }
        IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != IOPMAssertionID(0) else { return }
        IOPMAssertionRelease(id)
        id = IOPMAssertionID(0)
    }

    private func releaseAllAssertions() {
        release(&systemAssertionID)
        release(&idleAssertionID)
        release(&displayAssertionID)
    }

    private func cancelTimer() {
        autoReleaseTimer?.invalidate()
        autoReleaseTimer = nil
        autoReleaseDate = nil
    }
}
