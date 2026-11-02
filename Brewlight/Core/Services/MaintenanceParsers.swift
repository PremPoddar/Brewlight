import Foundation

/// Parsers for maintenance command output.
enum MaintenanceParsers {
    struct DoctorWarning: Identifiable, Sendable, Hashable {
        let id = UUID()
        var title: String
        var body: String
    }

    /// `brew doctor` prints "Warning: <title>\n<body…>" blocks separated by blank lines.
    static func doctor(_ output: String) -> [DoctorWarning] {
        var result: [DoctorWarning] = []
        var title: String?
        var body: [String] = []
        func flush() {
            // Keep leading spaces: indented lines are how doctor lists packages.
            if let t = title { result.append(DoctorWarning(title: t, body: body.joined(separator: "\n").trimmingCharacters(in: .newlines))) }
            title = nil; body = []
        }
        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("Warning: ") || line.hasPrefix("Error: ") {
                flush()
                title = line.replacingOccurrences(of: "Warning: ", with: "").replacingOccurrences(of: "Error: ", with: "")
            } else if title != nil {
                body.append(line)
            }
        }
        flush()
        return result
    }

    /// Something `brew doctor` says you can do about a warning.
    enum Suggestion: Hashable, Sendable, Identifiable {
        /// A formula or cask the warning names.
        case package(String)
        /// A `brew …` command printed in the warning (arguments after `brew`).
        case brew([String])
        /// A command that needs a terminal (e.g. `sudo …`, which asks for your password).
        case terminal(String)
        case link(URL)

        var id: String {
            switch self {
            case .package(let n): "pkg:" + n
            case .brew(let a): "brew:" + a.joined(separator: " ")
            case .terminal(let c): "term:" + c
            case .link(let u): "url:" + u.absoluteString
            }
        }
    }

    /// Pulls actionable items out of a doctor warning: package names listed on their own indented
    /// lines, `brew`/`sudo` commands, and links. Placeholder commands like `brew trust --formula <user>/…`
    /// are skipped.
    static func suggestions(for w: DoctorWarning) -> [Suggestion] {
        var out: [Suggestion] = []
        for raw in w.body.split(separator: "\n").map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.contains("<") else { continue }
            if line.hasPrefix("brew ") {
                out.append(.brew(line.dropFirst(5).split(separator: " ").map(String.init)))
            } else if line.hasPrefix("sudo ") {
                out.append(.terminal(line))
            } else if let url = line.split(separator: " ").first(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }).flatMap({ URL(string: String($0)) }) {
                out.append(.link(url))
            } else if raw.hasPrefix(" ") || raw.hasPrefix("\t"),
                      line.allSatisfy({ $0.isLetter || $0.isNumber || "@._+-/".contains($0) }),
                      line.first?.isLetter == true || line.first?.isNumber == true {
                out.append(.package(line))
            }
        }
        var seen = Set<Suggestion>()
        return out.filter { seen.insert($0).inserted }
    }

    struct CleanupPreview: Sendable {
        var items: [String]
        var reclaimable: String?
    }

    /// `brew cleanup -n`: "Would remove: <path> (N files, 12MB)" and a final
    /// "This operation would free approximately 2.4GB of disk space."
    static func cleanup(_ output: String) -> CleanupPreview {
        var items: [String] = []
        var total: String?
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Would remove: ") { items.append(String(line.dropFirst("Would remove: ".count))) }
            if let r = line.range(of: "free approximately ") {
                total = String(line[r.upperBound...]).components(separatedBy: " of disk").first
            }
        }
        return CleanupPreview(items: items, reclaimable: total)
    }

    /// `brew autoremove --dry-run`: "==> Would autoremove N unneeded formulae:" then names.
    static func autoremove(_ output: String) -> [String] {
        var names: [String] = []
        var inList = false
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("==> Would autoremove") || line.hasPrefix("==> Would uninstall") { inList = true; continue }
            if line.hasPrefix("==>") { inList = false; continue }
            if inList { names += line.split(separator: " ").map(String.init) }
        }
        return names
    }
}
