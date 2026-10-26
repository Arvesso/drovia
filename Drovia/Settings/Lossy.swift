import Foundation

/// Decodes an array element that may fail (written by a newer version, or damaged) as `nil`,
/// so one bad element doesn't lose the whole array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
