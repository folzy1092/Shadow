import SwiftSignalKit
import TelegramCore

// Keep the Shadow username preference pipeline cheap for the Swift constraint
// solver. ChatListNode consumes these settings as a Bool tuple; providing exact
// overloads avoids forcing the compiler to infer the full generic pipeline in
// one expression.
func map(_ transform: @escaping (AyuGramSettings) -> (Bool, Bool)) -> (Signal<AyuGramSettings, NoError>) -> Signal<(Bool, Bool), NoError> {
    return SwiftSignalKit.map(transform)
}

func distinctUntilChanged(isEqual: @escaping ((Bool, Bool), (Bool, Bool)) -> Bool) -> (Signal<(Bool, Bool), NoError>) -> Signal<(Bool, Bool), NoError> {
    return SwiftSignalKit.distinctUntilChanged(isEqual: isEqual)
}
