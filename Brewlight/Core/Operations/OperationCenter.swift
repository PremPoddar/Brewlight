import Foundation
import Observation

/// One brew invocation tracked in the Activity panel.
@MainActor @Observable
final class BrewOperation: Identifiable {
    enum State: Equatable {
        case queued, running, succeeded, failed(Int32), cancelled

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .cancelled: true
            default: false
            }
        }
    }

    let id = UUID()
    let title: String
    let args: [String]
    let packages: [String]
    let isMutating: Bool
    var state: State = .queued
    var phase: OperationPhase = .queued
    var percent: Double?
    private(set) var log: [OutputLine] = []
    var needsTerminal = false
    /// Things in the output the user should act on (e.g. untrusted taps).
    private(set) var notices: [OperationNotice] = []
    @ObservationIgnored private var classifier = LogClassifier()
    @ObservationIgnored private var detector = NoticeDetector()

    /// Adds a line, classifying it once. Returns a notice if this line completed one.
    @discardableResult
    func append(_ line: OutputLine) -> OperationNotice? {
        var l = line
        l.kind = classifier.classify(line.text)
        log.append(l)
        return record(detector.feed(line.text))
    }

    /// Ends output; returns a notice still being collected.
    func finishOutput() -> OperationNotice? { record(detector.flush()) }

    func replaceLog(_ lines: [OutputLine]) {
        log = []
        for l in lines { append(l) }
    }

    private func record(_ notice: OperationNotice?) -> OperationNotice? {
        guard let notice, !notices.contains(notice) else { return nil }
        notices.append(notice)
        return notice
    }
    let queuedAt = Date()
    var startedAt: Date?
    var finishedAt: Date?

    init(title: String, args: [String], packages: [String], isMutating: Bool) {
        self.title = title
        self.args = args
        self.packages = packages
        self.isMutating = isMutating
    }

    var command: String { "brew " + args.joined(separator: " ") }
    var duration: TimeInterval? {
        guard let s = startedAt else { return nil }
        return (finishedAt ?? .now).timeIntervalSince(s)
    }
    var errorLines: [String] { log.filter { $0.kind == .error }.map(\.text) }
    var fullLog: String { log.map(\.text).joined(separator: "\n") }

    var bugReport: String {
        """
        Command: \(command)
        Result: \(state)
        Brewlight \(AppInfo.version) (\(AppInfo.build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)

        \(log.suffix(80).map(\.text).joined(separator: "\n"))
        """
    }
}

/// Runs brew commands. Mutating operations go through a strict FIFO queue because Homebrew
/// holds a global lock; read-only commands run immediately alongside.
@MainActor @Observable
final class OperationCenter {
    private(set) var operations: [BrewOperation] = []
    private var runner: (any BrewRunning)?
    private var queueTask: Task<Void, Never>?
    private var pending: [BrewOperation] = []
    /// Called on the main actor when an operation finishes (refresh state, record history).
    var onFinish: ((BrewOperation) -> Void)?
    /// Called when brew's output contains something the user should act on.
    var onNotice: ((BrewOperation, OperationNotice) -> Void)?

    /// Seconds without any output after which an operation is assumed stuck (e.g. a hidden prompt).
    var stallTimeout: TimeInterval = 15 * 60

    var running: BrewOperation? { operations.first { $0.state == .running && $0.isMutating } }
    var active: [BrewOperation] { operations.filter { !$0.state.isFinished } }
    var hasActive: Bool { !active.isEmpty }

    /// Overall progress for the toolbar ring: running op's percent, or indeterminate.
    var overallProgress: Double? {
        guard let r = running else { return nil }
        return r.percent
    }

    func configure(runner: any BrewRunning) { self.runner = runner }

    @discardableResult
    func enqueue(_ title: String, _ args: [String], packages: [String] = [], mutating: Bool = true) -> BrewOperation {
        let op = BrewOperation(title: title, args: args, packages: packages, isMutating: mutating)
        operations.insert(op, at: 0)
        if mutating {
            pending.append(op)
            pumpQueue()
        } else {
            Task { await execute(op) }
        }
        return op
    }

    func cancel(_ op: BrewOperation) {
        if op.state == .queued {
            pending.removeAll { $0.id == op.id }
            op.state = .cancelled
            op.finishedAt = .now
            return
        }
        guard op.state == .running, let runner else { return }
        let args = op.args
        Task { await runner.cancel(args) }
        cancelledIDs.insert(op.id)
        streamTasks[op.id]?.cancel()
    }

    func cancelAll() {
        for op in active { cancel(op) }
    }

    func retry(_ op: BrewOperation) {
        enqueue(op.title, op.args, packages: op.packages, mutating: op.isMutating)
    }

    func clearFinished() {
        operations.removeAll { $0.state.isFinished }
    }

    // MARK: Execution

    private var cancelledIDs: Set<UUID> = []
    private var streamTasks: [UUID: Task<Void, Never>] = [:]

    private func pumpQueue() {
        guard queueTask == nil else { return }
        queueTask = Task {
            while !pending.isEmpty {
                let op = pending.removeFirst()
                await execute(op)
            }
            queueTask = nil
        }
    }

    private func execute(_ op: BrewOperation) async {
        guard let runner else {
            op.state = .failed(-1)
            op.append(OutputLine(stream: .stderr, text: String(localized: "Error: Homebrew is not available.")))
            return
        }
        op.state = .running
        op.phase = .starting
        op.startedAt = .now
        var lastOutput = Date()
        var status: Int32 = -1

        let watchdog = Task { [stallTimeout] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Date().timeIntervalSince(lastOutput) > stallTimeout {
                    op.append(OutputLine(stream: .stderr, text: String(localized: "Error: No output for a long time. It may be waiting for input it can't get; cancelling.")))
                    op.needsTerminal = true
                    self.cancel(op)
                    return
                }
            }
        }

        let task = Task {
            for await event in runner.stream(op.args, extraEnv: [:]) {
                switch event {
                case .line(let line):
                    lastOutput = .now
                    if let notice = op.append(line) { self.onNotice?(op, notice) }
                    let u = ProgressParser.parse(line.text)
                    if let p = u.phase { op.phase = p }
                    if let pct = u.percent { op.percent = pct }
                    if u.needsTerminal { op.needsTerminal = true }
                case .exit(let s):
                    status = s
                }
            }
        }
        streamTasks[op.id] = task
        await task.value
        watchdog.cancel()
        streamTasks[op.id] = nil

        if let notice = op.finishOutput() { onNotice?(op, notice) }
        op.finishedAt = .now
        if cancelledIDs.remove(op.id) != nil {
            op.state = .cancelled
        } else {
            op.state = status == 0 ? .succeeded : .failed(status)
        }
        op.phase = .done
        op.percent = op.state == .succeeded ? 1 : op.percent
        onFinish?(op)
    }
}
