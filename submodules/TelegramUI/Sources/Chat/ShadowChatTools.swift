import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import UndoUI
import TextFormat
import ChatInterfaceState
import ChatPresentationInterfaceState
import ContextUI
import PresentationDataUtils
import SettingsUI

// Shadow: chat tools (ShadowPaperclip.Tool), started from the paperclip menu
// or the formatting panel. Nothing here sends a message by itself.
extension ChatControllerImpl {
    func shadowRunChatTool(_ tool: ShadowPaperclip.Tool, sourceView: UIView?) {
        switch tool {
        case .scrollToStart:
            self.scrollToStartOfHistory()
        case .mentionAll:
            self.shadowInsertMentionAll()
        case .translate:
            self.shadowToggleInputTranslation(sourceView: sourceView)
        }
    }

    // «Упомянуть всех» is offered in groups only.
    var shadowCanMentionAll: Bool {
        guard let peer = self.presentationInterfaceState.renderedPeer?.peer else {
            return false
        }
        return ShadowMentionAll.isAvailable(peer: EnginePeer(peer))
    }

    // Inserts a mention of every member at the caret: @username when there is
    // one, otherwise the name as a text mention, which notifies its owner the
    // same way (as the stock mention autocomplete does).
    func shadowInsertMentionAll() {
        let presentationData = self.presentationData
        guard let peerId = self.chatLocation.peerId, self.shadowCanMentionAll else {
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "«Упомянуть всех» работает только в группах", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            return
        }
        let progress = UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Собираю участников…", timeout: 60.0, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
        self.present(progress, in: .current)

        let _ = (ShadowMentionAll.members(account: self.context.account, peerId: peerId)
        |> deliverOnMainQueue).startStandalone(next: { [weak self, weak progress] members in
            progress?.dismiss()
            guard let self else {
                return
            }
            guard !members.isEmpty else {
                self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Некого упоминать: в группе только ты и боты", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
                return
            }
            let text = shadowMentionsText(members)
            self.updateChatPresentationInterfaceState(animated: true, interactive: true, { state in
                return state.updatedInterfaceState { interfaceState in
                    let current = interfaceState.effectiveInputState
                    let selection = current.selectionRange
                    var insertion = text
                    // A space between the mentions and text right before the caret.
                    if selection.lowerBound > 0 {
                        let before = (current.inputText.string as NSString).substring(with: NSRange(location: selection.lowerBound - 1, length: 1))
                        if before != " " && before != "\n" {
                            let spaced = NSMutableAttributedString(string: " ")
                            spaced.append(insertion)
                            insertion = spaced
                        }
                    }
                    let updated = current.replacingFlatRange(NSRange(location: selection.lowerBound, length: selection.count), with: insertion)
                    return interfaceState.withUpdatedEffectiveInputState(updated)
                }
            })
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Вставлено упоминаний: \(members.count). Отправишь сам", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
        })
    }
}

// "@alice @bob Charlie " — Charlie without a username as a text mention.
func shadowMentionsText(_ members: [EnginePeer]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for peer in members {
        if let addressName = peer.addressName, !addressName.isEmpty {
            result.append(NSAttributedString(string: "@" + addressName))
        } else {
            let title = peer.compactDisplayTitle
            guard !title.isEmpty else {
                continue
            }
            result.append(NSAttributedString(string: title, attributes: [ChatTextInputAttributes.textMention: ChatTextInputTextMentionAttribute(peerId: peer.id)]))
        }
        result.append(NSAttributedString(string: " "))
    }
    return result
}

// MARK: «Перевод при отправке» (ShadowInputTranslation)

