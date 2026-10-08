import Foundation

@main
struct AdFilterTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        let matcher = ShadowAdMatcher(markers: .builtIn)
        func ad(_ text: String, _ extra: [String] = []) -> Bool {
            return matcher.isAd(texts: [text] + extra)
        }

        // Marked ads.
        check(ad("Кешбэк 10% на всё.\n\nРеклама. ООО «Ромашка», ИНН 7701234567, erid: 2VtzqwJFKdP"), "Full legal marking")
        check(ad("Откройте вклад под 20% годовых\nerid 2VtzqwJFKdP"), "erid with a space")
        check(ad("Подробнее", ["https://example.com/promo?utm_source=tg&erid=LjN8KXabcde"]), "erid only in a hidden link")
        check(ad("Перейти", ["https://example.com/?erid=2VtzqwJFKdP&x=1"]), "erid in a button URL")
        check(ad("Лучший курс по Python.\n\nРеклама ИП Иванов И.И."), "Реклама ИП")
        check(ad("Рекламодатель: ООО Лаборатория"), "Рекламодатель ООО")
        check(ad("Реклама. ПАО «Банк»"), "Реклама. ПАО")
        check(ad("Скидки до 50%\nИНН: 770123456789"), "12-digit ИНН")
        check(ad("Новая игра уже доступна #реклама"), "#реклама")
        check(ad("Обзор новинки #ad"), "#ad")
        check(ad("Обзор новинки #партнёрский"), "#партнёрский")
        check(ad("Публикуется на правах рекламы"), "на правах рекламы")
        check(ad("Это партнёрский материал от студии"), "партнёрский материал")
        check(ad("Это рекламная интеграция"), "рекламная интеграция")
        check(ad("Купите наш курс!\n\nРеклама"), "Line that is only «Реклама»")
        check(ad("РЕКЛАМА. ООО «Ромашка»"), "Case-insensitive")

        // Ordinary posts that must stay.
        check(!ad("Метро продлевает работу на выходных до 02:00."), "Plain news")
        check(!ad("По вопросам рекламы: @manager"), "Ad contact footer is not an ad")
        check(!ad("Реклама в канале — @sales_bot"), "Ad sales footer is not an ad")
        check(!ad("Рекламодатели уходят из соцсетей, пишут аналитики"), "News about advertisers")
        check(!ad("Реклама ипотеки запрещена с 1 марта"), "Реклама ипотеки — not «Реклама ИП»")
        check(!ad("Попробуйте бота: https://t.me/somebot?start=ref123"), "Referral links are not markers")
        check(!ad("Инна прислала 1234567890 фото"), "Name Инна with digits")
        check(!ad("Federico и Erid… пошли гулять"), "erid without a token")
        check(!ad("#adventure в горах"), "#adventure is not #ad")
        check(!ad("Рекламная пауза на ТВ стала длиннее"), "Рекламная пауза")
        check(!ad(""), "Empty text")

        // Remote file.
        let objects = """
        {"version": 3, "patterns": [{"regex": "erid", "note": "token"}, "#реклама", "(broken", "  "]}
        """.data(using: .utf8)!
        let parsed = ShadowAdMarkers.parse(objects)
        check(parsed?.version == 3, "Version parsed")
        check(parsed?.patterns == ["erid", "#реклама"], "Objects and strings; broken and blank patterns dropped")
        check(ShadowAdMarkers.parse("{\"patterns\": []}".data(using: .utf8)!) == nil, "Empty list keeps the current markers")
        check(ShadowAdMarkers.parse("not json".data(using: .utf8)!) == nil, "Malformed file ignored")
        check(ShadowAdMarkers.parse("{\"patterns\": [\"(broken\"]}".data(using: .utf8)!) == nil, "Only broken patterns ignored")

        // The shipped file in tgfork has to stay in sync with builtIn in spirit:
        // it is parsed by the same code, so every builtIn pattern must compile.
        check(ShadowAdMatcher(markers: .builtIn).isAd(texts: ["erid: 2VtzqwJFKdP"]), "Built-in compiles")
        for pattern in ShadowAdMarkers.builtIn.patterns {
            check((try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil, "Built-in pattern compiles: \(pattern)")
        }

        // Places.
        let defaults = ShadowAdScope(channels: true, groups: false, forwarded: false)
        check(defaults.applies(place: .channel, isForwarded: false), "Channels on by default")
        check(defaults.applies(place: .channel, isForwarded: true), "Channel repost follows channels")
        check(!defaults.applies(place: .group, isForwarded: false), "Groups off by default")
        check(!defaults.applies(place: .privateChat, isForwarded: true), "Forwarded off by default")
        let forwarded = ShadowAdScope(channels: false, groups: false, forwarded: true)
        check(forwarded.applies(place: .privateChat, isForwarded: true), "Forwarded ad in a private chat")
        check(forwarded.applies(place: .group, isForwarded: true), "Forwarded ad in a group")
        check(!forwarded.applies(place: .privateChat, isForwarded: false), "Own words in a private chat never hidden")
        check(!forwarded.applies(place: .channel, isForwarded: true), "Channels follow their own toggle")
        let groups = ShadowAdScope(channels: false, groups: true, forwarded: false)
        check(groups.applies(place: .group, isForwarded: false), "Groups toggle")
        check(groups.applies(place: .group, isForwarded: true), "Groups toggle covers forwards there")
        check(!ShadowAdScope(channels: false, groups: false, forwarded: false).isEnabled, "All off")

        print("Shadow ad filter: \(count) checks passed")
    }
}
