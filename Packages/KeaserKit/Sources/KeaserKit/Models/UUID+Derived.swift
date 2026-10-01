import Foundation

extension UUID {
    /// A UUID made from `text` alone: the same text gives the same UUID on
    /// every device, platform and run. Two devices that make the same
    /// built-in item for the same account (the default income categories)
    /// then make the same IDs, so iCloud sync sees one item, not two.
    ///
    /// The 128 bits are two FNV-1a 64-bit hashes of the UTF-8 bytes, with
    /// the two halves of the FNV-128 offset basis as their starting values,
    /// marked as an RFC 9562 version 8 (custom) UUID.
    static func derived(from text: String) -> UUID {
        let bytes = Array(text.utf8)
        func fnv1a(_ basis: UInt64) -> UInt64 {
            var hash = basis
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return hash
        }
        let high = fnv1a(0x6C62_272E_07BB_0142)
        let low = fnv1a(0x62B8_2175_6295_C58D)
        var u = (0..<8).map { UInt8(truncatingIfNeeded: high >> (56 - 8 * $0)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: low >> (56 - 8 * $0)) }
        u[6] = (u[6] & 0x0F) | 0x80 // version 8
        u[8] = (u[8] & 0x3F) | 0x80 // variant 10
        return UUID(uuid: (
            u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
            u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]
        ))
    }
}
