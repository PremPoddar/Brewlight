import Foundation
import FoundationModels

/// A plain-language request turned into Brewlight's search filters.
struct SmartQuery: Equatable, Sendable {
    enum Source: Sendable { case onDeviceModel, keywords }

    var kind: PackageKind?
    var categories: [PackageCategory] = []
    var keywords: [String] = []
    var installedOnly = false
    var source: Source = .keywords

    /// What goes in the search field, e.g. `type:cask cat:media video editor`.
    var queryString: String {
        var parts: [String] = []
        if let kind { parts.append("type:\(kind.rawValue)") }
        if installedOnly { parts.append("is:installed") }
        parts += categories.map { "cat:\($0.slug)" }
        parts += keywords
        return parts.joined(separator: " ")
    }
}

/// The on-device model's output shape (guided generation).
@Generable
struct SmartSearchPlan {
    @Guide(description: "\"cask\" for apps with a window, \"formula\" for command-line tools and libraries, or \"\" when unclear.")
    var kind: String
    @Guide(description: "Zero to two category names, copied exactly from the list in the instructions.")
    var categories: [String]
    @Guide(description: "One to four short words likely to appear in package names or descriptions, e.g. video, editor, pdf. Never generic words like app, tool, software, mac.")
    var keywords: [String]
    @Guide(description: "True only if the user is asking about things they already have installed.")
    var installedOnly: Bool
}

enum SmartSearch {
    /// Three or more words and no filter syntax: worth interpreting rather than matching literally.
    static func looksLikeNaturalLanguage(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.count >= 3 && !words.contains { $0.contains(":") }
    }

    static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Uses Apple's on-device model when available (nothing leaves the Mac), otherwise keywords.
    static func interpret(_ text: String) async -> SmartQuery {
        if isModelAvailable, let q = try? await viaModel(text) { return q }
        return heuristic(text)
    }

    private static func viaModel(_ text: String) async throws -> SmartQuery {
        let names = PackageCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You turn a request for Mac software into search filters for the Homebrew package catalog \
            (command-line formulae and app casks). Categories: \(names).
            """)
        let plan = try await session.respond(to: text, generating: SmartSearchPlan.self).content
        var q = SmartQuery(source: .onDeviceModel)
        q.kind = PackageKind(rawValue: plan.kind.lowercased())
        q.categories = plan.categories.compactMap { name in
            PackageCategory.allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }
        }.prefix(2).map { $0 }
        q.keywords = plan.keywords.map { singular($0.lowercased()) }.filter { !stopWords.contains($0) && !$0.contains(" ") }.prefix(4).map { $0 }
        q.installedOnly = plan.installedOnly
        if q.keywords.isEmpty && q.categories.isEmpty { return heuristic(text) }
        return q
    }

    static let stopWords: Set<String> = [
        "a", "an", "the", "for", "to", "of", "and", "or", "with", "on", "in", "my", "me", "i", "some", "something",
        "that", "which", "can", "could", "want", "need", "looking", "find", "show", "lets", "let", "good", "best", "mac",
        "macos", "app", "apps", "application", "applications", "tool", "tools", "program", "software", "thing", "free",
        "help", "helps", "way", "like", "is", "are", "do", "does", "use", "using", "from", "what", "installed", "already", "have"
    ]

    /// Keyword fallback: category words from the heuristic rules, app/CLI hints, and the rest as keywords.
    static func heuristic(_ text: String) -> SmartQuery {
        let lower = text.lowercased()
        var q = SmartQuery(source: .keywords)
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { ["app", "apps", "gui", "application", "applications", "window"].contains($0) }) { q.kind = .cask }
        if lower.contains("command line") || lower.contains("command-line") || words.contains(where: { ["cli", "cmdline"].contains($0) }) { q.kind = .formula }
        q.installedOnly = lower.contains("installed") || lower.contains(" i have") || lower.hasPrefix("my ")
        let probe = Package(kind: .formula, token: "", fullName: "", displayName: "", desc: lower, homepage: "", version: "", tap: "")
        let cat = CategoryStore.heuristic(probe)
        if cat != .other { q.categories = [cat] }
        q.keywords = Array(words.filter { $0.count > 2 && !stopWords.contains($0) && !filterWords.contains($0) }.map(singular).prefix(4))
        return q
    }

    /// Words that only choose a filter (type:formula/cask) and would add noise as search terms.
    static let filterWords: Set<String> = ["command", "line", "cli", "gui", "window"]

    /// "videos" → "video", "images" → "image", "files" → "file"; prefix matching does the rest.
    static func singular(_ w: String) -> String {
        guard w.count > 4, w.hasSuffix("s"), !w.hasSuffix("ss") else { return w }
        return String(w.dropLast())
    }
}
