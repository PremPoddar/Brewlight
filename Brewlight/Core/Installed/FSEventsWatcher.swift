import CoreServices
import Foundation

/// Watches directories (Cellar, Caskroom, pinned) and calls back, coalesced, when anything changes,
/// so the UI stays live when the user runs `brew` in Terminal.
final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "brewlight.fsevents")
    private let callback: @Sendable () -> Void

    init(paths: [URL], latency: TimeInterval = 0.6, callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let existing = paths.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue().callback()
            },
            &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
