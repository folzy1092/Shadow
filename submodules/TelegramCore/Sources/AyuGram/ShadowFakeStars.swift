import Foundation
import Postbox
import SwiftSignalKit

// Shadow: фейковые операции со звёздами (только на этом устройстве, на сервер
// ничего не уходит), часть скрытой подмены баланса (ShadowStarsBalance):
//  - «Фейковое зачисление» — продажа коллекционного подарка: меню двойного
//    тапа по балансу → ссылка t.me/nft/…, цена, покупатель;
//  - «Фейковое списание» — покупка коллекционного подарка: ссылка, цена,
//    продавец;
//  - отправка подарка, когда настоящих звёзд не хватает, а подмена включена:
//    карточка «Вы отправили подарок» в чате и списание в истории.
// Каждая операция сдвигает показанный баланс и стоит в истории операций
// (StarsContext / StarsTransactionsContext подмешивают их в свои списки).
// Записи — в UserDefaults на аккаунт; готовые операции (с собеседником из
// Postbox) держит кэш, его заполняет `load`.
public final class ShadowFakeStars {
    public static let shared = ShadowFakeStars()

    static let idPrefix = "shadow-fake-"

    enum Kind: Int32, Codable {
        case giftSale = 0
        case giftSent = 1
        case giftPurchase = 2
    }

    struct Record: Codable {
        var id: String
        var date: Int32
        var nanos: Int64
        var peerId: Int64
        var kind: Kind
        var gift: StarGift
    }

    private let queue = Queue()
    private var cache: [Int64: [StarsContext.State.Transaction]] = [:]
    private let cacheLock = NSLock()

    private static func key(accountPeerId: Int64) -> String {
        return "shadow.fakeStarsTransactions.\(accountPeerId)"
    }

    private func records(accountPeerId: Int64) -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: ShadowFakeStars.key(accountPeerId: accountPeerId)) else {
            return []
        }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private func save(_ records: [Record], accountPeerId: Int64) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: ShadowFakeStars.key(accountPeerId: accountPeerId))
        }
    }

    // The ready operations of the account, newest first; empty until `load`.
    public func transactions(accountPeerId: Int64) -> [StarsContext.State.Transaction] {
        self.cacheLock.lock()
        defer {
            self.cacheLock.unlock()
        }
        return self.cache[accountPeerId] ?? []
    }

    // Builds the operations (peers come from Postbox) and tells the stars
    // contexts to show them.
    public func load(account: Account) {
        let accountPeerId = account.peerId.toInt64()
        let records = self.records(accountPeerId: accountPeerId)
        let _ = (account.postbox.transaction { transaction -> [StarsContext.State.Transaction] in
            var result: [StarsContext.State.Transaction] = []
            for record in records {
                guard let peer = transaction.getPeer(PeerId(record.peerId)) else {
                    continue
                }
                let parts = ShadowStarsBalance.parts(record.nanos)
                result.append(StarsContext.State.Transaction(
                    flags: record.kind == .giftPurchase ? [.isStarGiftResale] : [],
                    id: record.id,
                    count: CurrencyAmount(amount: StarsAmount(value: parts.value, nanos: parts.nanos), currency: .stars),
                    date: record.date,
                    peer: .peer(EnginePeer(peer)),
                    title: nil,
                    description: nil,
                    photo: nil,
                    transactionDate: nil,
                    transactionUrl: nil,
                    paidMessageId: nil,
                    giveawayMessageId: nil,
                    media: [],
                    subscriptionPeriod: nil,
                    starGift: record.gift,
                    floodskipNumber: nil,
                    starrefCommissionPermille: nil,
                    starrefPeerId: nil,
                    starrefAmount: nil,
                    paidMessageCount: nil,
                    premiumGiftMonths: nil,
                    adsProceedsFromDate: nil,
                    adsProceedsToDate: nil
                ))
            }
            return result.sorted(by: { $0.date > $1.date })
        }
        |> deliverOnMainQueue).start(next: { [weak self] transactions in
            guard let self else {
                return
            }
            self.cacheLock.lock()
            self.cache[accountPeerId] = transactions
            self.cacheLock.unlock()
            NotificationCenter.default.post(name: ShadowStarsBalance.didChangeNotification, object: nil, userInfo: ["accountPeerId": accountPeerId])
        })
    }

    fileprivate func add(account: Account, record: Record) {
        let accountPeerId = account.peerId.toInt64()
        var records = self.records(accountPeerId: accountPeerId)
        records.append(record)
        self.save(records, accountPeerId: accountPeerId)
        ShadowStarsBalance.adjust(by: record.nanos, accountPeerId: accountPeerId)
        self.load(account: account)
    }

    // Removes every fake operation of the account (the balance stays as shown).
    public func clear(account: Account) {
        UserDefaults.standard.removeObject(forKey: ShadowFakeStars.key(accountPeerId: account.peerId.toInt64()))
        self.load(account: account)
    }

    // `transactions` (newest first) with the fake ones put in by date; fakes
    // already in the list are replaced. `filter` keeps a mode's operations.
    static func merged(_ transactions: [StarsContext.State.Transaction], fakes: [StarsContext.State.Transaction], filter: (StarsContext.State.Transaction) -> Bool = { _ in true }) -> [StarsContext.State.Transaction] {
        var result = transactions.filter { !$0.id.hasPrefix(ShadowFakeStars.idPrefix) }
        for fake in fakes where filter(fake) {
            if let index = result.firstIndex(where: { $0.date < fake.date }) {
                result.insert(fake, at: index)
            } else {
                result.append(fake)
            }
        }
        return result
    }
}

