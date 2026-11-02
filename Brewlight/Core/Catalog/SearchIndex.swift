import Foundation

/// In-memory search over the whole catalog. Built once per catalog load (off the main thread).
///
/// Every field is pre-lowercased into byte buffers shaped so that each kind of match is one
/// `memmem`/`memcmp` call:
/// - name segments are stored as `-seg1-seg2` so a segment-prefix match is a search for `-q`;
/// - description words as ` w1 w2 ` so a word-prefix match is a search for ` q`;
/// - aliases as `\0a1\0a2\0` so exact = `\0q\0` and prefix = `\0q`.
///
/// Ranking: exact name > exact alias > (name / segment / alias prefix, ordered by popularity)
/// > name substring > description word prefix > homepage domain > description substring > fuzzy.
struct SearchIndex: Sendable {
    struct Entry: Sendable {
        let name: [UInt8]
        let display: [UInt8]
        let segments: [UInt8]
        let aliases: [UInt8]
        let words: [UInt8]
        let host: [UInt8]
    }

    struct Hit: Sendable, Hashable {
        let index: Int
        let score: Int
    }

    private let entries: [Entry]

    init(packages: [Package]) {
        entries = packages.map { p in
            let name = Self.lowerBytes(p.token)
            var segs: [UInt8] = [UInt8(ascii: "-")]
            segs.reserveCapacity(name.count + 1)
            for b in name { segs.append(b == 95 || b == 46 || b == 64 || b == 32 ? 45 : b) } // _ . @ space → -
            var aliases: [UInt8] = [0]
            for a in p.aliases + p.oldNames { aliases += Self.lowerBytes(a); aliases.append(0) }
            if aliases.count == 1 { aliases.append(0) }
            var words: [UInt8] = [32]
            words.reserveCapacity(p.desc.utf8.count + 2)
            for b in Self.lowerBytes(p.desc) {
                let alnum = (b >= 48 && b <= 57) || (b >= 97 && b <= 122) || b >= 128
                words.append(alnum ? b : 32)
            }
            words.append(32)
            return Entry(name: name, display: Self.lowerBytes(p.displayName), segments: segs,
                         aliases: aliases, words: words, host: Self.lowerBytes(Self.host(of: p.homepage)))
        }
    }

    /// ASCII-lowercased UTF-8 bytes (non-ASCII bytes pass through untouched).
    static func lowerBytes(_ s: String) -> [UInt8] {
        s.utf8.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
    }

    /// Host without scheme or `www.`, without the cost of URL parsing.
    static func host(of url: String) -> String {
        var s = Substring(url)
        if let r = s.range(of: "://") { s = s[r.upperBound...] }
        if let slash = s.firstIndex(of: "/") { s = s[..<slash] }
        if s.hasPrefix("www.") { s = s.dropFirst(4) }
        return String(s)
    }

    var count: Int { entries.count }

    /// Returns package indices ordered by relevance. `popularity[i]` (installs) lifts popular
    /// packages within the prefix tier and breaks ties elsewhere.
    func search(_ rawQuery: String, limit: Int = 500, popularity: [Int] = []) -> [Hit] {
        let q = Array(rawQuery.trimmingCharacters(in: .whitespaces).lowercased().utf8)
        guard !q.isEmpty else { return [] }
        let dashQ = [UInt8(ascii: "-")] + q
        let spaceQ = [UInt8(ascii: " ")] + q
        let nulQ = [0] + q
        let nulQnul = nulQ + [0]
        var hits: [Hit] = []
        hits.reserveCapacity(512)
        for i in entries.indices {
            let pop = i < popularity.count ? popularity[i] : 0
            let s = Self.score(entries[i], q: q, dashQ: dashQ, spaceQ: spaceQ, nulQ: nulQ, nulQnul: nulQnul, popularity: pop)
            if s > 0 { hits.append(Hit(index: i, score: s)) }
        }
        // Fuzzy subsequence only when the direct matches are thin.
        if hits.count < 20 && q.count >= 2 {
            let have = Set(hits.map(\.index))
            for i in entries.indices where !have.contains(i) && Self.isSubsequence(q, of: entries[i].name) {
                hits.append(Hit(index: i, score: 100))
            }
        }
        // One integer key per hit: score, then popularity, then shorter names.
        var keyed = hits.map { h -> (key: Int64, hit: Hit) in
            let pop = Int64(min(h.index < popularity.count ? popularity[h.index] : 0, (1 << 30) - 1))
            let len = Int64(min(entries[h.index].name.count, 255))
            return ((Int64(h.score) << 40) | (pop << 8) | (255 - len), h)
        }
        keyed.sort { $0.key > $1.key }
        return keyed.prefix(limit).map(\.hit)
    }

