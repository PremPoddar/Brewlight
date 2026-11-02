import Foundation

/// Install counts from formulae.brew.sh analytics (30/90/365 days), cached on disk for a day.
struct Popularity: Codable, Sendable {
    /// package id -> installs
    var installs30: [String: Int] = [:]
    var installs90: [String: Int] = [:]
    var installs365: [String: Int] = [:]
    var fetchedAt: Date = .distantPast

    /// Ratio of the last 30 days to the average 30 days of the last 90, minus one.
    /// Positive means the package is growing.
    func trend(_ id: String) -> Double? {
        guard let a = installs30[id], let b = installs90[id], b > 0, a >= 500 else { return nil }
        return Double(a) / (Double(b) / 3.0) - 1.0
    }
}

actor PopularityStore {
    private let file = Paths.caches.appending(path: "analytics.plist")

    func cached() -> Popularity? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? PropertyListDecoder().decode(Popularity.self, from: data)
    }

    func refresh(force: Bool = false) async -> Popularity? {
        if !force, let c = cached(), c.fetchedAt.timeIntervalSinceNow > -86_400 { return c }
        var p = Popularity()
        async let f30 = fetch("install", "30d")
        async let c30 = fetch("cask-install", "30d")
        async let f90 = fetch("install", "90d")
        async let c90 = fetch("cask-install", "90d")
        async let f365 = fetch("install", "365d")
        async let c365 = fetch("cask-install", "365d")
        p.installs30 = (await f30).merging(await c30) { a, _ in a }
        p.installs90 = (await f90).merging(await c90) { a, _ in a }
        p.installs365 = (await f365).merging(await c365) { a, _ in a }
        guard !p.installs30.isEmpty else { return cached() }
        p.fetchedAt = .now
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try? encoder.encode(p).write(to: file, options: .atomic)
        return p
    }

    private func fetch(_ category: String, _ period: String) async -> [String: Int] {
        guard let url = URL(string: "https://formulae.brew.sh/api/analytics/\(category)/\(period).json"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [:] }
        return Self.parse(data)
    }

    /// `{"items": [{"formula": "x", "count": "1,234"} | {"cask": "y", ...}]}`
    static func parse(_ data: Data) -> [String: Int] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [:] }
        var out: [String: Int] = [:]
        for item in items {
            let count = Int((item["count"] as? String ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
            // Analytics keys options too ("ffmpeg --HEAD"); keep the base name and add them up.
            if let f = item["formula"] as? String {
                let name = String(f.split(separator: " ").first ?? "")
                out[Package.id(.formula, name), default: 0] += count
            } else if let c = item["cask"] as? String {
                out[Package.id(.cask, c), default: 0] += count
            }
        }
        return out
    }
}
