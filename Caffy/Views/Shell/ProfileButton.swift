import SwiftUI

/// The round glass button in the top corner of every screen.
struct ProfileButton: View {
    #if DEBUG
    @AppStorage("hasOnboarded") private var hasOnboarded = true
    #endif

    var body: some View {
        #if DEBUG
        // DEBUG builds only: a menu to see onboarding again. Release builds
        // keep the plain button below.
        Menu {
            Button("Replay onboarding", systemImage: "arrow.counterclockwise") {
                withAnimation(.easeInOut(duration: 0.4)) { hasOnboarded = false }
            }
        } label: {
            avatar
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel("Profile")
        #else
        // The profile screen isn't designed yet, so this does nothing.
        Button {} label: {
            avatar
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel("Profile")
        #endif
    }

    private var avatar: some View {
        PhotoPlaceholder(seed: "Profile", showsIcon: false)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.cream)
            }
            .clipShape(.circle)
            .frame(width: 44, height: 44)
            .padding(6)
            .contentShape(.circle)
    }
}
