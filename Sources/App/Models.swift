import Foundation
import SwiftData
import SwiftUI

enum CaptureSource: String, Codable {
    case applePay, screenshot, manual, imported
    var title: String {
        switch self {
        case .applePay: return "Auto · Apple Pay"
        case .screenshot: return "Auto · Screenshot"
        case .manual: return "Manual"
        case .imported: return "Restored"
        }
    }
}

@Model
final class Txn {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Double = 0
    var merchant: String = ""
    var note: String = ""
    var category: String = "Others"
    var methodRaw: String = PayMethod.other.rawValue
    var sourceRaw: String = CaptureSource.manual.rawValue
    var reference: String = ""
    var card: String = ""
    var needsReview: Bool = false
    var possibleDuplicate: Bool = false
    var ocrText: String = ""
    @Attribute(.externalStorage) var receipt: Data?
    var createdAt: Date = Date()

    init(date: Date = Date(), amount: Double = 0, merchant: String = "", category: String = "Others",
         method: PayMethod = .other, source: CaptureSource = .manual) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.merchant = merchant
        self.category = category
        self.methodRaw = method.rawValue
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    var method: PayMethod {
        get { PayMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
    var source: CaptureSource { CaptureSource(rawValue: sourceRaw) ?? .manual }
    var displayName: String { merchant.isEmpty ? "Unknown payee" : merchant }
}

@Model
final class SpendCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "tag.fill"
    var colorHex: String = "9E9E9E"
    var monthlyBudget: Double = 0
    var sortOrder: Int = 0

    init(name: String, icon: String, colorHex: String, sortOrder: Int, monthlyBudget: Double = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.monthlyBudget = monthlyBudget
    }

    var color: Color { Color(hex: colorHex) }
}

@Model
final class MerchantRule {
    var id: UUID = UUID()
    var keyword: String = ""
    var category: String = ""
    var learned: Bool = false
    var createdAt: Date = Date()

    init(keyword: String, category: String, learned: Bool) {
        self.id = UUID()
        self.keyword = keyword
        self.category = category
        self.learned = learned
        self.createdAt = Date()
    }
}

// MARK: - Seeding and lookups

enum Store {
    static func seedIfNeeded(_ ctx: ModelContext) {
        let count = (try? ctx.fetchCount(FetchDescriptor<SpendCategory>())) ?? 0
        guard count == 0 else { return }
        for (i, d) in Categorizer.defaults.enumerated() {
            ctx.insert(SpendCategory(name: d.name, icon: d.icon, colorHex: d.colorHex, sortOrder: i))
        }
        for r in Categorizer.defaultRules() {
            ctx.insert(MerchantRule(keyword: r.keyword, category: r.category, learned: false))
        }
        try? ctx.save()
    }

    static func rules(_ ctx: ModelContext) -> [CategoryRule] {
        let all = (try? ctx.fetch(FetchDescriptor<MerchantRule>())) ?? []
        return all.map { CategoryRule(keyword: $0.keyword, category: $0.category, exact: $0.learned) }
    }

    static func categoryFor(merchant: String, method: PayMethod, ctx: ModelContext) -> String {
        if let c = Categorizer.category(for: merchant, rules: rules(ctx)) { return c }
        return method == .transfer ? Categorizer.transfer : Categorizer.fallback
    }

    /// Remember the category you picked for this payee, so the next payment there is filed the same way.
    static func learn(merchant: String, category: String, ctx: ModelContext) {
        let key = Categorizer.normalize(merchant)
        guard !key.isEmpty else { return }
        let all = (try? ctx.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.learned == true }))) ?? []
        if let r = all.first(where: { Categorizer.normalize($0.keyword) == key }) {
            r.category = category
        } else {
            ctx.insert(MerchantRule(keyword: merchant, category: category, learned: true))
        }
    }

    /// Same amount within 10 minutes of another payment → probably recorded twice.
    static func markDuplicate(_ t: Txn, ctx: ModelContext) {
        let lo = t.date.addingTimeInterval(-600), hi = t.date.addingTimeInterval(600)
        let tid = t.id
        let near = (try? ctx.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.date >= lo && $0.date <= hi && $0.id != tid }))) ?? []
        if near.contains(where: { abs($0.amount - t.amount) < 0.005 }) { t.possibleDuplicate = true }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x9E9E9E
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
