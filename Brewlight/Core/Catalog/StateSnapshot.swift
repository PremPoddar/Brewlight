import Foundation

/// The last-known installed state, written after it changes and read at launch so the window shows
/// real data immediately while Homebrew is re-checked in the background.
struct StateSnapshot: Codable, Sendable {
    var version = 1
    var installed: [InstalledPackage]
    var outdated: [OutdatedInfo]
    var outdatedCheckedAt: Date?
    var sizes: [String: Int64]
    var services: [BrewService]
    var taps: [BrewTap]
    var env: BrewEnvironment?

    static var url: URL { Paths.appSupport.appending(path: "state.plist") }

    static func load() -> StateSnapshot? {
        let t = Perf.begin("load.state")
        defer { Perf.end(t) }
        guard let data = try? Data(contentsOf: url),
              let s = try? PropertyListDecoder().decode(StateSnapshot.self, from: data), s.version == 1 else { return nil }
        return s
    }

    func save() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }
}
