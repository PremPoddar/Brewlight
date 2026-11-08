import AppKit
import Foundation

/// Resolves package icons. Order: installed cask's real app icon → homepage icon
/// (GitHub owner avatar for github.com homepages, apple-touch-icon, favicon) → nil (the view
/// shows a monogram tile). Results are cached in memory and on disk, keyed by token + source.
actor IconResolver {
    static let shared = IconResolver()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var misses: Set<String> = []
    private let memory = NSCache<NSString, NSImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.timeoutIntervalForResource = 8
        c.httpAdditionalHeaders = ["User-Agent": "Brewlight/\(AppInfo.version)"]
        return URLSession(configuration: c)
    }()

    struct Request: Sendable, Hashable {
        var id: String
        var appPath: String?
        var homepage: String
        var allowWeb: Bool
        var pixelSize: Int
    }

    init() {
        // Startup purge: icons and miss markers older than a month simply re-fetch, so the
        // cache doesn't collect every package ever browsed.
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: Paths.iconCache, includingPropertiesForKeys: nil) {
            for f in files {
                let modified = (try? fm.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date
                if (modified ?? .distantPast) < cutoff { try? fm.removeItem(at: f) }
            }
        }
    }

    func clearCache() {
        memory.removeAllObjects()
        misses.removeAll()
        try? FileManager.default.removeItem(at: Paths.iconCache)
    }

    /// Returns a display-ready (downsampled) image, or nil to keep the monogram.
    func icon(for r: Request) async -> NSImage? {
        let key = "\(r.id)|\(r.appPath != nil ? "app" : "web")|\(r.pixelSize)"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if misses.contains(key) { return nil }
        if let task = inFlight[key] { return await task.value }
        let session = self.session
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            await Self.resolve(r, session: session)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) } else { misses.insert(key) }
        return image
    }

    private static func diskURL(_ r: Request, source: String) -> URL {
        let safe = r.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "-")
        return Paths.iconCache.appending(path: "\(safe)-\(source).png")
    }

    private static func resolve(_ r: Request, session: URLSession) async -> NSImage? {
        if let app = r.appPath {
            let disk = diskURL(r, source: "app")
            if let cached = load(disk) { return cached }
            let icon = NSWorkspace.shared.icon(forFile: app)
            let image = downsample(icon, to: r.pixelSize)
            save(image, to: disk)
            return image
        }
        guard r.allowWeb, let home = URL(string: r.homepage), let host = home.host() else { return nil }
        let disk = diskURL(r, source: "web")
        if let cached = load(disk) { return cached }
        if FileManager.default.fileExists(atPath: disk.path + ".miss") { return nil }

        var candidates: [URL] = []
        if host == "github.com" {
            let parts = home.pathComponents.filter { $0 != "/" }
            if let owner = parts.first { candidates.append(URL(string: "https://github.com/\(owner).png?size=128")!) }
        } else {
            let base = "\(home.scheme ?? "https")://\(host)"
            candidates += ["\(base)/apple-touch-icon.png", "\(base)/apple-touch-icon-precomposed.png", "\(base)/favicon.ico"].compactMap(URL.init(string:))
        }
        for url in candidates {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count > 100, let img = NSImage(data: data), img.size.width >= 32 else { continue }
            let image = downsample(img, to: r.pixelSize)
            save(image, to: disk)
            return image
        }
        FileManager.default.createFile(atPath: disk.path + ".miss", contents: nil)
        return nil
    }

    private static func load(_ url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    private static func save(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }

    /// Renders to a bitmap at the display size so rows never draw a 1024px icon.
    private static func downsample(_ image: NSImage, to px: Int) -> NSImage {
        let size = NSSize(width: px, height: px)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}
