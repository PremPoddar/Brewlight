import CFNetwork
import Foundation

/// Where Homebrew downloads from. Mirrors set Homebrew's documented environment variables
/// (`HOMEBREW_API_DOMAIN`, `HOMEBREW_BOTTLE_DOMAIN`, `HOMEBREW_BREW_GIT_REMOTE`).
enum DownloadMirror: String, CaseIterable, Identifiable, Sendable {
    case official, tuna, ustc, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .official: String(localized: "Official (GitHub / formulae.brew.sh)")
        case .tuna: String(localized: "Tsinghua University (TUNA)")
        case .ustc: String(localized: "USTC")
        case .custom: String(localized: "Custom…")
        }
    }

    /// API, bottle and brew-repository locations, or nil for Homebrew's defaults.
    var preset: (api: String, bottles: String, git: String)? {
        switch self {
        case .official, .custom: nil
        case .tuna: ("https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api",
                     "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles",
                     "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git")
        case .ustc: ("https://mirrors.ustc.edu.cn/homebrew-bottles/api",
                     "https://mirrors.ustc.edu.cn/homebrew-bottles",
                     "https://mirrors.ustc.edu.cn/brew.git")
        }
    }
}

/// Network-related environment for `brew`, from Settings → Network.
enum NetworkSettings {
    static let useSystemProxyKey = "useSystemProxy"
    static let mirrorKey = "downloadMirror"
    static let customAPIKey = "mirrorAPIDomain"
    static let customBottlesKey = "mirrorBottleDomain"
    static let customGitKey = "mirrorBrewGitRemote"

    static var mirror: DownloadMirror {
        DownloadMirror(rawValue: UserDefaults.standard.string(forKey: mirrorKey) ?? "") ?? .official
    }

    /// Variables to add to every brew invocation.
    static func environment(defaults: UserDefaults = .standard,
                            systemProxy: () -> [String: Any]? = Self.systemProxySettings) -> [String: String] {
        var env: [String: String] = [:]
        if defaults.object(forKey: useSystemProxyKey) as? Bool ?? true, let settings = systemProxy() {
            env.merge(proxyEnvironment(from: settings)) { a, _ in a }
        }
        let m = DownloadMirror(rawValue: defaults.string(forKey: mirrorKey) ?? "") ?? .official
        if let p = m.preset {
            env["HOMEBREW_API_DOMAIN"] = p.api
            env["HOMEBREW_BOTTLE_DOMAIN"] = p.bottles
            env["HOMEBREW_BREW_GIT_REMOTE"] = p.git
        } else if m == .custom {
            for (key, name) in [(customAPIKey, "HOMEBREW_API_DOMAIN"), (customBottlesKey, "HOMEBREW_BOTTLE_DOMAIN"), (customGitKey, "HOMEBREW_BREW_GIT_REMOTE")] {
                if let v = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespaces), !v.isEmpty { env[name] = v }
            }
        }
        return env
    }

    /// Base URL for Brewlight's own catalog fallback downloads (follows the mirror).
    static var apiBase: String {
        environment(systemProxy: { nil })["HOMEBREW_API_DOMAIN"] ?? "https://formulae.brew.sh/api"
    }

    static func systemProxySettings() -> [String: Any]? {
        CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
    }

    /// macOS proxy settings → curl-style variables, which Homebrew (curl and git) understands.
    static func proxyEnvironment(from s: [String: Any]) -> [String: String] {
        func endpoint(_ enable: String, _ host: String, _ port: String, scheme: String) -> String? {
            guard (s[enable] as? Int ?? 0) == 1, let h = s[host] as? String, !h.isEmpty else { return nil }
            let p = (s[port] as? Int).map { ":\($0)" } ?? ""
            return "\(scheme)://\(h)\(p)"
        }
        var env: [String: String] = [:]
        if let http = endpoint("HTTPEnable", "HTTPProxy", "HTTPPort", scheme: "http") {
            env["http_proxy"] = http
            env["HTTP_PROXY"] = http
        }
        if let https = endpoint("HTTPSEnable", "HTTPSProxy", "HTTPSPort", scheme: "http") {
            env["https_proxy"] = https
            env["HTTPS_PROXY"] = https
        }
        if let socks = endpoint("SOCKSEnable", "SOCKSProxy", "SOCKSPort", scheme: "socks5h") {
            env["all_proxy"] = socks
            env["ALL_PROXY"] = socks
        }
        if !env.isEmpty, let exceptions = s["ExceptionsList"] as? [String], !exceptions.isEmpty {
            let list = exceptions.map { $0.replacingOccurrences(of: "*.", with: ".") }.joined(separator: ",")
            env["no_proxy"] = list
            env["NO_PROXY"] = list
        }
        return env
    }

    /// One-line description of the active macOS proxy, for Settings.
    static func systemProxySummary() -> String? {
        guard let s = systemProxySettings() else { return nil }
        let env = proxyEnvironment(from: s)
        return env["https_proxy"] ?? env["http_proxy"] ?? env["all_proxy"]
    }
}
