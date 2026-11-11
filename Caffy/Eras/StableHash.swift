import Foundation

/// A hash that gives the same number for the same text on every device and
/// every launch.
///
/// Swift's `hashValue` is randomly seeded each time the app starts, so it must
/// never decide anything the user can see. Anything chosen "at random but
/// always the same" (a title's wording, a fallback palette) uses this instead.
nonisolated enum StableHash {
    /// The 64-bit FNV-1a hash of `text`'s UTF-8 bytes.
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            // `&*=` multiplies and wraps around on overflow, as FNV expects.
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// An index in `0..<count`, always the same for the same `key`.
    static func index(for key: String, count: Int) -> Int {
        precondition(count > 0, "Can't pick from an empty list")
        return Int(fnv1a64(key) % UInt64(count))
    }
}
