import AppKit
import SwiftUI

/// Design tokens from the Brewlight design (warm neutrals + amber accent), with light, dark,
/// and Increase Contrast variants resolved by the system per appearance.
enum Theme {
    static let accent = dynamic(light: 0xF8AC3D, dark: 0xF8AC3D, hcLight: 0xE08A00, hcDark: 0xFFC060)
    static let accentInk = dynamic(light: 0x2A1903, dark: 0x241602)
    static let accentText = dynamic(light: 0xAC5800, dark: 0xFEBD56, hcLight: 0x7A3E00, hcDark: 0xFFD08A)
    static let accentTint = dynamic(light: 0xF8AC3D, dark: 0xF8AC3D, alphaLight: 0.20, alphaDark: 0.17)
    static let sidebarSelection = dynamic(light: 0xF8AC3D, dark: 0xF8AC3D, alphaLight: 0.30, alphaDark: 0.24)

    static let text = dynamic(light: 0x1C1A17, dark: 0xF4F1EC)
    static let text2 = dynamic(light: 0x67625B, dark: 0xABA59C, hcLight: 0x403C37, hcDark: 0xD5D0C8)
    static let text3 = dynamic(light: 0x99938A, dark: 0x7C776F, hcLight: 0x5E5952, hcDark: 0xB0AAA2)

    static let list = dynamic(light: 0xFFFFFF, dark: 0x1C1B19)
    static let detail = dynamic(light: 0xFAF9F7, dark: 0x211F1D)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x262422)
    static let window = dynamic(light: 0xEFECE8, dark: 0x141311)

    static let separator = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alphaLight: 0.08, alphaDark: 0.08, hcAlpha: 0.25)
    static let chip = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alphaLight: 0.05, alphaDark: 0.075, hcAlpha: 0.14)
    static let key = dynamic(light: 0x1C1A17, dark: 0xFFFFFF, alphaLight: 0.07, alphaDark: 0.10)
    static let segmentOn = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alphaLight: 1, alphaDark: 0.16)
    static let caveat = dynamic(light: 0xF8AC3D, dark: 0xF8AC3D, alphaLight: 0.10, alphaDark: 0.08)
    static let caveatBorder = dynamic(light: 0xF8AC3D, dark: 0xF8AC3D, alphaLight: 0.35, alphaDark: 0.22)
    static let dim = dynamic(light: 0x281E14, dark: 0x000000, alphaLight: 0.16, alphaDark: 0.45)

    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    /// Log colours: readable yellow/green on both the light and dark backgrounds.
    static let warning = dynamic(light: 0x9A6700, dark: 0xF2C94C, hcLight: 0x7A5200, hcDark: 0xFFD966)
    static let success = dynamic(light: 0x1F8A3B, dark: 0x5BD17A, hcLight: 0x146B2C, hcDark: 0x7BE395)

    /// Ambient glow behind the floating glass sidebar.
    static func ambient(dark: Bool) -> some View {
        ZStack {
            Color(nsColor: dark ? NSColor(hex: 0x141311) : NSColor(hex: 0xEFECE8))
            RadialGradient(colors: [Color(hex: dark ? 0x733E00 : 0xFFCC8E).opacity(dark ? 0.85 : 0.95), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: dark ? 0x642629 : 0xFFBDB9).opacity(dark ? 0.75 : 0.85), .clear],
                           center: UnitPoint(x: 0.06, y: 1), startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color(hex: dark ? 0x114D46 : 0xB7ECD8).opacity(dark ? 0.55 : 0.7), .clear],
                           center: UnitPoint(x: 0.18, y: 0.52), startRadius: 0, endRadius: 360)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32, hcLight: UInt32? = nil, hcDark: UInt32? = nil,
                                alphaLight: CGFloat = 1, alphaDark: CGFloat = 1, hcAlpha: CGFloat? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch match {
            case .darkAqua: return NSColor(hex: dark, alpha: alphaDark)
            case .accessibilityHighContrastAqua: return NSColor(hex: hcLight ?? light, alpha: hcAlpha ?? alphaLight)
            case .accessibilityHighContrastDarkAqua: return NSColor(hex: hcDark ?? dark, alpha: hcAlpha ?? alphaDark)
            default: return NSColor(hex: light, alpha: alphaLight)
            }
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }

    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    /// OKLCH → sRGB, used to reproduce the design's icon gradients exactly.
    static func oklch(_ L: Double, _ C: Double, _ h: Double) -> Color {
        let a = C * cos(h * .pi / 180), b = C * sin(h * .pi / 180)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return Color(.sRGB, red: gamma(r), green: gamma(g), blue: gamma(bl))
    }
}

/// Fixed palette for user tags.
enum TagPalette {
    static let colors: [String] = ["#F8AC3D", "#E5484D", "#30A46C", "#3E63DD", "#8E4EC6", "#12A594", "#D6409F", "#978365"]
}
