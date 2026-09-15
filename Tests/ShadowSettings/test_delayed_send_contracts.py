"""Source contracts for Ghost-mode scheduled-send composer behaviour."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CORE = (ROOT / "submodules/TelegramCore/Sources/AyuGram/AyuDelayedSend.swift").read_text()
CHAT = (ROOT / "submodules/TelegramUI/Sources/ChatControllerNode.swift").read_text()
CHAT_CONTROLLER = (ROOT / "submodules/TelegramUI/Sources/ChatController.swift").read_text()
MEDIA_RECORDING = (ROOT / "submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift").read_text()


class DelayedSendContracts(unittest.TestCase):
    def test_ui_and_transform_share_one_eligibility_gate(self):
        self.assertIn("public static func willAutomaticallySchedule", CORE)
        transform = CORE.split("public static func transform", 1)[1]
        self.assertIn("guard willAutomaticallySchedule(messages: messages, peerId: peerId)", transform)

    def test_existing_send_semantics_are_not_overridden(self):
        gate = CORE.split("public static func willAutomaticallySchedule", 1)[1].split("private static func messageHasMedia", 1)[0]
        self.assertIn("effectiveSendViaScheduled", gate)
        self.assertIn("peerSupportsScheduling(peerId)", gate)
        self.assertIn("!hasOverridingAttribute(message.attributes)", gate)

    def test_only_automatic_scheduling_uses_immediate_clear(self):
        send = CHAT.split("let doSend: (Int64?) -> Void", 1)[1].split("var targetThreadId", 1)[0]
        self.assertIn("scheduleTime == nil, repeatPeriod == nil, !postpone", send)
        self.assertIn("AyuDelayedSend.willAutomaticallySchedule", send)
        self.assertIn("if !shouldClearInputImmediately", send)

    def test_composer_clears_after_enqueue_call(self):
        send = CHAT.split("let doSend: (Int64?) -> Void", 1)[1].split("var targetThreadId", 1)[0]
        enqueue = send.index("self.sendMessages(messages")
        immediate_clear = send.index("clearInputAfterSend()", enqueue)
        self.assertLess(enqueue, immediate_clear)
        self.assertIn('textInputPanelNode.text = ""', send)

    def test_automatic_schedule_does_not_leave_transition_waiting(self):
        send = CHAT.split("let doSend: (Int64?) -> Void", 1)[1].split("var targetThreadId", 1)[0]
        self.assertIn("if !shouldClearInputImmediately, !messages.isEmpty", send)

    def test_attachment_media_voice_and_round_video_clear_the_same_draft(self):
        self.assertIn("func clearGhostScheduledDraft()", CHAT_CONTROLLER)
        self.assertIn("withUpdatedMediaDraftState(nil)", CHAT_CONTROLLER)
        self.assertIn("withUpdatedComposeDisableUrlPreviews([])", CHAT_CONTROLLER)

        attachment_source = CHAT_CONTROLLER.split("private func commitEnqueueMediaMessages", 1)[1]
        attachment_send = attachment_source.split("let doSend: (Int64?) -> Void", 1)[1].split("if let targetThreadId", 1)[0]
        self.assertIn("shouldClearGhostScheduledDraft", attachment_send)
        self.assertIn("strongSelf.clearGhostScheduledDraft()", attachment_send)
        self.assertIn("completionImpl?()", attachment_send)

        self.assertGreaterEqual(MEDIA_RECORDING.count("AyuDelayedSend.willAutomaticallySchedule"), 3)
        self.assertGreaterEqual(MEDIA_RECORDING.count("clearGhostScheduledDraft()"), 3)


if __name__ == "__main__":
    unittest.main()
