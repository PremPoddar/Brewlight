import Foundation

/// The app's identity in one place. The values that change per release (bundle ID, version,
/// cask token, repository) come from `Config/App.xcconfig` via Info.plist.
enum AppInfo {
    static let name = "Brewlight"

    /// Short tagline, shown under the name in About.
    static let tagline = String(localized: "Like Spotlight, but for brew.", comment: "App tagline")

    /// Full tagline used in onboarding, the palette, and release material.
    static let fullTagline = String(localized: "Brewlight — like Spotlight, but for brew.", comment: "App tagline with name")

    static let nonAffiliation = String(
        localized: "Brewlight is an independent app, not affiliated with the Homebrew project or Apple. Spotlight is a trademark of Apple Inc.",
        comment: "Trademark notice")

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.prempoddar.brewlight" }
    static var version: String { info("CFBundleShortVersionString") ?? "0.0" }
    static var build: String { info("CFBundleVersion") ?? "0" }
    static var caskToken: String { info("BLCaskToken") ?? "brewlight" }
    static var copyright: String { info("NSHumanReadableCopyright") ?? "" }

    static var repositoryURL: URL {
        URL(string: info("BLRepositoryURL") ?? "https://github.com/PremPoddar/Brewlight")!
    }
    static var issuesURL: URL { repositoryURL.appending(path: "issues/new") }
    static var releasesURL: URL { repositoryURL.appending(path: "releases") }
    static let homebrewDonateURL = URL(string: "https://github.com/Homebrew/brew#donations")!
    static let websiteURL = URL(string: "https://prempoddar.is-a.dev/Brewlight/")!
    static let privacyURL = URL(string: "https://prempoddar.is-a.dev/Brewlight/privacy/")!
    static let moreAppsURL = URL(string: "https://prempoddar.is-a.dev/apps/")!

    /// Demo mode uses bundled fixture data and a mock runner (launch with `-demo`).
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
