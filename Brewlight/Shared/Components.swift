import SwiftUI

// MARK: Package icon

/// Monogram tile with a stable gradient (from the design), cross-fading to the real icon when one loads.
struct PackageIcon: View {
    let package: Package
    var size: CGFloat = 32
    var appPath: String?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Monogram(name: package.token, size: size)
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: appPath != nil ? 0 : size * 0.24, style: .continuous))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: appPath ?? package.id) {
            let fetchIcons = UserDefaults.standard.object(forKey: "fetchIcons") as? Bool ?? true
            let req = IconResolver.Request(id: package.id, appPath: appPath, homepage: package.homepage,
                                           allowWeb: fetchIcons && !AppInfo.isDemo,
                                           pixelSize: Int(size * 2))
            image = await IconResolver.shared.icon(for: req)
        }
        .accessibilityHidden(true)
    }
}

struct Monogram: View {
    let name: String
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hue = Self.hue(for: name)
        let dark = scheme == .dark
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [.oklch(dark ? 0.74 : 0.82, 0.11, hue), .oklch(dark ? 0.55 : 0.64, 0.15, hue + 18)],
                                 startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1)))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .black.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
            }
            .overlay {
                Text(Self.letters(for: name))
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }

    /// Two letters: first of each word for multi-word tokens (`visual-studio-code` → "vs"),
    /// otherwise the first two letters (`ffmpeg` → "ff").
    static func letters(for name: String) -> String {
        let clean = name.split(separator: "@").first.map(String.init) ?? name
        let words = clean.split(whereSeparator: { "-_. ".contains($0) })
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return String([a, b]) }
        return String(clean.prefix(2))
    }

    /// Stable hue from the name (FNV-1a), so a package always gets the same colour.
    static func hue(for name: String) -> Double {
        var h: UInt32 = 2_166_136_261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return Double(h % 360)
    }
}

// MARK: Badges and pills

struct KindBadge: View {
    let kind: PackageKind
    var body: some View {
        Text(kind.badge)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 5)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.separator))
            .accessibilityLabel(kind.label)
    }
}

/// Small "Install" / "Open" / "Upgrade" capsule used in rows and cards.
struct RowActionButton: View {
    let title: String
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Theme.accentText : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(prominent ? Theme.accentTint : Theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The big amber primary button (Upgrade All, Install in the detail header).
struct PrimaryPillButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height > 35 ? 14 : 13, weight: .semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, height > 35 ? 22 : 18)
            .frame(height: height)
            .background {
                Capsule().fill(Theme.accent)
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 2)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
    }
}

struct ChipButtonStyle: ButtonStyle {
    var height: CGFloat = 34
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(minWidth: height, minHeight: height)
            .background(Capsule().fill(Theme.chip))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.key))
    }
}

struct CountBadge: View {
    let count: Int
    var hot = false
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(hot ? Theme.accentInk : Theme.text3)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(hot ? Theme.accent : .clear))
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var sub: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
            Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).tracking(-0.3)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub.isEmpty ? " " : sub).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator))
        .accessibilityElement(children: .combine)
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    var size: CGFloat = 30
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: size, weight: .bold)).tracking(-0.8)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: size > 28 ? 13 : 12)).foregroundStyle(Theme.text2)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "", size: CGFloat = 30) {
        self.init(title: title, subtitle: subtitle, size: size) { EmptyView() }
    }
}

struct SectionTitle: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle = String(localized: "See all")

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold)).tracking(-0.3).accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentText)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .foregroundStyle(Theme.text2)
    }
}

/// Monospaced command line with a Copy button (from the detail design).
struct CommandLineBox: View {
    let command: String
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Text("❯").foregroundStyle(Theme.accentText)
            Text(command).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "Copy")) { model.copy(command) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chip))
        }
        .font(.system(size: 12.5, design: .monospaced))
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.separator))
    }
}

extension Date {
    var relative: String { formatted(.relative(presentation: .named)) }
}

extension Int {
    /// 161000 → "161K", 4_100_000 → "4.1M". Fixed K/M (not locale compact names such as lakh)
    /// so a column of install counts always reads the same way.
    var compact: String {
        func short(_ v: Double) -> String {
            let s = v < 100 ? String(format: "%.1f", v) : String(format: "%.0f", v)
            return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        switch abs(self) {
        case ..<1000: return "\(self)"
        case ..<999_500: return short(Double(self) / 1000) + "K"
        default: return short(Double(self) / 1_000_000) + "M"
        }
    }
}
