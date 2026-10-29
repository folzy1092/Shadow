"""Source contracts: a forward of a protected (noforwards) or secret message never reaches the server as a native forward."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SUB = ROOT / "submodules"


def read(path):
    return (SUB / path).read_text(encoding="utf-8")


class ProtectedForwardContracts(unittest.TestCase):
    def test_needs_copy_uses_server_flags(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowProtectedCopy.swift")
        needs = core.split("public static func needsCopy(_ message: Message)", 1)[1].split("}", 1)[0]
        # Not isCopyProtected(): «allow save» forces that to false.
        self.assertIn("message.isServerCopyProtected()", needs)
        self.assertIn("message.containsSecretMedia", needs)
        self.assertNotIn("isCopyProtected()", needs)

    def test_enqueue_messages_replaces_protected_forwards(self):
        enqueue = read("TelegramCore/Sources/PendingMessages/EnqueueMessage.swift")
        public = enqueue.split("public func enqueueMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage])", 1)[1].split("\n}\n", 1)[0].replace("\r\n", "\n")
        self.assertIn("ShadowProtectedCopy.needsCopy(sourceMessage)", public)
        self.assertIn("ShadowProtectedCopy.replacingProtectedForwards(account: account", public)
        # Unprotected sends keep the stock path.
        self.assertIn("if protectedSources.isEmpty {\n            return ayuEnqueueMessages(", public)
        # One id per input message, in order.
        self.assertIn("result.append(nil)", public)

    def test_copies_keep_send_options_and_correlation(self):
        core = read("TelegramCore/Sources/AyuGram/ShadowProtectedCopy.swift")
        replacing = core.split("static func replacingProtectedForwards", 1)[1].split("private enum Source", 1)[0]
        self.assertIn("!(attribute is ForwardOptionsMessageAttribute)", replacing)
        self.assertIn("correlationIds[copyIndex] = correlationId", replacing)
        self.assertIn("threadId = forwardThreadId", replacing)

    def test_chat_forward_switches_to_copy_by_itself(self):
        forward = read("TelegramUI/Sources/ChatControllerForwardMessages.swift")
        self.assertIn("let asCopy = asCopy || ShadowProtectedCopy.needsCopy(messages)", forward)

    def test_share_sheet_in_the_app_goes_through_enqueue_messages(self):
        # In the main app ShareController uses shareLegacy (enqueueMessages), so
        # the net covers gallery, profile media and search shares.
        share = read("ShareController/Sources/ShareController.swift")
        self.assertIn("if self.environment.isMainApp {\n                useLegacy = true", share.replace("\r\n", "\n"))
        legacy = share.split("private func shareLegacy(", 1)[1]
        self.assertIn("enqueueMessages(account: currentContext.context.account", legacy)


if __name__ == "__main__":
    unittest.main()
