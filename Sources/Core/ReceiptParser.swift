import Foundation

/// How a payment was made.
enum PayMethod: String, CaseIterable, Codable, Identifiable {
    case applePay, duitnowQR, fpx, transfer, card, cash, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .applePay: return "Apple Pay"
        case .duitnowQR: return "DuitNow QR"
        case .fpx: return "FPX"
        case .transfer: return "Transfer"
        case .card: return "Card"
        case .cash: return "Cash"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .applePay: return "applelogo"
        case .duitnowQR: return "qrcode"
        case .fpx: return "building.columns.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .card: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .other: return "ellipsis"
        }
    }
}

/// One piece of text found on a screenshot. Coordinates are 0...1, origin top-left (y grows downwards).
struct OCRLine {
    var text: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var midY: Double { y + h / 2 }
}

struct ParsedReceipt {
    var amount: Double?
    var merchant: String = ""
    var reference: String = ""
    var date: Date?
    var method: PayMethod = .other
    var failed = false
    var text = ""
    /// Amount and payee both found: safe to save without asking.
    var confident: Bool { amount != nil && !merchant.isEmpty }
}

/// Reads the "Successful" screen of MAE / Maybank2u / FPX pages from OCR text.
enum ReceiptParser {

    struct Row {
        var lines: [OCRLine]
        var midY: Double
        var height: Double { lines.map { $0.h }.max() ?? 0 }
        var text: String { lines.sorted { $0.x < $1.x }.map { $0.text }.joined(separator: " ") }
    }

    static let payeeLabels = [
        "recipient name", "recipient", "paid to", "pay to", "payee name", "payee", "merchant name", "merchant",
        "beneficiary name", "beneficiary", "seller name", "seller", "biller name", "biller", "bill name", "to",
        "nama penerima", "penerima", "dibayar kepada", "nama peniaga", "peniaga"
    ]
    static let referenceLabels = [
        "reference id", "reference no", "reference no.", "reference number", "ref id", "ref no", "ref no.", "ref. no.",
        "transaction id", "transaction reference", "transaction ref", "fpx transaction id", "fpx txn id",
        "seller order no", "seller order no.", "order no", "order id", "no. rujukan", "no rujukan", "rujukan", "id transaksi"
    ]
    static let amountLabels = ["amount", "total amount", "total", "jumlah", "amaun", "payment amount", "transaction amount"]
    static let dateLabels = ["date & time", "date and time", "date/time", "transaction date", "date", "tarikh", "tarikh & masa", "time"]
    static let ignoreAmountWords = ["balance", "baki", "available", "limit", "fee", "fees", "charge", "caj", "points", "cashback", "rebate"]
    static let failWords = ["unsuccessful", "not successful", "failed", "declined", "rejected", "tidak berjaya", "gagal", "cancelled", "dibatalkan"]

    // MARK: Entry point

    static func parse(_ raw: [OCRLine], now: Date = Date(), calendar: Calendar = .current) -> ParsedReceipt {
        let lines = raw.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let rows = makeRows(lines)
        var r = ParsedReceipt()
        r.text = rows.map { $0.text }.joined(separator: "\n")
        let lower = r.text.lowercased()

        r.failed = failWords.contains(where: { lower.contains($0) })
        r.method = method(in: lower)
        r.amount = amount(rows)
        r.merchant = clean(labelledValue(rows, labels: payeeLabels) ?? fallbackPayee(rows) ?? "")
        r.reference = clean(labelledValue(rows, labels: referenceLabels) ?? "")
        r.date = date(rows, now: now, calendar: calendar)
        return r
    }

    // MARK: Rows

    static func makeRows(_ lines: [OCRLine]) -> [Row] {
        var rows: [Row] = []
        for l in lines.sorted(by: { $0.midY < $1.midY }) {
            if let i = rows.lastIndex(where: { abs($0.midY - l.midY) < max($0.height, l.h) * 0.55 }) {
                rows[i].lines.append(l)
                let n = Double(rows[i].lines.count)
                rows[i].midY = rows[i].midY * (n - 1) / n + l.midY / n
            } else {
                rows.append(Row(lines: [l], midY: l.midY))
            }
        }
        return rows.sorted { $0.midY < $1.midY }
    }

    static func norm(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ":-–".contains(last) { t.removeLast(); t = t.trimmingCharacters(in: .whitespaces) }
        return t
    }

