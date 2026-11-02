import AppKit

// SUDO_ASKPASS helper. sudo runs this with the prompt as the first argument and reads the
// password from stdout. Exits non-zero on cancel or after a timeout, so brew never hangs.

let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let alert = NSAlert()
alert.messageText = "Brewlight needs your administrator password"
alert.informativeText = """
Homebrew is running a step that requires administrator privileges.
\(prompt.isEmpty ? "" : "\n\(prompt)\n")
Your password goes directly to sudo. Brewlight never stores it.
"""
alert.alertStyle = .warning
alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
alert.addButton(withTitle: "OK")
alert.addButton(withTitle: "Cancel")

let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
field.placeholderString = "Password"
alert.accessoryView = field
alert.window.initialFirstResponder = field

// Give up after two minutes so a forgotten prompt never blocks the queue forever.
DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
    NSApp.abortModal()
}

app.activate()
let response = alert.runModal()
guard response == .alertFirstButtonReturn else { exit(1) }
FileHandle.standardOutput.write((field.stringValue + "\n").data(using: .utf8)!)
exit(0)
