import Foundation

// Compile-and-run check of the receipt reader and auto-categories (runs on the build machine before the app is built).
var failures = 0
func check(_ name: String, _ cond: Bool) {
    print((cond ? "PASS " : "FAIL ") + name)
    if !cond { failures += 1 }
}
func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 19, minute: 30))!

func L(_ t: String, _ x: Double, _ y: Double, _ h: Double = 0.015, _ w: Double = 0.3) -> OCRLine { OCRLine(text: t, x: x, y: y, w: w, h: h) }

// 1. MAE DuitNow QR style: big amount split into "RM" + number, label/value columns, balance shown lower down.
let qr = ReceiptParser.parse([
    L("9:41", 0.05, 0.01),
    L("Payment successful", 0.25, 0.18, 0.022, 0.5),
    L("RM", 0.30, 0.255, 0.02, 0.08),
    L("25.90", 0.40, 0.245, 0.04, 0.2),
    L("Paid to", 0.05, 0.40),
    L("MYDIN MALL KUANTAN", 0.50, 0.40),
    L("Reference ID", 0.05, 0.45),
    L("20261111MBBEMYKL0001234", 0.50, 0.45),
    L("Date & time", 0.05, 0.50),
    L("11 Nov 2026, 7:15 PM", 0.50, 0.50),
    L("Available balance RM 1,234.56", 0.05, 0.60),
    L("DuitNow QR", 0.05, 0.70)
], now: now, calendar: cal)
check("QR amount 25.90 (not the balance)", near(qr.amount, 25.90))
check("QR payee", qr.merchant == "MYDIN MALL KUANTAN")
check("QR reference", qr.reference == "20261111MBBEMYKL0001234")
check("QR method", qr.method == .duitnowQR)
check("QR date 11 Nov 19:15", qr.date == cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 19, minute: 15)))
check("QR not failed", !qr.failed && qr.confident)

// 2. FPX page: labels above values, amount without big font, slash date with seconds.
let fpx = ReceiptParser.parse([
    L("Transaction Successful", 0.2, 0.10, 0.02),
    L("Amount", 0.05, 0.20),
    L("RM 150.00", 0.05, 0.225),
    L("Merchant Name", 0.05, 0.27),
    L("SHOPEE MOBILE MALAYSIA SDN BHD", 0.05, 0.295),
    L("FPX Transaction ID", 0.05, 0.34),
    L("2611111920050123", 0.05, 0.365),
    L("Transaction Date", 0.05, 0.41),
    L("11/11/2026 19:20:05", 0.05, 0.435),
    L("Service fee RM 0.00", 0.05, 0.48)
], now: now, calendar: cal)
check("FPX amount", near(fpx.amount, 150))
check("FPX merchant", fpx.merchant == "SHOPEE MOBILE MALAYSIA SDN BHD")
check("FPX reference", fpx.reference == "2611111920050123")
check("FPX method", fpx.method == .fpx)
check("FPX date", fpx.date == cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 19, minute: 20, second: 5)))

// 3. Transfer with "Paid to: NAME" inline, thousands separator.
let tr = ReceiptParser.parse([
    L("Transfer Successful", 0.2, 0.1, 0.02),
    L("RM 1,200.00", 0.3, 0.2, 0.04),
    L("Paid to: AHMAD BIN ALI", 0.05, 0.35),
    L("DuitNow Transfer", 0.05, 0.40)
], now: now, calendar: cal)
check("Transfer amount 1,200", near(tr.amount, 1200))
check("Transfer payee inline", tr.merchant == "AHMAD BIN ALI")
check("Transfer method", tr.method == .transfer)
check("No date -> nil", tr.date == nil)

// 4. Failed payment is detected.
let bad = ReceiptParser.parse([L("Payment Unsuccessful", 0.2, 0.1, 0.02), L("RM 10.00", 0.3, 0.2, 0.04)], now: now, calendar: cal)
check("Unsuccessful is flagged", bad.failed)