    static func isLabel(_ s: String) -> Bool {
        let n = norm(s)
        return (payeeLabels + referenceLabels + amountLabels + dateLabels).contains(n)
            || ["status", "from", "from account", "recipient reference", "payment details", "transfer type", "account", "account number", "bank", "recipient bank", "payment type", "note", "notes", "description"].contains(n)
    }

    // MARK: Method

    static func method(in lower: String) -> PayMethod {
        if lower.contains("fpx") { return .fpx }
        if lower.contains("duitnow qr") || lower.contains("qr pay") || lower.contains("scan & pay") || lower.contains("scan and pay") || lower.contains("qrpay") { return .duitnowQR }
        if lower.contains("transfer") || lower.contains("pindahan") || lower.contains("ibg") { return .transfer }
        if lower.contains("qr") { return .duitnowQR }
        return .other
    }

    // MARK: Amount

    private static let moneyWithRM = try! NSRegularExpression(
        pattern: "(?:RM|MYR)\\s*([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)", options: [.caseInsensitive])
    private static let bareMoney = try! NSRegularExpression(
        pattern: "(?<![0-9.,])([0-9]{1,3}(?:,[0-9]{3})+\\.[0-9]{2}|[0-9]+\\.[0-9]{2})(?![0-9])", options: [])

    static func amount(_ rows: [Row]) -> Double? {
        var best: (value: Double, score: Double)?
        for (i, row) in rows.enumerated() {
            let text = row.text
            let lower = text.lowercased()
            if ignoreAmountWords.contains(where: { lower.contains($0) }) { continue }
            let sameRowLabel = amountLabels.contains(where: { lower.hasPrefix($0) })
            let rowAboveLabel = i > 0 && amountLabels.contains(norm(rows[i - 1].text))
            let labelled = sameRowLabel || rowAboveLabel
            var values = matches(moneyWithRM, in: text)
            if values.isEmpty && labelled { values = matches(bareMoney, in: text) }
            for v in values where v > 0 {
                let score = row.height + (labelled ? 0.02 : 0)
                if best == nil || score > best!.score + 1e-9 { best = (v, score) }
            }
        }
        return best?.value
    }

