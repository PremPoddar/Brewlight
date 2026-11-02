import Foundation

enum Paths {
    static var appSupport: URL {
        let url = URL.applicationSupportDirectory.appending(path: AppInfo.isDemo ? "Brewlight-Demo" : "Brewlight")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var caches: URL {
        let url = URL.cachesDirectory.appending(path: AppInfo.bundleID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var iconCache: URL {
        let url = caches.appending(path: "Icons")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var logs: URL {
        let url = URL.libraryDirectory.appending(path: "Logs/Brewlight")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Expands `~` and resolves shell globs (`*`) in Homebrew zap paths, returning paths that exist.
    static func expandExisting(_ pattern: String) -> [URL] {
        let expanded = (pattern as NSString).expandingTildeInPath
        guard expanded.contains("*") || expanded.contains("?") else {
            return FileManager.default.fileExists(atPath: expanded) ? [URL(fileURLWithPath: expanded)] : []
        }
        var gt = glob_t()
        defer { globfree(&gt) }
        guard glob(expanded, 0, nil, &gt) == 0 else { return [] }
        return (0..<Int(gt.gl_pathc)).compactMap { i in
            gt.gl_pathv[i].map { URL(fileURLWithPath: String(cString: $0)) }
        }
    }

    /// Recursive allocated size of a file or directory. Call off the main thread.
    static func diskSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true { return Int64(values.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: nil)
        while let item = e?.nextObject() as? URL {
            if let v = try? item.resourceValues(forKeys: keys), v.isDirectory != true, v.isSymbolicLink != true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