    /// Several words: packages matching more of the words rank first; an exact phrase match ranks
    /// above everything else. A single word is the same as `search`.
    func searchWords(_ rawQuery: String, limit: Int = 500, popularity: [Int] = []) -> [Hit] {
        let words = rawQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return search(rawQuery, limit: limit, popularity: popularity) }
        var total: [Int: (matched: Int, score: Int)] = [:]
        for w in Set(words.map { $0.lowercased() }) {
            for h in search(w, limit: 4000, popularity: popularity) {
                let t = total[h.index] ?? (0, 0)
                total[h.index] = (t.matched + 1, t.score + h.score)
            }
        }
        for h in search(rawQuery, limit: 200, popularity: popularity) {
            let t = total[h.index] ?? (0, 0)
            total[h.index] = (t.matched + words.count, t.score + h.score + 2000)
        }
        let ranked = total.map { i, t in Hit(index: i, score: t.matched * 10_000 + t.score) }
        return Array(ranked.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            let pa = a.index < popularity.count ? popularity[a.index] : 0
            let pb = b.index < popularity.count ? popularity[b.index] : 0
            return pa != pb ? pa > pb : a.index < b.index
        }.prefix(limit))
    }

    /// Up to ~150 points for popularity, on a log scale (1M installs ≈ 150).
    static func popularityBonus(_ installs: Int) -> Int {
        installs > 0 ? min(150, Int(log10(Double(installs)) * 25)) : 0
    }

    static func score(_ e: Entry, q: [UInt8], dashQ: [UInt8], spaceQ: [UInt8], nulQ: [UInt8], nulQnul: [UInt8], popularity: Int) -> Int {
        if e.name == q { return 1000 }
        if e.display == q { return 980 }
        if contains(e.aliases, nulQnul) { return 950 }
        let bonus = popularityBonus(popularity)
        if hasPrefix(e.name, q) { return 720 + bonus - min(e.name.count - q.count, 20) }
        if contains(e.aliases, nulQ) { return 700 + bonus }
        if hasPrefix(e.display, q) { return 700 + bonus }
        if contains(e.segments, dashQ) { return 690 + bonus - min(e.name.count - q.count, 20) }
        if contains(e.name, q) { return 500 + bonus / 3 }
        if q.count >= 2 && contains(e.words, spaceQ) { return 300 + bonus / 3 }
        if q.count >= 3 && contains(e.host, q) { return 250 }
        if q.count >= 4 && contains(e.words, q) { return 200 }
        return 0
    }

    @inline(__always)
    static func hasPrefix(_ s: [UInt8], _ p: [UInt8]) -> Bool {
        guard s.count >= p.count else { return false }
        return s.withUnsafeBytes { sb in p.withUnsafeBytes { pb in memcmp(sb.baseAddress!, pb.baseAddress!, p.count) == 0 } }
    }

    @inline(__always)
    static func contains(_ s: [UInt8], _ p: [UInt8]) -> Bool {
        guard s.count >= p.count, !p.isEmpty else { return false }
        return s.withUnsafeBytes { sb in
            p.withUnsafeBytes { pb in memmem(sb.baseAddress!, s.count, pb.baseAddress!, p.count) != nil }
        }
    }

    static func isSubsequence(_ q: [UInt8], of s: [UInt8]) -> Bool {
        var j = 0
        for c in s where j < q.count && c == q[j] { j += 1 }
        return j == q.count
    }
}

/// Parsed search query: free text plus `tag:`, `tap:`, `cat:`, `is:` and `type:` filters.
struct SearchQuery: Equatable, Sendable {
    var text = ""
    var tags: [String] = []
    var taps: [String] = []
    var categories: [String] = []
    var isInstalled = false
    var isOutdated = false
    var isPinned = false
    var isDeprecated = false
    var kind: PackageKind?

    init(_ raw: String) {
        var words: [String] = []
        for token in raw.split(separator: " ") {
            let t = String(token)
            let lower = t.lowercased()
            if lower.hasPrefix("tag:") { tags.append(String(t.dropFirst(4))) }
            else if lower.hasPrefix("tap:") { taps.append(String(lower.dropFirst(4))) }
            else if lower.hasPrefix("cat:") { categories.append(String(lower.dropFirst(4))) }
            else if lower == "is:installed" { isInstalled = true }
            else if lower == "is:outdated" { isOutdated = true }
            else if lower == "is:pinned" { isPinned = true }
            else if lower == "is:deprecated" { isDeprecated = true }
            else if lower == "type:cask" { kind = .cask }
            else if lower == "type:formula" { kind = .formula }
            else { words.append(t) }
        }
        text = words.joined(separator: " ")
    }

    var hasFilters: Bool {
        !tags.isEmpty || !taps.isEmpty || !categories.isEmpty || isInstalled || isOutdated || isPinned || isDeprecated || kind != nil
    }
}
