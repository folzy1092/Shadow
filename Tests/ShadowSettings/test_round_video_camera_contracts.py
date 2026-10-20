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

    def test_chat_drops_the_dead_round_draft(self):
        media = read(MEDIA_RECORDING)
        failed = media.split("guard var message else {", 1)[1].split("let replyMessageSubject", 1)[0]
        self.assertIn("withUpdatedMediaDraftState(nil)", failed)
        self.assertIn("self.recorderDataDisposable.set(nil)", failed)
        short = media.split("if data.duration < 1.0 {", 1)[1].split("} else {", 1)[0]
        self.assertIn("withUpdatedMediaDraftState(nil)", short)


if __name__ == "__main__":
    unittest.main()
