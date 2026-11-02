import Foundation

struct BrewService: Codable, Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var status: String
    var user: String?
    var file: String?
    var pid: Int?
    var exitCode: Int?

    var isRunning: Bool { status == "started" || status == "scheduled" }
    var isError: Bool { status == "error" }

    /// `brew services list --json`
    static func parse(_ json: Any?) -> [BrewService] {
        (json as? [[String: Any]] ?? []).map {
            BrewService(name: $0["name"] as? String ?? "", status: $0["status"] as? String ?? "none",
                        user: $0["user"] as? String, file: $0["file"] as? String,
                        pid: $0["pid"] as? Int, exitCode: $0["exit_code"] as? Int)
        }
    }

    /// Log files under `<prefix>/var/log` that look like they belong to this service.
    func logFiles(prefix: URL) -> [URL] {
        let logDir = prefix.appending(path: "var/log")
        let items = (try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)) ?? []
        let base = name.split(separator: "@").first.map(String.init) ?? name
        return items.filter { $0.lastPathComponent.lowercased().hasPrefix(base.lowercased()) }
    }
}

struct BrewTap: Codable, Identifiable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var remote: String?
    var path: String?
    var isOfficial: Bool
    var formulaCount: Int
    var caskCount: Int
    var lastCommit: String?
    /// False when Homebrew ignores the tap until `brew trust` (official taps are always trusted).
    var trusted: Bool? = nil

    /// `brew tap-info --json --installed`
    static func parse(_ json: Any?) -> [BrewTap] {
        (json as? [[String: Any]] ?? []).map {
            BrewTap(name: $0["name"] as? String ?? "", remote: $0["remote"] as? String, path: $0["path"] as? String,
                    isOfficial: $0["official"] as? Bool ?? false,
                    formulaCount: ($0["formula_names"] as? [Any])?.count ?? 0,
                    caskCount: ($0["cask_tokens"] as? [Any])?.count ?? 0,
                    lastCommit: $0["last_commit"] as? String,
                    trusted: $0["trusted"] as? Bool)
        }
    }

    /// `user/repo` or a git URL.
    static func isValidName(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("https://") || t.hasPrefix("git@") { return true }
        let parts = t.split(separator: "/")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }
    }
}
