import SwiftUI

/// The app's two sections.
enum AppTab: CaseIterable, Identifiable {
    case home
    case library

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .library: "Library"
        }
    }

    var icon: some View {
        // Drawn from the design rather than SF Symbols.
        Canvas { context, size in
            let scale = size.width / 24
            context.scaleBy(x: scale, y: scale)
            context.stroke(iconPath, with: .foreground, lineWidth: 2)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var iconPath: Path {
        var path = Path()
        switch self {
        case .home:
            path.addRect(CGRect(x: 3, y: 3, width: 8, height: 10))
            path.addRect(CGRect(x: 13, y: 3, width: 8, height: 6))
            path.addRect(CGRect(x: 3, y: 15, width: 8, height: 6))
            path.addRect(CGRect(x: 13, y: 11, width: 8, height: 10))
        case .library:
            // Two wavy streams, echoing the genre river.
            for x in [8.0, 16.0] {
                path.move(to: CGPoint(x: x, y: 2))
                path.addCurve(to: CGPoint(x: x + 2, y: 14), control1: CGPoint(x: x + 8, y: 7), control2: CGPoint(x: x - 3, y: 10))
                path.addCurve(to: CGPoint(x: x + 3, y: 22), control1: CGPoint(x: x + 5, y: 16), control2: CGPoint(x: x, y: 20))
            }
        }
        return path
    }
}

/// The floating pill that switches between Home and Library.
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 7) {
                        tab.icon
                        Text(tab.title)
                            .font(Theme.display(15))
                    }
                    .foregroundStyle(tab == selection ? Theme.cream : Theme.ink)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(tab == selection ? Theme.ink : .clear, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .padding(5)
        .glassEffect(.regular.tint(Theme.cream.opacity(0.6)), in: .capsule)
        .shadow(color: Theme.shadow.opacity(0.26), radius: 12, y: 8)
    }
}
