import Foundation

/// Replays canned output. Used by demo mode and tests so nothing touches the real Homebrew.
struct MockBrewRunner: BrewRunning {
    /// Maps a command prefix (e.g. "outdated --json=v2") to its output lines and exit status.
    var responses: [String: (lines: [String], status: Int32)] = [:]
    var lineDelay: Duration = .milliseconds(60)

    func stream(_ args: [String], extraEnv: [String: String]) -> AsyncStream<RunEvent> {
        let key = args.joined(separator: " ")
        let match = responses.keys.filter { key.hasPrefix($0) }.max { $0.count < $1.count }
        let response = match.flatMap { responses[$0] } ?? (Self.genericOutput(for: args), 0)
        let delay = lineDelay
        return AsyncStream { continuation in
            let task = Task {
                for line in response.lines {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: delay)
                    continuation.yield(.line(OutputLine(stream: .stdout, text: line)))
                }
                continuation.yield(.exit(Task.isCancelled ? 130 : response.status))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel(_ args: [String]) async {}

    /// Real-world doctor warnings (deprecated formulae, compromised CA roots, unlinked kegs).
    static let demoDoctor = """
    Please note that these warnings are just used to help the Homebrew maintainers
    with debugging if you file an issue. If everything you use Homebrew for is
    working fine: please don't worry or file an issue; just ignore this. Thanks!

    Warning: Some installed formulae are deprecated or disabled.
    You should find replacements for the following formulae:
      icu4c@78

    Warning: Root certificates in /etc/ssl/cert.pem can trust compromised CAs.
    Command-line tools using this file may accept forged TLS certificates:
      AAA Certificate Services
      emSign ECC Root CA - G3
    Run this script to create a backup and remove these roots:
      sudo /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.9/bin/ruby --disable=gems,rubyopt /opt/homebrew/Library/Homebrew/utils/emudhra_certificates.rb
    For details and software update plans, see:
      https://support.apple.com/en-us/149555

    Warning: You have unlinked kegs in your Cellar.
    Leaving kegs unlinked can lead to build-trouble and cause formulae that depend on
    those kegs to fail to run properly once built. Run `brew link` on these:
      node
    """

    static func genericOutput(for args: [String]) -> [String] {
        let name = args.last ?? "package"
        switch args.first {
        case "install", "reinstall", "upgrade":
            // Demo mode has an untrusted tap (oven-sh/bun), so installs show Homebrew's trust warning.
            return ["Warning: The following taps are not trusted:", "  oven-sh/bun",
                    "Homebrew is currently ignoring formulae, casks and commands",
                    "from these taps because tap trust is required.", "Trust whole taps with:", "  brew trust oven-sh/bun",
                    "==> Fetching \(name)", "==> Downloading https://ghcr.io/v2/homebrew/core/\(name)/blobs/sha256:0f3c",
                    "######################################################################## 100.0%",
                    "==> Pouring \(name)--1.0.arm64_tahoe.bottle.tar.gz", "==> Linking \(name)",
                    "🍺  /opt/homebrew/Cellar/\(name)/1.0: 42 files, 3.1MB"]
        case "doctor":
            return demoDoctor.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        case "uninstall":
            return ["Uninstalling /opt/homebrew/Cellar/\(name)/1.0... (42 files, 3.1MB)"]
        default:
            return ["==> Done"]
        }
    }
}
