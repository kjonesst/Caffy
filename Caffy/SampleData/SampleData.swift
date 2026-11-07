import Foundation
import SwiftData

/// Fills the database with example eras, moments, and playlists so the app
/// has something to show before PhotoKit and MusicKit are connected.
enum SampleData {
    /// An era to create, plus the month its photos were taken in.
    private struct SampleEra {
        let title: String
        let whenLabel: String
        let summary: String
        let year: Int
        let month: Int
        var isCurrent = false
        let palette: EraPalette
        /// One width-to-height ratio per photo. The count sets the collage.
        let photoAspectRatios: [Double]
    }

    private static let eras: [SampleEra] = [
        SampleEra(
            title: "The Long Way Round", whenLabel: "2026",
            summary: "Trance comes back bigger than ever, and chillout thins out.",
            year: 2026, month: 4, isCurrent: true, palette: .rust,
            photoAspectRatios: [1.6, 0.7, 1, 0.9, 1.2]
        ),
        SampleEra(
            title: "Looking Up", whenLabel: "2025",
            summary: "Chillout takes over, and drum & bass arrives.",
            year: 2025, month: 5, palette: .olive,
            photoAspectRatios: [0.75, 0.8, 1]
        ),
        SampleEra(
            title: "Congrats", whenLabel: "2024",
            summary: "Progressive and trance replace classic rock.",
            year: 2024, month: 5, palette: .marigold,
            photoAspectRatios: [0.75]
        ),
        SampleEra(
            title: "Early Days", whenLabel: "way back",
            summary: "Where it starts: classic rock.",
            year: 2012, month: 7, palette: .oxblood,
            photoAspectRatios: [1.75]
        )
    ]

    /// Inserts sample data only when the database has no eras yet,
    /// so it runs on first launch and never duplicates.
    static func insertIfNeeded(into context: ModelContext, using provider: some MusicProvider) async throws {
        let eraCount = try context.fetchCount(FetchDescriptor<Era>())
        guard eraCount == 0 else { return }
        try await insert(into: context, using: provider)
    }

    /// Inserts the sample data unconditionally. Used by previews.
    static func insert(into context: ModelContext, using provider: some MusicProvider) async throws {
        let calendar = Calendar.current
        for (index, sample) in eras.enumerated() {
            let start = calendar.date(from: DateComponents(year: sample.year, month: sample.month, day: 1)) ?? .now
            // Each era ends where the next-newest one begins.
            let newerEraStart = index > 0
                ? calendar.date(from: DateComponents(year: eras[index - 1].year, month: eras[index - 1].month, day: 1))
                : nil
            let era = Era(
                title: sample.title,
                whenLabel: sample.whenLabel,
                summary: sample.summary,
                startDate: start,
                endDate: sample.isCurrent ? nil : newerEraStart,
                palette: sample.palette
            )
            context.insert(era)

            for (photo, aspectRatio) in sample.photoAspectRatios.enumerated() {
                // The first photo is the newest, so it leads the collage.
                let date = calendar.date(byAdding: .day, value: sample.photoAspectRatios.count - photo, to: start) ?? start
                let songs = try await provider.songs(playedAround: date)
                // Appending to the relationship also inserts the moment and
                // sets `moment.era` for us, because of the `inverse`.
                era.moments.append(Moment(date: date, songs: songs, photoAspectRatio: aspectRatio))
            }

            era.playlist = CaffyPlaylist(
                name: sample.title,
                lastUpdated: sample.isCurrent ? .now : era.momentsNewestFirst.first?.date ?? start
            )
        }
        try context.save()
    }
}
