// Renders the placeholder app icon (see Design/ICON_BRIEF.md) at every macOS size.
// Usage: swift scripts/make-icon.swift <output.appiconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    // Warm dark base
    _ = NSShadow().then { $0.shadowColor = .black.withAlphaComponent(0.3); $0.shadowBlurRadius = s * 0.03; $0.shadowOffset = NSSize(width: 0, height: -s * 0.012); $0.set() }
    NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.14, blue: 0.10, alpha: 1), NSColor(srgbRed: 0.08, green: 0.07, blue: 0.06, alpha: 1)])!
        .draw(in: squircle, angle: -90)
    NSShadow().set()
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Beam of light from the top-right
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: rect.maxX + s * 0.05, y: rect.maxY + s * 0.05))
    beam.line(to: NSPoint(x: rect.midX - s * 0.20, y: rect.minY + s * 0.30))
    beam.line(to: NSPoint(x: rect.midX + s * 0.22, y: rect.minY + s * 0.30))
    beam.line(to: NSPoint(x: rect.maxX + s * 0.05, y: rect.maxY - s * 0.25))
    beam.close()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.80, blue: 0.45, alpha: 0.75), NSColor(srgbRed: 0.97, green: 0.67, blue: 0.24, alpha: 0.05)])!
        .draw(in: beam, angle: -120)

    // Glass mug
    let mug = NSRect(x: rect.midX - s * 0.19, y: rect.minY + s * 0.17, width: s * 0.34, height: s * 0.36)
    let mugPath = NSBezierPath(roundedRect: mug, xRadius: s * 0.06, yRadius: s * 0.06)
    NSColor.white.withAlphaComponent(0.16).setFill(); mugPath.fill()
    // Amber brew inside
    let brew = NSRect(x: mug.minX + s * 0.025, y: mug.minY + s * 0.025, width: mug.width - s * 0.05, height: mug.height * 0.62)
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.78, blue: 0.36, alpha: 1), NSColor(srgbRed: 0.90, green: 0.52, blue: 0.10, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: brew, xRadius: s * 0.04, yRadius: s * 0.04), angle: -90)
    // Handle
    let handle = NSBezierPath(roundedRect: NSRect(x: mug.maxX - s * 0.01, y: mug.minY + s * 0.09, width: s * 0.11, height: s * 0.17), xRadius: s * 0.05, yRadius: s * 0.05)
    handle.lineWidth = s * 0.03
    NSColor.white.withAlphaComponent(0.45).setStroke(); handle.stroke()
    // Rim highlight
    NSColor.white.withAlphaComponent(0.6).setStroke()
    mugPath.lineWidth = s * 0.012; mugPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Glass edge
    NSColor.white.withAlphaComponent(0.18).setStroke()
    squircle.lineWidth = max(1, s * 0.006); squircle.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSShadow { func then(_ f: (NSShadow) -> Void) -> NSShadow { f(self); return self } }

var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! render(pt * scale).write(to: out.appending(path: name))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted])
try! json.write(to: out.appending(path: "Contents.json"))
