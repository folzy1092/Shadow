import Foundation
import Postbox
import SwiftSignalKit

// Shadow: «Упомянуть всех» (paperclip tool, formatting panel). The members of
// a group to mention: everyone but bots, deleted accounts and the account
// itself, in the server's order. A basic group comes from its full info
// (refreshed first); a supergroup is paged through channels.getParticipants,
// 200 at a time, until the server has no more (it serves about 10 000).
public enum ShadowMentionAll {
    public static let pageSize: Int32 = 200
    public static let maxMembers = 10_000

    public static func isAvailable(peer: EnginePeer) -> Bool {
        switch peer {
        case .legacyGroup:
            return true
        case let .channel(channel):
            if case .group = channel.info {
                return true
            }
            return false
        default:
            return false
        }
    }

    static func isMentionable(_ peer: EnginePeer, accountPeerId: PeerId) -> Bool {
        guard case let .user(user) = peer else {
            return false
        }
        return user.id != accountPeerId && user.botInfo == nil && !(user.firstName == nil && user.lastName == nil)
    }

    public static func members(account: Account, peerId: PeerId) -> Signal<[EnginePeer], NoError> {
        let accountPeerId = account.peerId
        if peerId.namespace == Namespaces.Peer.CloudGroup {
            return _internal_fetchAndUpdateCachedPeerData(accountPeerId: accountPeerId, peerId: peerId, network: account.network, postbox: account.postbox)
            |> take(1)
            |> mapToSignal { _ -> Signal<[EnginePeer], NoError> in
                return account.postbox.transaction { transaction -> [EnginePeer] in
                    guard let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedGroupData, let participants = cachedData.participants else {
                        return []
                    }
                    var result: [EnginePeer] = []
                    for participant in participants.participants {
                        if let peer = transaction.getPeer(participant.peerId).map(EnginePeer.init), ShadowMentionAll.isMentionable(peer, accountPeerId: accountPeerId) {
                            result.append(peer)
                        }
                    }
                    return result
                }
            }
        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
            return channelPage(account: account, peerId: peerId, offset: 0, collected: [], seen: Set())
        } else {
            return .single([])
        }
    }

    private static func channelPage(account: Account, peerId: PeerId, offset: Int32, collected: [EnginePeer], seen: Set<PeerId>) -> Signal<[EnginePeer], NoError> {
        return _internal_channelMembers(postbox: account.postbox, network: account.network, accountPeerId: account.peerId, peerId: peerId, category: .recent(.all), offset: offset, limit: ShadowMentionAll.pageSize)
        |> take(1)
        |> mapToSignal { participants -> Signal<[EnginePeer], NoError> in
            guard let participants, !participants.isEmpty else {
                return .single(collected)
            }
            var collected = collected
            var seen = seen
            for participant in participants where !seen.contains(participant.peer.id) {
                seen.insert(participant.peer.id)
                if ShadowMentionAll.isMentionable(participant.peer, accountPeerId: account.peerId) {
                    collected.append(participant.peer)
                }
            }
            let nextOffset = offset + Int32(participants.count)
            if participants.count < Int(ShadowMentionAll.pageSize) || Int(nextOffset) >= ShadowMentionAll.maxMembers {
                return .single(collected)
            }
            return channelPage(account: account, peerId: peerId, offset: nextOffset, collected: collected, seen: seen)
        }
    }
}