extension ChatControllerImpl {
    // On: off with a toast. Off: a compact menu of the pairs from settings;
    // the chosen one is active in every chat until turned off.
    func shadowToggleInputTranslation(sourceView: UIView?) {
        let context = self.context
        let presentationData = self.presentationData
        if let active = ShadowInputTranslation.activeTemplate {
            ShadowInputTranslation.activeTemplate = nil
            self.requestLayout(transition: .immediate)
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Перевод выключен (\(active.shortTitle))", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            return
        }
        let templates = ShadowInputTranslation.parseTemplates(currentAyuGramSettings(accountId: context.account.id).inputTranslateTemplates)
        guard !templates.isEmpty else {
            self.push(shadowInputTranslateTemplatesController(context: context))
            return
        }
        let choose: (ShadowInputTranslation.Template) -> Void = { [weak self] template in
            ShadowInputTranslation.activeTemplate = template
            guard let self else {
                return
            }
            self.requestLayout(transition: .immediate)
            self.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Перевод включён: \(template.title). Пиши как обычно — уйдёт перевод. Выключить — та же кнопка.", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
        }

        var items: [ContextMenuItem] = []
        for template in templates {
            items.append(.action(ContextMenuActionItem(text: template.title, icon: { theme in
                return generateTintedImage(image: UIImage(systemName: "character.bubble"), color: theme.contextMenu.primaryColor)
            }, action: { _, f in
                f(.default)
                choose(template)
            })))
        }
        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: "Шаблоны перевода", icon: { theme in
            return generateTintedImage(image: UIImage(systemName: "gearshape"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] _, f in
            f(.default)
            self?.push(shadowInputTranslateTemplatesController(context: context))
        })))

        if let sourceView {
            let contextController = makeContextController(presentationData: presentationData, source: .reference(ChatControllerContextReferenceContentSource(controller: self, sourceView: sourceView, insets: .zero, actionsOnTop: true)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
            self.presentInGlobalOverlay(contextController)
        } else {
            let sheet = ActionSheetController(presentationData: presentationData)
            var sheetItems: [ActionSheetItem] = [ActionSheetTextItem(title: "Перевод при отправке", parseMarkdown: false)]
            for template in templates {
                sheetItems.append(ActionSheetButtonItem(title: template.title, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    choose(template)
                }))
            }
            sheet.setItemGroups([ActionSheetItemGroup(items: sheetItems), ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])])
            self.present(sheet, in: .window(.root))
        }
    }

    // Texts typed in this chat are translated; business message editors
    // (custom chat contents) are not.
    func shadowHasTranslatableText(_ messages: [EnqueueMessage]) -> Bool {
        if case .customChatContents = self.subject {
            return false
        }
        return messages.contains { message in
            if case let .message(text, _, _, _, _, _, _, _, _, _) = message {
                return ShadowInputTranslation.isTranslatable(text)
            }
            return false
        }
    }

    // Translates every message text: plain text on the phone first (Apple
    // Translation, iOS 18+), else Telegram's server; formatted text on the
    // server first, which keeps the formatting and mentions. If a text cannot
    // be translated, asks whether to send it as written.
    func shadowTranslateOutgoing(_ messages: [EnqueueMessage], template: ShadowInputTranslation.Template, completion: @escaping ([EnqueueMessage]) -> Void) {
        let context = self.context
        let signals: [Signal<EnqueueMessage?, NoError>] = messages.map { message -> Signal<EnqueueMessage?, NoError> in
            guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, ShadowInputTranslation.isTranslatable(text) else {
                return .single(message)
            }
            let entities = (attributes.first(where: { $0 is TextEntitiesMessageAttribute }) as? TextEntitiesMessageAttribute)?.entities ?? []
            let rebuild: (String, [MessageTextEntity]) -> EnqueueMessage = { translated, translatedEntities in
                var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
                if !translatedEntities.isEmpty {
                    updatedAttributes.append(TextEntitiesMessageAttribute(entities: translatedEntities))
                }
                return .message(text: translated, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
            }
            let server: Signal<EnqueueMessage?, NoError> = context.engine.messages.translate(text: text, toLang: template.to, entities: entities)
            |> map { result -> EnqueueMessage? in
                return result.map { rebuild($0.0, $0.1) }
            }
            |> `catch` { _ -> Signal<EnqueueMessage?, NoError> in
                return .single(nil)
            }
            let local: Signal<EnqueueMessage?, NoError>
            if let service = engineExperimentalInternalTranslationService {
                local = service.translate(texts: [AnyHashable(0): text], fromLang: template.from, toLang: template.to)
                |> map { result -> EnqueueMessage? in
                    guard let translated = result?[AnyHashable(0)], !translated.isEmpty else {
                        return nil
                    }
                    return rebuild(translated, [])
                }
            } else {
                local = .single(nil)
            }
            let first = entities.isEmpty ? local : server
            let second = entities.isEmpty ? server : local
            return first
            |> take(1)
            |> mapToSignal { result -> Signal<EnqueueMessage?, NoError> in
                if let result {
                    return .single(result)
                }
                return second |> take(1)
            }
            |> timeout(20.0, queue: Queue.mainQueue(), alternate: .single(nil))
        }

        let _ = (combineLatest(signals)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] results in
            if !results.contains(where: { $0 == nil }) {
                completion(results.compactMap { $0 })
                return
            }
            guard let self else {
                return
            }
            self.present(textAlertController(context: context, title: "Не удалось перевести", text: "Перевод \(template.shortTitle) сейчас не получился. Отправить как написано?", actions: [
                TextAlertAction(type: .genericAction, title: "Не отправлять", action: { [weak self] in
                    // The text goes back into the input field.
                    for message in messages {
                        if case let .message(text, _, _, _, _, _, _, _, _, _) = message, ShadowInputTranslation.isTranslatable(text) {
                            self?.updateTextInputState(ChatTextInputState(inputText: NSAttributedString(string: text)))
                            break
                        }
                    }
                }),
                TextAlertAction(type: .defaultAction, title: "Отправить", action: {
                    completion(messages)
                })
            ]), in: .window(.root))
        })
    }
}
