import SwiftUI

/// Shown when Homebrew isn't installed. Never runs the install script silently.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var downloading = false
    @State private var error: String?

    static let installCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(AppInfo.fullTagline).font(.system(size: 30, weight: .bold)).tracking(-0.8).multilineTextAlignment(.center)
            Text(String(localized: "Brewlight is a fast, friendly window onto Homebrew — the package manager most Mac developers use to install command-line tools and apps. Homebrew isn't installed on this Mac yet."))
                .font(.system(size: 14)).foregroundStyle(Theme.text2).multilineTextAlignment(.center).frame(maxWidth: 520)
            HStack(spacing: 12) {
                Button(downloading ? String(localized: "Downloading…") : String(localized: "Install Homebrew")) { Task { await installPkg() } }
                    .buttonStyle(PrimaryPillButtonStyle(height: 38))
                    .disabled(downloading)
                Button(String(localized: "Use Terminal Instead")) { model.runInTerminal(Self.installCommand) }
                    .buttonStyle(ChipButtonStyle(height: 38))
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.red) }
            Text(String(localized: "The installer is Homebrew's official signed package from GitHub. You'll be asked for your password by macOS, not by Brewlight."))
                .font(.system(size: 11)).foregroundStyle(Theme.text3).multilineTextAlignment(.center).frame(maxWidth: 460)
            Button(String(localized: "I've installed it — check again")) { Task { await model.retryLocating() } }
                .buttonStyle(.link)
            Button(String(localized: "Homebrew is installed somewhere else…")) {
                let panel = NSOpenPanel()
                panel.message = String(localized: "Choose the brew executable")
                if panel.runModal() == .OK, let url = panel.url {
                    UserDefaults.standard.set(url.path, forKey: BrewLocator.overrideKey)
                    Task { await model.retryLocating() }
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ambient(dark: scheme == .dark).ignoresSafeArea())
    }

    /// Downloads the latest `Homebrew-*.pkg` from Homebrew's GitHub releases and opens it in Installer.
    private func installPkg() async {
        downloading = true
        defer { downloading = false }
        do {
            let api = URL(string: "https://api.github.com/repos/Homebrew/brew/releases/latest")!
            let (data, _) = try await URLSession.shared.data(from: api)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let assets = obj?["assets"] as? [[String: Any]] ?? []
            guard let asset = assets.first(where: { ($0["name"] as? String ?? "").hasSuffix(".pkg") }),
                  let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) else {
                error = String(localized: "Couldn't find the installer package. Use Terminal instead.")
                return
            }
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory.appending(path: url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            NSWorkspace.shared.open(dest)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
