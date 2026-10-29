import Foundation
import UIKit
import SwiftUI
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext
import TextFormat
import ChatPresentationInterfaceState

// Shadow 2.0.0: «Панель форматирования» (ShadowInputToolbar), ported from
// Swiftgram's SGInputToolbar (Swiftgram/SGInputToolbar, MIT-style fork code):
// a horizontally scrolling row of round glass buttons under the input field,
// shown while the field has focus. The buttons come from
// AyuGramSettings.inputToolbarButtons; a formatting button with nothing
// selected formats the word before the caret.

final class ShadowInputToolbarModel: ObservableObject {
    @Published var buttons: [ShadowInputToolbar.Button]
    @Published var translationActive: Bool

    init(buttons: [ShadowInputToolbar.Button], translationActive: Bool) {
        self.buttons = buttons
        self.translationActive = translationActive
    }
}

@available(iOS 13.0, *)
struct ShadowInputToolbarView: View {
    @ObservedObject var model: ShadowInputToolbarModel
    let onAction: (ShadowInputToolbar.Button) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(self.model.buttons, id: \.rawValue) { button in
                    Button(action: { self.onAction(button) }) {
                        ShadowInputToolbarLabel(button: button, isActive: button == .translate && self.model.translationActive)
                    }
                    .buttonStyle(ShadowInputToolbarButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .background(Color(UIColor.clear))
    }
}

@available(iOS 13.0, *)
private struct ShadowInputToolbarLabel: View {
    let button: ShadowInputToolbar.Button
    let isActive: Bool

    var body: some View {
        Group {
            if let icon = self.button.icon {
                Image(systemName: self.isActive ? "character.bubble.fill" : icon)
            } else {
                Text("M").font(.system(size: 17.0, weight: .regular, design: .monospaced)).foregroundColor(Color.primary)
            }
        }
        .foregroundColor(self.isActive ? Color.accentColor : Color.primary)
    }
}

// Swiftgram's glass circle: a thin material with a hairline and a soft shadow.
@available(iOS 13.0, *)
private struct ShadowInputToolbarGlass: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = self.colorScheme == .dark
        return Group {
            if #available(iOS 15.0, *) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(isDark ? 0.05 : 0.25)))
            } else {
                Circle()
                    .fill(Color.clear)
                    .background(ShadowInputToolbarBlur(style: .systemThinMaterial).clipShape(Circle()))
                    .overlay(Circle().fill(Color.white.opacity(isDark ? 0.05 : 0.25)))
            }
        }
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}

@available(iOS 13.0, *)
private struct ShadowInputToolbarBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: self.style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: self.style)
    }
}

@available(iOS 13.0, *)
private struct ShadowInputToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 39

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: self.size, height: self.size)
            .contentShape(Circle())
            .background(ShadowInputToolbarGlass())
            .overlay(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(nil, value: configuration.isPressed)
    }
}

extension ChatTextInputPanelNode {
    static let shadowToolbarHeight: CGFloat = 44.0
    static let shadowToolbarSpacing: CGFloat = 6.0

