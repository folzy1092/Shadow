import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
//import PhoneNumberFormat

public extension EnginePeer {
    func shadowUsername(accountPeerId: EnginePeer.Id, isContact: Bool?, enabled: Bool) -> String? {
        guard case .user = self, !self.id.isRepliesOrVerificationCodes else { return nil }
        return ShadowPeerName.username(self.addressName, enabled: enabled, isContact: isContact, isSelf: self.id == accountPeerId)
    }

    func shadowDisplayTitle(strings: PresentationStrings, displayOrder: PresentationPersonNameOrder, accountPeerId: EnginePeer.Id, isContact: Bool?, enabled: Bool) -> String {
        return self.shadowUsername(accountPeerId: accountPeerId, isContact: isContact, enabled: enabled)
            ?? self.displayTitle(strings: strings, displayOrder: displayOrder)
    }

    var compactDisplayTitle: String {
        switch self {
        case let .user(user):
            if let firstName = user.firstName, !firstName.isEmpty {
                return firstName
            } else if let lastName = user.lastName, !lastName.isEmpty {
                return lastName
            } else if let _ = user.phone {
                return "" //formatPhoneNumber("+\(phone)")
            } else {
                return "Deleted Account"
            }
        case let .legacyGroup(group):
            return group.title
        case let .channel(channel):
            return channel.title
        case let .community(community):
            return community.title
        case .secretChat:
            return ""
        }
    }

    func displayTitle(strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> String {
        switch self {
        case let .user(user):
            if user.id.isReplies {
                return strings.DialogList_Replies
            }
            if let firstName = user.firstName, !firstName.isEmpty {
                if let lastName = user.lastName, !lastName.isEmpty {
                    switch displayOrder {
                    case .firstLast:
                        return "\(firstName) \(lastName)"
                    case .lastFirst:
                        return "\(lastName) \(firstName)"
                    }
                } else {
                    return firstName
                }
            } else if let lastName = user.lastName, !lastName.isEmpty {
                return lastName
            } else if let _ = user.phone {
                return "" //formatPhoneNumber("+\(phone)")
            } else {
                return strings.User_DeletedAccount
            }
        case let .legacyGroup(group):
            return group.title
        case let .channel(channel):
            return channel.title
        case let .community(community):
            return community.title
        case .secretChat:
            return ""
        }
    }
}

public extension EnginePeer.IndexName {
    func isLessThan(other: EnginePeer.IndexName, ordering: PresentationPersonNameOrder) -> ComparisonResult {
        switch self {
        case let .title(lhsTitle, _):
            let rhsString: String
            switch other {
            case let .title(title, _):
                rhsString = title
            case let .personName(first, last, _, _):
                switch ordering {
                case .firstLast:
                    if first.isEmpty {
                        rhsString = last
                    } else {
                        rhsString = first + last
                    }
                case .lastFirst:
                    if last.isEmpty {
                        rhsString = first
                    } else {
                        rhsString = last + first
                    }
                }
            }
            return lhsTitle.caseInsensitiveCompare(rhsString)
        case let .personName(lhsFirst, lhsLast, _, _):
            let lhsString: String
            switch ordering {
            case .firstLast:
                if lhsFirst.isEmpty {
                    lhsString = lhsLast
                } else {
                    lhsString = lhsFirst + lhsLast
                }
            case .lastFirst:
                if lhsLast.isEmpty {
                    lhsString = lhsFirst
                } else {
                    lhsString = lhsLast + lhsFirst
                }
            }
            let rhsString: String
            switch other {
            case let .title(title, _):
                rhsString = title
            case let .personName(first, last, _, _):
                switch ordering {
                case .firstLast:
                    if first.isEmpty {
                        rhsString = last
                    } else {
                        rhsString = first + last
                    }
                case .lastFirst:
                    if last.isEmpty {
                        rhsString = first
                    } else {
                        rhsString = last + first
                    }
                }
            }
            return lhsString.caseInsensitiveCompare(rhsString)
        }
    }
}
