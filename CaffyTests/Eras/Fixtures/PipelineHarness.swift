import Foundation
@testable import Caffy

/// Runs the whole era pipeline on fixture scenarios.
enum PipelineHarness {
    static let sydneyGreen: UInt32 = 0x4F8A3A
    static let melbourneBlue: UInt32 = 0x2F5BC8
    static let hobartTeal: UInt32 = 0x1F8A80
    static let wollongongOrange: UInt32 = 0xE07A2E

    /// Photos take their city's colour. Photos without a location can't be read.
    static func sampler(for moments: [PhotoMoment]) -> FixtureColorSampler {
        let cityColours: [(FixturePlace, UInt32)] = [
            (.sydney, sydneyGreen), (.melbourne, melbourneBlue), (.hobart, hobartTeal), (.wollongong, wollongongOrange)
        ]
        var colors: [String: UInt32] = [:]
        for moment in moments {
            guard let coordinate = moment.coordinate,
                  let colour = cityColours.first(where: { $0.0.coordinate.distance(to: coordinate) < 25_000 })?.1
            else { continue }
            colors[moment.coverID] = colour
        }
        return FixtureColorSampler(colors: colors)
    }

    static func run(
        _ scenario: Scenario,
        moments: [PhotoMoment]? = nil,
        frozen: [FrozenEra] = [],
        now: Date? = nil,
        config: EraBuildConfig = .standard
    ) async -> EraPipelineResult {
        let moments = moments ?? scenario.moments
        let pipeline = EraPipeline(namer: FixturePlaceNamer(), sampler: sampler(for: moments), config: config)
        return await pipeline.run(
            moments: moments,
            plays: scenario.plays,
            frozen: frozen,
            now: now ?? scenario.now,
            calendar: scenario.calendar
        )
    }

    /// The frozen eras of a result, as they would be saved.
    static func frozen(_ result: EraPipelineResult) -> [FrozenEra] {
        result.eras.filter(\.isFrozen).map(\.frozen)
    }
}

extension EraPipelineResult {
    var titles: [String] { eras.map(\.content.title) }
    var kinds: [EraKind] { eras.map(\.draft.kind) }
}
