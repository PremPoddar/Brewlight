import Foundation

enum PackageCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case developerTools = "Developer Tools"
    case languages = "Languages & Runtimes"
    case databases = "Databases"
    case networking = "Networking"
    case security = "Security"
    case media = "Media & Graphics"
    case productivity = "Productivity"
    case browsers = "Browsers"
    case communication = "Communication"
    case utilities = "Utilities"
    case fonts = "Fonts"
    case games = "Games"
    case system = "System"
    case cloud = "Cloud & DevOps"
    case ai = "AI & ML"
    case terminal = "Terminal & Shell"
    case editors = "Editors & IDEs"
    case science = "Science"
    case other = "Other"

    var id: String { rawValue }
    var localizedName: String { String(localized: String.LocalizationValue(rawValue)) }

    var symbol: String {
        switch self {
        case .developerTools: "hammer"
        case .languages: "chevron.left.forwardslash.chevron.right"
        case .databases: "cylinder.split.1x2"
        case .networking: "network"
        case .security: "lock.shield"
        case .media: "photo.on.rectangle"
        case .productivity: "checklist"
        case .browsers: "globe"
        case .communication: "bubble.left.and.bubble.right"
        case .utilities: "wrench.and.screwdriver"
        case .fonts: "textformat"
        case .games: "gamecontroller"
        case .system: "gearshape.2"
        case .cloud: "cloud"
        case .ai: "brain"
        case .terminal: "apple.terminal"
        case .editors: "pencil.and.outline"
        case .science: "atom"
        case .other: "square.grid.2x2"
        }
    }

    /// Short slug for `cat:` search filters.
    var slug: String {
        rawValue.lowercased().split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? rawValue
    }
}

/// Category assignment: user override > bundled `categories.json` > keyword heuristic ("auto").
struct CategoryStore: Sendable {
    struct Assignment: Sendable, Hashable {
        let category: PackageCategory
        let isAuto: Bool
    }

    private var bundled: [String: PackageCategory] = [:]
    var version = 0

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        load(data)
    }

    init(json: Data) { load(json) }

    /// `{"version": 1, "categories": {"Developer Tools": ["git", "cask:docker-desktop", ...]}}`
    private mutating func load(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = obj["categories"] as? [String: [String]] else { return }
        version = obj["version"] as? Int ?? 0
        for (name, tokens) in cats {
            guard let cat = PackageCategory(rawValue: name) else { continue }
            for t in tokens { bundled[t] = cat }
        }
    }

    func category(for p: Package, overrides: [String: String] = [:]) -> Assignment {
        if let o = overrides[p.id], let cat = PackageCategory(rawValue: o) { return .init(category: cat, isAuto: false) }
        if let cat = bundled[p.id] ?? bundled[p.token] { return .init(category: cat, isAuto: false) }
        return .init(category: Self.heuristic(p), isAuto: true)
    }

    private static let rules: [(PackageCategory, [String])] = [
        (.fonts, ["font", "typeface"]),
        (.browsers, ["web browser", "browser"]),
        (.ai, [" ai ", "llm", "machine learning", "neural", "language model", "chatgpt", "openai", "inference", "deep learning", "ai-", "agent"]),
        (.databases, ["database", "sql", "postgres", "mysql", "redis", "sqlite", "mongodb", "key-value", "nosql"]),
        (.languages, ["programming language", "compiler", "interpreter", "runtime", "javascript runtime", "python", "ruby", "rust", "golang", " go ", "haskell", "erlang", "jdk", "java ", "scheme", "lisp"]),
        (.editors, ["text editor", "code editor", " ide", "editor"]),
        (.terminal, ["terminal", "shell", "prompt", "tmux", "zsh", "command-line interface", "tui"]),
        (.security, ["security", "encrypt", "password", "vpn", "firewall", "vulnerab", "crypto", "gpg", "ssl", "tls", "certificate", "malware", "forensic"]),
        (.cloud, ["kubernetes", "docker", "container", "cloud", "aws", "azure", "gcp", "terraform", "deploy", "devops", "ci/cd", "infrastructure", "serverless", "helm"]),
        (.networking, ["network", "http", "dns", "proxy", "tcp", "ssh", "ftp", "download", "bandwidth", "packet", "torrent"]),
        (.media, ["video", "audio", "image", "photo", "music", "graphics", "media", "pdf", "svg", "camera", "codec", "player", "3d"]),
        (.communication, ["chat", "messag", "mail", "slack", "meeting", "voice", "irc", "discord"]),
        (.games, ["game", "emulator", "chess", "steam"]),
        (.science, ["scientific", "bioinformatic", "genom", "math", "statistic", "astronom", "chemistry", "physics", "simulation"]),
        (.productivity, ["note", "todo", "calendar", "task", "markdown", "productivity", "clipboard", "launcher", "window manager", "time tracking"]),
        (.system, ["system", "disk", "monitor", "menu bar", "battery", "kernel", "macos", "finder", "uninstall", "backup"]),
        (.developerTools, ["git", "library", "sdk", "api", "build", "debug", "lint", "test", "framework", "parser", "json", "yaml", "developer", "code"]),
        (.utilities, ["utility", "tool", "convert", "file", "archive", "compress", "search"])
    ]

    private static let byteRules: [(PackageCategory, [[UInt8]])] = rules.map { cat, words in (cat, words.map { Array($0.utf8) }) }

    /// Keyword match over the description and name, using byte search (16k packages in a few ms).
    static func heuristic(_ p: Package) -> PackageCategory {
        if p.kind == .cask && p.token.hasPrefix("font-") { return .fonts }
        let hay = SearchIndex.lowerBytes(" \(p.desc) \(p.token) ")
        for (cat, words) in byteRules where words.contains(where: { SearchIndex.contains(hay, $0) }) { return cat }
        return .other
    }
}
