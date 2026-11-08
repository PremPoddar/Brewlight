import Foundation

/// A package's downloads in Homebrew's cache. Homebrew 7 keeps the files in `downloads/` and points
/// at them with per-package symlinks: `<name>--<version>` and `<name>_bottle_manifest--<version>`
/// for formulae, `Cask/<token>--<version>.<ext>` for casks. Following those links finds exactly this
/// package's files, never another package's. Real files in older layouts count too.
enum PackageCache {
    struct Entry: Hashable, Sendable {
        /// This package's cache path: a symlink Homebrew made, or the file itself in older layouts.
        var link: URL
        /// The downloaded file it points to (nil if the link is broken).
        var file: URL?
        var size: Int64
    }

    static func entries(for p: Package, cache: URL) -> [Entry] {
        let fm = FileManager.default
        let (dir, prefixes): (URL, [String]) = p.kind == .cask
            ? (cache.appending(path: "Cask"), [p.token + "--"])
            : (cache, [p.token + "--", p.token + "_bottle_manifest--"])
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [Entry] = []
        for name in names where prefixes.contains(where: { name.hasPrefix($0) }) {
            let link = dir.appending(path: name)
            if let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                // Links are relative to their own folder ("downloads/…" or "../downloads/…").
                let target = (dest.hasPrefix("/") ? URL(fileURLWithPath: dest) : dir.appending(path: dest)).standardizedFileURL
                let exists = fm.fileExists(atPath: target.path)
                out.append(Entry(link: link, file: exists ? target : nil, size: exists ? Paths.diskSize(target) : 0))
            } else {
                // Not a symlink: Homebrew's older layouts cached the file (or folder) itself.
                out.append(Entry(link: link, file: link, size: Paths.diskSize(link)))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    static func totalSize(_ entries: [Entry]) -> Int64 { entries.reduce(0) { $0 + $1.size } }

    /// Deletes the files and their links. Returns paths that couldn't be removed.
    @discardableResult
    static func remove(_ entries: [Entry]) -> [String] {
        var failed: [String] = []
        for e in entries {
            // file == link for real-file entries; visit each path once.
            var visited: Set<String> = []
            for url in [e.file, e.link].compactMap({ $0 }) where visited.insert(url.path).inserted {
                do { try FileManager.default.removeItem(at: url) } catch { failed.append(url.path) }
            }
        }
        return failed
    }
}
