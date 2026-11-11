import Foundation

/// Every tunable threshold in the era pipeline, in one place.
///
/// The pipeline (match → home → segment → palette → title) reads all of its
/// numbers from here, so tuning Caffy against a real library means changing
/// this struct, never the logic. Tests pass custom values to check each rule.
nonisolated struct EraBuildConfig: Sendable, Equatable {
    // MARK: - Match: songs for each moment

    /// How far before a moment's first photo a song still counts as "playing then".
    var matchWindowBefore: TimeInterval = 45 * 60
    /// How far after a moment's last photo a song still counts.
    var matchWindowAfter: TimeInterval = 30 * 60
    /// Plays just outside the window still count, halving in weight every this long.
    var matchDecayHalfLife: TimeInterval = 30 * 60
    /// Plays further than this outside the window don't count at all
    /// (four half-lives, where the weight has dropped to 1/16).
    var matchDecayCutoff: TimeInterval = 2 * 60 * 60
    /// The most songs a single moment keeps.
    var maxSongsPerMoment: Int = 8
    /// When nothing plays near a moment, fall back to songs from the same day,
    /// marked as a loose match.
    var dayFallbackMatching: Bool = true

    // MARK: - Home and trips

    /// Photos within this many metres of each other count as the same place
    /// (roughly one city).
    var placeClusterRadius: Double = 25_000
    /// How long, in days, someone has to stay in a place before it counts as home.
    var homeAdoptionDays: Int = 28
    /// A place only counts as home over a stretch if at least this share of
    /// the located days in that stretch were spent there.
    var homeMinShare: Double = 0.5
    /// A photo without a location takes the home-or-away label of the nearest
    /// located photo within this long. Otherwise it counts as home.
    var unlocatedInheritWindow: TimeInterval = 12 * 60 * 60
    /// A run of photos away from home is an overnight trip if it crosses this
    /// local hour (04:00). Runs that don't are day trips.
    var overnightCutoffHour: Int = 4

    // MARK: - Segment: era boundaries

    /// A gap with no photos at least this long always starts a new era.
    var longGap: TimeInterval = 21 * 24 * 60 * 60
    /// The shortest a home era should be, unless a hard cut forces it.
    var minEraLength: TimeInterval = 30 * 24 * 60 * 60
    /// The length a home era aims for: about a season.
    var targetEraLength: TimeInterval = 75 * 24 * 60 * 60
    /// A home era longer than this is cut at its best candidate point.
    var maxEraLength: TimeInterval = 120 * 24 * 60 * 60
    /// How much listening on each side of a candidate cut is compared to
    /// measure a change in music.
    var musicWindow: TimeInterval = 21 * 24 * 60 * 60
    /// Each side of a candidate cut needs at least this many plays before a
    /// change in music can count. Below that, music is treated as unchanged.
    var musicMinPlays: Int = 10
    /// How much a change in music counts when scoring a candidate cut.
    var musicChangeWeight: Double = 0.6
    /// How much the length of the photo gap counts when scoring a candidate cut.
    var gapWeight: Double = 0.4
    /// A candidate cut scoring at least this much is made even when the era
    /// isn't too long yet.
    var strongCutScore: Double = 0.7

    // MARK: - Stability

    /// An era is frozen (never re-cut or renamed) this long after it ends.
    var freezeAfter: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Palette

    /// How many moments' cover photos are sampled for an era's colours.
    var paletteSampleMoments: Int = 12
    /// How much album art counts next to photos when choosing colours (0–1).
    var albumArtWeight: Double = 0.3
    /// The OKLCH lightness range the paper colour is kept within.
    var paperLightness: ClosedRange<Double> = 0.35...0.75
    /// The OKLCH chroma range the paper colour is kept within.
    var paperChroma: ClosedRange<Double> = 0.06...0.16
    /// The lowest contrast ratio allowed between ink and paper (WCAG AA).
    var minInkContrast: Double = 4.5
    /// Neighbouring eras' paper colours must differ by at least this much
    /// (ΔE in OKLab × 100).
    var minNeighbourDeltaE: Double = 12

    // MARK: - Title

    /// An artist with at least this share of an era's plays can title it
    /// ("On repeat: …").
    var dominantArtistShare: Double = 0.25

    static let standard = EraBuildConfig()
}
