import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Txn.date, order: .reverse) private var txns: [Txn]
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    @AppStorage(Keys.overallBudget) private var overallBudget = 0.0
    @State private var month = Date()
    @State private var editingCategory: SpendCategory?
    @State private var editingOverall = false
    @State private var budgetText = ""

    private var monthTxns: [Txn] { txns.filter { $0.date.sameMonth(month) } }
    private func spent(_ name: String) -> Double { monthTxns.filter { $0.category == name }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(title: "Budgets", color: Theme.reminder) {
                MonthStepper(month: $month)
            }
            ScrollView {
                VStack(spacing: 12) {
                    overallCard
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(categories.enumerated()), id: \.element.id) { i, c in
                                if i > 0 { Divider().padding(.leading, 44) }
                                categoryRow(c)
                            }
                        }
                    }
                    Text("Tap a category to set its monthly budget. Leave it at 0 for no budget.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }
        }
        .background(Theme.background)
        .alert(editingOverall ? "Monthly budget" : "Budget for \(editingCategory?.name ?? "")",
               isPresented: Binding(get: { editingOverall || editingCategory != nil },
                                    set: { if !$0 { editingOverall = false; editingCategory = nil } })) {
            TextField("RM", text: $budgetText).keyboardType(.decimalPad)
            Button("Save") {
                let v = parseAmountText(budgetText) ?? 0
                if editingOverall { overallBudget = v } else { editingCategory?.monthlyBudget = v; try? ctx.save() }
                editingOverall = false
                editingCategory = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(editingOverall ? "Total for all spending in a month. Leave empty to use the sum of the category budgets." : "Enter 0 for no budget.")
        }
    }

    private var overallCard: some View {
        let total = monthTxns.reduce(0) { $0 + $1.amount }
        let budget = overallBudget > 0 ? overallBudget : categories.reduce(0) { $0 + $1.monthlyBudget }
        let cal = Calendar.current
        let daysIn = Double(cal.range(of: .day, in: .month, for: month)?.count ?? 30)
        let isCurrent = month.sameMonth(Date())
        let dayNow = isCurrent ? Double(cal.component(.day, from: Date())) : daysIn
        let projected = dayNow > 0 ? total / dayNow * daysIn : total
        return Button {
            budgetText = overallBudget > 0 ? String(format: "%.0f", overallBudget) : ""
            editingOverall = true
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("This month").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.reminder)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(rm(total)).font(.system(size: 26, weight: .bold))
                        if budget > 0 { Text("of \(rm0(budget))").font(.system(size: 13)).foregroundStyle(.secondary) }
                    }
                    if budget > 0 {
                        ProgressView(value: min(total / budget, 1)).tint(total > budget ? Theme.rouge : Theme.reminder)
                        HStack {
                            Text(total > budget ? "Over by \(rm(total - budget))" : "\(rm(budget - total)) left")
                                .foregroundStyle(total > budget ? Theme.rouge : .secondary)
                            Spacer()
                            if isCurrent && budget > total {
                                let daysLeft = max(daysIn - dayNow + 1, 1)
                                Text("\(rm((budget - total) / daysLeft)) a day").foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 11))
                    } else {
                        Text("Tap to set a monthly budget").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if isCurrent && total > 0 {
                        Text("At this pace: \(rm0(projected)) by month end").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Color.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryRow(_ c: SpendCategory) -> some View {
        let s = spent(c.name)
        return Button {
            budgetText = c.monthlyBudget > 0 ? String(format: "%.0f", c.monthlyBudget) : ""
            editingCategory = c
        } label: {
            HStack(spacing: 10) {
                CategoryIcon(icon: c.icon, color: c.color, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(c.monthlyBudget > 0 ? "\(rm(s)) / \(rm0(c.monthlyBudget))" : rm(s))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.monthlyBudget > 0 && s > c.monthlyBudget ? Theme.rouge : Color.primary)
                    }
                    if c.monthlyBudget > 0 {
                        ProgressView(value: min(s / c.monthlyBudget, 1)).tint(s > c.monthlyBudget ? Theme.rouge : c.color)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
