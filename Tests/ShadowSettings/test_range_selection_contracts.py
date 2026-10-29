"""Source contracts: «Диапазон» in the chat's selection panel (2.0.0)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class RangeSelectionContracts(unittest.TestCase):
    def test_core_scans_stored_history(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowRangeSelection.swift")
        self.assertIn("transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud", core)
        self.assertIn("threadId == nil || message.threadId == threadId", core)
        for case in ("case between(", "case toNewest(", "case toOldest("):
            self.assertIn(case, core)

    def test_panel_button_and_hook(self):
        panel = read("TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift")
        self.assertIn("self.interfaceInteraction?.shadowSelectRange?(self.rangeButton)", panel)
        self.assertIn("visibleButtons.insert(self.rangeButton", panel)
        interaction = read("ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift")
        self.assertIn("public var shadowSelectRange: ((UIView) -> Void)?", interaction)
        setup = read("TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift")
        self.assertIn("self?.shadowSelectRange(sourceView: sourceView)", setup)

    def test_one_or_many(self):
        tools = read("TelegramUI/Sources/Chat/ShadowChatTools.swift")
        selection = tools.split("func shadowSelectRange(sourceView: UIView)", 1)[1]
        self.assertIn("if ids.count >= 2 {", selection)
        self.assertIn('"До самого нового"', selection)
        self.assertIn('"До начала переписки"', selection)
        self.assertIn("withUpdatedSelectedMessages(ids)", selection)

    def test_core_sends_in_chunks_of_100(self):
        # No client cap on the selection: forwards and deletes are split by the core.
        pending = read("TelegramCore/Sources/State/PendingMessageManager.swift")
        self.assertIn("let forwardGroupLimit = 100", pending)
        delete = read("TelegramCore/Sources/State/ManagedCloudChatRemoveMessagesOperations.swift")
        self.assertIn("stride(from: 0, to: operation.messageIds.count, by: 100)", delete)


if __name__ == "__main__":
    unittest.main()
