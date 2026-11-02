import Foundation

/// Parses Homebrew's API data into `Package` values.
///
/// Supports both formats seen in the wild:
/// - Homebrew 7+: one `api/internal/packages.<bottle_tag>.jws.json` file whose payload is an object
///   with `formulae` and `casks` dictionaries keyed by name (compact field names).
/// - Legacy: `api/formula.jws.json` / `api/cask.jws.json` (or `formulae.brew.sh/api/*.json`)
///   whose payload is an array of full objects.
///
/// Unknown or missing fields are tolerated everywhere.
enum CatalogLoader {
    enum LoadError: Error, LocalizedError {
        case notFound
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: "Homebrew's API cache was not found."
            case .malformed(let s): "Homebrew's API data could not be read: \(s)"
            }
        }
    }

    // MARK: Locating files

    /// Finds the newest internal packages file in `<cache>/api/internal`.
    static func internalPackagesFile(cache: URL) -> URL? {
        let dir = cache.appending(path: "api/internal")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("packages.") && $0.lastPathComponent.hasSuffix(".jws.json") }
            .max { modDate($0) < modDate($1) }
    }

    static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: JWS

    /// Returns the payload of a JWS-wrapped file, or the data itself if it is plain JSON.
    /// Detection doesn't depend on key order: a top-level array is plain JSON; a top-level object
    /// is JWS exactly when it has a string `payload`.
    static func unwrapJWS(_ data: Data) throws -> Data {
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }), first == UInt8(ascii: "{"),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        guard let payload = obj["payload"] as? String else { return data }
        guard let payloadData = payload.data(using: .utf8) else { throw LoadError.malformed("JWS payload is not UTF-8") }
        return payloadData
    }

    // MARK: Entry points

    static func loadInternal(from url: URL) throws -> Catalog {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parseInternal(try unwrapJWS(data), source: url.lastPathComponent)
    }

    static func parseInternal(_ payload: Data, source: String) throws -> Catalog {
        guard let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw LoadError.malformed("payload is not an object")
        }
        var packages: [Package] = []
        let formulae = root["formulae"] as? [String: [String: Any]] ?? [:]
        let casks = root["casks"] as? [String: [String: Any]] ?? [:]
        packages.reserveCapacity(formulae.count + casks.count)
        for (name, f) in formulae { packages.append(internalFormula(name: name, f)) }
        for (token, c) in casks { packages.append(internalCask(token: token, c)) }

        var aliases = root["formula_aliases"] as? [String: String] ?? [:]
        // Old names resolve to their new names too.
        for (old, new) in root["formula_renames"] as? [String: String] ?? [:] { aliases[old] = new }
        // Attach aliases/old names to packages for search.
        var aliasByTarget: [String: [String]] = [:]
        for (alias, target) in root["formula_aliases"] as? [String: String] ?? [:] {
            aliasByTarget[target, default: []].append(alias)
        }
        var renamesByTarget: [String: [String]] = [:]
        for (old, new) in root["formula_renames"] as? [String: String] ?? [:] {
            renamesByTarget[new, default: []].append(old)
        }
        for (old, new) in root["cask_renames"] as? [String: String] ?? [:] {
            renamesByTarget["cask:" + new, default: []].append(old)
        }
        for i in packages.indices {
            let p = packages[i]
            if p.kind == .formula {
                if let extra = aliasByTarget[p.token] { packages[i].aliases = Array(Set(p.aliases + extra)).sorted() }
                if let olds = renamesByTarget[p.token] { packages[i].oldNames = Array(Set(p.oldNames + olds)).sorted() }
            } else if let olds = renamesByTarget["cask:" + p.token] {
                packages[i].oldNames = Array(Set(p.oldNames + olds)).sorted()
            }
        }

        var generated: Date?
        if let meta = root["metadata"] as? [String: Any], let ts = meta["generated_at"] as? Double {
            generated = Date(timeIntervalSince1970: ts)
        }
        packages.sort { $0.token < $1.token }
        return Catalog(packages: packages, formulaAliases: aliases, generatedAt: generated, sourceDescription: source)
    }

    /// Legacy array payloads (`formula.json` / `cask.json` and their JWS versions).
    static func parseLegacy(formulae: Data?, casks: Data?, source: String) throws -> Catalog {
        var packages: [Package] = []
        var aliases: [String: String] = [:]
        if let formulae {
            let arr = try JSONSerialization.jsonObject(with: try unwrapJWS(formulae)) as? [[String: Any]] ?? []
            for f in arr {
                let p = legacyFormula(f)
                packages.append(p)
                for a in p.aliases { aliases[a] = p.token }
                for o in p.oldNames { aliases[o] = p.token }
            }
        }
        if let casks {
            let arr = try JSONSerialization.jsonObject(with: try unwrapJWS(casks)) as? [[String: Any]] ?? []
            for c in arr { packages.append(legacyCask(c)) }
        }
        packages.sort { $0.token < $1.token }
        return Catalog(packages: packages, formulaAliases: aliases, generatedAt: nil, sourceDescription: source)
    }

    // MARK: Internal format

    static func internalFormula(name: String, _ f: [String: Any]) -> Package {
        var p = Package(
            kind: .formula, token: name, fullName: name, displayName: name,
            desc: f["desc"] as? String ?? "", homepage: f["homepage"] as? String ?? "",
            version: f["stable_version"] as? String ?? "", tap: "homebrew/core")
        p.revision = f["revision"] as? Int ?? 0
        p.license = f["license"] as? String
        p.aliases = f["aliases"] as? [String] ?? []
        p.oldNames = f["oldnames"] as? [String] ?? []
        p.caveats = (f["caveats"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let deps = splitDependencies(f["stable_dependencies"])
        p.dependencies = deps.runtime
        p.buildDependencies = deps.build
        p.optionalDependencies = deps.optional
        p.recommendedDependencies = deps.recommended
        p.usesFromMacOS = usesFromMacOS(f["stable_uses_from_macos"])
        p.hasBottle = f["bottle_checksum"] != nil
        p.kegOnly = f["keg_only_args"] != nil
        p.hasHead = f["head_url_args"] != nil
        p.hasService = f["service_args"] != nil || f["service_run_args"] != nil
        p.versionedFormulae = f["versioned_formulae"] as? [String] ?? []
        p.conflicts = (f["conflicts"] as? [Any])?.compactMap { item -> String? in
            if let s = item as? String { return s }
            if let arr = item as? [Any] { return arr.first as? String }
            return nil
        } ?? []
        (p.deprecationReason, p.replacement) = reasonArgs(f["deprecate_args"], fallback: "deprecated")
        let disabled = reasonArgs(f["disable_args"], fallback: "disabled")
        p.disableReason = disabled.0
        if p.replacement == nil { p.replacement = disabled.1 }
        return p
    }

    static func internalCask(token: String, _ c: [String: Any]) -> Package {
        let names = c["names"] as? [String] ?? []
        var p = Package(
            kind: .cask, token: token, fullName: token, displayName: names.first ?? token,
            desc: c["desc"] as? String ?? "", homepage: c["homepage"] as? String ?? "",
            version: c["version"] as? String ?? "", tap: c["tap_string"] as? String ?? "homebrew/cask")
        p.autoUpdates = c["auto_updates"] as? Bool ?? false
        p.caveats = (c["raw_caveats"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        p.oldNames = c["renames"] as? [String] ?? []
        if let artifacts = c["raw_artifacts"] as? [Any] {
            for case let pair as [Any] in artifacts {
                guard pair.count == 2, let kind = pair[0] as? String else { continue }
                applyCaskArtifact(kind: kind.trimmingCharacters(in: [":"]), value: pair[1], to: &p)
            }
        }
        if let dependsOn = c["depends_on_args"] as? [String: Any] {
            p.macOSRequirement = macOSRequirement(dependsOn[":macos"])
            p.caskFormulaDependencies = stringList(dependsOn[":formula"])
        }
        p.conflicts = stringList((c["conflicts_with_args"] as? [String: Any])?[":cask"])
        (p.deprecationReason, p.replacement) = reasonArgs(c["deprecate_args"], fallback: "deprecated")
        let disabled = reasonArgs(c["disable_args"], fallback: "disabled")
        p.disableReason = disabled.0
        return p
    }

    /// Dependencies are `"name"` or `{"name": ":build"}` / `{"name": [":build", ":test"]}`.
    static func splitDependencies(_ value: Any?) -> (runtime: [String], build: [String], optional: [String], recommended: [String]) {
        var runtime: [String] = [], build: [String] = [], optional: [String] = [], recommended: [String] = []
        for item in value as? [Any] ?? [] {
            if let name = item as? String {
                runtime.append(name)
            } else if let dict = item as? [String: Any] {
                for (name, tags) in dict {
                    let list = (tags as? [String]) ?? [(tags as? String) ?? ""]
                    if list.contains(":build") || list.contains(":test") { build.append(name) }
                    else if list.contains(":optional") { optional.append(name) }
                    else if list.contains(":recommended") { recommended.append(name) }
                    else { runtime.append(name) }
                }
            }
        }
        return (runtime, build, optional, recommended)
    }

    static func usesFromMacOS(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { item in
            if let arr = item as? [Any] { return arr.first as? String }
            if let s = item as? String { return s }
            if let d = item as? [String: Any] { return d.keys.first }
            return nil
        }
    }

    /// `deprecate_args` / `disable_args`: `{":date": "...", ":because": ":unmaintained", ":replacement_formula": "x"}`.
    static func reasonArgs(_ value: Any?, fallback: String) -> (String?, String?) {
        guard let dict = value as? [String: Any] else { return (nil, nil) }
        var because = dict[":because"] as? String ?? fallback
        because = because.trimmingCharacters(in: [":"]).replacingOccurrences(of: "_", with: " ")
        let replacement = (dict[":replacement_formula"] ?? dict[":replacement_cask"] ?? dict[":replacement"]) as? String
        return (because, replacement)
    }

    static func applyCaskArtifact(kind: String, value: Any, to p: inout Package) {
        switch kind {
        case "app":
            p.appNames += stringList(value)
        case "binary":
            p.binaries += stringList(value).map { ($0 as NSString).lastPathComponent }
        case "pkg":
            p.pkgs += stringList(value)
        case "zap":
            for case let dict as [String: Any] in (value as? [Any] ?? [value]) {
                for key in [":trash", ":delete", ":rmdir", "trash", "delete", "rmdir"] {
                    p.zapPaths += stringList(dict[key])
                }
            }
        default:
            break
        }
    }

    static func stringList(_ value: Any?) -> [String] {
        if let s = value as? String { return [s] }
        guard let arr = value as? [Any] else { return [] }
        var out: [String] = []
        for item in arr {
            if let s = item as? String { out.append(s) }
            else if let nested = item as? [Any] { out += stringList(nested) }
        }
        return out
    }

    static func macOSRequirement(_ value: Any?) -> String? {
        if let s = value as? String { return s.trimmingCharacters(in: [":"]) }
        if let d = value as? [String: Any], let first = d.first {
            let v = stringList(first.value).first ?? ""
            return "\(first.key) \(v.trimmingCharacters(in: [":"]))"
        }
        return nil
    }

    // MARK: Legacy format

    static func legacyFormula(_ f: [String: Any]) -> Package {
        let name = f["name"] as? String ?? ""
        let versions = f["versions"] as? [String: Any] ?? [:]
        var p = Package(
            kind: .formula, token: name, fullName: f["full_name"] as? String ?? name, displayName: name,
            desc: f["desc"] as? String ?? "", homepage: f["homepage"] as? String ?? "",
            version: versions["stable"] as? String ?? "", tap: f["tap"] as? String ?? "homebrew/core")
        p.revision = f["revision"] as? Int ?? 0
        p.license = f["license"] as? String
        p.aliases = f["aliases"] as? [String] ?? []
        p.oldNames = f["oldnames"] as? [String] ?? []
        p.caveats = f["caveats"] as? String
        p.dependencies = f["dependencies"] as? [String] ?? []
        p.buildDependencies = f["build_dependencies"] as? [String] ?? []
        p.optionalDependencies = f["optional_dependencies"] as? [String] ?? []
        p.recommendedDependencies = f["recommended_dependencies"] as? [String] ?? []
        p.usesFromMacOS = usesFromMacOS(f["uses_from_macos"])
        p.hasBottle = ((f["bottle"] as? [String: Any])?["stable"]) != nil
        p.kegOnly = f["keg_only"] as? Bool ?? false
        p.hasHead = versions["head"] is String
        p.hasService = f["service"] != nil && !(f["service"] is NSNull)
        p.versionedFormulae = f["versioned_formulae"] as? [String] ?? []
        p.conflicts = f["conflicts_with"] as? [String] ?? []
        if f["deprecated"] as? Bool == true {
            p.deprecationReason = (f["deprecation_reason"] as? String) ?? "deprecated"
            p.replacement = f["deprecation_replacement_formula"] as? String
        }
        if f["disabled"] as? Bool == true {
            p.disableReason = (f["disable_reason"] as? String) ?? "disabled"
        }
        return p
    }

    static func legacyCask(_ c: [String: Any]) -> Package {
        let token = c["token"] as? String ?? ""
        let names = c["name"] as? [String] ?? []
        var p = Package(
            kind: .cask, token: token, fullName: c["full_token"] as? String ?? token, displayName: names.first ?? token,
            desc: c["desc"] as? String ?? "", homepage: c["homepage"] as? String ?? "",
            version: c["version"] as? String ?? "", tap: c["tap"] as? String ?? "homebrew/cask")
        p.autoUpdates = c["auto_updates"] as? Bool ?? false
        p.caveats = c["caveats"] as? String
        p.oldNames = c["old_tokens"] as? [String] ?? []
        for case let dict as [String: Any] in c["artifacts"] as? [Any] ?? [] {
            for (k, v) in dict { applyCaskArtifact(kind: k, value: v, to: &p) }
        }
        if let dependsOn = c["depends_on"] as? [String: Any] {
            p.macOSRequirement = macOSRequirement(dependsOn["macos"])
            p.caskFormulaDependencies = stringList(dependsOn["formula"])
        }
        p.conflicts = stringList((c["conflicts_with"] as? [String: Any])?["cask"])
        if c["deprecated"] as? Bool == true { p.deprecationReason = c["deprecation_reason"] as? String ?? "deprecated" }
        if c["disabled"] as? Bool == true { p.disableReason = c["disable_reason"] as? String ?? "disabled" }
        return p
    }
}
