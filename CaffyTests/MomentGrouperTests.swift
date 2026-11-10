import Foundation
import Testing
@testable import Caffy

/// Tests for `MomentGrouper.group`, the pure function that splits photos into
/// moments by time and distance.
struct MomentGrouperTests {
    // MARK: - Fixtures

    /// A fixed starting time, so tests never depend on the clock.
    private static let t0 = Date(timeIntervalSince1970: 1_776_000_000)

    /// Bondi Beach, Sydney.
    private static let bondi = Coordinate(latitude: -33.8908, longitude: 151.2743)

    /// One degree of latitude is about 111 km, so this many degrees is roughly
    /// `metres` north of `coordinate`.
    private static func north(of coordinate: Coordinate, metres: Double) -> Coordinate {
        Coordinate(latitude: coordinate.latitude + metres / 111_000, longitude: coordinate.longitude)
    }

    private static func photo(
        _ id: String,
        minutes: Double,
        at coordinate: Coordinate? = bondi,
        aspectRatio: Double = 1
    ) -> PhotoItem {
        PhotoItem(
            id: id,
            creationDate: t0.addingTimeInterval(minutes * 60),
            coordinate: coordinate,
            aspectRatio: aspectRatio
        )
    }

    private static func ids(_ moments: [PhotoMoment]) -> [[String]] {
        moments.map(\.photoIDs)
    }

    // MARK: - Basics

    @Test func emptyLibraryHasNoMoments() {
        #expect(MomentGrouper.group([]).isEmpty)
    }

    @Test func singlePhotoIsItsOwnMoment() throws {
        let photo = Self.photo("a", minutes: 0, aspectRatio: 1.5)
        let moments = MomentGrouper.group([photo])

        let moment = try #require(moments.first)
        #expect(moments.count == 1)
        #expect(moment.id == "a")
        #expect(moment.start == photo.creationDate)
        #expect(moment.end == photo.creationDate)
        #expect(moment.coverID == "a")
        #expect(moment.coverAspectRatio == 1.5)
        #expect(moment.coordinate == Self.bondi)
    }

