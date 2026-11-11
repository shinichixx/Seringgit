import Foundation

/// One spending row read from a CSV exported by Seringgit, Belanje or another expense app.
struct ImportedRow {
    var date: Date
    var amount: Double
    var payee: String
    var category: String
    var method: PayMethod?
    var note: String
}

struct CSVImportResult {
    var rows: [ImportedRow] = []
    var skippedIncome = 0
    var skippedBad = 0
    var headers: [String] = []
    var error: String?
}

enum CSVImporter {

    // MARK: CSV text → cells

    static func detectDelimiter(_ firstLine: String) -> Character {
        let counts: [(Character, Int)] = [",", ";", "\t", "|"].map { d in (d, firstLine.filter { $0 == d }.count) }
        return counts.max(by: { $0.1 < $1.1 }).map { $0.1 > 0 ? $0.0 : "," } ?? ","
    }

    static func parse(_ raw: String) -> [[String]] {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let delim = detectDelimiter(firstLine)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delim {
                row.append(field); field = ""
            } else if c.isNewline {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    // MARK: Columns

    static func key(_ h: String) -> String {
        let mapped = h.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    struct Columns {
        var date: Int?
        var time: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
        var payee: Int?
        var category: Int?
        var subcategory: Int?
        var method: Int?
        var note: Int?
        var type: Int?
    }

    static func find(_ keys: [String], _ names: [String], used: Set<Int> = [], contains: Bool = false) -> Int? {
        for n in names {
            if let i = keys.indices.first(where: { !used.contains($0) && keys[$0] == n }) { return i }
        }
        if contains {
            for n in names {
                if let i = keys.indices.first(where: { !used.contains($0) && keys[$0].contains(n) }) { return i }
            }
        }
        return nil
    }

    static func columns(_ header: [String]) -> Columns {
        let k = header.map(key)
        var c = Columns()
        var used = Set<Int>()
        func take(_ names: [String], contains: Bool = false) -> Int? {
            let i = find(k, names, used: used, contains: contains)
            if let i { used.insert(i) }
            return i
        }
        c.date = take(["date", "date time", "datetime", "transaction date", "date and time", "tarikh", "created", "created at", "timestamp", "time stamp", "day"], contains: true)
        c.time = take(["time", "masa"])
        c.amount = take(["amount rm", "amount", "amount myr", "total", "jumlah", "amaun", "value", "price", "cost", "expense", "expenses", "spent", "rm", "myr", "nilai"], contains: true)
        if c.amount == nil {
            c.debit = take(["debit", "withdrawal", "money out", "keluar"], contains: true)
            c.credit = take(["credit", "deposit", "money in", "masuk"], contains: true)
        }
        c.type = take(["type", "transaction type", "jenis", "income expense", "expense income", "kind", "flow"])
        c.category = take(["category", "kategori", "categories", "category name", "main category"], contains: true)
        c.subcategory = take(["subcategory", "sub category", "subkategori"])
        c.payee = take(["payee", "merchant", "merchant name", "title", "name", "item", "store", "shop", "vendor", "place", "recipient", "description", "keterangan", "perkara"], contains: false)
        c.method = take(["paid with", "payment method", "method", "payment", "account", "wallet", "akaun", "source", "payment type"], contains: true)
        c.note = take(["note", "notes", "memo", "remark", "remarks", "description", "comment", "comments", "catatan", "details"], contains: true)
        if c.payee == nil { c.payee = c.note; c.note = nil }
        return c
    }

    // MARK: Values

    static func signedAmount(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let negative = t.contains("-") || (t.hasPrefix("(") && t.hasSuffix(")")) || t.lowercased().hasSuffix("dr")
        guard let v = parseAmountText(t) else { return t.filter({ $0.isNumber }).allSatisfy({ $0 == "0" }) ? 0 : nil }
        return negative ? -v : v
    }

    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a", "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd",
        "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy h:mm:ss a", "dd/MM/yyyy h:mm a", "dd/MM/yyyy, h:mm a", "dd/MM/yyyy",
        "d/M/yyyy HH:mm", "d/M/yyyy h:mm a", "d/M/yyyy", "dd/MM/yy", "d/M/yy",
        "dd-MM-yyyy HH:mm:ss", "dd-MM-yyyy HH:mm", "dd-MM-yyyy", "dd.MM.yyyy HH:mm", "dd.MM.yyyy",
        "d MMM yyyy, h:mm a", "d MMM yyyy h:mm a", "d MMM yyyy HH:mm", "d MMM yyyy, HH:mm", "d MMM yyyy", "dd MMM yyyy", "d-MMM-yyyy", "dd-MMM-yy",
        "MMM d, yyyy h:mm a", "MMM d, yyyy, h:mm a", "MMM d, yyyy HH:mm", "MMM d, yyyy", "MMMM d, yyyy", "d MMMM yyyy",
        "EEE, d MMM yyyy", "EEEE, d MMMM yyyy"
    ]

    static func parseDate(_ s: String, calendar: Calendar) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: t) { return d }
        // Excel serial day number (e.g. 46337)
        if let n = Double(t), n > 30000, n < 80000 {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            if let base = utc.date(from: DateComponents(year: 1899, month: 12, day: 30)) {
                let d = base.addingTimeInterval(n * 86400)
                let comps = utc.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                return calendar.date(from: comps)
            }
        }
        return nil
    }

