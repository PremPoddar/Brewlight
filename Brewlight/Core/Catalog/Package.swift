import Foundation

enum PackageKind: String, Codable, Sendable, CaseIterable, Hashable {
    case formula, cask

    var label: String {
        switch self {
        case .formula: String(localized: "Formula")
        case .cask: String(localized: "Cask")
        }
    }
    var badge: String { rawValue }
    var flag: String { self == .cask ? "--cask" : "--formula" }
}

/// Catalog data for one formula or cask. Immutable; installed state lives in `InstalledPackage`.
struct Package: Codable, Sendable, Identifiable, Hashable {
    /// `formula:<name>` or `cask:<token>`; unique across both kinds. Stored, because it is
    /// looked up for every row on every keystroke.
    let id: String
    let kind: PackageKind
    let token: String
    var fullName: String
    var displayName: String
    var desc: String
    var homepage: String
    var version: String
    var revision: Int = 0
    var license: String?
    var tap: String
    var aliases: [String] = []
    var oldNames: [String] = []
    var caveats: String?

    // Formula dependencies
    var dependencies: [String] = []
    var buildDependencies: [String] = []
    var optionalDependencies: [String] = []
    var recommendedDependencies: [String] = []
    var usesFromMacOS: [String] = []
    var hasBottle = false
    var kegOnly = false
    var hasHead = false
    var hasService = false
    var versionedFormulae: [String] = []
    var conflicts: [String] = []

    var deprecationReason: String?
    var disableReason: String?
    var replacement: String?

    // Cask data
    var autoUpdates = false
    var appNames: [String] = []
    var binaries: [String] = []
    var pkgs: [String] = []
    var zapPaths: [String] = []
    var macOSRequirement: String?
    var caskFormulaDependencies: [String] = []

    var isDeprecated: Bool { deprecationReason != nil }
    var isDisabled: Bool { disableReason != nil }
    var isOfficial: Bool { tap.hasPrefix("homebrew/") }

    /// Version as Homebrew writes it into the Cellar, including the revision suffix.
    var fullVersion: String { revision > 0 ? "\(version)_\(revision)" : version }

    var homepageURL: URL? { URL(string: homepage) }
    var homepageHost: String {
        (homepageURL?.host() ?? homepage).replacingOccurrences(of: "www.", with: "")
    }

    var installCommand: String {
        kind == .cask ? "brew install --cask \(token)" : "brew install \(token)"
    }

    /// GitHub URL of the formula/cask source in its tap, for "View formula source".
    var sourceURL: URL? {
        guard isOfficial else { return nil }
        if kind == .formula {
            let first = token.first.map(String.init) ?? "a"
            return URL(string: "https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/\(first)/\(token).rb")
        } else {
            let first = token.first.map(String.init) ?? "a"
            return URL(string: "https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/\(first)/\(token).rb")
        }
    }

    var issuesURL: URL? {
        guard let url = homepageURL, url.host() == "github.com" else { return nil }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else { return nil }
        return URL(string: "https://github.com/\(comps[0])/\(comps[1])/issues")
    }

    /// GitHub releases page when the homepage is a GitHub repository.
    var releasesURL: URL? {
        guard let url = homepageURL, url.host() == "github.com" else { return nil }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2 else { return nil }
        return URL(string: "https://github.com/\(comps[0])/\(comps[1])/releases")
    }

    init(kind: PackageKind, token: String, fullName: String, displayName: String, desc: String, homepage: String,
         version: String, revision: Int = 0, license: String? = nil, tap: String) {
        self.id = Self.id(kind, token)
        self.kind = kind
        self.token = token
        self.fullName = fullName
        self.displayName = displayName
        self.desc = desc
        self.homepage = homepage
        self.version = version
        self.revision = revision
        self.license = license
        self.tap = tap
    }

    static func id(_ kind: PackageKind, _ token: String) -> String { "\(kind.rawValue):\(token)" }
}

/// Everything known about the catalog at a point in time.
struct Catalog: Codable, Sendable {
    var packages: [Package]
    var formulaAliases: [String: String]
    var generatedAt: Date?
    var sourceDescription: String

    static let empty = Catalog(packages: [], formulaAliases: [:], generatedAt: nil, sourceDescription: "")
}
