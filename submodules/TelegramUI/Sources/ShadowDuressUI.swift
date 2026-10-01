import Foundation
import UIKit
import CoreMotion
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext

// Shadow: app side of emergency protection (ShadowDuress).
//
//   * the duress code logs out of the chosen accounts;
//   * the panic gesture: face down / shake (accelerometer, only while the app is
//     in the foreground and the gesture is chosen) or a two-finger triple tap on
//     the main window (does not cancel other touches).
final class ShadowDuressCoordinator: NSObject, UIGestureRecognizerDelegate {
    private static var current: ShadowDuressCoordinator?

    static func install(sharedContext: SharedAccountContextImpl, mainWindow: Window1?) {
        if self.current != nil {
            return
        }
        self.current = ShadowDuressCoordinator(sharedContext: sharedContext, mainWindow: mainWindow)
    }

    private weak var sharedContext: SharedAccountContextImpl?
    private weak var mainWindow: Window1?
    private var observers: [NSObjectProtocol] = []
    private let logoutDisposable = MetaDisposable()
    private var foregroundDisposable: Disposable?
    private var inForeground = true

    private let motionManager = CMMotionManager()
    private var isMotionRunning = false
    private var faceDownSince: Double?
    private var faceDownArmed = true
    private var shakeSpikes: [Double] = []
    private var lastPanic: Double = 0.0

    private var tapRecognizer: UITapGestureRecognizer?

    private init(sharedContext: SharedAccountContextImpl, mainWindow: Window1?) {
        self.sharedContext = sharedContext
        self.mainWindow = mainWindow
        super.init()

        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: ShadowDuress.didTriggerNotification, object: nil, queue: .main, using: { [weak self] notification in
            let ids = notification.userInfo?[ShadowDuress.logoutAccountPeerIdsKey] as? [Int64] ?? []
            self?.logout(accountPeerIds: ids)
        }))
        self.observers.append(center.addObserver(forName: ShadowDuress.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateGesture()
        }))
        self.observers.append(center.addObserver(forName: ShadowDisguise.didChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateGesture()
        }))
        self.foregroundDisposable = (sharedContext.applicationBindings.applicationInForeground
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.inForeground = value
            self?.updateGesture()
        })
        self.updateGesture()
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.logoutDisposable.dispose()
        self.foregroundDisposable?.dispose()
        self.motionManager.stopAccelerometerUpdates()
    }

    // MARK: Logout

    private func logout(accountPeerIds: [Int64]) {
        guard let sharedContext = self.sharedContext, !accountPeerIds.isEmpty else {
            return
        }
        let accountManager = sharedContext.accountManager
        let wanted = Set(accountPeerIds)
        self.logoutDisposable.set((sharedContext.activeAccountContexts
        |> take(1)
        |> mapToSignal { _, accounts, _ -> Signal<Void, NoError> in
            let ids = accounts.filter { wanted.contains($0.1.account.peerId.toInt64()) }.map { $0.0 }
            return combineLatest(ids.map { logoutFromAccount(id: $0, accountManager: accountManager, alreadyLoggedOutRemotely: false) })
            |> map { _ -> Void in }
        }).start())
    }

    // MARK: Panic gesture

    private func updateGesture() {
        let duress = ShadowDuress.shared
        let gesture: ShadowDuress.PanicGesture = duress.isPanicGestureActive ? duress.panicGesture : .off

        let needsMotion = self.inForeground && (gesture == .faceDown || gesture == .shake)
        if needsMotion && !self.isMotionRunning && self.motionManager.isAccelerometerAvailable {
            self.isMotionRunning = true
            self.faceDownSince = nil
            self.faceDownArmed = true
            self.shakeSpikes = []
            self.motionManager.accelerometerUpdateInterval = 0.1
            self.motionManager.startAccelerometerUpdates(to: OperationQueue.main, withHandler: { [weak self] data, _ in
                guard let self, let data else {
                    return
                }
                self.handle(acceleration: data.acceleration, timestamp: data.timestamp)
            })
        } else if !needsMotion && self.isMotionRunning {
            self.isMotionRunning = false
            self.motionManager.stopAccelerometerUpdates()
        }

        if gesture == .twoFingerTripleTap {
            if self.tapRecognizer == nil, let containerView = self.mainWindow?.hostView.containerView {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
                recognizer.numberOfTouchesRequired = 2
                recognizer.numberOfTapsRequired = 3
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesEnded = false
                recognizer.delegate = self
                containerView.addGestureRecognizer(recognizer)
                self.tapRecognizer = recognizer
            }
        } else if let recognizer = self.tapRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
            self.tapRecognizer = nil
        }
    }

    private func handle(acceleration: CMAcceleration, timestamp: Double) {
        switch ShadowDuress.shared.panicGesture {
        case .faceDown:
            // Screen down: gravity points out of the screen (z ≈ +1 g).
            if acceleration.z > 0.85 {
                if !self.faceDownArmed {
                    return
                }
                if let since = self.faceDownSince {
                    if timestamp - since >= 0.5 {
                        self.faceDownArmed = false
                        self.faceDownSince = nil
                        self.firePanic(timestamp: timestamp)
                    }
                } else {
                    self.faceDownSince = timestamp
                }
            } else {
                self.faceDownSince = nil
                if acceleration.z < 0.3 {
                    self.faceDownArmed = true
                }
            }
        case .shake:
            let magnitude = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
            if magnitude > 2.3 {
                self.shakeSpikes.append(timestamp)
            }
            self.shakeSpikes.removeAll(where: { timestamp - $0 > 1.2 })
            if self.shakeSpikes.count >= 3 {
                self.shakeSpikes = []
                self.firePanic(timestamp: timestamp)
            }
        case .off, .twoFingerTripleTap:
            break
        }
    }

    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            self.firePanic(timestamp: CACurrentMediaTime())
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func firePanic(timestamp: Double) {
        if timestamp - self.lastPanic < 2.0 {
            return
        }
        self.lastPanic = timestamp
        if ShadowDuress.shared.panic() {
            self.mainWindow?.hostView.containerView.endEditing(true)
            // Leave whatever was open (a chat, Shadow settings) for the chat list.
            if let navigationController = self.mainWindow?.viewController as? NavigationController {
                navigationController.popToRoot(animated: false)
            }
        }
    }
}
