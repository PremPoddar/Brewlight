import Foundation

/// Paths of a Homebrew installation. Resolved once and cached.
struct BrewEnvironment: Codable, Sendable, Equatable {
    var brew: URL
    var prefix: URL
    var cellar: URL
    var caskroom: URL
    var cache: URL
    var repository: URL
    var version: String

    var pinnedDir: URL { prefix.appending(path: "var/homebrew/pinned") }
    var optDir: URL { prefix.appending(path: "opt") }
    var tapsDir: URL { repository.appending(path: "Library/Taps") }

    /// Bin directories brew needs on PATH.
    var path: String {
        [prefix.appending(path: "bin").path, prefix.appending(path: "sbin").path,
         "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
    }
}

enum BrewLocator {
    static let overrideKey = "brewPathOverride"
    private static let cacheKey = "brewEnvironmentCache"

    /// Finds `brew` without blocking the caller's actor. Never hard-codes the prefix:
    /// checks the user override, the two standard locations, then a login shell's PATH.
    static func locate(override: String?) async -> BrewEnvironment? {
        await Task.detached(priority: .userInitiated) { () -> BrewEnvironment? in
            guard let brew = findBrew(override: override) else { return nil }
            if let cached = loadCached(), cached.brew == brew,
               FileManager.default.fileExists(atPath: cached.cellar.path) {
                return cached
            }
            let env = resolve(brew: brew)
            if let env { saveCached(env) }
            return env
        }.value
    }

    static func findBrew(override: String?) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let override, !override.isEmpty { candidates.append(override) }
        candidates += ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for c in candidates where fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        // Custom prefix: ask a login shell.
        if let out = try? runSync("/bin/zsh", ["-lc", "command -v brew"]),
           let line = out.split(separator: "\n").last.map(String.init),
           fm.isExecutableFile(atPath: line) {
            return URL(fileURLWithPath: line)
        }
        return nil
    }

    /// Derives every path from one `brew --prefix` style call batch.
    static func resolve(brew: URL) -> BrewEnvironment? {
        let script = "\(brew.path) --prefix; \(brew.path) --cellar; \(brew.path) --caskroom; \(brew.path) --cache; \(brew.path) --repository; \(brew.path) --version"
        guard let out = try? runSync("/bin/sh", ["-c", script], env: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]) else { return nil }
        let lines = out.split(separator: "\n").map(String.init)
        guard lines.count >= 6 else { return nil }
        let version = lines[5].replacingOccurrences(of: "Homebrew ", with: "")
        return BrewEnvironment(
            brew: brew,
            prefix: URL(fileURLWithPath: lines[0]),
            cellar: URL(fileURLWithPath: lines[1]),
            caskroom: URL(fileURLWithPath: lines[2]),
            cache: URL(fileURLWithPath: lines[3]),
            repository: URL(fileURLWithPath: lines[4]),
            version: version)
    }

    static func invalidateCache() { UserDefaults.standard.removeObject(forKey: cacheKey) }

    private static func loadCached() -> BrewEnvironment? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(BrewEnvironment.self, from: data)
    }

    private static func saveCached(_ env: BrewEnvironment) {
        if let data = try? JSONEncoder().encode(env) { UserDefaults.standard.set(data, forKey: cacheKey) }
    }

    /// Small synchronous helper for locating brew. Only call from a background task.
    static func runSync(_ exe: String, _ args: [String], env: [String: String] = [:]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
