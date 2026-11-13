import Foundation
import SwiftData

/// A photo paired with the songs the user was listening to around then.
///
/// Fields added after the first release are optional or have a default, so
/// an existing database gains them on its own when the app updates.
@Model
final class Moment {
    /// When the moment's first photo was taken.
    var date: Date

    /// The `PhotoMoment` id this was saved from (its first photo's PhotoKit
    /// identifier), so the next sync can find it again. `nil` for sample data.
    var momentID: String?

    /// When the moment's last photo was taken. `nil` for sample data.
    var endDate: Date?

    /// The PhotoKit `PHAsset.localIdentifier` for the photo that stands for
    /// this moment in collages. `nil` for sample data, which shows a
    /// placeholder image instead.
    var photoAssetIdentifier: String?

    /// The photo's width divided by its height. A collage with a single photo
    /// uses this to choose a portrait or landscape print.
    var photoAspectRatio: Double = 1

    /// Where the moment happened, if its photos have a location.
    var latitude: Double?
    var longitude: Double?

    /// The songs playing around this moment, strongest first.
    ///
    /// - `nil`: never matched against real listening data (it happened
    ///   before Caffy had any). A frozen era's moment can still get songs.
    /// - `[]`: matched, and nothing was playing (or the user cleared them).
    var songs: [Song]?

    /// The matcher's weight for each of `songs`, in the same order. `nil` for
    /// sample data and moments saved before weights were kept.
    var songScores: [Double]?

    /// `true` when `songs` only come from the same day, not from near the moment.
    var songsAreLoose: Bool = false

    /// The era this moment belongs to. The other side of `Era.moments`.
    var era: Era?

    /// Where this moment happened, if Caffy knows. The other side of `Place.moments`.
    var place: Place?

    init(date: Date, songs: [Song]?, photoAssetIdentifier: String? = nil, photoAspectRatio: Double = 1) {
        self.date = date
        self.songs = songs
        self.photoAssetIdentifier = photoAssetIdentifier
        self.photoAspectRatio = photoAspectRatio
    }
}

extension Moment {
    /// Copies everything about `moment` except its songs. Only what changed
    /// is set (see `assign`).
    func update(from moment: PhotoMoment) {
        assign(moment.id, to: \.momentID)
        assign(moment.start, to: \.date)
        assign(moment.end, to: \.endDate)
        assign(moment.coverID, to: \.photoAssetIdentifier)
        assign(moment.coverAspectRatio, to: \.photoAspectRatio)
        assign(moment.coordinate?.latitude, to: \.latitude)
        assign(moment.coordinate?.longitude, to: \.longitude)
    }
}

extension Moment {
    /// This moment's songs with where they came from, strongest first.
    var matches: [EraSong] {
        let songs = songs ?? []
        let evidence: SongEvidence = songsAreLoose ? .loosePlay : .nearPlay
        return songs.enumerated().map { index, song in
            // Without saved weights, earlier songs count for more.
            let score = songScores.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                ?? Double(songs.count - index)
            return EraSong(song: song, evidence: evidence, score: score)
        }
    }

    /// Sets this moment's songs, weights and looseness together, changing
    /// only what's different. `nil` means not matched against real listening.
    func setMatches(_ matches: [EraSong]?) {
        assign(matches?.map(\.song), to: \.songs)
        assign(matches?.map(\.score), to: \.songScores)
        assign(matches?.first?.evidence == .loosePlay, to: \.songsAreLoose)
    }

    /// The moment's own songs as shown against it: the strongest
    /// `maxSongsPerMoment`. Its era's playlist still gets all of them.
    var shownSongs: [Song] {
        Array((songs ?? []).prefix(EraBuildConfig.standard.maxSongsPerMoment))
    }

    /// Whether this moment has no songs of its own, so it shows its era's
    /// songs instead (labelled "From this era").
    var isEraFallback: Bool {
        songs?.isEmpty ?? true
    }

    /// The songs to show for this moment: its own, or else its era's top
    /// songs. Check `isEraFallback` before presenting them: era songs must
    /// never look as if they were playing at this moment.
    func displaySongs(limit: Int = EraBuildConfig.standard.maxSongsPerMoment) -> [Song] {
        if let songs, !songs.isEmpty { return Array(songs.prefix(limit)) }
        guard let era, era.isLive else { return [] }
        return Array(era.songs.prefix(limit).map(\.song))
    }
}
