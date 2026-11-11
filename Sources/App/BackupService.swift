import Foundation
import SwiftData

struct BackupFile: Codable {
    var version = 1
    var createdAt: Date
    var txns: [TxnDTO]
    var categories: [CategoryDTO]
    var rules: [RuleDTO]
    var overallBudget: Double
}

struct TxnDTO: Codable {
    var id: UUID
    var date: Date
    var amount: Double
    var merchant: String
    var note: String
    var category: String
    var methodRaw: String
    var sourceRaw: String
    var reference: String
    var card: String
    var needsReview: Bool
    var possibleDuplicate: Bool
    var createdAt: Date
}

struct CategoryDTO: Codable {
    var name: String
    var icon: String
    var colorHex: String
    var monthlyBudget: Double
    var sortOrder: Int
}

struct RuleDTO: Codable {
    var keyword: String
    var category: String
    var learned: Bool
}

/// Backups go to Files → On My iPhone → Seringgit → Backups (screenshots are not included, to keep them small).
@MainActor
enum BackupService {
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func make(ctx: ModelContext) -> BackupFile {
        let txns = (try? ctx.fetch(FetchDescriptor<Txn>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let cats = (try? ctx.fetch(FetchDescriptor<SpendCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let rules = (try? ctx.fetch(FetchDescriptor<MerchantRule>())) ?? []
        return BackupFile(
            createdAt: Date(),
            txns: txns.map { TxnDTO(id: $0.id, date: $0.date, amount: $0.amount, merchant: $0.merchant, note: $0.note,
                                    category: $0.category, methodRaw: $0.methodRaw, sourceRaw: $0.sourceRaw,
                                    reference: $0.reference, card: $0.card, needsReview: $0.needsReview,
                                    possibleDuplicate: $0.possibleDuplicate, createdAt: $0.createdAt) },
            categories: cats.map { CategoryDTO(name: $0.name, icon: $0.icon, colorHex: $0.colorHex, monthlyBudget: $0.monthlyBudget, sortOrder: $0.sortOrder) },
            rules: rules.map { RuleDTO(keyword: $0.keyword, category: $0.category, learned: $0.learned) },
            overallBudget: UserDefaults.standard.double(forKey: Keys.overallBudget)
        )
    }

    @discardableResult
    static func backup(ctx: ModelContext) -> URL? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(make(ctx: ctx)) else { return nil }
        let url = folder.appendingPathComponent("Seringgit_\(Fmt.fileStamp.string(from: Date())).json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastBackup)
        prune()
        return url
    }

    /// Runs when the app goes to the background, at most every 6 hours.
    static func autoBackup(ctx: ModelContext) {
        let last = UserDefaults.standard.double(forKey: Keys.lastBackup)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        let count = (try? ctx.fetchCount(FetchDescriptor<Txn>())) ?? 0
        guard count > 0 else { return }
        backup(ctx: ctx)
    }

    private static func prune(keep: Int = 20) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Seringgit_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in files.dropFirst(keep) { try? FileManager.default.removeItem(at: f) }
    }

    /// Import a Seringgit backup (.json) or a CSV from Seringgit, Belanje or another app. Returns a message to show.
    static func importFile(_ url: URL, ctx: ModelContext) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            return "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
        if data.starts(with: [0x50, 0x4B]) {
            return "\(url.lastPathComponent) is an Excel/zip file. Open it in Numbers → Share → Export → CSV, then import the CSV."
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let file = try? dec.decode(BackupFile.self, from: data) {
            do {
                let n = try restore(file, ctx: ctx)
                return "Restored \(n) payment\(n == 1 ? "" : "s") from \(url.lastPathComponent)."
            } catch {
                return "Restore failed: \(error.localizedDescription)"
            }
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .windowsCP1252) else {
            return "\(url.lastPathComponent) isn't a text file Seringgit can read."
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            var why = ""
            do { _ = try dec.decode(BackupFile.self, from: data) } catch { why = "\n\n\(String(describing: error).prefix(300))" }
            return "\(url.lastPathComponent) is JSON but not a Seringgit backup.\(why)"
        }
        return importCSV(text, name: url.lastPathComponent, ctx: ctx)
    }

    static func importCSV(_ text: String, name: String, ctx: ModelContext) -> String {
        let result = CSVImporter.importRows(text)
        if let err = result.error { return "\(name): \(err)" }

        var cats = (try? ctx.fetch(FetchDescriptor<SpendCategory>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let palette = CategoryForm.colors
        func categoryName(for r: ImportedRow, method: PayMethod) -> String {
            let wanted = r.category.trimmingCharacters(in: .whitespaces)
            if wanted.isEmpty { return Store.categoryFor(merchant: r.payee, method: method, ctx: ctx) }
            if let c = cats.first(where: { $0.name.lowercased() == wanted.lowercased() }) { return c.name }
            let c = SpendCategory(name: wanted, icon: "tag.fill", colorHex: palette[cats.count % palette.count],
                                  sortOrder: (cats.map { $0.sortOrder }.max() ?? 0) + 1)
            ctx.insert(c)
            cats.append(c)
            return c.name
        }

        let existing = (try? ctx.fetch(FetchDescriptor<Txn>())) ?? []
        func dupKey(_ d: Date, _ a: Double, _ p: String) -> String {
            "\(Int(d.timeIntervalSince1970 / 60))|\(Int((a * 100).rounded()))|\(Categorizer.normalize(p))"
        }
        var seen = Set(existing.map { dupKey($0.date, $0.amount, $0.merchant) })
        var added = 0, dups = 0
        for r in result.rows {
            let k = dupKey(r.date, r.amount, r.payee)
            if seen.contains(k) { dups += 1; continue }
            seen.insert(k)
            let m = r.method ?? .other
            let t = Txn(date: r.date, amount: r.amount, merchant: r.payee, category: categoryName(for: r, method: m), method: m, source: .imported)
            t.note = r.note
            ctx.insert(t)
            added += 1
        }
        try? ctx.save()
        var parts: [String] = []
        if result.skippedIncome > 0 { parts.append("\(result.skippedIncome) income") }
        if dups > 0 { parts.append("\(dups) already in Seringgit") }
        if result.skippedBad > 0 { parts.append("\(result.skippedBad) unreadable") }
        return "Imported \(added) payment\(added == 1 ? "" : "s") from \(name)." + (parts.isEmpty ? "" : " Skipped: " + parts.joined(separator: ", ") + ".")
    }

    /// Adds anything in the backup that isn't already in the app (matched by payment id). Returns payments added.
    static func restore(_ file: BackupFile, ctx: ModelContext) throws -> Int {
        let existingCats = Set(((try? ctx.fetch(FetchDescriptor<SpendCategory>())) ?? []).map { $0.name })
        for c in file.categories where !existingCats.contains(c.name) {
            ctx.insert(SpendCategory(name: c.name, icon: c.icon, colorHex: c.colorHex, sortOrder: c.sortOrder, monthlyBudget: c.monthlyBudget))
        }
        let existingRules = Set(((try? ctx.fetch(FetchDescriptor<MerchantRule>())) ?? []).map { "\($0.learned)|\(Categorizer.normalize($0.keyword))" })
        for r in file.rules where !existingRules.contains("\(r.learned)|\(Categorizer.normalize(r.keyword))") {
            ctx.insert(MerchantRule(keyword: r.keyword, category: r.category, learned: r.learned))
        }
        let existingIds = Set(((try? ctx.fetch(FetchDescriptor<Txn>())) ?? []).map { $0.id })
        var added = 0
        for d in file.txns where !existingIds.contains(d.id) {
            let t = Txn(date: d.date, amount: d.amount, merchant: d.merchant, category: d.category,
                        method: PayMethod(rawValue: d.methodRaw) ?? .other, source: CaptureSource(rawValue: d.sourceRaw) ?? .imported)
            t.id = d.id
            t.note = d.note
            t.reference = d.reference
            t.card = d.card
            t.needsReview = d.needsReview
            t.possibleDuplicate = d.possibleDuplicate
            t.createdAt = d.createdAt
            ctx.insert(t)
            added += 1
        }
        if UserDefaults.standard.double(forKey: Keys.overallBudget) == 0 && file.overallBudget > 0 {
            UserDefaults.standard.set(file.overallBudget, forKey: Keys.overallBudget)
        }
        try ctx.save()
        return added
    }

    /// Spreadsheet-friendly export of every payment.
    static func csv(ctx: ModelContext) -> URL? {
        let txns = (try? ctx.fetch(FetchDescriptor<Txn>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "Date,Amount (RM),Payee,Category,Paid with,Note,Reference,Recorded by\n"
        for t in txns {
            out += [Fmt.csv.string(from: t.date), String(format: "%.2f", t.amount), q(t.merchant), q(t.category),
                    q(t.method.title), q(t.note), q(t.reference), q(t.source.title)].joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Seringgit_\(Fmt.fileStamp.string(from: Date())).csv")
        do { try out.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }
}
