import Foundation
import os

/// One line of output from a brew invocation.
struct OutputLine: Sendable, Hashable {
    enum Stream: Sendable { case stdout, stderr }
    let stream: Stream
    let text: String
    /// Set when the line is added to an operation's log (see `LogClassifier`).
    var kind: LogKind = .plain
}

enum RunEvent: Sendable {
    case line(OutputLine)
    case exit(Int32)
}

/// Anything that can run `brew`. The real implementation is `BrewRunner`; tests and demo mode
/// use `MockBrewRunner`, which replays recorded output.
protocol BrewRunning: Sendable {
    func stream(_ args: [String], extraEnv: [String: String]) -> AsyncStream<RunEvent>
    func cancel(_ args: [String]) async
}

extension BrewRunning {
    /// Runs to completion and returns stdout, stderr and the exit status.
    func output(_ args: [String], extraEnv: [String: String] = [:]) async -> (stdout: String, stderr: String, status: Int32) {
        var out: [String] = [], err: [String] = []
        var status: Int32 = -1
        for await event in stream(args, extraEnv: extraEnv) {
            switch event {
            case .line(let l): if l.stream == .stdout { out.append(l.text) } else { err.append(l.text) }
            case .exit(let s): status = s
            }
        }
        return (out.joined(separator: "\n"), err.joined(separator: "\n"), status)
    }

    func json(_ args: [String]) async -> Any? {
        let r = await output(args)
        guard r.status == 0, let data = r.stdout.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

/// Runs `brew` with a controlled environment, streaming output line by line.
///
/// Mutating commands are serialized by `OperationCenter` (Homebrew takes a global lock);
/// read-only commands may run concurrently through this actor.
actor BrewRunner: BrewRunning {
    private let env: BrewEnvironment
    private let extraEnvironment: @Sendable () -> [String: String]
    private var running: [UUID: (args: [String], process: Process)] = [:]
    private static let log = Logger(subsystem: "com.prempoddar.brewlight", category: "runner")

    init(env: BrewEnvironment, extraEnvironment: @escaping @Sendable () -> [String: String] = { [:] }) {
        self.env = env
        self.extraEnvironment = extraEnvironment
    }

    /// Environment for every brew call. Single operations never auto-update; output is plain.
    nonisolated func environment(extra: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = env.path
        e["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        e["HOMEBREW_NO_ENV_HINTS"] = "1"
        e["HOMEBREW_NO_EMOJI"] = "1"
        e["HOMEBREW_COLOR"] = "0"
        e["HOMEBREW_NO_COLOR"] = "1"
        e["NONINTERACTIVE"] = "1"
        e["TERM"] = "dumb"
        if let askpass = AskPass.helperPath { e["SUDO_ASKPASS"] = askpass }
        for (k, v) in extraEnvironment() { e[k] = v }
        for (k, v) in extra { e[k] = v }
        return e
    }

    nonisolated func stream(_ args: [String], extraEnv: [String: String]) -> AsyncStream<RunEvent> {
        AsyncStream { continuation in
            let id = UUID()
            let process = Process()
            process.executableURL = env.brew
            process.arguments = args
            process.environment = environment(extra: extraEnv)
            // No TTY and no stdin: anything that wants to prompt fails fast instead of hanging.
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err

            let outBuffer = LineBuffer(stream: .stdout, continuation: continuation)
            let errBuffer = LineBuffer(stream: .stderr, continuation: continuation)
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { outBuffer.append(d) }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil } else { errBuffer.append(d) }
            }
            process.terminationHandler = { [weak self] p in
                // Drain anything left after the handlers are torn down.
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                outBuffer.append(out.fileHandleForReading.readDataToEndOfFile())
                errBuffer.append(err.fileHandleForReading.readDataToEndOfFile())
                outBuffer.flush(); errBuffer.flush()
                continuation.yield(.exit(p.terminationStatus))
                continuation.finish()
                Task { await self?.forget(id) }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning { Self.interrupt(process) }
            }
            Self.log.debug("brew \(args.joined(separator: " "), privacy: .public)")
            // posix_spawn takes milliseconds; never do it on the caller's (often the main) thread.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    Task { await self.remember(id, args: args, process: process) }
                } catch {
                    continuation.yield(.line(OutputLine(stream: .stderr, text: error.localizedDescription)))
                    continuation.yield(.exit(-1))
                    continuation.finish()
                }
            }
        }
    }

    func cancel(_ args: [String]) {
        for (_, entry) in running where entry.args == args { Self.interrupt(entry.process) }
    }

    private func remember(_ id: UUID, args: [String], process: Process) { running[id] = (args, process) }
    private func forget(_ id: UUID) { running[id] = nil }

    /// SIGINT first (brew cleans up), SIGTERM if it is still running after three seconds.
    nonisolated static func interrupt(_ process: Process) {
        guard process.isRunning else { return }
        process.interrupt()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if process.isRunning { kill(pid, SIGTERM) }
        }
    }
}

/// Splits a byte stream into lines. Handles `\r` progress updates by treating them as line breaks.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let stream: OutputLine.Stream
    private let continuation: AsyncStream<RunEvent>.Continuation

    init(stream: OutputLine.Stream, continuation: AsyncStream<RunEvent>.Continuation) {
        self.stream = stream
        self.continuation = continuation
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        while let idx = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = pending[pending.startIndex..<idx]
            pending.removeSubrange(pending.startIndex...idx)
            emit(lineData)
        }
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        if !pending.isEmpty { emit(pending); pending.removeAll() }
    }

    private func emit(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        continuation.yield(.line(OutputLine(stream: stream, text: text)))
    }
}

/// Locates the bundled `SUDO_ASKPASS` helper.
enum AskPass {
    static let helperPath: String? = {
        let url = Bundle.main.bundleURL.appending(path: "Contents/MacOS/BrewlightAskPass")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }()
}
