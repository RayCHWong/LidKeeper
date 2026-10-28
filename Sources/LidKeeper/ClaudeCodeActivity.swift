import Foundation

/// Tells when Claude Code last did something, from the session transcripts
/// under ~/.claude/projects. Every Claude Code front end (terminal, IDE,
/// desktop app) writes these as it works. Only file dates are read, never
/// their contents.
struct ClaudeCodeActivity {

    private let projectsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    /// When any session transcript was last written, or `nil` if there are none.
    func lastActivity() -> Date? {
        guard let files = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: Date?
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else { continue }
            if newest.map({ modified > $0 }) ?? true { newest = modified }
        }
        return newest
    }
}
