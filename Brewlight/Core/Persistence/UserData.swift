import Foundation
import SwiftData

@Model
final class TagModel {
    @Attribute(.unique) var name: String
    var colorHex: String
    var packageIDs: [String]
    var createdAt: Date

    init(name: String, colorHex: String, packageIDs: [String] = []) {
        self.name = name
        self.colorHex = colorHex
        self.packageIDs = packageIDs
        self.createdAt = .now
    }
}

@Model
final class FavouriteModel {
    @Attribute(.unique) var packageID: String
    var addedAt: Date
    init(packageID: String) { self.packageID = packageID; addedAt = .now }
}

@Model
final class NoteModel {
    @Attribute(.unique) var packageID: String
    var text: String
    var updatedAt: Date
    init(packageID: String, text: String) { self.packageID = packageID; self.text = text; updatedAt = .now }
}

@Model
final class HistoryEntry {
    var date: Date
    var title: String
    var command: String
    var packages: [String]
    var succeeded: Bool
    var exitCode: Int
    var duration: Double
    var logExcerpt: String

    init(date: Date, title: String, command: String, packages: [String], succeeded: Bool, exitCode: Int, duration: Double, logExcerpt: String) {
        self.date = date
        self.title = title
        self.command = command
        self.packages = packages
        self.succeeded = succeeded
        self.exitCode = exitCode
        self.duration = duration
        self.logExcerpt = logExcerpt
    }
}

@Model
final class SkippedVersionModel {
    @Attribute(.unique) var packageID: String
    var version: String
    init(packageID: String, version: String) { self.packageID = packageID; self.version = version }
}

@Model
final class CategoryOverrideModel {
    @Attribute(.unique) var packageID: String
    var category: String
    init(packageID: String, category: String) { self.packageID = packageID; self.category = category }
}

