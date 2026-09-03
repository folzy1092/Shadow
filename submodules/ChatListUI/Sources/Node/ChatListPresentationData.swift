import Foundation
import UIKit
import TelegramPresentationData
import TelegramUIPreferences

public final class ChatListPresentationData {
    public let theme: PresentationTheme
    public let fontSize: PresentationFontSize
    public let strings: PresentationStrings
    public let dateTimeFormat: PresentationDateTimeFormat
    public let nameSortOrder: PresentationPersonNameOrder
    public let nameDisplayOrder: PresentationPersonNameOrder
    public let disableAnimations: Bool
    public let preferUsernameForNonContacts: Bool
    
    public init(theme: PresentationTheme, fontSize: PresentationFontSize, strings: PresentationStrings, dateTimeFormat: PresentationDateTimeFormat, nameSortOrder: PresentationPersonNameOrder, nameDisplayOrder: PresentationPersonNameOrder, disableAnimations: Bool, preferUsernameForNonContacts: Bool = false) {
        self.theme = theme
        self.fontSize = fontSize
        self.strings = strings
        self.dateTimeFormat = dateTimeFormat
        self.nameSortOrder = nameSortOrder
        self.nameDisplayOrder = nameDisplayOrder
        self.disableAnimations = disableAnimations
        self.preferUsernameForNonContacts = preferUsernameForNonContacts
    }

    public func withPreferUsernameForNonContacts(_ enabled: Bool) -> ChatListPresentationData {
        return ChatListPresentationData(theme: self.theme, fontSize: self.fontSize, strings: self.strings, dateTimeFormat: self.dateTimeFormat, nameSortOrder: self.nameSortOrder, nameDisplayOrder: self.nameDisplayOrder, disableAnimations: self.disableAnimations, preferUsernameForNonContacts: enabled)
    }
}
