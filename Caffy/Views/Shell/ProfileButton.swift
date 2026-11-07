import SwiftUI

/// The round glass button in the top corner of every screen.
struct ProfileButton: View {
    var body: some View {
        // The profile screen isn't designed yet, so this does nothing.
        Button {} label: {
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
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .accessibilityLabel("Profile")
    }
}
