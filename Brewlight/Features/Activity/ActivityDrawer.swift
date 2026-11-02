import SwiftUI

/// Bottom drawer listing queued, running and finished operations with live logs.
struct ActivityDrawer: View {
    @Environment(AppModel.self) private var model
    @State private var selected: UUID?
    @State private var showRaw = false

    var body: some View {
        let ops = model.operations.operations
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(localized: "Activity")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if ops.contains(where: { $0.state.isFinished }) {
                        Button(String(localized: "Clear")) { model.operations.clearFinished() }.buttonStyle(.link).font(.system(size: 12))
                    }
                    Button { model.showActivity = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Theme.chip))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help(String(localized: "Close (Esc or ⌘L)"))
                    .accessibilityLabel(String(localized: "Close activity"))
                }
                .padding(12)
                if ops.isEmpty {
                    Text(String(localized: "No operations yet. Installs, upgrades and removals show up here."))
                        .font(.system(size: 12)).foregroundStyle(Theme.text2).padding(12)
                    Spacer()
                } else {
                    List(ops, selection: $selected) { op in
                        OperationRow(op: op).tag(op.id)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(width: 300)
            Divider()
            if let op = ops.first(where: { $0.id == (selected ?? ops.first?.id) }) {
                OperationLogView(op: op, showRaw: $showRaw)
            } else {
                Spacer()
            }
        }
        .frame(height: 280)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(10)
    }
}

struct OperationRow: View {
    let op: BrewOperation
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            stateIcon.frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(op.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if op.state == .running {
                    ProgressView(value: op.percent ?? 0).progressViewStyle(.linear).tint(Theme.accent)
                        .opacity(op.percent == nil ? 0.4 : 1)
                }
                Text(statusText).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer()
            if !op.state.isFinished {
                Button { model.operations.cancel(op) } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.plain).help(String(localized: "Cancel"))
                    .accessibilityLabel(String(localized: "Cancel \(op.title)"))
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var stateIcon: some View {
        switch op.state {
        case .queued: Image(systemName: "clock").foregroundStyle(Theme.text3)
        case .running: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.red)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(Theme.text3)
        }
    }

    private var statusText: String {
        switch op.state {
        case .queued: String(localized: "Queued")
        case .running: op.phase.label
        case .succeeded: String(localized: "Done in \(Int(op.duration ?? 0))s")
        case .failed(let c): String(localized: "Failed (exit \(c))")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}

struct OperationLogView: View {
    let op: BrewOperation
    @Binding var showRaw: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(op.command).font(.system(size: 12, design: .monospaced)).lineLimit(1).textSelection(.enabled)
                Spacer()
                Toggle(String(localized: "Raw output"), isOn: $showRaw).toggleStyle(.checkbox).font(.system(size: 11))
                Button(String(localized: "Copy Log")) { model.copy(op.fullLog) }.buttonStyle(.glass).controlSize(.small)
            }
            .padding(12)

            ForEach(op.notices) { NoticeBanner(notice: $0) }
            if case .failed = op.state { failureBanner }
            if op.needsTerminal { terminalBanner }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(visibleLines.enumerated()), id: \.offset) { i, line in
                            Text(line.text)
                                .font(.system(size: 11, weight: line.kind == .heading ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(Self.color(line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
                .onChange(of: op.log.count) { proxy.scrollTo(visibleLines.count - 1, anchor: .bottom) }
            }
        }
    }

    /// Without raw output, hide progress-bar noise and keep headings and messages.
    private var visibleLines: [OutputLine] {
        showRaw ? op.log : op.log.filter { $0.kind != .progress }
    }

    static func color(_ kind: LogKind) -> Color {
        switch kind {
        case .plain: Theme.text
        case .heading: Theme.text
        case .success: Theme.success
        case .warning: Theme.warning
        case .error: Theme.red
        case .progress: Theme.text3
        }
    }

    private var failureBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(op.errorLines.prefix(3), id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)) }
            HStack(spacing: 12) {
                Button(String(localized: "Retry")) { model.operations.retry(op) }
                Button(String(localized: "Copy for Bug Report")) { model.copy(op.bugReport) }
                Button(String(localized: "Run brew doctor")) { model.showDoctor() }
                if let name = op.packages.first, let url = model.package(named: name)?.issuesURL {
                    Link(String(localized: "Package issues"), destination: url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.red.opacity(0.1)))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var terminalBanner: some View {
        HStack {
            Image(systemName: "terminal")
            Text(String(localized: "This step needs a terminal (it asked for input Brewlight can't provide)."))
            Spacer()
            Button(String(localized: "Run in Terminal")) { model.runInTerminal(op.command) }.buttonStyle(.glassProminent)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.caveat))
        .padding(.horizontal, 12).padding(.bottom, 8)
    }
}

/// An actionable notice from brew's output, with the same choices as the prompt.
struct NoticeBanner: View {
    let notice: OperationNotice
    @Environment(AppModel.self) private var model

    var body: some View {
        switch notice {
        case .untrustedTaps(let taps):
            let names = taps.joined(separator: ", ")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Homebrew is ignoring packages from \(names) until you trust it."))
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 10) {
                        Button(taps.count == 1 ? String(localized: "Trust \(names)…") : String(localized: "Trust These Taps…")) {
                            model.pendingNotice = notice
                        }
                        .buttonStyle(.glassProminent)
                        Button(String(localized: "Untap")) { for t in taps { model.removeTap(t) } }
                            .buttonStyle(.glass)
                        Link(String(localized: "About tap trust"), destination: AppModel.tapTrustDocs)
                            .font(.system(size: 12))
                    }
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.12)))
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}
