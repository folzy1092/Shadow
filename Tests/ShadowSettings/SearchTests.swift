import Foundation

@main
struct SearchTests {
    static func main() {
        func finds(_ query: String, _ destination: ShadowSettingsSearchDestination, _ entryId: Int32) -> Bool {
            return ShadowSettingsSearchIndex.search(query).contains { $0.destination == destination && $0.entryId == entryId }
        }
        precondition(ShadowSettingsSearchIndex.search("").isEmpty)
        precondition(ShadowSettingsSearchIndex.search(" \n\t ").isEmpty)
        precondition(finds("призрак", .ghost, 1))
        precondition(finds("GHOST MODE", .ghost, 1))
        precondition(finds("ＧＨＯＳＴ", .ghost, 1))
        precondition(finds("удаленные", .spy, 1))
        precondition(finds("удалённые", .spy, 1))
        precondition(finds("read receipts", .ghost, 4))
        precondition(finds("нижняя компактная", .customization, 17))
        precondition(finds("export", .backup, 0))
        precondition(finds("импортировать", .backup, 1))
        precondition(ShadowSettingsSearchIndex.search("неттакогопункта123").isEmpty)
        let all = ShadowSettingsSearchIndex.items
        precondition(Set(all.map { $0.id }).count == all.count)
        precondition(all == all.sorted { $0.id < $1.id })
        precondition(all.first { $0.destination == .customization && $0.entryId == 6 }?.parentEntryId == 5)
        print("Shadow settings search: 15 checks passed")
    }
}
