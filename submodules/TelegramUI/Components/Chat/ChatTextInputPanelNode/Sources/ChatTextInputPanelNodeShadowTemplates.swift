import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext

// Shadow: local quick reply templates. The accessory button lists the templates
// stored in AyuGramSettings.quickReplyTemplates; picking one puts its text into
// the composer (it is not sent automatically).
extension ChatTextInputPanelNode {
    func shadowPresentQuickReplyTemplates() {
        guard let context = self.context, let interfaceInteraction = self.interfaceInteraction else {
            return
        }
        let templates = currentAyuGramSettings(accountId: context.account.id).quickReplyTemplates
        if templates.isEmpty {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: "Шаблоны ответов", parseMarkdown: false)]
        for template in templates {
            items.append(ActionSheetButtonItem(title: shadowQuickReplyTemplatePreview(template), color: .accent, action: { [weak actionSheet, weak interfaceInteraction] in
                actionSheet?.dismissAnimated()
                interfaceInteraction?.updateTextInputStateAndMode { _, inputMode in
                    return (ChatTextInputState(inputText: NSAttributedString(string: template)), inputMode)
                }
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        interfaceInteraction.presentController(actionSheet, nil)
    }
}

// One line, at most 60 characters, for the template list.
func shadowQuickReplyTemplatePreview(_ text: String) -> String {
    let singleLine = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    if singleLine.count <= 60 {
        return singleLine
    }
    return String(singleLine.prefix(59)) + "…"
}
