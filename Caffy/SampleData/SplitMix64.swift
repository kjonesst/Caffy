import Foundation

/// A tiny seeded random number generator for fixtures.
///
/// The same seed always gives the same numbers, on every device and Swift
/// version. The helpers below do their own maths instead of using
/// `Double.random(in:using:)`, whose exact output the standard library
/// doesn't promise to keep.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in `0..<1`.
    mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// A number in `range`.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// A whole number in `range`.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    /// One element of a non-empty array.
    mutating func pick<T>(_ items: [T]) -> T {
        items[int(in: 0...(items.count - 1))]
    }
}
