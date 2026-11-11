import Foundation

struct CategoryRule {
    var keyword: String
    var category: String
    /// Learned from your own edits: matches the whole merchant name, and wins over keywords.
    var exact: Bool
}

struct DefaultCategory {
    let name: String
    let icon: String
    let colorHex: String
    let keywords: [String]
}

enum Categorizer {
    static let fallback = "Others"
    static let transfer = "Transfer"

    /// Lowercase, accents removed, punctuation turned into spaces (keeps &), single spaces.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US")).lowercased()
        let mapped = folded.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "&") ? ch : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func category(for merchant: String, rules: [CategoryRule]) -> String? {
        let m = normalize(merchant)
        guard !m.isEmpty else { return nil }
        if let r = rules.first(where: { $0.exact && normalize($0.keyword) == m }) { return r.category }
        let padded = " " + m + " "
        var best: (len: Int, cat: String)?
        for r in rules where !r.exact {
            let k = normalize(r.keyword)
            guard !k.isEmpty else { continue }
            // Short keywords (tm, kfc, tng, aeon…) must be a whole word; longer ones only need to start a word.
            let hit = k.count <= 4 ? padded.contains(" " + k + " ") : padded.contains(" " + k)
            if hit, best == nil || k.count > best!.len { best = (k.count, r.category) }
        }
        return best?.cat
    }

    static func defaultRules() -> [CategoryRule] {
        defaults.flatMap { d in d.keywords.map { CategoryRule(keyword: $0, category: d.name, exact: false) } }
    }

    static let defaults: [DefaultCategory] = [
        DefaultCategory(name: "Food & Drinks", icon: "fork.knife", colorHex: "FF9800", keywords: [
            "mcd", "mcdonald", "mcdonalds", "kfc", "starbucks", "zus", "zus coffee", "tealive", "chagee", "mixue", "kenny rogers",
            "pizza", "domino", "dominos", "secret recipe", "subway", "marrybrown", "texas chicken", "burger", "oldtown",
            "nasi", "mee", "roti", "mamak", "restoran", "restaurant", "resto", "cafe", "kafe", "coffee", "kopi", "kopitiam",
            "bakery", "grabfood", "foodpanda", "shopeefood", "sushi", "tutti frutti", "baskin", "dunkin", "a&w", "kedai makan",
            "warung", "gerai", "bistro", "kitchen", "noodle", "chicken", "bubble tea", "boba", "nandos", "llaollao", "satay",
            "sate", "ayam", "makan", "food", "tapau", "manjoi", "tg nasi kandar", "pelita", "ali maju", "family mart cafe"
        ]),
        DefaultCategory(name: "Groceries", icon: "cart.fill", colorHex: "2E7D32", keywords: [
            "mydin", "aeon", "aeon big", "lotus", "lotuss", "tesco", "giant", "econsave", "speedmart", "99 speedmart",
            "kk mart", "kk super", "family mart", "familymart", "7 eleven", "seven eleven", "7eleven", "jaya grocer",
            "village grocer", "hero", "nsk", "the store", "mercato", "cold storage", "pasar", "pasaraya", "supermarket",
            "borong", "grocer", "mynews", "emart", "hypermarket", "minimarket", "mart"
        ]),
        DefaultCategory(name: "Transport", icon: "car.fill", colorHex: "1565C0", keywords: [
            "petronas", "shell", "petron", "bhp", "caltex", "setel", "plus", "plus malaysia", "touch n go", "touchngo", "tng",
            "toll", "tol", "parking", "parkir", "grab", "ktm", "rapidkl", "rapid", "mrt", "lrt", "airasia", "air asia",
            "malaysia airlines", "firefly", "batik air", "ets", "bus", "taxi", "car wash", "tayar", "tyre", "tire",
            "workshop", "jpj", "mypark", "flexi parking", "smart parking", "petrol", "e hailing", "indrive", "maxim"
        ]),
        DefaultCategory(name: "Shopping", icon: "bag.fill", colorHex: "D81B60", keywords: [
            "shopee", "lazada", "mr diy", "mrdiy", "ikea", "uniqlo", "padini", "decathlon", "courts", "harvey norman",
            "senheng", "senq", "machines", "switch", "popular", "mph", "h&m", "zara", "cotton on", "daiso", "eco shop",
            "ecoshop", "brands outlet", "sports direct", "nike", "adidas", "apple store", "tiktok shop", "temu", "shein",
            "kaison", "aeon mall", "mall", "boutique", "fashion", "hardware", "kedai"
        ]),
        DefaultCategory(name: "Bills", icon: "bolt.fill", colorHex: "6A1B9A", keywords: [
            "tnb", "tenaga", "tenaga nasional", "unifi", "tm", "telekom", "maxis", "hotlink", "celcom", "digi",
            "celcomdigi", "u mobile", "umobile", "yes 4g", "astro", "air selangor", "syabas", "saj", "paip", "pba",
            "pengurusan air", "indah water", "iwk", "lhdn", "hasil", "cukai", "majlis", "mbk", "mpk", "takaful",
            "insurance", "insurans", "etiqa", "prudential", "aia", "great eastern", "allianz", "zurich", "tokio marine",
            "ptptn", "jompay", "bill", "bil", "zakat", "tabung haji"
        ]),
        DefaultCategory(name: "Family", icon: "figure.and.child.holdinghands", colorHex: "00897B", keywords: [
            "tadika", "taska", "kindergarten", "nursery", "school", "sekolah", "toys", "toy", "mothercare", "anakku",
            "baby", "pampers", "mamypoko", "tuition", "tuisyen", "kids", "kid", "playground", "smart reader"
        ]),
        DefaultCategory(name: "Health", icon: "cross.case.fill", colorHex: "E53935", keywords: [
            "watsons", "guardian", "caring", "aa pharmacy", "big pharmacy", "alpro", "farmasi", "pharmacy", "klinik",
            "clinic", "hospital", "kpj", "columbia asia", "pantai", "sunway medical", "dental", "gigi", "optometrist",
            "optical", "gym", "fitness", "anytime fitness", "medical", "health"
        ]),
        DefaultCategory(name: "Entertainment", icon: "popcorn.fill", colorHex: "3949AB", keywords: [
            "tgv", "gsc", "mbo", "lfs", "netflix", "spotify", "youtube", "disney", "steam", "playstation", "nintendo",
            "cinema", "cinemas", "bowling", "karaoke", "apple com bill", "icloud", "hbo", "viu", "iqiyi", "games", "game"
        ]),
        DefaultCategory(name: "Transfer", icon: "arrow.left.arrow.right", colorHex: "546E7A", keywords: []),
        DefaultCategory(name: "Others", icon: "ellipsis.circle.fill", colorHex: "9E9E9E", keywords: [])
    ]
}
