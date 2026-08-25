import Foundation
import Postbox
import SwiftSignalKit

// Shadow: значки поддержавших exteraGram / AyuGram.
//
// Данные берутся с того же публичного эндпоинта, что использует AyuGram Desktop
// (см. RCManager в AyuGramDesktop). Схема ответа:
//   developers / officialChannels / supporters / supporterChannels — массивы id
//   customBadges — [{ id, badge: { documentId, text } }] — персональный значок
//
// Важно: у ОБЫЧНОГО поддержавшего (он есть в supporters, но не в customBadges)
// эндпоинт не отдаёт никакой эмодзи — в десктопе ему рисуется картинка из
// ресурсов приложения. У нас такой картинки нет, поэтому общий значок берётся
// из нашего же config.json (ключ extera_badge_emoji_id). Не задан — обычные
// поддержавшие значка не получают, персональные из customBadges работают всегда.
//
// Устроено намеренно так же, как GitConfig: снимок в памяти + кэш на диске +
// фоновое обновление, чтобы значки были доступны синхронно из слоя отрисовки.

public struct AyuExteraBadge: Equatable {
    public let emojiId: Int64
    public let description: String

    public init(emojiId: Int64, description: String) {
        self.emojiId = emojiId
        self.description = description
    }
}

private struct AyuExteraConfig {
    var supporters: Set<Int64> = []
    var supporterChannels: Set<Int64> = []
    var developers: Set<Int64> = []
    var officialChannels: Set<Int64> = []
    var customBadges: [Int64: (emojiId: Int64, text: String)] = [:]
}

private let exteraConfigLock = NSLock()
private var exteraConfigValue = AyuExteraConfig()

private func currentExteraConfig() -> AyuExteraConfig {
    exteraConfigLock.lock()
    defer { exteraConfigLock.unlock() }
    return exteraConfigValue
}

private func setExteraConfig(_ config: AyuExteraConfig) {
    exteraConfigLock.lock()
    exteraConfigValue = config
    exteraConfigLock.unlock()
}

// MARK: - Публичный поиск значка

// Значок поддержавшего для конкретного пира. nil — пир не из списков Extera,
// либо это обычный поддержавший, а общий emoji_id в config.json не задан.
public func ayuExteraBadge(peerId: PeerId) -> AyuExteraBadge? {
    let raw = peerId.id._internalGetInt64Value()
    let config = currentExteraConfig()

    // Персональный значок имеет приоритет: у человека свой эмодзи и свой текст.
    if let custom = config.customBadges[raw] {
        return AyuExteraBadge(emojiId: custom.emojiId, description: custom.text)
    }

    let isDeveloper = config.developers.contains(raw) || config.officialChannels.contains(raw)
    let isSupporter = config.supporters.contains(raw) || config.supporterChannels.contains(raw)
    guard isDeveloper || isSupporter else {
        return nil
    }
    guard let emojiId = ayuExteraDefaultBadgeEmojiId() else {
        return nil
    }
    let description = isDeveloper
        ? "Разработчик exteraGram / AyuGram"
        : "Пользователь поддержал exteraGram / AyuGram"
    return AyuExteraBadge(emojiId: emojiId, description: description)
}

// Только id эмодзи — для мест, которые рисуют иконку без попапа.
public func ayuExteraBadgeEmojiId(peerId: PeerId) -> Int64? {
    return ayuExteraBadge(peerId: peerId)?.emojiId
}

// Текст статуса без привязки к эмодзи. Нужен карточке профиля: подпись
// "поддержал exteraGram" осмысленна и тогда, когда общий emoji_id не задан и
// рисовать рядом с именем нечего.
public func ayuExteraDescription(peerId: PeerId) -> String? {
    let raw = peerId.id._internalGetInt64Value()
    let config = currentExteraConfig()
    if let custom = config.customBadges[raw] {
        return custom.text
    }
    if config.developers.contains(raw) || config.officialChannels.contains(raw) {
        return "Разработчик exteraGram / AyuGram"
    }
    if config.supporters.contains(raw) || config.supporterChannels.contains(raw) {
        return "Пользователь поддержал exteraGram / AyuGram"
    }
    return nil
}

// MARK: - Разбор ответа

// JSONDecoder, а не JSONSerialization: documentId — большие Int64, при разборе
// через NSNumber/Double они теряют младшие биты.
private struct AyuExteraDTO: Codable {
    struct CustomBadgeEntry: Codable {
        struct Badge: Codable {
            let documentId: Int64?
            let text: String?
        }
        let id: Int64?
        let badge: Badge?
    }
    let developers: [Int64]?
    let officialChannels: [Int64]?
    let supporters: [Int64]?
    let supporterChannels: [Int64]?
    let customBadges: [CustomBadgeEntry]?
}

private func parseExteraConfig(_ data: Data) -> AyuExteraConfig? {
    guard let dto = try? JSONDecoder().decode(AyuExteraDTO.self, from: data) else {
        return nil
    }
    var config = AyuExteraConfig()
    config.developers = Set(dto.developers ?? [])
    config.officialChannels = Set(dto.officialChannels ?? [])
    config.supporters = Set(dto.supporters ?? [])
    config.supporterChannels = Set(dto.supporterChannels ?? [])
    for entry in dto.customBadges ?? [] {
        guard let id = entry.id, let badge = entry.badge, let documentId = badge.documentId else {
            continue
        }
        let text = badge.text ?? "Пользователь поддержал exteraGram / AyuGram"
        config.customBadges[id] = (emojiId: documentId, text: text)
    }
    return config
}

// MARK: - Загрузка и кэш

private let exteraConfigURLString = "https://api.exteragram.app/api/v1/profiles/compact"

private func exteraConfigCacheURL() -> URL? {
    guard let directory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
        return nil
    }
    return directory.appendingPathComponent("AyuExteraConfig.json")
}

// Ошибки (нет сети, битый JSON) намеренно проглатываются: значки просто не
// меняются, UI это никак не задевает.
private func fetchExteraConfig(completion: ((Bool) -> Void)? = nil) {
    guard let remoteURL = URL(string: exteraConfigURLString) else {
        completion?(false)
        return
    }
    var request = URLRequest(url: remoteURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20.0
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        guard error == nil, let data = data, let config = parseExteraConfig(data) else {
            if let completion = completion {
                Queue.mainQueue().async { completion(false) }
            }
            return
        }
        setExteraConfig(config)
        if let cacheURL = exteraConfigCacheURL() {
            try? data.write(to: cacheURL, options: .atomic)
        }
        if let completion = completion {
            Queue.mainQueue().async { completion(true) }
        }
    }
    task.resume()
}

private let exteraConfigStartLock = NSLock()
private var exteraConfigStarted = false

// Вызывается один раз за процесс. Сначала поднимает кэш с диска, чтобы значки
// были доступны сразу, потом обновляет с сервера в фоне.
public func startAyuExteraConfigIfNeeded() {
    exteraConfigStartLock.lock()
    if exteraConfigStarted {
        exteraConfigStartLock.unlock()
        return
    }
    exteraConfigStarted = true
    exteraConfigStartLock.unlock()

    if let cacheURL = exteraConfigCacheURL(), let data = try? Data(contentsOf: cacheURL), let config = parseExteraConfig(data) {
        setExteraConfig(config)
    }

    fetchExteraConfig()
}

// Принудительное обновление (кнопка синхронизации в настройках).
public func refreshAyuExteraConfig(completion: ((Bool) -> Void)? = nil) {
    fetchExteraConfig(completion: completion)
}
