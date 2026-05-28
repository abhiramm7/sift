import Foundation

struct PrefsEntry: Codable, Hashable {
    var rating: Int?
    var saved: Bool = false
    var hidden: Bool = false
    var read: Bool = false
    var updated_at: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try? c.decodeIfPresent(Int.self, forKey: .rating)
        saved = (try? c.decode(Bool.self, forKey: .saved)) ?? false
        hidden = (try? c.decode(Bool.self, forKey: .hidden)) ?? false
        read = (try? c.decode(Bool.self, forKey: .read)) ?? false
        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
    }

    init() {}

    /// Match Python `_flush_to_icloud`: always emit all five keys, with `null`
    /// for missing rating/updated_at, so the file shape stays identical.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rating, forKey: .rating)
        try c.encode(saved, forKey: .saved)
        try c.encode(hidden, forKey: .hidden)
        try c.encode(read, forKey: .read)
        try c.encode(updated_at, forKey: .updated_at)
    }

    enum CodingKeys: String, CodingKey {
        case rating, saved, hidden, read, updated_at
    }
}

typealias PrefsMap = [String: PrefsEntry]
