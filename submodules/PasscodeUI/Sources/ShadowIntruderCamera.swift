import Foundation
import UIKit
import AVFoundation
import TelegramCore

// Shadow: takes a front-camera photo after a wrong password (spec 7.2) and
// stores it in ShadowIntruderLog. Never asks for camera access here (that is
// done when the option is turned on): without access nothing is captured.
public final class ShadowIntruderCamera: NSObject, AVCapturePhotoCaptureDelegate {
    private static var active: ShadowIntruderCamera?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let reason: ShadowIntruderLog.Reason
    private let queue = DispatchQueue(label: "shadow.intruder.camera")

    private init(reason: ShadowIntruderLog.Reason) {
        self.reason = reason
        super.init()
    }

    public static func captureIfEnabled(reason: ShadowIntruderLog.Reason) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized, ShadowIntruderLog.shared.beginCapture() else {
            return
        }
        DispatchQueue.main.async {
            if self.active != nil {
                return
            }
            let camera = ShadowIntruderCamera(reason: reason)
            self.active = camera
            camera.start()
        }
    }

    private func start() {
        self.queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                self.finish()
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            // Give auto-exposure a moment, otherwise the first frame is dark.
            self.queue.asyncAfter(deadline: .now() + 0.8) {
                guard self.session.isRunning, !self.session.outputs.isEmpty else {
                    self.finish()
                    return
                }
                self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil, let data = photo.fileDataRepresentation() {
            var jpeg = data
            if let image = UIImage(data: data), let compressed = image.jpegData(compressionQuality: 0.7) {
                jpeg = compressed
            }
            ShadowIntruderLog.shared.save(jpeg: jpeg, reason: self.reason)
        }
        self.queue.async {
            self.finish()
        }
    }

    private func finish() {
        if self.session.isRunning {
            self.session.stopRunning()
        }
        DispatchQueue.main.async {
            ShadowIntruderCamera.active = nil
        }
    }
}
