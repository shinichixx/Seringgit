import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query(sort: \Txn.date, order: .reverse) private var txns: [Txn]
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    @State private var month = Date()
    @State private var drill: String?

    struct Slice: Identifiable {
        let name: String
        let amount: Double
        let color: Color
        let icon: String
        let count: Int
        var id: String { name }
    }

    struct MonthBar: Identifiable {
        let month: Date
        let amount: Double
        var id: Date { month }
    }

    private var monthTxns: [Txn] { txns.filter { $0.date.sameMonth(month) } }

    private var slices: [Slice] {
        let groups = Dictionary(grouping: monthTxns, by: { $0.category })
        return groups.map { name, items in
            let c = categories.first(where: { $0.name == name })
            return Slice(name: name, amount: items.reduce(0) { $0 + $1.amount }, color: c?.color ?? .gray,
                         icon: c?.icon ?? "tag.fill", count: items.count)
        }
        .sorted { $0.amount > $1.amount }
    }

    private var bars: [MonthBar] {
        let start = month.startOfMonth
        return (0..<6).reversed().compactMap { back -> MonthBar? in
            guard let m = Calendar.current.date(byAdding: .month, value: -back, to: start) else { return nil }
            let total = txns.filter { $0.date.sameMonth(m) }.reduce(0) { $0 + $1.amount }
            return MonthBar(month: m, amount: total)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: "Reports", color: Theme.rouge) {
                MonthStepper(month: $month)
            }
            ScrollView {
                VStack(spacing: 12) {
                    categoryCard
                    methodCard
                    trendCard
                    topPayeesCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
        }
        .background(Theme.background)
        .sheet(item: Binding(get: { drill.map { DrillKey(name: $0) } }, set: { drill = $0?.name })) { key in
            CategoryDetail(category: key.name, month: month)
        }
    }

    struct MethodRow: Identifiable {
        let method: PayMethod
        let amount: Double
        var id: String { method.rawValue }
    }

    struct DrillKey: Identifiable { let name: String; var id: String { name } }

    // MARK: Cards

    private var categoryCard: some View {
        let total = slices.reduce(0) { $0 + $1.amount }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("By category").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.rouge)
                if slices.isEmpty {
                    Text("No spending in \(Fmt.month.string(from: month)).").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ZStack {
                        Chart(slices) { s in
                            SectorMark(angle: .value("RM", s.amount), innerRadius: .ratio(0.62), angularInset: 1.2)
                                .foregroundStyle(s.color)
                                .cornerRadius(3)
                        }
                        .frame(height: 190)
                        VStack(spacing: 2) {
                            Text("Total").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(rm(total)).font(.system(size: 17, weight: .bold))
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(slices) { s in
                            Button { drill = s.name } label: {
                                HStack(spacing: 10) {
                                    CategoryIcon(icon: s.icon, color: s.color, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.name).font(.system(size: 13, weight: .medium))
                                        Text("\(s.count) payment\(s.count == 1 ? "" : "s")").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(rm(s.amount)).font(.system(size: 13, weight: .semibold))
                                        Text(num(total > 0 ? s.amount / total * 100 : 0, 1) + "%").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var methodCard: some View {
        let groups = Dictionary(grouping: monthTxns, by: { $0.method }).mapValues { $0.reduce(0) { $0 + $1.amount } }
        let rows: [MethodRow] = PayMethod.allCases.compactMap { m in
            guard let v = groups[m] else { return nil }
            return MethodRow(method: m, amount: v)
        }
        let maxV = max(rows.map { $0.amount }.max() ?? 1, 0.01)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("By payment method").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.rouge)
                if rows.isEmpty {
                    Text("—").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    let m = row.method
                    let v = row.amount
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(m.title, systemImage: m.symbol).font(.system(size: 12))
                            Spacer()
                            Text(rm(v)).font(.system(size: 12, weight: .semibold))
                        }
                        GeometryReader { g in
                            Capsule().fill(Theme.teal.opacity(0.85)).frame(width: max(4, g.size.width * v / maxV), height: 6)
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private var trendCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 6 months").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.rouge)
                Chart(bars) { b in
                    BarMark(x: .value("Month", Fmt.shortMonth.string(from: b.month)), y: .value("RM", b.amount))
                        .foregroundStyle(b.month.sameMonth(month) ? Theme.rouge : Theme.teal.opacity(0.7))
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            if b.amount > 0 { Text(rm0(b.amount)).font(.system(size: 8)).foregroundStyle(.secondary) }
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 160)
                let nonZero = bars.filter { $0.amount > 0 }
                if !nonZero.isEmpty {
                    Text("Average \(rm(nonZero.reduce(0) { $0 + $1.amount } / Double(nonZero.count))) a month")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var topPayeesCard: some View {
        let groups = Dictionary(grouping: monthTxns.filter { !$0.merchant.isEmpty }, by: { Categorizer.normalize($0.merchant) })
        let top = groups.values.map { items in (name: items[0].merchant, total: items.reduce(0) { $0 + $1.amount }, count: items.count) }
            .sorted { $0.total > $1.total }.prefix(8)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top payees").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.rouge)
                if top.isEmpty { Text("—").foregroundStyle(.secondary) }
                ForEach(Array(top.enumerated()), id: \.offset) { i, p in
                    HStack {
                        Text("\(i + 1).").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                        Text(p.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text("×\(p.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(rm(p.total)).font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
    }
}

struct CategoryDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Txn.date, order: .reverse) private var txns: [Txn]
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    let category: String
    let month: Date
    @State private var editing: Txn?

    var body: some View {
        let items = txns.filter { $0.category == category && $0.date.sameMonth(month) }
        let cat = categories.first(where: { $0.name == category })
        NavigationStack {
            List {
                Section {
                    LabeledContent("Total", value: rm(items.reduce(0) { $0 + $1.amount }))
                }
                Section {
                    ForEach(items) { t in
                        TxnRow(txn: t, category: cat)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = t }
                    }
                }
            }
            .navigationTitle("\(category) · \(Fmt.month.string(from: month))")
            .navigationBarTitleDisplayMode(.inline)
            .tealNav(Theme.rouge)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(.white) }
            }
            .sheet(item: $editing) { t in TxnForm(txn: t) }
        }
    }
}
