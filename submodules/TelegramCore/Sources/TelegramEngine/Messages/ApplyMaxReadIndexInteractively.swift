import Foundation
import Postbox
internal import TelegramApi
import SwiftSignalKit


func _internal_applyMaxReadIndexInteractively(postbox: Postbox, stateManager: AccountStateManager, index: MessageIndex) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: stateManager, index: index)
    }
}

/// Applies a read from a caller that has only a message id and no `MessageIndex` - a
/// notification action or a Siri intent.
///
/// Never applies to a secret chat. Reading there is destructive and irreversible: it
/// starts every message's autoremove countdown (below) and tells the other party the
/// messages were seen, for messages the user has not actually opened. These callers act on
/// an id the user never looked at - a notification they replied to, a Siri phrase - so the
/// chat is left unread until it is opened, which is recoverable. That is also what these
/// callers already did in effect: they passed `MessageIndex(id:, timestamp: 0)`, whose zero
/// date matched no message, so a secret chat was never actually read. All that changes is
/// that the invented index no longer becomes the chat's read marker, from where it was
/// pushed as `messages.readEncryptedHistory(max_date: 0)` and rejected.
///
/// For every other peer the read state is id-based: it reads up to `messageId.id` and the
/// index's timestamp is unused, so the id alone is enough. Resolve the stored message's
/// real index anyway when there is one, since it is the honest value.
///
/// Reports whether a read was applied, so a caller that has to answer the user - a Siri
/// intent - can say it did nothing rather than claim success.
func _internal_applyMaxReadMessageIdInteractively(postbox: Postbox, stateManager: AccountStateManager, messageId: MessageId) -> Signal<Bool, NoError> {
    return postbox.transaction { transaction -> Bool in
        guard messageId.peerId.namespace != Namespaces.Peer.SecretChat else {
            return false
        }
        // A channel the account is not a member of has no read state to apply to.
        guard peerKeepsReadState(transaction.getPeer(messageId.peerId)) else {
            return false
        }
        let index = transaction.getMessage(messageId)?.index ?? MessageIndex(id: messageId, timestamp: 0)
        _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: stateManager, index: index)
        return true
    }
}

func _internal_applyMaxReadIndexInteractively(transaction: Transaction, stateManager: AccountStateManager, index: MessageIndex) {
    // A channel the account is not a member of has no read state on the server
    // (NonMemberChannelReadState.swift): nothing moves locally and no push is queued.
    guard peerKeepsReadState(transaction.getPeer(index.id.peerId)) else {
        return
    }
    let messageIds = transaction.applyInteractiveReadMaxIndex(index)
    
    if let peer = transaction.getPeer(index.id.peerId), peer.isForumOrMonoForum {
        if let combinedPeerReadState = transaction.getCombinedPeerReadState(peer.id), combinedPeerReadState.count == 0 {
            for item in transaction.getMessageHistoryThreadIndex(peerId: peer.id, limit: 100) {
                guard var data = transaction.getMessageHistoryThreadInfo(peerId: index.id.peerId, threadId: item.threadId)?.data.get(MessageHistoryThreadData.self) else {
                    continue
                }
                guard let messageIndex = transaction.getMessageHistoryThreadTopMessage(peerId: index.id.peerId, threadId: item.threadId, namespaces: Set([Namespaces.Message.Cloud])) else {
                    continue
                }
                if data.incomingUnreadCount != 0 {
                    data.incomingUnreadCount = 0
                    data.isMarkedUnread = false
                    data.maxIncomingReadId = max(messageIndex.id.id, data.maxIncomingReadId)
                    data.maxKnownMessageId = max(data.maxKnownMessageId, messageIndex.id.id)
                    
                    if let entry = StoredMessageHistoryThreadInfo(data) {
                        transaction.setMessageHistoryThreadInfo(peerId: index.id.peerId, threadId: item.threadId, info: entry)
                    }
                }
            }
        }
    }
    
    if index.id.peerId.namespace == Namespaces.Peer.SecretChat {
        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        for id in messageIds {
            if let message = transaction.getMessage(id) {
                for attribute in message.attributes {
                    if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
                        if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && !message.containsSecretMedia {
                            transaction.updateMessage(message.id, update: { currentMessage in
                                var storeForwardInfo: StoreMessageForwardInfo?
                                if let forwardInfo = currentMessage.forwardInfo {
                                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                                }
                                let updatedAttributes = currentMessage.attributes.map({ currentAttribute -> MessageAttribute in
                                    if let currentAttribute = currentAttribute as? AutoremoveTimeoutMessageAttribute {
                                        return AutoremoveTimeoutMessageAttribute(timeout: currentAttribute.timeout, countdownBeginTime: timestamp)
                                    } else {
                                        return currentAttribute
                                    }
                                })
                                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                            })
                        }
                        break
                    }
                }
            }
        }
    } else if index.id.peerId.namespace == Namespaces.Peer.CloudUser || index.id.peerId.namespace == Namespaces.Peer.CloudGroup || index.id.peerId.namespace == Namespaces.Peer.CloudChannel {
        stateManager.notifyAppliedIncomingReadMessages([index.id])
    }
}

