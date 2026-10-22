import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import AvatarNode

// Shadow: avatars for "Открыть профиль" header buttons (ShadowHeaderAction.openProfile).
//
// The header asks for an image key by the step link; the first request starts
// loading the person (by id, @username or "me") and their avatar, the header
// redraws when `version` changes. The image goes to ShadowHeaderButtonImages
// under a new key every time it changes (letters first, then the photo).
// Main thread only.
// Images for header buttons that are not glyphs (a person's avatar on a
// "Открыть профиль" button). `img:<key>` draws `images[key]` untinted; a new
// picture must come under a new key, so the button sees a new image. Main
// thread only.
enum ShadowHeaderButtonImages {
    static var images: [String: UIImage] = [:]
}

final class ShadowHeaderAvatars {
    static let shared = ShadowHeaderAvatars()

    static let size = CGSize(width: 28.0, height: 28.0)

    private var keys: [String: String] = [:]
    private var disposables: [String: Disposable] = [:]
    private var counter = 0
    private var versionValue = 0
    let version = ValuePromise<Int>(0, ignoreRepeated: true)

    private func cacheKey(context: AccountContext, link: String) -> String {
        return "\(context.account.peerId.toInt64())|\(link)"
    }

    // "img:<key>" for shadowHeaderButtonContent, nil until the image is loaded.
    func iconName(context: AccountContext, link: String) -> String? {
        let cacheKey = self.cacheKey(context: context, link: link)
        if let key = self.keys[cacheKey] {
            return "img:" + key
        }
        if self.disposables[cacheKey] == nil, let target = ShadowProfileTarget(string: link) {
            self.disposables[cacheKey] = (shadowResolveProfile(context: context, target: target)
            |> mapToSignal { peer -> Signal<UIImage?, NoError> in
                guard let peer else {
                    return .single(nil)
                }
                return peerAvatarCompleteImage(account: context.account, peer: peer, size: ShadowHeaderAvatars.size)
            }
            |> deliverOnMainQueue).start(next: { [weak self] image in
                guard let self, let image else {
                    return
                }
                self.counter += 1
                let key = "shadow-avatar-\(self.counter)"
                if let previous = self.keys[cacheKey] {
                    ShadowHeaderButtonImages.images[previous] = nil
                }
                ShadowHeaderButtonImages.images[key] = image
                self.keys[cacheKey] = key
                self.versionValue += 1
                self.version.set(self.versionValue)
            })
        }
        return nil
    }
}

// The person a profile link points to; nil when this account cannot find them
// (an id it has never seen, an unknown username).
func shadowResolveProfile(context: AccountContext, target: ShadowProfileTarget) -> Signal<EnginePeer?, NoError> {
    let byId: (EnginePeer.Id) -> Signal<EnginePeer?, NoError> = { id in
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id))
    }
    switch target {
    case .me:
        return byId(context.account.peerId)
    case let .id(value):
        return byId(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(value)))
    case let .username(name):
        return context.engine.peers.resolvePeerByName(name: name, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result {
                return .single(peer)
            }
            return .complete()
        }
        |> take(1)
    }
}
