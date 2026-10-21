from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCREEN = ROOT / "submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources"
NEO = ROOT / "submodules/Camera/CameraNeo/Sources"
LEGACY = ROOT / "submodules/Camera/CameraLegacy/Sources"
MEDIA_RECORDING = ROOT / "submodules/TelegramUI/Sources/Chat/ChatControllerMediaRecording.swift"


def read(path):
    return path.read_text(encoding="utf-8")


class RoundVideoCameraContracts(unittest.TestCase):
    def test_both_cameras_start_on_the_configured_side(self):
        # "Кружки на заднюю камеру": the screen picks the side once, and both
        # pipelines must record from it from the very first frame.
        screen = read(SCREEN / "VideoMessageCameraScreen.swift")
        self.assertIn("let isFrontPosition = !ayuGramSettingsCurrent.roundVideoUseBackCamera", screen)
        self.assertIn("position: isFrontPosition ? .front : .back", screen)
        self.assertIn("position: self.cameraState.position,", screen)

        neo = read(NEO / "CameraNeo.swift")
        self.assertIn("self.positionValue = Atomic<Camera.Position>(value: configuration.position)", neo)
        self.assertIn("self.singleMediaPosition = configuration.position", neo)
        self.assertIn("initialPosition: self.positionValue.with { $0 }", neo)
        self.assertIn("configureSingleCameraVideo(position: self.positionValue.with { $0 }, addOutput: true)", neo)
        recorder = read(NEO / "VideoRecorder.swift")
        self.assertIn("self.activePosition = initialPosition", recorder)

        legacy = read(LEGACY / "LegacyCamera.swift")
        self.assertIn("self.mainDeviceContext?.output.markPositionChange(position: self.positionValue)", legacy)

    def test_a_failed_stop_never_leaves_the_screen_waiting(self):
        screen = read(SCREEN / "VideoMessageCameraScreen.swift")
        stop = screen.split("func stopVideoRecording() {", 1)[1].split("func lockVideoRecording()", 1)[0]
        self.assertIn("timeout(10.0, queue: Queue.mainQueue(), alternate: .single(.failed))", stop)
        self.assertIn("controller.node.shadowRecordingFailed()", stop)
        self.assertIn("completed:", stop)
        # A stop inside the 0.5 s debounce is postponed, not dropped.
        self.assertIn("Queue.mainQueue().after(0.5 - (currentTimestamp - lastActionTimestamp))", stop)

        failed = screen.split("fileprivate func shadowRecordingFailed()", 1)[1].split("func addCaptureResult(", 1)[0]
        self.assertIn("self.resultsPipe.putNext(nil)", failed)
        self.assertLess(failed.index("self.resultsPipe.putNext(nil)"), failed.index("controller.completion(nil, nil, nil, nil)"))
        self.assertIn("controller.updateCameraState({ $0.updatedRecording(.none) }", failed)
        self.assertIn("ValuePipe<VideoMessageCameraScreen.CaptureResult?>()", screen)
        self.assertIn("if let next {", screen)

    def test_camera_neo_failure_falls_back_to_the_old_camera(self):
        screen = read(SCREEN / "VideoMessageCameraScreen.swift")
        self.assertIn("!ShadowRoundVideoCameraFallback.prefersLegacyCamera", screen)
        self.assertIn("ShadowRoundVideoCameraFallback.noteModernCameraFailure()", screen)
        self.assertIn("controller.node.shadowNoteCameraFailure()", screen)
        fallback = read(SCREEN / "ShadowRoundVideoCameraFallback.swift")
        self.assertIn('"CFBundleVersion"', fallback)
        self.assertIn("failedBuild == Self.currentBuild", fallback)

    def test_camera_neo_never_blocks_the_main_thread_on_release(self):
        # Cancel/Send close the screen and release the camera on the main
        # thread; the stock deinit waited on the session and media queues there
        # and froze the app.
        neo = read(NEO / "CameraNeo.swift")
        deinit = neo.split("    deinit {", 1)[1].split("\n    }\n", 1)[0]
        code = "\n".join(line for line in deinit.splitlines() if not line.strip().startswith("//"))
        self.assertNotIn(".sync", code)
        self.assertIn("self.sessionQueue.async {", deinit)
        self.assertIn("self.mediaQueue.async {", deinit)
        self.assertNotIn("self.", deinit.split("self.sessionQueue.async {", 1)[1].split("if let recorder", 1)[0])
        for source in (NEO).glob("*.swift"):
            self.assertNotIn("DispatchQueue.main.sync", read(source), source.name)
            self.assertNotIn(".sync(", read(source), source.name)

    def test_a_freeze_on_camera_neo_falls_back_to_the_old_camera(self):
        screen = read(SCREEN / "VideoMessageCameraScreen.swift")
        self.assertIn("ShadowRoundVideoCameraFallback.beginModernSession()", screen)
        dismiss = screen.split("fileprivate func requestDismiss(animated: Bool)", 1)[1].split("override public func containerLayoutUpdated", 1)[0]
        self.assertIn("ShadowRoundVideoCameraFallback.endModernSession()", dismiss)
        fallback = read(SCREEN / "ShadowRoundVideoCameraFallback.swift")
        self.assertIn("parts[1] != Self.launchId", fallback)
        self.assertIn("Self.noteModernCameraFailure()", fallback)

    def test_chat_drops_the_dead_round_draft(self):
        media = read(MEDIA_RECORDING)
        failed = media.split("guard var message else {", 1)[1].split("let replyMessageSubject", 1)[0]
        self.assertIn("withUpdatedMediaDraftState(nil)", failed)
        self.assertIn("self.recorderDataDisposable.set(nil)", failed)
        short = media.split("if data.duration < 1.0 {", 1)[1].split("} else {", 1)[0]
        self.assertIn("withUpdatedMediaDraftState(nil)", short)


if __name__ == "__main__":
    unittest.main()
