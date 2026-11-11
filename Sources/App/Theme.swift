import SwiftUI

/// Same colours and shapes as Fleetly.
enum Theme {
    static let teal = Color(red: 0.0, green: 0.588, blue: 0.655)
    static let rouge = Color(red: 0.80, green: 0.09, blue: 0.15)
    static let blue = Color(red: 0.13, green: 0.40, blue: 0.80)
    static let orange = Color(red: 1.0, green: 0.596, blue: 0.0)
    static let reminder = Color(red: 0.404, green: 0.227, blue: 0.718)
    static let green = Color(red: 0.180, green: 0.490, blue: 0.196)
    static let background = Color(red: 0.945, green: 0.953, blue: 0.961)
    static let tabInactive = Color(white: 0.45)
}

extension View {
    func tealNav(_ color: Color = Theme.teal) -> some View {
        self
            .toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
}

struct HeaderButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(Color.white.opacity(0.22)).frame(width: 36, height: 36)
                .overlay(Image(systemName: systemName).foregroundStyle(.white).font(.system(size: 15, weight: .semibold)))
        }
    }
}

/// Coloured top bar: title on the left, buttons on the right.
struct AppHeader<Trailing: View>: View {
    let title: String
    var subtitle: String = ""
    let color: Color
    let trailing: Trailing

    init(title: String, subtitle: String = "", color: Color = Theme.teal, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.85))
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(color.ignoresSafeArea(edges: .top))
    }
}

extension AppHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "", color: Color = Theme.teal) {
        self.init(title: title, subtitle: subtitle, color: color) { EmptyView() }
    }
}

/// Round coloured icon used for categories.
struct CategoryIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 34
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(Image(systemName: icon).foregroundStyle(.white).font(.system(size: size * 0.42, weight: .semibold)))
    }
}

/// Month picker with ‹ › arrows, white text for coloured headers.
struct MonthStepper: View {
    @Binding var month: Date
    var body: some View {
        HStack(spacing: 6) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Text(Fmt.month.string(from: month)).font(.system(size: 13, weight: .semibold)).frame(minWidth: 86)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
                .opacity(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) ? 0.35 : 1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
    }
    private func shift(_ n: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: n, to: month) { month = d }
    }
}
