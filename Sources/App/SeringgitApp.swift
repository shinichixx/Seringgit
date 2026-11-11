import SwiftUI
import SwiftData
import PhotosUI
import UserNotifications

enum AppEnv {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Txn.self, SpendCategory.self, MerchantRule.self)
        } catch {
            fatalError("Could not open the database: \(error)")
        }
    }()
}

@main
struct SeringgitApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Task { @MainActor in Store.seedIfNeeded(AppEnv.container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.teal)
        }
        .modelContainer(AppEnv.container)
    }
}

enum AppTab { case home, reports, budgets, more }

enum AddSheet: String, Identifiable {
    case menu, manual
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var router = Router.shared
    @State private var tab: AppTab = .home
    @State private var sheet: AddSheet?
    @State private var keyboardUp = false
    @State private var editing: Txn?
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var importMessage: String?
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home: HomeView()
                case .reports: ReportsView()
                case .budgets: BudgetsView()
                case .more: MoreView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !keyboardUp {
                BottomBar(tab: $tab, onAdd: { sheet = .menu })
                    .padding(.bottom, -18)
            }
        }
        .background(Theme.background)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            let h = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            if h > 120 { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
        .dynamicTypeSize(.xSmall ... .large)
        .sheet(item: $sheet) { s in
            switch s {
            case .menu:
                AddMenuSheet(onManual: { sheet = .manual }, onScreenshot: {
                    sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pickingPhoto = true }
                })
                .presentationDetents([.height(215)])
                .presentationDragIndicator(.visible)
            case .manual:
                TxnForm(txn: nil)
            }
        }
        .sheet(item: $editing) { t in TxnForm(txn: t) }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            importing = true
            Task { @MainActor in
                defer { importing = false; photoItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    importMessage = "Couldn't open that photo."
                    return
                }
                let out = await Capture.screenshot(data, ctx: ctx, notify: false)
                if out.saved, let t = out.txn {
                    editing = t     // show what was read so you can confirm it
                } else {
                    importMessage = out.message
                }
            }
        }
        .overlay {
            if importing {
                ProgressView("Reading screenshot…")
                    .padding(20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .alert("Screenshot", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .onReceive(router.$openTxn) { id in
            guard let id else { return }
            let found = (try? ctx.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.id == id })))?.first
            if let found {
                tab = .home
                sheet = nil
                editing = found
            }
            router.openTxn = nil
        }
        .task {
            Store.seedIfNeeded(ctx)
            Notify.requestPermission()
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .background { BackupService.autoBackup(ctx: ctx) }
        }
    }
}

struct BottomBar: View {
    @Binding var tab: AppTab
    let onAdd: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                item(.home, "Home", "list.bullet.rectangle")
                item(.reports, "Reports", "chart.pie")
                Spacer().frame(width: 76)
                item(.budgets, "Budgets", "target")
                item(.more, "More", "ellipsis")
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            .background(Color.white, ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.10)).frame(height: 0.5) }

            Button(action: onAdd) {
                Circle().fill(Theme.teal).frame(width: 56, height: 56)
                    .overlay(Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white))
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
            }
            .offset(y: -22)
        }
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20)).frame(height: 24)
                Text(title).font(.caption2.weight(tab == t ? .bold : .regular))
            }
            .foregroundStyle(tab == t ? Theme.teal : Theme.tabInactive)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct AddMenuSheet: View {
    let onManual: () -> Void
    let onScreenshot: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Add").font(.headline).padding(.top, 30)
            HStack(spacing: 34) {
                option("Spending", "plus.circle.fill", Theme.teal, onManual)
                option("From screenshot", "camera.viewfinder", Theme.blue, onScreenshot)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private func option(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle().fill(color).frame(width: 58, height: 58)
                    .overlay(Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.white))
                Text(title).font(.caption).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
