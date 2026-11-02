import Foundation
import os

/// Lightweight timing: `os_signpost` intervals for Instruments plus recorded durations
/// for the in-app Performance HUD (Debug → Show Performance HUD).
enum Perf {
    static let signposter = OSSignposter(subsystem: "com.example.brewlight", category: .pointsOfInterest)
    static let processStart = Date()

    struct Token: Sendable {
        let name: StaticString
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    static func begin(_ name: StaticString) -> Token {
        Token(name: name, state: signposter.beginInterval(name), start: .now)
    }

    static func end(_ token: Token) {
        signposter.endInterval(token.name, token.state)
        let ms = (ContinuousClock.now - token.start).milliseconds
        let label = "\(token.name)"
        Task { @MainActor in PerfLog.shared.record(label, ms: ms) }
    }

    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let t = begin(name)
        defer { end(t) }
        return try body()
    }
}

extension Duration {
    var milliseconds: Double {
        let c = components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

@MainActor @Observable
final class PerfLog {
    static let shared = PerfLog()
    private(set) var latest: [String: Double] = [:]
    private(set) var order: [String] = []

    func record(_ name: String, ms: Double) {
        if latest[name] == nil { order.append(name) }
        latest[name] = ms
    }
}
