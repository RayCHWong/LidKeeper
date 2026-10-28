import Foundation
import ServiceManagement

/// Opens LidKeeper automatically at login, using `SMAppService` (macOS 13+).
///
/// The item appears under System Settings → General → Login Items, where
/// it can also be switched off. macOS launches the app without arguments,
/// so it opens in the menu bar inactive.
enum StartAtLogin {

    /// True when LidKeeper is registered to open at login.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// True when macOS wants the user to approve the item in System Settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// A short description of the current state, for the command line.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "on"
        case .requiresApproval: return "waiting for approval in System Settings"
        case .notRegistered: return "off"
        case .notFound: return "unavailable"
        @unknown default: return "unknown"
        }
    }

    /// Turns open-at-login on or off. On failure, logs the details and
    /// returns a short reference to show the user; returns `nil` on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            switch (enabled, service.status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                break // already as requested, or waiting on the user's approval
            }
            return nil
        } catch {
            let reference = String(UUID().uuidString.prefix(8))
            NSLog("LidKeeper: Start at Login change failed [ref %@]: %@",
                  reference, String(describing: error))
            return reference
        }
    }

    /// Opens System Settings → General → Login Items.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
