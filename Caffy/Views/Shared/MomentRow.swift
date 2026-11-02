import SwiftUI

/// One moment in a list: when it happened and what was playing.
struct MomentRow: View {
    let date: Date
    let songs: [Song]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.weekday(.wide).day().month().year())
                .font(.headline)
            // `.list(type: .and)` joins the titles naturally for the user's
            // language, e.g. "Dreams, Kids, and Riptide".
            Text(songs.map(\.title), format: .list(type: .and))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    List {
        MomentRow(date: .now, songs: Array(MockMusicProvider.catalog.prefix(3)))
    }
}