// 5. Merchant heading under the amount (no label).
let head = ReceiptParser.parse([
    L("Successful", 0.3, 0.1, 0.02),
    L("RM 8.50", 0.3, 0.2, 0.045),
    L("ZUS COFFEE KUANTAN", 0.3, 0.26, 0.018),
    L("Reference ID", 0.05, 0.4), L("998877", 0.5, 0.4)
], now: now, calendar: cal)
check("Payee taken from heading under amount", head.merchant == "ZUS COFFEE KUANTAN")

// Amount text from the Apple Pay Shortcut
check("parse RM12.50", near(parseAmountText("RM12.50"), 12.5))
check("parse MYR 1,234.50", near(parseAmountText("MYR 1,234.50"), 1234.5))
check("parse 12,50", near(parseAmountText("12,50"), 12.5))
check("parse 7", near(parseAmountText("7"), 7))
check("parse junk", parseAmountText("abc") == nil)

// Categories
let rules = Categorizer.defaultRules()
func cat(_ m: String) -> String? { Categorizer.category(for: m, rules: rules) }
check("McDonald's -> Food", cat("MCDONALD'S KUANTAN") == "Food & Drinks")
check("Petronas -> Transport", cat("PETRONAS JLN BESERAH") == "Transport")
check("GrabFood -> Food", cat("GRABFOOD") == "Food & Drinks")
check("Grab -> Transport", cat("Grab") == "Transport")
check("ATM does not match TM", cat("ATM WITHDRAWAL") == nil)
check("AEON BIG -> Groceries", cat("AEON BIG KUANTAN") == "Groceries")
check("7-Eleven -> Groceries", cat("7-ELEVEN MALAYSIA") == "Groceries")
check("Shopee -> Shopping", cat(fpx.merchant) == "Shopping")
check("TNB -> Bills", cat("TNB ePay") == "Bills")
var learned = rules
learned.append(CategoryRule(keyword: "MYDIN MALL KUANTAN", category: "Family", exact: true))
check("Learned merchant wins", Categorizer.category(for: "Mydin Mall Kuantan", rules: learned) == "Family")

// CSV import: Seringgit's own export
let own = CSVImporter.importRows("Date,Amount (RM),Payee,Category,Paid with,Note,Reference,Recorded by\n2026-11-11 19:15,25.90,\"MYDIN, KUANTAN\",Groceries,DuitNow QR,\"\",123,Auto · Screenshot\n", calendar: cal)
check("CSV own: 1 row", own.rows.count == 1 && own.error == nil)
check("CSV own: quoted comma payee", own.rows.first?.payee == "MYDIN, KUANTAN")
check("CSV own: amount + method + category", near(own.rows.first?.amount, 25.90) && own.rows.first?.method == .duitnowQR && own.rows.first?.category == "Groceries")
check("CSV own: date", own.rows.first?.date == cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 19, minute: 15)))

// Belanje-style: Type column, income row, dd/MM/yyyy, CRLF line ends, BOM
let bel = CSVImporter.importRows("\u{FEFF}Date,Time,Type,Category,Amount,Note\r\n10/11/2026,08:30,Expense,Food,RM 8.50,Nasi lemak\r\n10/11/2026,09:00,Income,Salary,5000.00,Gaji\r\n11/11/2026,12:00,Expense,Petrol,-60.00,Petronas\r\n", calendar: cal)
check("CSV Belanje: 2 expenses, 1 income skipped", bel.rows.count == 2 && bel.skippedIncome == 1)
check("CSV Belanje: date+time joined", bel.rows.first?.date == cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 8, minute: 30)))
check("CSV Belanje: note used as payee", bel.rows.first?.payee == "Nasi lemak" && bel.rows.first?.category == "Food")
check("CSV Belanje: negative amount made positive", near(bel.rows.last?.amount, 60))

// Semicolon file, signed amounts with no type column (positives = income)
let semi = CSVImporter.importRows("Tarikh;Keterangan;Jumlah\n11 Nov 2026;ZUS Coffee;-12.90\n11 Nov 2026;Refund;5.00\n", calendar: cal)
check("CSV semicolon: 1 expense, 1 income", semi.rows.count == 1 && semi.skippedIncome == 1 && semi.rows.first?.payee == "ZUS Coffee")

let junk = CSVImporter.importRows("hello,world\n1,2\n", calendar: cal)
check("CSV without date/amount gives a clear error", junk.error != nil && junk.rows.isEmpty)

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
