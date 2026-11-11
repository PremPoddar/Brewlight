import SwiftUI

struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(AppInfo.name).font(.system(size: 28, weight: .bold)).tracking(-0.6)
                Text(AppInfo.tagline).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentText)
                Text(String(localized: "Version \(AppInfo.version) (\(AppInfo.build))")).font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text(AppInfo.copyright).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "System info")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                    Spacer()
                    Button(String(localized: "Copy")) { model.copy(systemInfo) }.buttonStyle(.link).font(.system(size: 11))
                }
                Text(systemInfo).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))

            GlassEffectContainer {
                HStack(spacing: 8) {
                    Button(String(localized: "Check for Updates")) {
                        Task { await model.updater.check(runner: model.runner, operations: model.operations) }
                    }
                    .buttonStyle(.glassProminent)
                    Button(String(localized: "Release Notes")) { NSWorkspace.shared.open(AppInfo.releasesURL) }.buttonStyle(.glass)
                    Button(String(localized: "Report an Issue")) { reportIssue() }.buttonStyle(.glass)
                }
            }
            // Two rows of single-line links; nothing wraps mid-word at the window's fixed width.
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    Link(String(localized: "Website"), destination: AppInfo.websiteURL)
                    Link("GitHub", destination: AppInfo.repositoryURL)
                    Link(String(localized: "Privacy"), destination: AppInfo.privacyURL)
                }
                HStack(spacing: 16) {
                    Link(String(localized: "Discover More Apps"), destination: AppInfo.moreAppsURL)
                    Link(String(localized: "Donate to Homebrew"), destination: AppInfo.homebrewDonateURL)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: 12))
            Text(AppInfo.nonAffiliation).font(.system(size: 11)).foregroundStyle(Theme.text3).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 460)
        .background(Theme.ambient(dark: scheme == .dark).opacity(0.6).ignoresSafeArea())
    }

    private var systemInfo: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        return """
        Brewlight \(AppInfo.version) (\(AppInfo.build)) · \(model.updater.channel.rawValue)
        Homebrew \(model.env?.version ?? "not found")
        Prefix \(model.env?.prefix.path ?? "—")
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(arch)
        """
    }

    private func reportIssue() {
        var c = URLComponents(url: AppInfo.issuesURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "body", value: "\n\n---\n```\n\(systemInfo)\n```")]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}