public enum ShadowFakeStarsError {
    case notFound
    case noBuyer
}

// «Фейковое зачисление» (продажа) или, с `isPurchase`, «Фейковое списание»
// (покупка) коллекционного подарка по ссылке за `stars`. Другая сторона —
// `buyerPeerId`, иначе нынешний владелец подарка.
public func shadowAddFakeGiftSale(account: Account, slug: String, stars: Int64, buyerPeerId: EnginePeer.Id?, isPurchase: Bool = false) -> Signal<Never, ShadowFakeStarsError> {
    return _internal_getUniqueStarGift(account: account, slug: slug)
    |> mapError { _ -> ShadowFakeStarsError in
        return .notFound
    }
    |> mapToSignal { gift -> Signal<Never, ShadowFakeStarsError> in
        guard let buyer = buyerPeerId ?? gift.owner?.peerId, buyer != account.peerId else {
            return .fail(.noBuyer)
        }
        return Signal { subscriber in
            Queue.mainQueue().async {
                ShadowFakeStars.shared.add(account: account, record: ShadowFakeStars.Record(
                    id: ShadowFakeStars.idPrefix + UUID().uuidString,
                    date: Int32(Date().timeIntervalSince1970),
                    nanos: (isPurchase ? -stars : stars) * ShadowStarsBalance.nanosPerStar,
                    peerId: buyer.toInt64(),
                    kind: isPurchase ? .giftPurchase : .giftSale,
                    gift: .unique(gift.withOwner(.peerId(isPurchase ? account.peerId : buyer)))
                ))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
}

// Отправка подарка, когда настоящих звёзд не хватает (а подмена включена):
// локальная карточка «Вы отправили подарок» в чате, списание с показанного
// баланса и операция в истории. Ничего не отправляется.
public func shadowFakeSendStarGift(account: Account, peerId: EnginePeer.Id, gift: StarGift.Gift, price: Int64, text: String?, entities: [MessageTextEntity]?, nameHidden: Bool) -> Signal<Never, NoError> {
    let accountPeerId = account.peerId
    return account.postbox.transaction { transaction -> Void in
        let action = TelegramMediaAction(action: .starGift(
            gift: .generic(gift),
            convertStars: gift.convertStars,
            text: text,
            entities: entities,
            nameHidden: nameHidden,
            savedToProfile: false,
            converted: false,
            upgraded: false,
            canUpgrade: false,
            upgradeStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            upgradeMessageId: nil,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            prepaidUpgradeHash: nil,
            giftMessageId: nil,
            upgradeSeparate: false,
            isAuctionAcquired: false,
            toPeerId: nil,
            number: nil
        ))
        let message = StoreMessage(peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: Int32(Date().timeIntervalSince1970), flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: accountPeerId, text: "", attributes: [], media: [action])
        let _ = transaction.addMessages([message], location: .Random)
    }
    |> deliverOnMainQueue
    |> mapToSignal { _ -> Signal<Never, NoError> in
        ShadowFakeStars.shared.add(account: account, record: ShadowFakeStars.Record(
            id: ShadowFakeStars.idPrefix + UUID().uuidString,
            date: Int32(Date().timeIntervalSince1970),
            nanos: -price * ShadowStarsBalance.nanosPerStar,
            peerId: peerId.toInt64(),
            kind: .giftSent,
            gift: .generic(gift)
        ))
        return .complete()
    }
}
