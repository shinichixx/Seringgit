import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var txns: [Txn]
    @AppStorage(Keys.notifyOnCapture) private var notifyOnCapture = true
    @AppStorage(Keys.lastBackup) private var lastBackup = 0.0
    @State private var csvURL: URL?
    @State private var restoring = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(title: "More", color: Theme.blue)
                List {
                    Section("Auto-capture") {
                        NavigationLink { SetupGuideView() } label: {
                            Label("Set up auto-capture", systemImage: "wand.and.stars")
                        }
                        Toggle(isOn: $notifyOnCapture) {
                            Label("Notify when a payment is saved", systemImage: "bell.badge")
                        }
                    }

                    Section("Categories") {
                        NavigationLink { CategoriesView() } label: {
                            Label("Categories", systemImage: "square.grid.2x2")
                        }
                        NavigationLink { RulesView() } label: {
                            Label("Payee rules", systemImage: "text.badge.checkmark")
                        }
                    }

                    Section {
                        Button {
                            if let url = BackupService.backup(ctx: ctx) { message = "Saved \(url.lastPathComponent) to Files → On My iPhone → Seringgit → Backups." }
                            else { message = "Backup failed." }
                        } label: { Label("Back up now", systemImage: "externaldrive.badge.checkmark") }
                        Button { restoring = true } label: { Label("Import CSV / restore backup", systemImage: "square.and.arrow.down") }
                        if let csvURL {
                            ShareLink(item: csvURL) { Label("Share CSV", systemImage: "square.and.arrow.up") }
                        } else {
                            Button { csvURL = BackupService.csv(ctx: ctx) } label: { Label("Export to CSV", systemImage: "tablecells") }
                        }
                    } header: {
                        Text("Data")
                    } footer: {
                        Text(lastBackup > 0
                             ? "\(txns.count) payments. Last backup \(Fmt.dateTime.string(from: Date(timeIntervalSince1970: lastBackup))). Backups run automatically when you leave the app (every 6 hours at most). Import takes a CSV from Seringgit, Belanje or most expense apps, or a Seringgit backup (.json); payments already in the app are skipped."
                             : "\(txns.count) payments. Backups run automatically when you leave the app. Import takes a CSV from Seringgit, Belanje or most expense apps, or a Seringgit backup (.json).")
                    }

                    Section {
                        LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .json, .plainText, .text, .spreadsheet, .data]) { result in
                switch result {
                case .success(let url):
                    message = BackupService.importFile(url, ctx: ctx)
                case .failure(let error):
                    message = "Couldn't open the file: \(error.localizedDescription)"
                }
            }
            .alert("Seringgit", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }
}

// MARK: - Setup guide

struct SetupGuideView: View {
    var body: some View {
        List {
            Section {
                step(1, "Open the Shortcuts app → Automation → + → Transaction.")
                step(2, "Choose your Maybank card(s) in Wallet, leave all categories ticked, and pick \"Run Immediately\".")
                step(3, "Tap New Blank Automation → Add Action → search \"Seringgit\" → Log Apple Pay Payment.")
                step(4, "Tap Amount → Shortcut Input → Amount. Tap Merchant → Shortcut Input → Merchant. Expand the action and set Card → Shortcut Input → Card or Pass.")
                step(5, "Done. Every Apple Pay tap is now saved automatically with a notification.")
            } header: {
                Label("Apple Pay — fully automatic", systemImage: "applelogo")
            }

            Section {
                step(1, "Shortcuts → Shortcuts tab → + → name it \"Log MAE payment\".")
                step(2, "Add action \"Take Screenshot\".")
                step(3, "Add action Seringgit → Log Payment from Screenshot, and set Screenshot to the Screenshot from step 2.")
                step(4, "Settings → Accessibility → Touch → Back Tap → Double Tap → choose \"Log MAE payment\".")
                step(5, "After paying with DuitNow QR or FPX, double-tap the back of your iPhone while MAE shows the \"Successful\" screen.")
            } header: {
                Label("DuitNow QR & FPX — double-tap the back", systemImage: "hand.tap")
            } footer: {
                Text("The screenshot is read on your iPhone; nothing is uploaded. If the amount or payee can't be read, the payment is marked \"to check\" on the Home tab.")
            }

            Section {
                step(1, "In the same \"Log MAE payment\" shortcut, tap ⓘ → turn on Show in Share Sheet.")
                step(2, "Or tap + → From screenshot in Seringgit to pick a screenshot from Photos.")
            } header: {
                Label("Other ways", systemImage: "square.and.arrow.up")
            }
        }
        .navigationTitle("Set up auto-capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tealNav(Theme.blue)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.teal))
            Text(text).font(.system(size: 13))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Categories

struct CategoriesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    @State private var editing: SpendCategory?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(categories) { c in
                Button { editing = c } label: {
                    HStack(spacing: 10) {
                        CategoryIcon(icon: c.icon, color: c.color, size: 28)
                        Text(c.name).foregroundStyle(Color.primary)
                        Spacer()
                        if c.monthlyBudget > 0 { Text(rm0(c.monthlyBudget)).font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                }
            }
            .onMove { from, to in
                var list = categories
                list.move(fromOffsets: from, toOffset: to)
                for (i, c) in list.enumerated() { c.sortOrder = i }
                try? ctx.save()
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tealNav(Theme.blue)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    EditButton().foregroundStyle(.white)
                    Button { adding = true } label: { Image(systemName: "plus") }.foregroundStyle(.white)
                }
            }
        }
        .sheet(item: $editing) { c in CategoryForm(category: c) }
        .sheet(isPresented: $adding) { CategoryForm(category: nil) }
    }
}

struct CategoryForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    let category: SpendCategory?

    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var colorHex = "00968A"
    @State private var budgetText = ""
    @State private var confirmDelete = false

