import SwiftUI
import SwiftData

struct TxnForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]

    let txn: Txn?

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var category = "Others"
    @State private var method: PayMethod = .cash
    @State private var date = Date()
    @State private var note = ""
    @State private var reference = ""
    @State private var pickedCategory = false
    @State private var loaded = false
    @State private var showReceipt = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool

    private var amount: Double? { parseAmountText(amountText) }

    var body: some View {
        NavigationStack {
            Form {
                if let t = txn, t.needsReview || t.possibleDuplicate {
                    Section {
                        if t.possibleDuplicate {
                            Label("Another payment of the same amount was recorded within 10 minutes. Delete this one if it's the same payment.", systemImage: "doc.on.doc")
                                .font(.system(size: 12)).foregroundStyle(Theme.orange)
                        }
                        if t.needsReview {
                            Label("Some details couldn't be read. Check them and tap Save.", systemImage: "exclamationmark.circle")
                                .font(.system(size: 12)).foregroundStyle(Theme.orange)
                        }
                    }
                }

                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("RM").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Theme.teal)
                            .focused($amountFocused)
                    }
                    TextField("Payee / merchant", text: $merchant)
                        .onChange(of: merchant) { _, m in
                            guard !pickedCategory, loaded else { return }
                            category = Store.categoryFor(merchant: m, method: method, ctx: ctx)
                        }
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(categories) { c in
                            Button {
                                category = c.name
                                pickedCategory = true
                            } label: {
                                VStack(spacing: 4) {
                                    CategoryIcon(icon: c.icon, color: category == c.name ? c.color : c.color.opacity(0.35), size: 30)
                                    Text(c.name).font(.system(size: 10, weight: category == c.name ? .bold : .regular))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                        .foregroundStyle(category == c.name ? Color.primary : Color.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(category == c.name ? c.color.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Paid with", selection: $method) {
                        ForEach(PayMethod.allCases) { m in
                            Label(m.title, systemImage: m.symbol).tag(m)
                        }
                    }
                    DatePicker("Date", selection: $date)
                    TextField("Note", text: $note, axis: .vertical)
                    if txn != nil || !reference.isEmpty {
                        TextField("Reference", text: $reference)
                            .font(.system(size: 13))
                    }
                    if let card = txn?.card, !card.isEmpty {
                        LabeledContent("Card", value: card)
                    }
                    if let t = txn {
                        LabeledContent("Recorded by", value: t.source.title)
                    }
                }

                if let data = txn?.receipt, let img = UIImage(data: data) {
                    Section("Screenshot") {
                        Button { showReceipt = true } label: {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 220)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showReceipt) {
                        ScrollView { Image(uiImage: img).resizable().scaledToFit() }
                            .presentationDragIndicator(.visible)
                    }
                }

                if txn != nil {
                    Section {
                        Button("Delete payment", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(txn == nil ? "Add spending" : "Payment")
            .navigationBarTitleDisplayMode(.inline)
            .tealNav()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .disabled(amount == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .confirmationDialog("Delete this payment?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let t = txn { ctx.delete(t); try? ctx.save() }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        if let t = txn {
            amountText = t.amount > 0 ? String(format: "%.2f", t.amount) : ""
            merchant = t.merchant
            category = t.category
            method = t.method
            date = t.date
            note = t.note
            reference = t.reference
            pickedCategory = true
        } else {
            amountFocused = true
        }
        DispatchQueue.main.async { loaded = true }
    }

    private func save() {
        guard let amount else { return }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let t: Txn
        let oldCategory: String?
        if let existing = txn {
            t = existing
            oldCategory = existing.category
        } else {
            t = Txn(date: date, amount: amount, merchant: name, category: category, method: method, source: .manual)
            ctx.insert(t)
            oldCategory = nil
        }
        t.amount = amount
        t.merchant = name
        t.category = category
        t.method = method
        t.date = date
        t.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        t.reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        t.needsReview = false
        t.possibleDuplicate = false
        // Remember the payee's category when you chose one that differs from the automatic guess.
        if !name.isEmpty {
            let changed: Bool
            if let oldCategory {
                changed = oldCategory != category
            } else {
                changed = pickedCategory && Categorizer.category(for: name, rules: Store.rules(ctx)) != category
            }
            if changed { Store.learn(merchant: name, category: category, ctx: ctx) }
        }
        try? ctx.save()
        dismiss()
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
