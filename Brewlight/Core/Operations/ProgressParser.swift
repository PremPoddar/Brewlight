import Foundation

enum OperationPhase: String, Sendable, Equatable {
    case queued, starting, downloading, building, installing, linking,
         uninstalling, upgrading, cleaning, caveats, done

    var label: String {
        switch self {
        case .queued: String(localized: "Queued")
        case .starting: String(localized: "Starting…")
        // Brew's "fetching downloads" and "pouring" are downloading and installing to everyone else.
        case .downloading: String(localized: "Downloading…")
        case .installing: String(localized: "Installing…")
        case .building: String(localized: "Building…")
        case .linking: String(localized: "Linking…")
        case .uninstalling: String(localized: "Removing…")
        case .upgrading: String(localized: "Upgrading…")
        case .cleaning: String(localized: "Cleaning up…")
        case .caveats: String(localized: "Finishing…")
        case .done: String(localized: "Done")
        }
    }

    /// The same status with the package brew is working on, when it named one.
    func label(subject: String?) -> String {
        guard let subject, !subject.isEmpty else { return label }
        switch self {
        case .downloading: return String(localized: "Downloading \(subject)…")
        case .installing: return String(localized: "Installing \(subject)…")
        case .building: return String(localized: "Building \(subject)…")
        case .upgrading: return String(localized: "Upgrading \(subject)…")
        case .linking: return String(localized: "Linking \(subject)…")
        case .uninstalling: return String(localized: "Removing \(subject)…")
        default: return label
        }
    }
}

/// Turns brew's plain-text output into a phase, the package it is about and, where brew prints
/// one, a percentage.
enum ProgressParser {
    struct Update: Equatable, Sendable {
        var phase: OperationPhase?
        /// The package brew named in the heading, when it named one.
        var subject: String?
        var percent: Double?
        var needsTerminal = false
        var isError = false
    }

    static func parse(_ line: String) -> Update {
        var u = Update()
        let lower = line.lowercased()
        if let pct = percent(in: line) { u.percent = pct }

        // Homebrew 7 downloads bottles and casks in parallel and, without a TTY, prints only
        // "Fetching downloads for: …" before they land. That is the download phase.
        if lower.hasPrefix("==> fetching downloads for:") {
            u.phase = .downloading
            u.subject = subject(after: "==> fetching downloads for:", in: line)
        } else if lower.hasPrefix("==> fetching") {
            u.phase = .downloading
            u.subject = subject(after: "==> fetching", in: line)
        } else if lower.hasPrefix("==> downloading") {
            u.phase = .downloading
        } else if lower.hasPrefix("==> pouring") {
            u.phase = .installing
            u.subject = bottleName(after: "==> pouring", in: line)
        } else if lower.hasPrefix("==> installing cask") {
            u.phase = .installing
            u.subject = subject(after: "==> installing cask", in: line)
        } else if lower.hasPrefix("==> installing dependencies for") {
            u.phase = .installing
            u.subject = subject(after: "==> installing dependencies for", in: line)
        } else if lower.hasPrefix("==> installing") {
            u.phase = .installing
            u.subject = subject(after: "==> installing", in: line)
        } else if lower.hasPrefix("==> ./configure") || lower.hasPrefix("==> cmake") || lower.hasPrefix("==> make") || lower.hasPrefix("==> cargo") || lower.hasPrefix("==> go build") { u.phase = .building }
        else if lower.hasPrefix("==> moving app") || lower.hasPrefix("==> running installer") { u.phase = .installing }
        else if lower.hasPrefix("==> linking") { u.phase = .linking }
        else if lower.hasPrefix("==> upgrading") {
            u.phase = .upgrading
            u.subject = subject(after: "==> upgrading", in: line)
        }
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

    /// The package token after a heading, e.g. "hello" in "==> Installing `hello`".
    private static func subject(after prefix: String, in line: String) -> String? {
        let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let first = rest.split(whereSeparator: { " \t,:;(".contains($0) }).first else { return nil }
        let token = String(first).trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
        // "==> Upgrading 2 outdated packages:" has no package name in the heading.
        guard !token.isEmpty, token.first?.isNumber != true else { return nil }
        return token
    }

    /// "hello--2.12.3.arm64_tahoe.bottle.tar.gz" → "hello".
    private static func bottleName(after prefix: String, in line: String) -> String? {
        let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let range = rest.range(of: "--") else { return nil }
        let token = String(rest[..<range.lowerBound])
        return token.isEmpty ? nil : token
    }

    /// Matches curl-style progress, e.g. "####### 64.0%".
    static func percent(in line: String) -> Double? {
        guard line.hasSuffix("%") else { return nil }
        let digits = line.dropLast().reversed().prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let v = Double(String(digits.reversed())), v <= 100 else { return nil }
        return v / 100
    }
}
