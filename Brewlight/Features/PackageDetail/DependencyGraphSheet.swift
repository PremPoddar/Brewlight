import SwiftUI

/// Top-down layered graph of a formula's dependencies (below) and installed dependents (above),
/// drawn with Canvas. Zoom with the slider or pinch; click a node to open it.
struct DependencyGraphSheet: View {
    let packageID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    struct Node: Hashable { let name: String; let layer: Int; let index: Int }

    var body: some View {
        let name = model.package(packageID)?.token ?? packageID
        let layout = makeLayout(root: name)
        let scale = zoom * pinch
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Dependency graph · \(name)")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Slider(value: $zoom, in: 0.4...2).frame(width: 160)
                    .accessibilityLabel(String(localized: "Zoom"))
                Button(String(localized: "Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for (from, to) in layout.edges {
                            guard let a = layout.positions[from], let b = layout.positions[to] else { continue }
                            var path = Path()
                            let p1 = CGPoint(x: a.x * scale, y: (a.y + 14) * scale)
                            let p2 = CGPoint(x: b.x * scale, y: (b.y - 14) * scale)
                            path.move(to: p1)
                            path.addCurve(to: p2, control1: CGPoint(x: p1.x, y: (p1.y + p2.y) / 2), control2: CGPoint(x: p2.x, y: (p1.y + p2.y) / 2))
                            ctx.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                        }
                    }
                    .frame(width: layout.size.width * scale, height: layout.size.height * scale)
                    ForEach(Array(layout.positions.keys), id: \.self) { node in
                        let pos = layout.positions[node]!
                        let installed = model.isInstalled(Package.id(.formula, node))
                        Button { dismiss(); model.reveal(Package.id(.formula, node)) } label: {
                            Text(node)
                                .font(.system(size: 11 * max(scale, 0.7), weight: node == name ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Capsule().fill(node == name ? Theme.accent : (installed ? Theme.card : Theme.chip)))
                                .overlay(Capsule().strokeBorder(Theme.separator))
                                .foregroundStyle(node == name ? Theme.accentInk : Theme.text)
                        }
                        .buttonStyle(.plain)
                        .position(x: pos.x * scale, y: pos.y * scale)
                    }
                }
                .frame(width: layout.size.width * scale, height: layout.size.height * scale)
                .padding(20)
            }
            .gesture(MagnifyGesture().updating($pinch) { v, s, _ in s = v.magnification }.onEnded { zoom = min(2, max(0.4, zoom * $0.magnification)) })
        }
        .frame(width: 900, height: 640)
        .background(Theme.detail)
    }

    struct Layout {
        var positions: [String: CGPoint] = [:]
        var edges: [(String, String)] = []
        var size: CGSize = .zero
    }

    /// Layer 0 = installed dependents, layer 1 = root, layers 2+ = dependencies by depth.
    private func makeLayout(root: String) -> Layout {
        var layers: [[String]] = []
        var edges: [(String, String)] = []
        let dependents = model.graph.dependents(of: root, installed: model.installedFormulaNames)
        layers.append(Array(dependents.prefix(14)))
        for d in dependents.prefix(14) { edges.append((d, root)) }
        layers.append([root])
        var seen: Set<String> = [root]
        var frontier = [root]
        while !frontier.isEmpty && layers.count < 9 {
            var next: [String] = []
            for n in frontier {
                for d in model.graph.directDependencies(of: n) {
                    edges.append((n, d))
                    if seen.insert(d).inserted { next.append(d) }
                }
            }
            if !next.isEmpty { layers.append(next) }
            frontier = next
        }
        let colWidth: CGFloat = 130, rowHeight: CGFloat = 90
        let maxCount = max(layers.map(\.count).max() ?? 1, 1)
        let width = CGFloat(maxCount) * colWidth + 40
        var layout = Layout()
        for (li, layer) in layers.enumerated() {
            let offset = (width - CGFloat(layer.count) * colWidth) / 2
            for (i, n) in layer.enumerated() {
                layout.positions[n] = CGPoint(x: offset + CGFloat(i) * colWidth + colWidth / 2, y: CGFloat(li) * rowHeight + 30)
            }
        }
        layout.edges = edges
        layout.size = CGSize(width: width, height: CGFloat(layers.count) * rowHeight + 20)
        return layout
    }
}