    static func method(_ s: String) -> PayMethod? {
        let l = s.lowercased()
        if l.isEmpty { return nil }
        if l.contains("apple") { return .applePay }
        if l.contains("fpx") { return .fpx }
        if l.contains("qr") { return .duitnowQR }
        if l.contains("transfer") || l.contains("pindahan") { return .transfer }
        if l.contains("cash") || l.contains("tunai") { return .cash }
        if l.contains("card") || l.contains("kad") || l.contains("visa") || l.contains("master") || l.contains("debit") || l.contains("credit") { return .card }
        if l == "other" { return .other }
        return nil
    }

    static func isIncomeType(_ s: String) -> Bool {
        let l = s.lowercased()
        let words = ["income", "pendapatan", "credit", "deposit", "masuk", "refund", "transfer in", "money in", "salary", "gaji"]
        let hit = words.contains(where: { l.contains($0) })
        return hit && !l.contains("expense")
    }

    // MARK: Import

    static func importRows(_ text: String, calendar: Calendar = .current) -> CSVImportResult {
        var result = CSVImportResult()
        let table = parse(text)
        guard !table.isEmpty else { result.error = "The file is empty."; return result }

        // Header = first of the top rows that has both a date and an amount column.
        var headerIndex: Int?
        var cols = Columns()
        for (i, r) in table.prefix(15).enumerated() {
            let c = columns(r)
            if c.date != nil && (c.amount != nil || c.debit != nil) { headerIndex = i; cols = c; break }
        }
        guard let h = headerIndex else {
            result.headers = table.first ?? []
            result.error = "Couldn't find Date and Amount columns. Columns in the file: \((table.first ?? []).joined(separator: ", "))"
            return result
        }
        result.headers = table[h]
        let body = Array(table[(h + 1)...])
        func cell(_ r: [String], _ i: Int?) -> String { guard let i, i < r.count else { return "" }; return r[i] }

        // If amounts are a mix of + and − with no Type column, the negative ones are the spending.
        let signs = body.compactMap { signedAmount(cell($0, cols.amount)) }.filter { $0 != 0 }
        let mixedSigns = cols.type == nil && signs.contains(where: { $0 < 0 }) && signs.contains(where: { $0 > 0 })

        for r in body {
            var dateText = cell(r, cols.date)
            let timeText = cell(r, cols.time)
            if !timeText.isEmpty && !dateText.contains(":") { dateText += " " + timeText }
            guard let date = parseDate(dateText, calendar: calendar) ?? parseDate(cell(r, cols.date), calendar: calendar) else {
                result.skippedBad += 1; continue
            }
            var amount: Double?
            if cols.amount != nil {
                amount = signedAmount(cell(r, cols.amount))
            } else {
                let d = signedAmount(cell(r, cols.debit)) ?? 0
                let c = signedAmount(cell(r, cols.credit)) ?? 0
                if abs(d) > 0 { amount = -abs(d) } else if abs(c) > 0 { result.skippedIncome += 1; continue }
            }
            guard var value = amount, value != 0 else { result.skippedBad += 1; continue }
            if !cell(r, cols.type).isEmpty {
                if isIncomeType(cell(r, cols.type)) { result.skippedIncome += 1; continue }
            } else if mixedSigns && value > 0 {
                result.skippedIncome += 1; continue
            }
            value = abs(value)
            var category = cell(r, cols.category)
            if category.isEmpty { category = cell(r, cols.subcategory) }
            var payee = cell(r, cols.payee)
            var note = cell(r, cols.note)
            if payee.isEmpty && !note.isEmpty { payee = note; note = "" }
            result.rows.append(ImportedRow(date: date, amount: (value * 100).rounded() / 100, payee: payee,
                                           category: category, method: method(cell(r, cols.method)), note: note))
        }
        if result.rows.isEmpty && result.error == nil {
            result.error = "No spending rows could be read. Columns in the file: \(result.headers.joined(separator: ", "))"
        }
        return result
    }
}
