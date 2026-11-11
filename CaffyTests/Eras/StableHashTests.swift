import Foundation
import Testing
@testable import Caffy

/// Tests for `StableHash`, which must give the same answer on every launch.
struct StableHashTests {
    /// Published FNV-1a 64-bit test vectors.
    @Test(arguments: [
        ("", 0xcbf2_9ce4_8422_2325 as UInt64),
        ("a", 0xaf63_dc4c_8601_ec8c),
        ("foobar", 0x8594_4171_f739_67e8)
    ])
    func matchesKnownValues(text: String, expected: UInt64) {
        #expect(StableHash.fnv1a64(text) == expected)
    }

    @Test func indexIsInRangeAndRepeatable() {
        for key in ["m0001", "m0002", "era-sydney-2026", ""] {
            let index = StableHash.index(for: key, count: 5)
            #expect((0..<5).contains(index))
            #expect(StableHash.index(for: key, count: 5) == index)
        }
    }

    @Test func differentKeysSpreadAcrossChoices() {
        let picks = Set((0..<100).map { StableHash.index(for: "m\($0)", count: 4) })
        #expect(picks == [0, 1, 2, 3])
    }
}
