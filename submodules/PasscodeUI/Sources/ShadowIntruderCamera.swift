import Foundation
import UIKit
import AVFoundation
import Photos
import TelegramCore

// Shadow: takes a front-camera photo after a wrong password (spec 7.2), stores
// it in ShadowIntruderLog (sent to Saved Messages after the next unlock) and, at
// once, in the photo library. Never asks for access here (that is done when the
// option is turned on): without camera access nothing is captured, without
// photo-library access the photo only waits for Saved Messages.
public final class ShadowIntruderCamera: NSObject, AVCapturePhotoCaptureDelegate {
    private static var active: ShadowIntruderCamera?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let reason: ShadowIntruderLog.Reason
    private let queue = DispatchQueue(label: "shadow.intruder.camera")
    private var didSave = false

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
                ShadowIntruderLog.shared.endCapture()
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
            // save()/endCapture() end the capture whether or not a file was written.
            self.didSave = true
            let log = ShadowIntruderLog.shared
            if log.savesToGallery {
                ShadowIntruderCamera.saveToPhotoLibrary(jpeg: jpeg)
            }
            if log.sendsToSaved {
                log.save(jpeg: jpeg, reason: self.reason)
            } else {
                log.endCapture()
            }
        }
        self.queue.async {
            self.finish()
        }
    }

    // Owner-granted (when the option was turned on) add-only access; never prompts here.
    public static var canSaveToPhotoLibrary: Bool {
        if #available(iOS 14.0, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            return status == .authorized || status == .limited
        } else {
            return PHPhotoLibrary.authorizationStatus() == .authorized
        }
    }

    public static func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            })
        } else {
            PHPhotoLibrary.requestAuthorization({ status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            })
        }
    }

    private static func saveToPhotoLibrary(jpeg: Data) {
        guard self.canSaveToPhotoLibrary else {
            return
        }
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpeg, options: nil)
        }, completionHandler: nil)
    }

    private func finish() {
        if self.session.isRunning {
            self.session.stopRunning()
        }
        if !self.didSave {
            // No photo (no camera, capture error): end the capture once.
            self.didSave = true
            ShadowIntruderLog.shared.endCapture()
        }
        DispatchQueue.main.async {
            ShadowIntruderCamera.active = nil
        }
    }
}
