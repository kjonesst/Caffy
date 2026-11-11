import Foundation
import Testing
@testable import Caffy

/// Sanity checks on the default thresholds, so a typo in a default can't
/// quietly break the rules that depend on them.
struct EraBuildConfigTests {
    private let config = EraBuildConfig.standard
    private let day: TimeInterval = 24 * 60 * 60

    @Test func eraLengthsAreInOrder() {
        #expect(config.minEraLength < config.targetEraLength)
        #expect(config.targetEraLength < config.maxEraLength)
        // Season-sized: about one to four months.
        #expect(config.minEraLength == 30 * day)
        #expect(config.maxEraLength == 120 * day)
    }

    @Test func aMaxLengthEraCanAlwaysBeCutInTwo() {
        #expect(config.maxEraLength >= 2 * config.minEraLength)
    }

    @Test func aLongGapIsShorterThanTheShortestEra() {
        // Otherwise a gap could never split an era that's already at its minimum.
        #expect(config.longGap < config.minEraLength)
    }

    @Test func tripsSplitBeforeErasDo() {
        // A trip broken by a long gap must already be two trips.
        #expect(config.maxTripGap < config.longGap)
        #expect(config.unlocatedInheritWindow < config.maxTripGap)
    }

    @Test func cutScoreWeightsAddUpToOne() {
        #expect(abs(config.musicChangeWeight + config.gapWeight - 1) < 1e-9)
        #expect(config.strongCutScore > 0 && config.strongCutScore <= 1)
    }

    @Test func matchDecayIsValid() {
        #expect(config.matchDecayHalfLife > 0)
        #expect(config.matchDecayCutoff >= config.matchDecayHalfLife)
        #expect(config.maxSongsPerMoment > 0)
    }

    @Test func paletteRangesAreValid() {
        #expect(config.paperLightness.lowerBound > 0 && config.paperLightness.upperBound < 1)
        #expect(config.paperChroma.lowerBound > 0)
        #expect((0...1).contains(config.albumArtWeight))
    }

    @Test func valuesCanBeOverridden() {
        var custom = EraBuildConfig()
        custom.longGap = 7 * day
        custom.homeAdoptionDays = 14
        #expect(custom.longGap == 7 * day)
        #expect(custom.homeAdoptionDays == 14)
        #expect(custom != .standard)
    }
}