func applyOutgoingReadMaxIndex(transaction: Transaction, index: MessageIndex, beginCountdownAt timestamp: Int32) {
    let messageIds = transaction.applyOutgoingReadMaxIndex(index)
    if index.id.peerId.namespace == Namespaces.Peer.SecretChat {
        for id in messageIds {
            applySecretOutgoingMessageReadActions(transaction: transaction, id: id, beginCountdownAt: timestamp)
        }
    }
}

func maybeReadSecretOutgoingMessage(transaction: Transaction, index: MessageIndex) {
    guard index.id.peerId.namespace == Namespaces.Peer.SecretChat else {
        assertionFailure()
        return
    }
    guard index.id.namespace == Namespaces.Message.Local else {
        assertionFailure()
        return
    }
    
    guard let combinedState = transaction.getCombinedPeerReadState(index.id.peerId) else {
        return
    }
    
    if combinedState.isOutgoingMessageIndexRead(index) {
        applySecretOutgoingMessageReadActions(transaction: transaction, id: index.id, beginCountdownAt: index.timestamp)
    }
}

func applySecretOutgoingMessageReadActions(transaction: Transaction, id: MessageId, beginCountdownAt timestamp: Int32) {
    guard id.peerId.namespace == Namespaces.Peer.SecretChat else {
        assertionFailure()
        return
    }
    guard id.namespace == Namespaces.Message.Local else {
        assertionFailure()
        return
    }
    
    if let message = transaction.getMessage(id), message.flags.intersection(.IsIncomingMask).isEmpty {
        if message.flags.intersection([.Unsent, .Sending, .Failed]).isEmpty {
            for attribute in message.attributes {
                if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
                    if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && !message.containsSecretMedia {
                        transaction.updateMessage(message.id, update: { currentMessage in
                            var storeForwardInfo: StoreMessageForwardInfo?
                            if let forwardInfo = currentMessage.forwardInfo {
                                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                            }
                            let updatedAttributes = currentMessage.attributes.map({ currentAttribute -> MessageAttribute in
                                if let currentAttribute = currentAttribute as? AutoremoveTimeoutMessageAttribute {
                                    return AutoremoveTimeoutMessageAttribute(timeout: currentAttribute.timeout, countdownBeginTime: timestamp)
                                } else {
                                    return currentAttribute
                                }
                            })
                            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                        })
                    }
                    break
                }
            }
        }
    }
}

func _internal_togglePeerUnreadMarkInteractively(postbox: Postbox, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, setToValue: Bool? = nil) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        _internal_togglePeerUnreadMarkInteractively(transaction: transaction, network: network, viewTracker: viewTracker, peerId: peerId, setToValue: setToValue)
    }
}

func _internal_toggleForumThreadUnreadMarkInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, threadId: Int64, setToValue: Bool?) {
    guard let peer = transaction.getPeer(peerId) else {
        return
    }
    guard peer.isForumOrMonoForum else {
        return
    }
    guard var data = transaction.getMessageHistoryThreadInfo(peerId: peerId, threadId: threadId)?.data.get(MessageHistoryThreadData.self) else {
        return
    }
    guard let messageIndex = transaction.getMessageHistoryThreadTopMessage(peerId: peerId, threadId: threadId, namespaces: Set([Namespaces.Message.Cloud])) else {
        return
    }
    
    let setToValue = setToValue ?? !(data.incomingUnreadCount != 0 || data.isMarkedUnread)
    
    if setToValue {
        data.isMarkedUnread = true
        if let entry = StoredMessageHistoryThreadInfo(data) {
            transaction.setMessageHistoryThreadInfo(peerId: peerId, threadId: threadId, info: entry)
        }
        
        if peer.isForum {
        } else if peer.isMonoForum {
            if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer), let subPeer = transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer) {
                let _ = network.request(Api.functions.messages.markDialogUnread(flags: 1 << 0, parentPeer: inputPeer, peer: .inputDialogPeer(.init(peer: subPeer)))).start()
            }
        }
    } else {
        if data.incomingUnreadCount != 0 || data.isMarkedUnread {
            data.incomingUnreadCount = 0
            data.isMarkedUnread = false
            data.maxIncomingReadId = max(messageIndex.id.id, data.maxIncomingReadId)
            data.maxKnownMessageId = max(data.maxKnownMessageId, messageIndex.id.id)
            
            if let entry = StoredMessageHistoryThreadInfo(data) {
                transaction.setMessageHistoryThreadInfo(peerId: peerId, threadId: threadId, info: entry)
            }
            
            if peer.isForum {
                if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer) {
                    let _ = network.request(Api.functions.messages.readDiscussion(peer: inputPeer, msgId: Int32(clamping: threadId), readMaxId: messageIndex.id.id)).start()
                }
            } else if peer.isMonoForum {
                if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer), let subPeer = transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer) {
                    let _ = network.request(Api.functions.messages.readSavedHistory(parentPeer: inputPeer, peer: subPeer, maxId: messageIndex.id.id)).start()
                }
            }
        }
    }
}

func _internal_markForumThreadAsReadInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, threadId: Int64) {
    guard let peer = transaction.getPeer(peerId) else {
        return
    }
    guard peer.isForumOrMonoForum else {
        return
    }
    guard var data = transaction.getMessageHistoryThreadInfo(peerId: peerId, threadId: threadId)?.data.get(MessageHistoryThreadData.self) else {
        return
    }
    guard let messageIndex = transaction.getMessageHistoryThreadTopMessage(peerId: peerId, threadId: threadId, namespaces: Set([Namespaces.Message.Cloud])) else {
        return
    }
    if data.incomingUnreadCount != 0 {
        data.incomingUnreadCount = 0
        data.isMarkedUnread = false
        data.maxIncomingReadId = max(messageIndex.id.id, data.maxIncomingReadId)
        data.maxKnownMessageId = max(data.maxKnownMessageId, messageIndex.id.id)
        
        if let entry = StoredMessageHistoryThreadInfo(data) {
            transaction.setMessageHistoryThreadInfo(peerId: peerId, threadId: threadId, info: entry)
        }
        
        if peer.isForum {
            if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer) {
                let _ = network.request(Api.functions.messages.readDiscussion(peer: inputPeer, msgId: Int32(clamping: threadId), readMaxId: messageIndex.id.id)).start()
            }
        } else if peer.isMonoForum {
            if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer), let subPeer = transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer) {
                let _ = network.request(Api.functions.messages.readSavedHistory(parentPeer: inputPeer, peer: subPeer, maxId: messageIndex.id.id)).start()
            }
        }
    }
}

func _internal_togglePeerUnreadMarkInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, peerId: PeerId, setToValue: Bool? = nil) {
    guard let peer = transaction.getPeer(peerId) else {
        return
    }
    
    var displayAsRegularChat: Bool = false
    if let channel = peer as? TelegramChannel, channel.flags.contains(.displayForumAsTabs) {
        displayAsRegularChat = true
    } else if let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData {
        displayAsRegularChat = cachedData.viewForumAsMessages.knownValue ?? false
    }
    
    if peer.isForumOrMonoForum, !displayAsRegularChat {
        for item in transaction.getMessageHistoryThreadIndex(peerId: peerId, limit: 20) {
            guard var data = transaction.getMessageHistoryThreadInfo(peerId: peerId, threadId: item.threadId)?.data.get(MessageHistoryThreadData.self) else {
                continue
            }
            guard let messageIndex = transaction.getMessageHistoryThreadTopMessage(peerId: peerId, threadId: item.threadId, namespaces: Set([Namespaces.Message.Cloud])) else {
                continue
            }
            if data.incomingUnreadCount != 0 {
                data.incomingUnreadCount = 0
                data.isMarkedUnread = false
                data.maxIncomingReadId = max(messageIndex.id.id, data.maxIncomingReadId)
                data.maxKnownMessageId = max(data.maxKnownMessageId, messageIndex.id.id)
                
                if let entry = StoredMessageHistoryThreadInfo(data) {
                    transaction.setMessageHistoryThreadInfo(peerId: peerId, threadId: item.threadId, info: entry)
                }
                
                if peer.isForum {
                    if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer) {
                        let _ = network.request(Api.functions.messages.readDiscussion(peer: inputPeer, msgId: Int32(clamping: item.threadId), readMaxId: messageIndex.id.id)).start()
                    }
                } else if peer.isMonoForum {
                    if !currentAyuGramSettings(transaction: transaction).suppressReadReceipts(peerId: peerId), let inputPeer = apiInputPeer(peer), let subPeer = transaction.getPeer(PeerId(item.threadId)).flatMap(apiInputPeer) {
                        let _ = network.request(Api.functions.messages.readSavedHistory(parentPeer: inputPeer, peer: subPeer, maxId: messageIndex.id.id)).start()
                    }
                }
            }
        }
    } else {
        let principalNamespace: MessageId.Namespace
        if peerId.namespace == Namespaces.Peer.SecretChat {
            principalNamespace = Namespaces.Message.SecretIncoming
        } else {
            principalNamespace = Namespaces.Message.Cloud
        }
        var hasUnread = false
        if let states = transaction.getPeerReadStates(peerId) {
            for state in states {
                if state.1.isUnread {
                    hasUnread = true
                    break
                }
            }
        }
        
        // Shadow: a chat whose only unread thing is a mention (e.g. one read
        // under Ghost Mode, so the server still counts it) is unread too, so
        // «Прочитать» clears the «@».
        if !hasUnread {
            let unseenSummary = transaction.getMessageTagSummary(peerId: peerId, threadId: nil, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil)
            let actionSummary = transaction.getPendingMessageActionsSummary(peerId: peerId, type: PendingMessageActionType.consumeUnseenPersonalMessage, namespace: Namespaces.Message.Cloud)
            if (unseenSummary?.count ?? 0) - (actionSummary ?? 0) > 0 {
                hasUnread = true
            }
        }
        
        if hasUnread {
            if setToValue == nil || !(setToValue!) {
                if let index = transaction.getTopPeerMessageIndex(peerId: peerId) {
                    let _ = transaction.applyInteractiveReadMaxIndex(index)
                } else {
                    transaction.applyMarkUnread(peerId: peerId, namespace: principalNamespace, value: false, interactive: true)
                }
                viewTracker.updateMarkAllMentionsSeen(peerId: peerId, threadId: nil)
            }
        } else {
            if setToValue == nil || setToValue! {
                transaction.applyMarkUnread(peerId: peerId, namespace: principalNamespace, value: true, interactive: true)
            }
        }
    }
}

public func clearPeerUnseenPersonalMessagesInteractively(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Void in
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return
        }
        account.viewTracker.updateMarkAllMentionsSeen(peerId: peerId, threadId: threadId)
    }
    |> ignoreValues
}

public func clearPeerUnseenReactionsAndPollVotesInteractively(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Void in
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return
        }
        account.viewTracker.updateMarkAllReactionsAndPollVotesSeen(peerId: peerId, threadId: threadId)
    }
    |> ignoreValues
}

