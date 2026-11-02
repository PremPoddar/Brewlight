import Foundation

/// What a line of brew output is, for colouring the activity log.
enum LogKind: Sendable, Hashable {
    case plain, heading, success, warning, error, progress
}

/// Classifies brew output line by line. Stateful because brew's warnings and errors span several
/// lines: a `Warning:` block (like tap-trust instructions) continues until a blank line or the next
/// `==>` step.
struct LogClassifier: Sendable {
    private enum Block: Sendable { case none, warning, error }
    private var block = Block.none

    mutating func classify(_ text: String) -> LogKind {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { block = .none; return .plain }
        if ProgressParser.percent(in: t) != nil || t.allSatisfy({ "#=O-. ".contains($0) }) { return .progress }
        let lower = t.lowercased()
        if lower.hasPrefix("error:") || lower.hasPrefix("fatal:") || lower.hasPrefix("error ") {
            block = .error
            return .error
        }
        if lower.hasPrefix("warning:") {
            block = .warning
            return .warning
        }
        if t.hasPrefix("==>") {
            block = .none
            return .heading
        }
        if t.hasPrefix("🍺") || lower.contains("successfully") || lower.hasPrefix("already up-to-date")
            || lower.hasPrefix("your system is ready to brew") || lower.hasPrefix("updated ") && lower.contains("tap") {
            block = .none
            return .success
        }
        switch block {
        case .error: return .error
        case .warning: return .warning
        case .none: return .plain
        }
    }
}

/// Something in brew's output the user should act on.
enum OperationNotice: Hashable, Identifiable, Sendable {
    /// Homebrew is ignoring these taps until they're trusted (`brew trust`).
    case untrustedTaps([String])

    var id: String {
        switch self {
        case .untrustedTaps(let taps): "untrusted:" + taps.joined(separator: ",")
        }
    }
}

/// Spots actionable notices in brew output, line by line.
struct NoticeDetector: Sendable {
    private var collectingTaps = false
    private var taps: [String] = []

    /// Returns a notice once its block of output is complete.
    mutating func feed(_ text: String) -> OperationNotice? {
        if text.lowercased().contains("following taps are not trusted") {
            collectingTaps = true
            taps = []
            return nil
        }
        guard collectingTaps else { return nil }
        let isIndented = text.hasPrefix(" ") || text.hasPrefix("\t")
        let item = text.trimmingCharacters(in: .whitespaces)
        if isIndented, BrewTap.isValidName(item), !item.contains("://") {
            taps.append(item)
            return nil
        }
        return flush()
    }

    /// Ends any notice in progress (end of output).
    mutating func flush() -> OperationNotice? {
        defer { collectingTaps = false; taps = [] }
        return collectingTaps && !taps.isEmpty ? .untrustedTaps(taps) : nil
    }
}
