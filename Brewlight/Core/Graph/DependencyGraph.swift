import Foundation

/// Formula dependency graph built from the catalog. All walks are cycle-safe.
struct DependencyGraph: Sendable {
    /// name -> runtime deps
    private(set) var runtime: [String: [String]] = [:]
    /// name -> build deps
    private(set) var build: [String: [String]] = [:]
    /// name -> packages whose runtime deps include it (all, not just installed)
    private(set) var reverse: [String: [String]] = [:]

    init(packages: [Package], aliases: [String: String] = [:]) {
        func canonical(_ n: String) -> String {
            // Third-party deps are written "user/tap/name"; core ones may use an alias.
            let short = n.split(separator: "/").last.map(String.init) ?? n
            return aliases[short] ?? short
        }
        for p in packages where p.kind == .formula {
            let deps = (p.dependencies + p.recommendedDependencies).map(canonical)
            runtime[p.token] = deps
            build[p.token] = p.buildDependencies.map(canonical)
            for d in deps { reverse[d, default: []].append(p.token) }
        }
        for p in packages where p.kind == .cask && !p.caskFormulaDependencies.isEmpty {
            let id = "cask:" + p.token
            runtime[id] = p.caskFormulaDependencies.map(canonical)
            for d in runtime[id]! { reverse[d, default: []].append(id) }
        }
    }

    func directDependencies(of name: String, includeBuild: Bool = false) -> [String] {
        (runtime[name] ?? []) + (includeBuild ? (build[name] ?? []) : [])
    }

    /// All transitive runtime dependencies (excluding `name`), in breadth-first order.
    func transitiveDependencies(of name: String, includeBuild: Bool = false) -> [String] {
        var seen: Set<String> = [name]
        var order: [String] = []
        var queue = directDependencies(of: name, includeBuild: includeBuild)
        var i = 0
        while i < queue.count {
            let n = queue[i]; i += 1
            guard seen.insert(n).inserted else { continue }
            order.append(n)
            // Build deps of deps aren't needed at runtime.
            queue.append(contentsOf: runtime[n] ?? [])
        }
        return order
    }

    struct TreeNode: Identifiable, Sendable, Hashable {
        let id: String
        let name: String
        let children: [TreeNode]?
        let isRepeat: Bool
    }

    /// Recursive tree for the disclosure view. Repeated subtrees are shown once and then marked.
    func tree(of name: String, includeBuild: Bool) -> [TreeNode] {
        var expanded = Set<String>()
        func build(_ n: String, path: String, depth: Int) -> TreeNode {
            let id = path + "/" + n
            if expanded.contains(n) || depth > 30 {
                return TreeNode(id: id, name: n, children: nil, isRepeat: true)
            }
            expanded.insert(n)
            let kids = (runtime[n] ?? []).map { build($0, path: id, depth: depth + 1) }
            return TreeNode(id: id, name: n, children: kids.isEmpty ? nil : kids, isRepeat: false)
        }
        return directDependencies(of: name, includeBuild: includeBuild).map { build($0, path: name, depth: 0) }
    }

    /// Installed packages that depend on `name` (directly).
    func dependents(of name: String, installed: Set<String>) -> [String] {
        (reverse[name] ?? []).filter { installed.contains($0) }.sorted()
    }

    func allDependents(of name: String) -> [String] { (reverse[name] ?? []).sorted() }

    /// Installed packages nothing else installed depends on (like `brew leaves`).
    func leaves(installed: Set<String>) -> [String] {
        var depended = Set<String>()
        for n in installed { for d in runtime[n] ?? [] { depended.insert(d) } }
        return installed.subtracting(depended).sorted()
    }

    /// Installed dependencies nothing requested needs anymore (like `brew autoremove`).
    func orphans(installed: Set<String>, requested: Set<String>) -> [String] {
        var needed = Set<String>()
        for r in requested where installed.contains(r) {
            needed.insert(r)
            for d in transitiveDependencies(of: r) { needed.insert(d) }
        }
        return installed.subtracting(needed).sorted()
    }

    /// Paths from installed top-level packages down to `name`: answers "why is this installed?".
    func whyInstalled(_ name: String, installed: Set<String>, requested: Set<String>, limit: Int = 8) -> [[String]] {
        var results: [[String]] = []
        var queue: [[String]] = [[name]]
        var visited: Set<String> = [name]
        while !queue.isEmpty && results.count < limit {
            let path = queue.removeFirst()
            let head = path[0]
            if head != name && requested.contains(head) { results.append(path); continue }
            for parent in (reverse[head] ?? []) where installed.contains(parent) && !visited.contains(parent) {
                visited.insert(parent)
                queue.append([parent] + path)
            }
        }
        return results
    }
}
