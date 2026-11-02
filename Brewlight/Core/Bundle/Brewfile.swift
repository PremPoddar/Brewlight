import Foundation

/// Minimal Brewfile model: the entries `brew bundle` writes (`tap`, `brew`, `cask`, `mas`, `vscode`).
struct Brewfile: Sendable, Equatable {
    enum Section: String, CaseIterable, Sendable, Identifiable {
        case tap, brew, cask, mas, vscode
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tap: String(localized: "Taps")
            case .brew: String(localized: "Formulae")
            case .cask: String(localized: "Casks")
            case .mas: String(localized: "Mac App Store apps (mas)")
            case .vscode: String(localized: "VS Code extensions")
            }
        }
    }

    struct Entry: Sendable, Hashable, Identifiable {
        var id: String { "\(section.rawValue):\(name)" }
        var section: Section
        var name: String
        var line: String
    }

    var entries: [Entry]

    static func parse(_ text: String) -> Brewfile {
        var entries: [Entry] = []
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let space = line.firstIndex(of: " "),
                  let section = Section(rawValue: String(line[..<space])) else { continue }
            let rest = line[line.index(after: space)...]
            // First quoted string is the name.
            guard let q1 = rest.firstIndex(of: "\"") else { continue }
            let afterQ = rest[rest.index(after: q1)...]
            guard let q2 = afterQ.firstIndex(of: "\"") else { continue }
            entries.append(Entry(section: section, name: String(afterQ[..<q2]), line: line))
        }
        return Brewfile(entries: entries)
    }

    /// Keeps only the chosen sections, plus comments directly above kept lines (`--describe`).
    static func filter(_ text: String, keep: Set<Section>) -> String {
        var out: [String] = []
        var pendingComments: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { pendingComments.append(line); continue }
            if let word = trimmed.split(separator: " ").first, let s = Section(rawValue: String(word)) {
                if keep.contains(s) { out += pendingComments; out.append(line) }
            } else if !trimmed.isEmpty {
                out += pendingComments; out.append(line)
            }
            pendingComments = []
        }
        return out.joined(separator: "\n") + "\n"
    }

    struct Diff: Sendable {
        var toInstall: [Entry]
        var alreadyPresent: [Entry]
        /// Installed on this Mac but not in the Brewfile (formulae requested by the user, casks).
        var extra: [String]
    }

    func diff(installedFormulae: Set<String>, installedCasks: Set<String>, taps: Set<String>, requestedFormulae: Set<String>) -> Diff {
        var install: [Entry] = [], present: [Entry] = []
        for e in entries {
            let short = e.name.split(separator: "/").last.map(String.init) ?? e.name
            let have: Bool
            switch e.section {
            case .brew: have = installedFormulae.contains(short)
            case .cask: have = installedCasks.contains(short)
            case .tap: have = taps.contains(e.name.lowercased())
            case .mas, .vscode: have = false
            }
            if have { present.append(e) } else { install.append(e) }
        }
        let listedF = Set(entries.filter { $0.section == .brew }.map { $0.name.split(separator: "/").last.map(String.init) ?? $0.name })
        let listedC = Set(entries.filter { $0.section == .cask }.map { $0.name.split(separator: "/").last.map(String.init) ?? $0.name })
        let extra = requestedFormulae.subtracting(listedF).sorted() + installedCasks.subtracting(listedC).sorted().map { "cask: \($0)" }
        return Diff(toInstall: install, alreadyPresent: present, extra: extra)
    }

    /// Text for a Brewfile containing only the given entries.
    static func render(_ entries: [Entry]) -> String {
        Section.allCases.flatMap { s in entries.filter { $0.section == s }.map(\.line) }.joined(separator: "\n") + "\n"
    }
}