    static let icons = ["fork.knife", "cart.fill", "car.fill", "fuelpump.fill", "bag.fill", "bolt.fill", "house.fill",
                        "figure.and.child.holdinghands", "cross.case.fill", "popcorn.fill", "arrow.left.arrow.right",
                        "gift.fill", "graduationcap.fill", "airplane", "pawprint.fill", "tshirt.fill", "wrench.fill",
                        "gamecontroller.fill", "heart.fill", "phone.fill", "wifi", "creditcard.fill", "banknote.fill",
                        "building.columns.fill", "cup.and.saucer.fill", "dumbbell.fill", "book.fill", "scissors",
                        "leaf.fill", "moon.stars.fill", "tag.fill", "ellipsis.circle.fill"]
    static let colors = ["FF9800", "2E7D32", "1565C0", "D81B60", "6A1B9A", "00897B", "E53935", "3949AB", "546E7A",
                         "9E9E9E", "F4511E", "00ACC1", "7CB342", "8D6E63", "FDD835", "C2185B"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        CategoryIcon(icon: icon, color: Color(hex: colorHex), size: 40)
                        TextField("Name", text: $name).font(.system(size: 17, weight: .semibold))
                    }
                    HStack {
                        Text("Monthly budget")
                        Spacer()
                        TextField("none", text: $budgetText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
                    }
                }
                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Self.colors, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == h ? 2 : 0).padding(-3))
                                .onTapGesture { colorHex = h }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { s in
                            Image(systemName: s).font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(icon == s ? Color(hex: colorHex).opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = s }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if category != nil {
                    Section {
                        Button("Delete category", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Payments in this category move to Others.")
                    }
                }
            }
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .tealNav(Theme.blue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.foregroundStyle(.white)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear {
                if let c = category {
                    name = c.name
                    icon = c.icon
                    colorHex = c.colorHex
                    budgetText = c.monthlyBudget > 0 ? String(format: "%.0f", c.monthlyBudget) : ""
                }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let budget = parseAmountText(budgetText) ?? 0
        if let c = category {
            if c.name != n { rename(from: c.name, to: n) }
            c.name = n
            c.icon = icon
            c.colorHex = colorHex
            c.monthlyBudget = budget
        } else {
            ctx.insert(SpendCategory(name: n, icon: icon, colorHex: colorHex, sortOrder: (categories.map { $0.sortOrder }.max() ?? 0) + 1, monthlyBudget: budget))
        }
        try? ctx.save()
        dismiss()
    }

    private func rename(from old: String, to new: String) {
        let txns = (try? ctx.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.category == old }))) ?? []
        for t in txns { t.category = new }
        let rules = (try? ctx.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.category == old }))) ?? []
        for r in rules { r.category = new }
    }

    private func delete() {
        guard let c = category else { return }
        rename(from: c.name, to: Categorizer.fallback)
        ctx.delete(c)
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Payee rules

struct RulesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MerchantRule.keyword) private var rules: [MerchantRule]
    @Query(sort: \SpendCategory.sortOrder) private var categories: [SpendCategory]
    @State private var newKeyword = ""
    @State private var newCategory = "Food & Drinks"
    @State private var filter = ""

    private var learned: [MerchantRule] { rules.filter { $0.learned && matches($0) } }
    private var keywords: [MerchantRule] { rules.filter { !$0.learned && matches($0) } }
    private func matches(_ r: MerchantRule) -> Bool {
        filter.isEmpty || r.keyword.lowercased().contains(filter.lowercased()) || r.category.lowercased().contains(filter.lowercased())
    }

    var body: some View {
        List {
            Section {
                TextField("Keyword, e.g. kedai runcit", text: $newKeyword)
                    .textInputAutocapitalization(.never)
                Picker("Category", selection: $newCategory) {
                    ForEach(categories) { c in Text(c.name).tag(c.name) }
                }
                Button("Add rule") {
                    let k = newKeyword.trimmingCharacters(in: .whitespaces)
                    guard !k.isEmpty else { return }
                    ctx.insert(MerchantRule(keyword: k, category: newCategory, learned: false))
                    try? ctx.save()
                    newKeyword = ""
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("New keyword rule")
            } footer: {
                Text("A payee containing the keyword goes to that category. The longest matching keyword wins.")
            }

            Section {
                if learned.isEmpty { Text("None yet — change a payment's category and Seringgit remembers it here.").font(.system(size: 12)).foregroundStyle(.secondary) }
                ForEach(learned) { r in row(r) }
                    .onDelete { idx in for i in idx { ctx.delete(learned[i]) }; try? ctx.save() }
            } header: {
                Text("Learned from your edits")
            }

            Section("Keywords (\(keywords.count))") {
                ForEach(keywords) { r in row(r) }
                    .onDelete { idx in for i in idx { ctx.delete(keywords[i]) }; try? ctx.save() }
            }
        }
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search rules")
        .navigationTitle("Payee rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tealNav(Theme.blue)
    }

    private func row(_ r: MerchantRule) -> some View {
        HStack {
            Text(r.keyword).font(.system(size: 13))
            Spacer()
            Menu {
                ForEach(categories) { c in
                    Button(c.name) { r.category = c.name; try? ctx.save() }
                }
            } label: {
                Text(r.category).font(.system(size: 12)).foregroundStyle(categories.first(where: { $0.name == r.category })?.color ?? Color.secondary)
            }
        }
    }
}
