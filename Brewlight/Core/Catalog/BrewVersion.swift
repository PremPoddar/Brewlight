import Foundation

/// A Homebrew version string with Homebrew-like ordering.
///
/// Handles formula revisions (`1.2.3_1`), cask build suffixes (`1.2.3,20260927`),
/// date versions (`2026-10-20`), and pre-release words (`1.0beta2` < `1.0`).
struct BrewVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let raw: String
    let revision: Int
    private let parts: [Part]

    enum Part: Hashable, Sendable {
        case number(Int)
        case word(String)
    }

    init(_ raw: String) {
        self.raw = raw
        var base = raw
        var rev = 0
        // Formula revisions are a trailing `_N`.
        if let underscore = base.lastIndex(of: "_"),
           let n = Int(base[base.index(after: underscore)...]) {
            rev = n
            base = String(base[..<underscore])
        }
        revision = rev
        parts = Self.tokenize(base)
    }

    var description: String { raw }

    /// `latest` and other non-comparable cask versions.
    var isUnversioned: Bool { raw == "latest" || raw.isEmpty }

    static func tokenize(_ s: String) -> [Part] {
        var result: [Part] = []
        var current = ""
        var currentIsDigit: Bool?
        func flush() {
            guard !current.isEmpty else { return }
            if currentIsDigit == true, let n = Int(current) {
                result.append(.number(n))
            } else {
                result.append(.word(current.lowercased()))
            }
            current = ""
        }
        for ch in s {
            if ch == "." || ch == "-" || ch == "," || ch == "+" || ch == "_" || ch == " " {
                flush(); currentIsDigit = nil
                continue
            }
            let isDigit = ch.isASCII && ch.isNumber
            if let c = currentIsDigit, c != isDigit { flush() }
            currentIsDigit = isDigit
            current.append(ch)
        }
        flush()
        return result
    }

    private static let preRelease: Set<String> = ["alpha", "a", "beta", "b", "pre", "rc", "dev", "preview"]

    static func < (lhs: BrewVersion, rhs: BrewVersion) -> Bool {
        let n = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<n {
            let l = i < lhs.parts.count ? lhs.parts[i] : nil
            let r = i < rhs.parts.count ? rhs.parts[i] : nil
            switch (l, r) {
            case let (.number(a)?, .number(b)?):
                if a != b { return a < b }
            case let (.word(a)?, .word(b)?):
                if a != b {
                    let ap = preRelease.contains(a), bp = preRelease.contains(b)
                    if ap != bp { return ap }
                    return a < b
                }
            case (.number?, .word(let w)?):
                // 1.0.1 > 1.0beta; a number beats a word
                _ = w; return false
            case (.word?, .number?):
                return true
            case (nil, .word(let w)?):
                // 1.0 > 1.0beta
                return !preRelease.contains(w)
            case (.word(let w)?, nil):
                return preRelease.contains(w)
            case (nil, .number?):
                return true
            case (.number?, nil):
                return false
            case (nil, nil):
                break
            }
        }
        return lhs.revision < rhs.revision
    }

    static func == (lhs: BrewVersion, rhs: BrewVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(raw) }
}