    @Test func nearbyPhotosCloseInTimeStayTogether() {
        let moments = MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 30, at: Self.north(of: Self.bondi, metres: 100))
        ])
        #expect(Self.ids(moments) == [["a", "b"]])
    }

    // MARK: - Time

    @Test func gapOfExactlyTheThresholdStaysTogether() {
        let moments = MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 120)
        ])
        #expect(Self.ids(moments) == [["a", "b"]])
    }

    @Test func gapJustOverTheThresholdSplits() {
        let a = Self.photo("a", minutes: 0)
        let b = PhotoItem(
            id: "b",
            creationDate: a.creationDate.addingTimeInterval(2 * 60 * 60 + 1),
            coordinate: Self.bondi
        )
        #expect(Self.ids(MomentGrouper.group([a, b])) == [["a"], ["b"]])
    }

    // MARK: - Distance

    @Test func farApartPhotosSplitEvenWhenCloseInTime() {
        let moments = MomentGrouper.group([
            Self.photo("bondi", minutes: 0),
            Self.photo("manly", minutes: 10, at: Self.north(of: Self.bondi, metres: 1_500))
        ])
        #expect(Self.ids(moments) == [["bondi"], ["manly"]])
    }

    @Test func photosWithoutLocationGroupByTimeOnly() {
        let moments = MomentGrouper.group([
            Self.photo("a", minutes: 0, at: nil),
            Self.photo("b", minutes: 30, at: nil),
            Self.photo("c", minutes: 30 + 180, at: nil)
        ])
        #expect(Self.ids(moments) == [["a", "b"], ["c"]])
    }

    @Test func distanceIsMeasuredFromTheLastLocatedPhoto() {
        let far = Self.north(of: Self.bondi, metres: 1_500)
        let near = Self.north(of: Self.bondi, metres: 200)

        // An unlocated photo in between doesn't reset the place: "far" is
        // still compared with Bondi, and splits.
        let split = MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 10, at: nil),
            Self.photo("c", minutes: 20, at: far)
        ])
        #expect(Self.ids(split) == [["a", "b"], ["c"]])

        let together = MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 10, at: nil),
            Self.photo("c", minutes: 20, at: near)
        ])
        #expect(Self.ids(together) == [["a", "b", "c"]])
    }

    @Test func unlocatedPhotoAfterALocatedOneJoinsByTime() {
        let moments = MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 10, at: nil)
        ])
        #expect(Self.ids(moments) == [["a", "b"]])
    }

    // MARK: - Ordering

    @Test func unsortedInputIsSortedFirst() {
        let moments = MomentGrouper.group([
            Self.photo("c", minutes: 400),
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 20)
        ])
        #expect(Self.ids(moments) == [["a", "b"], ["c"]])
    }

    @Test func photosWithTheSameTimeKeepTheirInputOrder() {
        let moments = MomentGrouper.group([
            Self.photo("first", minutes: 5),
            Self.photo("second", minutes: 5),
            Self.photo("third", minutes: 5)
        ])
        #expect(Self.ids(moments) == [["first", "second", "third"]])
    }

    @Test func momentSpansItsFirstAndLastPhoto() throws {
        let photos = [
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 15),
            Self.photo("c", minutes: 50)
        ]
        let moment = try #require(MomentGrouper.group(photos).first)
        #expect(moment.photoIDs == ["a", "b", "c"])
        #expect(moment.start == photos[0].creationDate)
        #expect(moment.end == photos[2].creationDate)
    }

    // MARK: - Cover and place

    @Test func coverIsTheMiddlePhoto() throws {
        let moment = try #require(MomentGrouper.group([
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 1, aspectRatio: 0.75),
            Self.photo("c", minutes: 2)
        ]).first)
        #expect(moment.coverID == "b")
        #expect(moment.coverAspectRatio == 0.75)
        #expect(moment.id == "a")
    }

    @Test func placeIsTheLocatedPhotoNearestTheCentre() throws {
        let south = Self.bondi
        let middle = Self.north(of: Self.bondi, metres: 300)
        let north = Self.north(of: Self.bondi, metres: 600)

        let moment = try #require(MomentGrouper.group([
            Self.photo("a", minutes: 0, at: south),
            Self.photo("b", minutes: 5, at: nil),
            Self.photo("c", minutes: 10, at: north),
            Self.photo("d", minutes: 15, at: middle)
        ]).first)
        #expect(moment.coordinate == middle)
    }

    @Test func placeIsNilWhenNoPhotoHasALocation() throws {
        let moment = try #require(MomentGrouper.group([
            Self.photo("a", minutes: 0, at: nil),
            Self.photo("b", minutes: 5, at: nil)
        ]).first)
        #expect(moment.coordinate == nil)
    }

    // MARK: - Config

    @Test func customThresholdsAreUsed() {
        let photos = [
            Self.photo("a", minutes: 0),
            Self.photo("b", minutes: 45, at: Self.north(of: Self.bondi, metres: 300)),
            Self.photo("c", minutes: 60, at: Self.north(of: Self.bondi, metres: 300))
        ]
        let strict = MomentGroupingConfig(maxTimeGap: 30 * 60, maxDistance: 200)
        #expect(Self.ids(MomentGrouper.group(photos, config: strict)) == [["a"], ["b", "c"]])
        #expect(Self.ids(MomentGrouper.group(photos)) == [["a", "b", "c"]])
    }

    // MARK: - Known behaviour

    /// Documents a limitation: each photo is compared with the one before it,
    /// so a whole day of photos 30 minutes apart, slowly drifting, is one moment.
    @Test func steadyPhotosAllDayStayOneMoment() {
        let photos = (0..<24).map { index in
            Self.photo(
                "p\(index)",
                minutes: Double(index) * 30,
                at: Self.north(of: Self.bondi, metres: Double(index) * 500)
            )
        }
        #expect(MomentGrouper.group(photos).count == 1)
    }

    // MARK: - Performance

    @Test func groupsTenThousandPhotosQuickly() {
        // Bursts of 10 photos, an hour apart, so there are about 1,000 moments.
        let photos = (0..<10_000).map { index in
            Self.photo(
                "p\(index)",
                minutes: Double(index / 10) * 60 * 3 + Double(index % 10),
                at: index.isMultiple(of: 3) ? nil : Self.bondi
            )
        }
        var moments: [PhotoMoment] = []
        let elapsed = ContinuousClock().measure {
            moments = MomentGrouper.group(photos)
        }
        #expect(moments.count == 1_000)
        // Generous, because tests run as an unoptimised Debug build.
        #expect(elapsed < .milliseconds(500))
    }
}
