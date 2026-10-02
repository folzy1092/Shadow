import Foundation

// Shadow: URL entities for quick links (ShadowLinks) so the chat draws and
// taps them like web links. Ranges already covered by an entity (for example
// a tg:// link the server marked itself) are left alone.
public extension ShadowLinks {
    static func addingLinkEntities(text: String, to entities: [MessageTextEntity]?) -> [MessageTextEntity]? {
        let ranges = self.ranges(in: text)
        if ranges.isEmpty {
            return entities
        }
        var result = entities ?? []
        for range in ranges {
            if result.contains(where: { $0.range.overlaps(range) }) {
                continue
            }
            result.append(MessageTextEntity(range: range, type: .Url))
        }
        return result
    }
}