    private static func matches(_ re: NSRegularExpression, in text: String) -> [Double] {
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let s = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            return Double(s)
        }
    }

    // MARK: Labelled values

    static func labelledValue(_ rows: [Row], labels: [String]) -> String? {
        for label in labels {
            for (i, row) in rows.enumerated() {
                let sorted = row.lines.sorted { $0.x < $1.x }
                for (j, l) in sorted.enumerated() {
                    let n = norm(l.text)
                    // "Paid to: MYDIN" on one line
                    if n.hasPrefix(label + ":") || n.hasPrefix(label + " :") {
                        let rest = l.text.split(separator: ":", maxSplits: 1).dropFirst().joined().trimmingCharacters(in: .whitespaces)
                        if !rest.isEmpty { return rest }
                    }
                    guard n == label else { continue }
                    // value to the right on the same row
                    let right = sorted[(j + 1)...].map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if !right.isEmpty { return right }
                    // value on the next row
                    if i + 1 < rows.count {
                        let next = rows[i + 1].text
                        if !isLabel(next) { return next }
                    }
                }
            }
        }
        return nil
    }

    /// QR receipts often show the merchant name as a heading just under the big amount.
    static func fallbackPayee(_ rows: [Row]) -> String? {
        guard let a = amount(rows),
              let idx = rows.firstIndex(where: { r in matches(moneyWithRM, in: r.text).contains(where: { abs($0 - a) < 0.001 }) })
        else { return nil }
        for r in rows[(idx + 1)...].prefix(2) {
            let t = r.text
            let lower = t.lowercased()
            let letters = t.filter { $0.isLetter }.count
            if letters >= 3, !isLabel(t), !lower.contains("successful"), !lower.contains("berjaya"),
               matches(moneyWithRM, in: t).isEmpty, dateIn(t, calendar: .current) == nil {
                return t
            }
        }
        return nil
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":-")))
    }

    // MARK: Date

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "mei": 5, "jun": 6, "jul": 7, "aug": 8, "ogo": 8,
                                 "sep": 9, "oct": 10, "okt": 10, "nov": 11, "dec": 12, "dis": 12]
    private static let dmyText = try! NSRegularExpression(pattern: "(\\d{1,2})\\s*([A-Za-z]{3})[A-Za-z]*\\.?\\s*,?\\s*(\\d{4})", options: [])
    private static let dmySlash = try! NSRegularExpression(pattern: "(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4})", options: [])
    private static let ymd = try! NSRegularExpression(pattern: "(\\d{4})-(\\d{2})-(\\d{2})", options: [])
    private static let time = try! NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*([AaPp][Mm])?", options: [])

    static func dateIn(_ text: String, calendar: Calendar) -> DateComponents? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var c = DateComponents()
        var end = 0
        if let m = ymd.firstMatch(in: text, range: full) {
            c.year = Int(ns.substring(with: m.range(at: 1))); c.month = Int(ns.substring(with: m.range(at: 2))); c.day = Int(ns.substring(with: m.range(at: 3)))
            end = m.range.location + m.range.length
        } else if let m = dmySlash.firstMatch(in: text, range: full) {
            c.day = Int(ns.substring(with: m.range(at: 1))); c.month = Int(ns.substring(with: m.range(at: 2))); c.year = Int(ns.substring(with: m.range(at: 3)))
            end = m.range.location + m.range.length
        } else if let m = dmyText.firstMatch(in: text, range: full),
                  let mon = months[ns.substring(with: m.range(at: 2)).lowercased()] {
            c.day = Int(ns.substring(with: m.range(at: 1))); c.month = mon; c.year = Int(ns.substring(with: m.range(at: 3)))
            end = m.range.location + m.range.length
        } else {
            return nil
        }
        guard let mo = c.month, (1...12).contains(mo), let d = c.day, (1...31).contains(d) else { return nil }
        let restRange = NSRange(location: end, length: ns.length - end)
        if let t = time.firstMatch(in: text, range: restRange) ?? time.firstMatch(in: text, range: full) {
            applyTime(t, ns, &c)
        }
        return c
    }

    private static func applyTime(_ t: NSTextCheckingResult, _ ns: NSString, _ c: inout DateComponents) {
        var h = Int(ns.substring(with: t.range(at: 1))) ?? 0
        let mi = Int(ns.substring(with: t.range(at: 2))) ?? 0
        if t.range(at: 4).location != NSNotFound {
            let ap = ns.substring(with: t.range(at: 4)).lowercased()
            if ap == "pm" && h < 12 { h += 12 }
            if ap == "am" && h == 12 { h = 0 }
        }
        guard h < 24, mi < 60 else { return }
        c.hour = h; c.minute = mi
        if t.range(at: 3).location != NSNotFound { c.second = Int(ns.substring(with: t.range(at: 3))) }
    }

    static func date(_ rows: [Row], now: Date, calendar: Calendar) -> Date? {
        for (i, row) in rows.enumerated() {
            guard var c = dateIn(row.text, calendar: calendar) else { continue }
            if c.hour == nil, i + 1 < rows.count {
                let ns = rows[i + 1].text as NSString
                if let t = time.firstMatch(in: rows[i + 1].text, range: NSRange(location: 0, length: ns.length)) { applyTime(t, ns, &c) }
            }
            if c.hour == nil {
                // Date only: keep today's time if it's today, otherwise noon.
                if let d = calendar.date(from: c), calendar.isDate(d, inSameDayAs: now) { return now }
                c.hour = 12
            }
            guard let d = calendar.date(from: c) else { continue }
            // Ignore anything far in the past or in the future (e.g. card expiry dates).
            if d > now.addingTimeInterval(86400) || d < now.addingTimeInterval(-400 * 86400) { continue }
            return d
        }
        return nil
    }
}

/// "RM12.50", "MYR 1,234.50", "12.5" → 12.5 (used for the Apple Pay Shortcut input).
func parseAmountText(_ s: String) -> Double? {
    let allowed = Set("0123456789.,")
    var t = String(s.filter { allowed.contains($0) })
    // "12,50" with no dot → decimal comma
    if !t.contains("."), let r = t.range(of: ",", options: .backwards), t.distance(from: r.upperBound, to: t.endIndex) == 2 {
        t.replaceSubrange(r, with: ".")
    }
    t = t.replacingOccurrences(of: ",", with: "")
    guard let v = Double(t), v > 0 else { return nil }
    return (v * 100).rounded() / 100
}
