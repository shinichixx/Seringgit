import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Txn.date, order: .reverse) private var txns: [Txn]
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    @AppStorage(Keys.overallBudget) private var overallBudget = 0.0
    @State private var month = Date()
    @State private var editing: Txn?
    @State private var searching = false
    @State private var query = ""
    @State private var methodFilter: PayMethod?
    @State private var categoryFilter: String?
    @FocusState private var searchFocused: Bool

    private var monthTxns: [Txn] { txns.filter { $0.date.sameMonth(month) } }
    private var reviewTxns: [Txn] { txns.filter { $0.needsReview || $0.possibleDuplicate } }

    private var shown: [Txn] {
        let base = searching && !query.isEmpty ? txns : monthTxns
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return base.filter { t in
            (methodFilter == nil || t.method == methodFilter)
            && (categoryFilter == nil || t.category == categoryFilter)
            && (q.isEmpty || t.merchant.lowercased().contains(q) || t.note.lowercased().contains(q)
                || t.category.lowercased().contains(q) || t.reference.lowercased().contains(q) || num(t.amount, 2).contains(q))
        }
    }

    struct DayGroup: Identifiable {
        let day: Date
        let items: [Txn]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let groups = Dictionary(grouping: shown, by: { Calendar.current.startOfDay(for: $0.date) })
        return groups.keys.sorted(by: >).map { d in DayGroup(day: d, items: (groups[d] ?? []).sorted(by: { $0.date > $1.date })) }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: "Seringgit") {
                MonthStepper(month: $month)
                HeaderButton(systemName: searching ? "xmark" : "magnifyingglass") {
                    withAnimation {
                        searching.toggle()
                        if !searching { query = ""; methodFilter = nil; categoryFilter = nil }
                        searchFocused = searching
                    }
                }
            }
            ScrollView {
                VStack(spacing: 12) {
                    if searching { searchBar }
                    else {
                        summary
                        if !reviewTxns.isEmpty { reviewBanner }
                    }
                    if days.isEmpty {
                        emptyState
                    }
                    ForEach(days) { group in
                        daySection(group.day, group.items)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background)
        .sheet(item: $editing) { t in TxnForm(txn: t) }
    }

    // MARK: Summary

    private var summary: some View {
        let total = monthTxns.reduce(0) { $0 + $1.amount }
        let prevMonth = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
        let cal = Calendar.current
        let isCurrent = month.sameMonth(Date())
        // Compare with the same days of last month when looking at the current month.
        let dayCut = isCurrent ? cal.component(.day, from: Date()) : 31
        let prevTotal = txns.filter { $0.date.sameMonth(prevMonth) && cal.component(.day, from: $0.date) <= dayCut }.reduce(0) { $0 + $1.amount }
        let budget = overallBudget > 0 ? overallBudget : categories.reduce(0) { $0 + $1.monthlyBudget }
        let byMethod = Dictionary(grouping: monthTxns, by: { $0.method }).mapValues { $0.reduce(0) { $0 + $1.amount } }

        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spent in \(Fmt.month.string(from: month))").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(rm(total)).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.teal)
                HStack(spacing: 6) {
                    if prevTotal > 0 {
                        let diff = total - prevTotal
                        Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(diff > 0 ? Theme.rouge : Theme.green)
                        Text("\(rm(abs(diff))) \(diff > 0 ? "more" : "less") than \(Fmt.shortMonth.string(from: prevMonth))\(isCurrent ? " (same days)" : "")")
                    } else {
                        Text("\(monthTxns.count) payment\(monthTxns.count == 1 ? "" : "s")")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                if budget > 0 {
                    let frac = min(total / budget, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: frac).tint(total > budget ? Theme.rouge : Theme.teal)
                        Text(total > budget ? "\(rm(total - budget)) over the \(rm0(budget)) budget" : "\(rm(budget - total)) left of \(rm0(budget))")
                            .font(.system(size: 11)).foregroundStyle(total > budget ? Theme.rouge : .secondary)
                    }
                }
                if !byMethod.isEmpty {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(PayMethod.allCases.filter { byMethod[$0] != nil }) { m in
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(m.title, systemImage: m.symbol).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Text(rm(byMethod[m] ?? 0)).font(.system(size: 12, weight: .semibold))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var reviewBanner: some View {
        Button { editing = reviewTxns.first } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reviewTxns.count) payment\(reviewTxns.count == 1 ? "" : "s") to check").font(.system(size: 13, weight: .semibold))
                    Text("Couldn't read everything, or may be recorded twice").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Theme.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Payee, note, amount, reference", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PayMethod.allCases) { m in
                        chip(m.title, selected: methodFilter == m) { methodFilter = methodFilter == m ? nil : m }
                    }
                    Divider().frame(height: 20)
                    ForEach(categories) { c in
                        chip(c.name, selected: categoryFilter == c.name, color: c.color) { categoryFilter = categoryFilter == c.name ? nil : c.name }
                    }
                }
            }
            if !shown.isEmpty {
                Text("\(shown.count) payments · \(rm(shown.reduce(0) { $0 + $1.amount }))\(query.isEmpty ? " in \(Fmt.month.string(from: month))" : "")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, color: Color = Theme.teal, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? color : Color.white)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(searching ? "Nothing matches." : "No spending recorded in \(Fmt.month.string(from: month)) yet.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if !searching {
                Text("Pay with Apple Pay, or double-tap the back of your iPhone on MAE's \"Successful\" screen. Set-up steps are in More → Set up auto-capture.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
    }

    // MARK: Day list

    private func daySection(_ day: Date, _ items: [Txn]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Calendar.current.isDateInToday(day) ? "Today" : Calendar.current.isDateInYesterday(day) ? "Yesterday" : Fmt.dayHeader.string(from: day))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(rm(items.reduce(0) { $0 + $1.amount })).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                        if i > 0 { Divider().padding(.leading, 46) }
                        TxnRow(txn: t, category: categories.first(where: { $0.name == t.category }))
                            .contentShape(Rectangle())
                            .onTapGesture { editing = t }
                    }
                }
            }
        }
    }
}

struct TxnRow: View {
    let txn: Txn
    let category: SpendCategory?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(icon: category?.icon ?? "tag.fill", color: category?.color ?? .gray)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(txn.displayName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if txn.needsReview || txn.possibleDuplicate {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.orange)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: txn.method.symbol).font(.system(size: 9))
                    Text("\(txn.category) · \(Fmt.time.string(from: txn.date))").lineLimit(1)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Text(rm(txn.amount)).font(.system(size: 14, weight: .semibold))
        }
        .padding(.vertical, 8)
    }
}