/// Main-actor facade over SwiftData with in-memory lookup tables, so list rows never fetch.
@MainActor @Observable
final class UserDataStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private(set) var tags: [TagModel] = []
    private(set) var favourites: Set<String> = []
    private(set) var notes: [String: String] = [:]
    private(set) var skipped: [String: String] = [:]
    private(set) var categoryOverrides: [String: String] = [:]
    private(set) var tagsByPackage: [String: [TagModel]] = [:]
    /// Called after every save so the model can refresh what depends on user data.
    @ObservationIgnored var onChange: (() -> Void)?

    init(inMemory: Bool = false) {
        let schema = Schema([TagModel.self, FavouriteModel.self, NoteModel.self, HistoryEntry.self,
                             SkippedVersionModel.self, CategoryOverrideModel.self])
        let url = Paths.appSupport.appending(path: "UserData.store")
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: url)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // A corrupt store must never stop the app from launching.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        reload()
    }

    func reload() {
        tags = (try? context.fetch(FetchDescriptor<TagModel>(sortBy: [SortDescriptor(\.name)]))) ?? []
        favourites = Set(((try? context.fetch(FetchDescriptor<FavouriteModel>())) ?? []).map(\.packageID))
        notes = Dictionary(((try? context.fetch(FetchDescriptor<NoteModel>())) ?? []).map { ($0.packageID, $0.text) }) { a, _ in a }
        skipped = Dictionary(((try? context.fetch(FetchDescriptor<SkippedVersionModel>())) ?? []).map { ($0.packageID, $0.version) }) { a, _ in a }
        categoryOverrides = Dictionary(((try? context.fetch(FetchDescriptor<CategoryOverrideModel>())) ?? []).map { ($0.packageID, $0.category) }) { a, _ in a }
        var byPackage: [String: [TagModel]] = [:]
        for t in tags { for id in t.packageIDs { byPackage[id, default: []].append(t) } }
        tagsByPackage = byPackage
    }

    private func save() {
        try? context.save()
        reload()
        onChange?()
    }

    // MARK: Tags

    func createTag(_ name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        context.insert(TagModel(name: trimmed, colorHex: colorHex))
        save()
    }

    func deleteTag(_ tag: TagModel) { context.delete(tag); save() }

    func toggle(tag: TagModel, on packageID: String) {
        if let i = tag.packageIDs.firstIndex(of: packageID) { tag.packageIDs.remove(at: i) }
        else { tag.packageIDs.append(packageID) }
        save()
    }

    func tag(named name: String) -> TagModel? {
        tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Favourites, notes

    func toggleFavourite(_ id: String) {
        if favourites.contains(id) {
            try? context.delete(model: FavouriteModel.self, where: #Predicate { $0.packageID == id })
        } else {
            context.insert(FavouriteModel(packageID: id))
        }
        save()
    }

    func setNote(_ text: String, for id: String) {
        let existing = try? context.fetch(FetchDescriptor<NoteModel>(predicate: #Predicate { $0.packageID == id })).first
        if text.isEmpty {
            if let existing { context.delete(existing) }
        } else if let existing {
            existing.text = text
            existing.updatedAt = .now
        } else {
            context.insert(NoteModel(packageID: id, text: text))
        }
        save()
    }

    // MARK: Skipped versions, categories

    func skip(_ id: String, version: String) {
        try? context.delete(model: SkippedVersionModel.self, where: #Predicate { $0.packageID == id })
        context.insert(SkippedVersionModel(packageID: id, version: version))
        save()
    }

    func unskip(_ id: String) {
        try? context.delete(model: SkippedVersionModel.self, where: #Predicate { $0.packageID == id })
        save()
    }

    func setCategory(_ category: PackageCategory?, for id: String) {
        try? context.delete(model: CategoryOverrideModel.self, where: #Predicate { $0.packageID == id })
        if let category { context.insert(CategoryOverrideModel(packageID: id, category: category.rawValue)) }
        save()
    }

    // MARK: History

    func record(_ op: BrewOperation) {
        let ok = op.state == .succeeded
        var code = 0
        if case .failed(let c) = op.state { code = Int(c) }
        if op.state == .cancelled { code = 130 }
        context.insert(HistoryEntry(
            date: op.startedAt ?? op.queuedAt, title: op.title, command: op.command, packages: op.packages,
            succeeded: ok, exitCode: code, duration: op.duration ?? 0,
            logExcerpt: op.log.suffix(40).map(\.text).joined(separator: "\n")))
        try? context.save()
    }

    func history(limit: Int = 2000) -> [HistoryEntry] {
        var d = FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    func clearHistory() {
        try? context.delete(model: HistoryEntry.self)
        try? context.save()
    }

    // MARK: Export / import

    struct Export: Codable {
        struct Tag: Codable { var name: String; var color: String; var packages: [String] }
        struct History: Codable { var date: Date; var title: String; var command: String; var packages: [String]; var succeeded: Bool }
        var version = 1
        var tags: [Tag]
        var favourites: [String]
        var notes: [String: String]
        var skipped: [String: String]
        var categoryOverrides: [String: String]
        var history: [History]
    }

    func exportData() throws -> Data {
        let e = Export(
            tags: tags.map { .init(name: $0.name, color: $0.colorHex, packages: $0.packageIDs) },
            favourites: favourites.sorted(), notes: notes, skipped: skipped, categoryOverrides: categoryOverrides,
            history: history().map { .init(date: $0.date, title: $0.title, command: $0.command, packages: $0.packages, succeeded: $0.succeeded) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(e)
    }

    func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let e = try decoder.decode(Export.self, from: data)
        for t in e.tags {
            if let existing = tag(named: t.name) {
                existing.packageIDs = Array(Set(existing.packageIDs + t.packages))
            } else {
                context.insert(TagModel(name: t.name, colorHex: t.color, packageIDs: t.packages))
            }
        }
        for f in e.favourites where !favourites.contains(f) { context.insert(FavouriteModel(packageID: f)) }
        for (id, text) in e.notes where notes[id] == nil { context.insert(NoteModel(packageID: id, text: text)) }
        for (id, v) in e.skipped where skipped[id] == nil { context.insert(SkippedVersionModel(packageID: id, version: v)) }
        for (id, c) in e.categoryOverrides where categoryOverrides[id] == nil { context.insert(CategoryOverrideModel(packageID: id, category: c)) }
        save()
    }

    func resetAll() {
        for type in [TagModel.self, FavouriteModel.self, NoteModel.self, SkippedVersionModel.self, CategoryOverrideModel.self] as [any PersistentModel.Type] {
            try? context.delete(model: type)
        }
        try? context.delete(model: HistoryEntry.self)
        save()
    }
}
