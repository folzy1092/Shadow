import Foundation
import TelegramCore
import TelegramUIPreferences
import AccountContext
import TelegramStringFormatting
import LocalizedPeerData
import TelegramPresentationData
import TextFormat

// Shadow: «Ответить» on a message anti-delete kept (DeletedMessageAttribute).
// The server no longer has it, so a real reply would fail. Instead, like
// AyuGram, the input gets the author's name — a t.me link when the author
// has a username, otherwise a text mention — and the message's text as a
// quote under it.
enum ShadowDeletedReplyQuote {
    static func isKeptDeleted(_ message: EngineMessage) -> Bool {
        return message._asMessage().attributes.contains(where: { $0 is DeletedMessageAttribute })
    }

    static func authorString(_ author: EnginePeer?, fallbackTitle: String, strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> NSAttributedString {
        guard let author else {
            return NSAttributedString(string: fallbackTitle)
        }
        let title = author.displayTitle(strings: strings, displayOrder: displayOrder)
        let result = NSMutableAttributedString(string: title.isEmpty ? fallbackTitle : title)
        let range = NSRange(location: 0, length: result.length)
        if let username = author.addressName, !username.isEmpty {
            result.addAttribute(ChatTextInputAttributes.textUrl, value: ChatTextInputTextUrlAttribute(url: "https://t.me/\(username)"), range: range)
        } else if case .user = author {
            result.addAttribute(ChatTextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: author.id), range: range)
        }
        return result
    }

    static func inputText(message: EngineMessage, author: EnginePeer?, mediaDescription: String, strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(authorString(author, fallbackTitle: strings.User_DeletedAccount, strings: strings, displayOrder: displayOrder))
        result.append(NSAttributedString(string: ":\n"))

        let body: NSAttributedString
        if !message.text.isEmpty {
            // Inner blockquotes would end the outer quote early: keep the rest.
            let entities = (message.textEntitiesAttribute?.entities ?? []).filter { entity in
                switch entity.type {
                case .BlockQuote, .Pre:
                    return false
                default:
                    return true
                }
            }
            body = chatInputStateStringWithAppliedEntities(message.text, entities: entities)
        } else {
            body = NSAttributedString(string: mediaDescription)
        }
        let quoteStart = result.length
        result.append(body)
        if result.length > quoteStart {
            result.addAttribute(ChatTextInputAttributes.block, value: ChatTextInputTextQuoteAttribute(kind: .quote, isCollapsed: false), range: NSRange(location: quoteStart, length: result.length - quoteStart))
        }
        result.append(NSAttributedString(string: "\n"))
        return result
    }
}

extension ChatControllerImpl {
    // Kept out of setupReplyMessage's closure: the interface interaction's
    // initializer is already near the type checker's limit.
    func shadowQuoteKeptDeletedMessage(_ message: EngineMessage) {
        let presentationData = self.presentationData
        let contentSettings = self.context.currentContentSettings.with { $0 }
        let mediaDescription: String = descriptionStringForMessage(contentSettings: contentSettings, message: message, strings: presentationData.strings, nameDisplayOrder: presentationData.nameDisplayOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: self.context.account.peerId).0.string
        let quote: NSAttributedString = ShadowDeletedReplyQuote.inputText(message: message, author: message.author, mediaDescription: mediaDescription, strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        self.interfaceInteraction?.updateTextInputStateAndMode { state, mode in
            let text = NSMutableAttributedString(attributedString: quote)
            text.append(state.inputText)
            return (ChatTextInputState(inputText: text, selectionRange: text.length ..< text.length), mode)
        }
        if !self.chatDisplayNode.ensureInputViewFocused() {
            DispatchQueue.main.async { [weak self] in
                self?.chatDisplayNode.ensureInputViewFocused()
            }
        }
    }
}
