import Foundation

enum OperationPhase: String, Sendable, Equatable {
    case queued, starting, fetching, downloading, pouring, building, installing, linking,
         uninstalling, upgrading, cleaning, caveats, done

    var label: String {
        switch self {
        case .queued: String(localized: "Queued")
        case .starting: String(localized: "Starting…")
        case .fetching: String(localized: "Fetching…")
        case .downloading: String(localized: "Downloading…")
        case .pouring: String(localized: "Pouring…")
        case .building: String(localized: "Building…")
        case .installing: String(localized: "Installing…")
        case .linking: String(localized: "Linking…")
        case .uninstalling: String(localized: "Removing…")
        case .upgrading: String(localized: "Upgrading…")
        case .cleaning: String(localized: "Cleaning up…")
        case .caveats: String(localized: "Finishing…")
        case .done: String(localized: "Done")
        }
    }
}

/// Turns brew's plain-text output into a phase and, where brew prints one, a percentage.
enum ProgressParser {
    struct Update: Equatable, Sendable {
        var phase: OperationPhase?
        var percent: Double?
        var needsTerminal = false
        var isError = false
    }

    static func parse(_ line: String) -> Update {
        var u = Update()
        let lower = line.lowercased()
        if let pct = percent(in: line) { u.percent = pct; u.phase = .downloading }
        if lower.hasPrefix("==> fetching") || lower.hasPrefix("==> fetching downloads") { u.phase = .fetching }
        else if lower.hasPrefix("==> downloading") { u.phase = .downloading }
        else if lower.hasPrefix("==> pouring") { u.phase = .pouring }
        else if lower.hasPrefix("==> ./configure") || lower.hasPrefix("==> cmake") || lower.hasPrefix("==> make") || lower.hasPrefix("==> cargo") || lower.hasPrefix("==> go build") { u.phase = .building }
        else if lower.hasPrefix("==> installing") || lower.hasPrefix("==> moving app") || lower.hasPrefix("==> running installer") { u.phase = .installing }
        else if lower.hasPrefix("==> linking") { u.phase = .linking }
        else if lower.hasPrefix("==> upgrading") { u.phase = .upgrading }
        else if lower.hasPrefix("uninstalling") || lower.hasPrefix("==> uninstalling") || lower.hasPrefix("==> removing") || lower.hasPrefix("==> trashing") { u.phase = .uninstalling }
        else if lower.hasPrefix("==> cleaning") || lower.hasPrefix("removing:") { u.phase = .cleaning }
        else if lower.hasPrefix("==> caveats") { u.phase = .caveats }
        else if lower.hasPrefix("🍺") || lower.contains("was successfully installed") || lower.contains("was successfully upgraded") { u.phase = .done }

        if lower.hasPrefix("error:") { u.isError = true }
        let ttyMarkers = ["a terminal is required", "no tty present", "sudo: a password is required",
                          "askpass", "must be run from a terminal", "inappropriate ioctl for device"]
        if ttyMarkers.contains(where: lower.contains) { u.needsTerminal = true }
        return u
    }

    /// Matches curl-style progress, e.g. "####### 64.0%".
    static func percent(in line: String) -> Double? {
        guard line.hasSuffix("%") else { return nil }
        let digits = line.dropLast().reversed().prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let v = Double(String(digits.reversed())), v <= 100 else { return nil }
        return v / 100
    }
}