// Shadow: the «@» counter of a chat cleared on this device only, no request.
// A mention read under Ghost Mode stays unread on the server and its counter
// comes back with the dialog, while the message itself is already consumed
// here, so nothing in the chat clears it. Returns whether there was one.
@discardableResult
func _internal_shadowClearMentionsLocally(transaction: Transaction, peerId: PeerId) -> Bool {
    guard let summary = transaction.getMessageTagSummary(peerId: peerId, threadId: nil, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil), summary.count > 0 else {
        return false
    }
    for index in transaction.getMessageIndicesWithTag(peerId: peerId, threadId: nil, namespace: Namespaces.Message.Cloud, tag: .unseenPersonalMessage) {
        transaction.updateMessage(index.id, update: { currentMessage in
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            var attributes = currentMessage.attributes
            for i in 0 ..< attributes.count {
                if let attribute = attributes[i] as? ConsumablePersonalMentionMessageAttribute {
                    attributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: attribute.pending)
                    break
                }
            }
            var tags = currentMessage.tags
            tags.remove(.unseenPersonalMessage)
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
    transaction.replaceMessageTagSummary(peerId: peerId, threadId: nil, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: summary.range.maxId)
    return true
}

func _internal_markAllChatsAsReadInteractively(transaction: Transaction, network: Network, viewTracker: AccountViewTracker, groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?) {
    for peerId in transaction.getUnreadChatListPeerIds(groupId: groupId, filterPredicate: filterPredicate, additionalFilter: nil, stopOnFirstMatch: false) {
        _internal_togglePeerUnreadMarkInteractively(transaction: transaction, network: network, viewTracker: viewTracker, peerId: peerId, setToValue: false)
    }
    // Shadow: «Прочитать все» of a folder also clears the «@» of its chats
    // that have nothing else unread (a mention read under Ghost Mode stays
    // unread on the server). Ghost Mode still keeps it off the server.
    let mentionPeerIds = transaction.getUnreadChatListPeerIds(groupId: groupId, filterPredicate: filterPredicate, additionalFilter: { peer in
        guard peer.id.namespace != Namespaces.Peer.SecretChat else {
            return false
        }
        return (transaction.getMessageTagSummary(peerId: peer.id, threadId: nil, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil)?.count ?? 0) > 0
    }, stopOnFirstMatch: false, requireUnread: false)
    for peerId in mentionPeerIds {
        viewTracker.updateMarkAllMentionsSeen(peerId: peerId, threadId: nil)
    }
}

// Shadow: clear unread counters in Postbox without installing any network read
// action. This is deliberately separate from the interactive/server path so a
// Ghost Mode user can clean the local chat list without emitting receipts.
func _internal_markAllChatsAsReadLocally(transaction: Transaction, groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?) {
    // Mentions too: a chat can have no unread messages but a stuck «@».
    if filterPredicate == nil {
        for peerId in transaction.chatListGetAllPeerIds(groupId: groupId) where peerId.namespace != Namespaces.Peer.SecretChat {
            _internal_shadowClearMentionsLocally(transaction: transaction, peerId: peerId)
        }
    }
    for peerId in transaction.getUnreadChatListPeerIds(groupId: groupId, filterPredicate: filterPredicate, additionalFilter: nil, stopOnFirstMatch: false) {
        guard let peer = transaction.getPeer(peerId) else {
            continue
        }
        if peer.isForumOrMonoForum {
            for item in transaction.getMessageHistoryThreadIndex(peerId: peerId, limit: 100) {
                guard var data = transaction.getMessageHistoryThreadInfo(peerId: peerId, threadId: item.threadId)?.data.get(MessageHistoryThreadData.self),
                      let index = transaction.getMessageHistoryThreadTopMessage(peerId: peerId, threadId: item.threadId, namespaces: Set([Namespaces.Message.Cloud])) else {
                    continue
                }
                data.incomingUnreadCount = 0
                data.isMarkedUnread = false
                data.maxIncomingReadId = max(index.id.id, data.maxIncomingReadId)
                data.maxKnownMessageId = max(data.maxKnownMessageId, index.id.id)
                if let entry = StoredMessageHistoryThreadInfo(data) {
                    transaction.setMessageHistoryThreadInfo(peerId: peerId, threadId: item.threadId, info: entry)
                }
            }
        }
        if let index = transaction.getTopPeerMessageIndex(peerId: peerId) {
            transaction.applyIncomingReadMaxId(index.id)
        } else {
            let namespace = peerId.namespace == Namespaces.Peer.SecretChat ? Namespaces.Message.SecretIncoming : Namespaces.Message.Cloud
            transaction.applyMarkUnread(peerId: peerId, namespace: namespace, value: false, interactive: true)
        }
    }
}