    // Creates the row on first use and keeps its buttons in step with settings.
    func shadowUpdateToolbarIfNeeded(context: AccountContext) {
        guard #available(iOS 13.0, *) else {
            return
        }
        let settings = currentAyuGramSettings(accountId: context.account.id)
        guard settings.inputToolbar else {
            if let node = self.shadowToolbarNode {
                node.removeFromSupernode()
                self.shadowToolbarNode = nil
                self.shadowToolbarModel = nil
            }
            return
        }
        let buttons = ShadowInputToolbar.parseButtons(settings.inputToolbarButtons)
        let translationActive = ShadowInputTranslation.activeTemplate != nil
        if let model = self.shadowToolbarModel {
            if model.buttons != buttons {
                model.buttons = buttons
            }
            if model.translationActive != translationActive {
                model.translationActive = translationActive
            }
            return
        }
        let model = ShadowInputToolbarModel(buttons: buttons, translationActive: translationActive)
        let view = ShadowInputToolbarView(model: model, onAction: { [weak self] button in
            self?.shadowToolbarAction(button)
        })
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = .clear
        // As in Swiftgram the hosting controller is not kept: keeping it broke
        // the row's touch handling and layout; the node keeps its view.
        let node = ASDisplayNode(viewBlock: { hostingController.view })
        self.shadowToolbarModel = model
        self.shadowToolbarNode = node
        // A swipe that starts on the row scrolls it instead of going back
        // (true: «this point has its own horizontal gesture»). Swiftgram has
        // this inverted, which blocked going back from anywhere on the panel.
        self.view.interactiveTransitionGestureRecognizerTest = { [weak self] point in
            if let self, let toolbarNode = self.shadowToolbarNode, toolbarNode.alpha > 0.0, toolbarNode.frame.contains(point) {
                return true
            }
            return false
        }
        self.addSubnode(node)
    }

    // Lays the row out under the panel and returns the height it adds.
    func shadowLayoutToolbar(transition: ContainedViewLayoutTransition, panelHeight: CGFloat, width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, displayBotStartButton: Bool) -> CGFloat {
        guard let node = self.shadowToolbarNode else {
            return 0.0
        }
        if displayBotStartButton || !self.isFocused {
            transition.updateAlpha(node: node, alpha: 0.0)
            return 0.0
        }
        transition.updateFrame(node: node, frame: CGRect(origin: CGPoint(x: leftInset, y: panelHeight + ChatTextInputPanelNode.shadowToolbarSpacing), size: CGSize(width: max(0.0, width - rightInset - leftInset), height: ChatTextInputPanelNode.shadowToolbarHeight)))
        transition.updateAlpha(node: node, alpha: 1.0)
        return ChatTextInputPanelNode.shadowToolbarHeight + ChatTextInputPanelNode.shadowToolbarSpacing
    }

    private func shadowToolbarAction(_ button: ShadowInputToolbar.Button) {
        if let tool = button.tool {
            let sourceView = self.shadowToolbarNode?.view ?? self.view
            self.interfaceInteraction?.shadowRunChatTool?(tool, sourceView)
            return
        }
        if button.formatsSelection {
            self.shadowSelectLastWordIfIdle()
        }
        switch button {
        case .newLine:
            self.interfaceInteraction?.updateTextInputStateAndMode { current, inputMode in
                return (chatTextInputStateInsertingText(current, text: NSAttributedString(string: "\n")), inputMode)
            }
        case .clearFormatting:
            self.interfaceInteraction?.updateTextInputStateAndMode { current, inputMode in
                return (chatTextInputClearFormattingAttributes(current), inputMode)
            }
        case .quote:
            self.formatAttributesQuote(self)
        case .spoiler:
            self.formatAttributesSpoiler(self)
        case .bold:
            self.formatAttributesBold(self)
        case .italic:
            self.formatAttributesItalic(self)
        case .underline:
            self.formatAttributesUnderline(self)
        case .strikethrough:
            self.formatAttributesStrikethrough(self)
        case .monospace:
            self.formatAttributesMonospace(self)
        case .code:
            self.formatAttributesCodeBlock(self)
        case .link:
            self.formatAttributesLink(self)
        case .date:
            self.formatAttributesDate(self)
        case .translate, .mentionAll, .scrollToStart:
            break
        }
    }

    // Nothing selected: select the word before the caret, so a formatting
    // button acts on what was just typed (Swiftgram's sgSelectLastWordIfIdle).
    private func shadowSelectLastWordIfIdle() {
        self.interfaceInteraction?.updateTextInputStateAndMode { current, inputMode in
            let selection = current.selectionRange
            guard selection.isEmpty, let range = ShadowInputToolbar.lastWordRange(in: current.inputText.string, caret: selection.lowerBound) else {
                return (current, inputMode)
            }
            return (ChatTextInputState(content: current.content, selectionRange: range.location ..< (range.location + range.length)), inputMode)
        }
    }
}
