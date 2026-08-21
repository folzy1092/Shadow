import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI

// Shadow fork settings.
//
// The whole settings surface is organised around the three Shadow ideas, one
// pushed sub-screen each:
//   • Кастомизация — appearance and behaviour of the app itself.
//   • Шпион        — keeping information Telegram would otherwise hide or delete.
//   • Призрак      — using Telegram as invisibly as possible.
// The entry point (`ayuGramSettingsController`) is a small hub that pushes those
// three screens. Everything is in Russian. The visual style is the stock
// Telegram settings style (blocks, switches, disclosure rows) — no custom UI.

// The maximum-age steps for the saved-attachments auto-clean, in seconds
// (0 = never). Kept in one place so picker and label stay in sync.
private let attachmentAgeIntervals: [Int32] = [0, 86400, 259200, 604800, 1209600, 2592000, 7776000, 15552000, 31536000]

private func attachmentAgeLabel(_ value: Int32) -> String {
    switch value {
    case 86400:
        return "1 день"
    case 259200:
        return "3 дня"
    case 604800:
        return "7 дней"
    case 1209600:
        return "14 дней"
    case 2592000:
        return "30 дней"
    case 7776000:
        return "90 дней"
    case 15552000:
        return "180 дней"
    case 31536000:
        return "1 год"
    default:
        return "Никогда"
    }
}

// The maximum-size steps for the saved-attachments cache, in bytes (0 = ∞).
private let attachmentSizeLimits: [Int64] = [0, 314572800, 1073741824, 2147483648, 5368709120, 6442450944, 12884901888]

private func attachmentSizeLabel(_ value: Int64) -> String {
    switch value {
    case 314572800:
        return "300 МБ"
    case 1073741824:
        return "1 ГБ"
    case 2147483648:
        return "2 ГБ"
    case 5368709120:
        return "5 ГБ"
    case 6442450944:
        return "6 ГБ"
    case 12884901888:
        return "12 ГБ"
    default:
        return "∞"
    }
}

// MARK: - Hub

private enum AyuHubSection: Int32 {
    case sections
    case info
}

private enum AyuHubEntry: ItemListNodeEntry {
    case customization
    case spy
    case ghost
    case misc
    case infoFooter

    var section: ItemListSectionId {
        switch self {
        case .customization, .spy, .ghost, .misc:
            return AyuHubSection.sections.rawValue
        case .infoFooter:
            return AyuHubSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .customization:
            return 0
        case .spy:
            return 1
        case .ghost:
            return 2
        case .misc:
            return 3
        case .infoFooter:
            return 4
        }
    }

    static func <(lhs: AyuHubEntry, rhs: AyuHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuHubArguments
        switch self {
        case .customization:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Кастомизация", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openCustomization()
            })
        case .spy:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Шпион", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openSpy()
            })
        case .ghost:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Призрак", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGhost()
            })
        case .misc:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Разное", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openMisc()
            })
        case .infoFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Кастомизация — внешний вид и поведение приложения. Шпион — сохранение информации, которую Telegram скрывает или удаляет. Призрак — максимально незаметное использование Telegram. Разное — визуальная подмена данных профиля для скриншотов."), sectionId: self.section)
        }
    }
}

private final class AyuHubArguments {
    let openCustomization: () -> Void
    let openSpy: () -> Void
    let openGhost: () -> Void
    let openMisc: () -> Void

    init(openCustomization: @escaping () -> Void, openSpy: @escaping () -> Void, openGhost: @escaping () -> Void, openMisc: @escaping () -> Void) {
        self.openCustomization = openCustomization
        self.openSpy = openSpy
        self.openGhost = openGhost
        self.openMisc = openMisc
    }
}

public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuHubArguments(
        openCustomization: {
            pushControllerImpl?(ayuCustomizationController(context: context))
        },
        openSpy: {
            pushControllerImpl?(ayuSpyController(context: context))
        },
        openGhost: {
            pushControllerImpl?(ayuGhostController(context: context))
        },
        openMisc: {
            pushControllerImpl?(ayuMiscController(context: context))
        }
    )

    let entries: [AyuHubEntry] = [.customization, .spy, .ghost, .misc, .infoFooter]

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Shadow"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// A small shared helper for the sub-controllers.
private func ayuUpdateSettings(context: AccountContext, _ f: @escaping (AyuGramSettings) -> AyuGramSettings) {
    let _ = updateAyuGramSettings(postbox: context.account.postbox, { current in
        return f(current)
    }).start()
}

// MARK: - Кастомизация

private final class AyuCustomizationArguments {
    let updateShowMessageSeconds: (Bool) -> Void
    let updateEditedIndicatorAsPencil: (Bool) -> Void
    let updateRegularEmojiFirst: (Bool) -> Void
    let updateDoubleTapToEdit: (Bool) -> Void
    let updateShowExactLastSeen: (Bool) -> Void
    let updateShowExactLastSeenSeconds: (Bool) -> Void
    let updateWideChannelPosts: (Bool) -> Void
    let updateShowExactViewCounts: (Bool) -> Void
    let updateShowForwardCount: (Bool) -> Void
    let updateRoundVideoBackCamera: (Bool) -> Void
    let updateShowCameraTile: (Bool) -> Void
    let updateCameraTileLivePreview: (Bool) -> Void
    let updateConfirmCalls: (Bool) -> Void
    let updateHideAllChatsFolder: (Bool) -> Void
    let updateFoldersAtBottom: (Bool) -> Void
    let updateHideBottomSearch: (Bool) -> Void
    let updateCompactBottomBar: (Bool) -> Void
    let updateShowProfileId: (Bool) -> Void
    let updateShowProfileDC: (Bool) -> Void
    let updateShowRegistrationDate: (Bool) -> Void
    let updateHideOwnPhoneNumber: (Bool) -> Void
    let syncGitConfig: () -> Void
    let updateCustomBanner: (Bool) -> Void
    let chooseBanner: () -> Void
    let updateCustomProfileBackground: (Bool) -> Void
    let updateCustomProfileBackgroundForOthers: (Bool) -> Void
    let updateCustomProfileBackgroundForSettings: (Bool) -> Void
    let chooseProfileBackground: () -> Void

    init(
        updateShowMessageSeconds: @escaping (Bool) -> Void,
        updateEditedIndicatorAsPencil: @escaping (Bool) -> Void,
        updateRegularEmojiFirst: @escaping (Bool) -> Void,
        updateDoubleTapToEdit: @escaping (Bool) -> Void,
        updateShowExactLastSeen: @escaping (Bool) -> Void,
        updateShowExactLastSeenSeconds: @escaping (Bool) -> Void,
        updateWideChannelPosts: @escaping (Bool) -> Void,
        updateShowExactViewCounts: @escaping (Bool) -> Void,
        updateShowForwardCount: @escaping (Bool) -> Void,
        updateRoundVideoBackCamera: @escaping (Bool) -> Void,
        updateShowCameraTile: @escaping (Bool) -> Void,
        updateCameraTileLivePreview: @escaping (Bool) -> Void,
        updateConfirmCalls: @escaping (Bool) -> Void,
        updateHideAllChatsFolder: @escaping (Bool) -> Void,
        updateFoldersAtBottom: @escaping (Bool) -> Void,
        updateHideBottomSearch: @escaping (Bool) -> Void,
        updateCompactBottomBar: @escaping (Bool) -> Void,
        updateShowProfileId: @escaping (Bool) -> Void,
        updateShowProfileDC: @escaping (Bool) -> Void,
        updateShowRegistrationDate: @escaping (Bool) -> Void,
        updateHideOwnPhoneNumber: @escaping (Bool) -> Void,
        syncGitConfig: @escaping () -> Void,
        updateCustomBanner: @escaping (Bool) -> Void,
        chooseBanner: @escaping () -> Void,
        updateCustomProfileBackground: @escaping (Bool) -> Void,
        updateCustomProfileBackgroundForOthers: @escaping (Bool) -> Void,
        updateCustomProfileBackgroundForSettings: @escaping (Bool) -> Void,
        chooseProfileBackground: @escaping () -> Void
    ) {
        self.updateShowMessageSeconds = updateShowMessageSeconds
        self.updateEditedIndicatorAsPencil = updateEditedIndicatorAsPencil
        self.updateRegularEmojiFirst = updateRegularEmojiFirst
        self.updateDoubleTapToEdit = updateDoubleTapToEdit
        self.updateShowExactLastSeen = updateShowExactLastSeen
        self.updateShowExactLastSeenSeconds = updateShowExactLastSeenSeconds
        self.updateWideChannelPosts = updateWideChannelPosts
        self.updateShowExactViewCounts = updateShowExactViewCounts
        self.updateShowForwardCount = updateShowForwardCount
        self.updateRoundVideoBackCamera = updateRoundVideoBackCamera
        self.updateShowCameraTile = updateShowCameraTile
        self.updateCameraTileLivePreview = updateCameraTileLivePreview
        self.updateConfirmCalls = updateConfirmCalls
        self.updateHideAllChatsFolder = updateHideAllChatsFolder
        self.updateFoldersAtBottom = updateFoldersAtBottom
        self.updateHideBottomSearch = updateHideBottomSearch
        self.updateCompactBottomBar = updateCompactBottomBar
        self.updateShowProfileId = updateShowProfileId
        self.updateShowProfileDC = updateShowProfileDC
        self.updateShowRegistrationDate = updateShowRegistrationDate
        self.updateHideOwnPhoneNumber = updateHideOwnPhoneNumber
        self.syncGitConfig = syncGitConfig
        self.updateCustomBanner = updateCustomBanner
        self.chooseBanner = chooseBanner
        self.updateCustomProfileBackground = updateCustomProfileBackground
        self.updateCustomProfileBackgroundForOthers = updateCustomProfileBackgroundForOthers
        self.updateCustomProfileBackgroundForSettings = updateCustomProfileBackgroundForSettings
        self.chooseProfileBackground = chooseProfileBackground
    }
}

private enum AyuCustomizationSection: Int32 {
    case buildInfo
    case appearance
    case chats
    case bottomBar
    case profiles
    case media
    case calls
    case githubConfig
    case banner
    case profileBackground
}

private enum AyuCustomizationEntry: ItemListNodeEntry {
    // Shadow: shown at the very top so a build can always be identified from
    // inside the app — this session's repeated "which build is this" confusion
    // (a compile error meant an earlier push never actually produced an
    // installable IPA, but there was no way to tell from the device alone)
    // is exactly what this is for. CFBundleVersion here is the exact commit-
    // count-based BUILD_NUMBER the CI workflow already stamps into the IPA
    // (same number the Telegram/Discord "Сборка готова" notification prints),
    // so no new build-system wiring is needed — just surfacing existing data.
    case buildInfo
    case appearanceHeader
    case showMessageSeconds(Bool)
    case editedIndicatorAsPencil(Bool)
    case regularEmojiFirst(Bool)
    case doubleTapToEdit(Bool)
    case showExactLastSeen(Bool)
    case showExactLastSeenSeconds(Bool)
    case wideChannelPosts(Bool)
    case showExactViewCounts(Bool)
    case showForwardCount(Bool)
    case appearanceFooter

    case chatsHeader
    case hideAllChatsFolder(Bool)
    case chatsFooter

    case bottomBarHeader
    case foldersAtBottom(Bool)
    case hideBottomSearch(Bool)
    case compactBottomBar(Bool)
    case bottomBarFooter

    case profilesHeader
    case showProfileId(Bool)
    case showProfileDC(Bool)
    case showRegistrationDate(Bool)
    case hideOwnPhoneNumber(Bool)
    case profilesFooter

    case mediaHeader
    case roundVideoBackCamera(Bool)
    case showCameraTile(Bool)
    case cameraTileLivePreview(Bool)
    case mediaFooter

    case callsHeader
    case confirmCalls(Bool)
    case callsFooter

    case githubConfigHeader
    case syncGithub
    case githubConfigFooter

    case bannerHeader
    case customBanner(Bool)
    case bannerChoose
    case bannerFooter

    case profileBackgroundHeader
    case customProfileBackground(Bool)
    case customProfileBackgroundForOthers(Bool)
    case customProfileBackgroundForSettings(Bool)
    case profileBackgroundChoose
    case profileBackgroundFooter

    var section: ItemListSectionId {
        switch self {
        case .buildInfo:
            return AyuCustomizationSection.buildInfo.rawValue
        case .appearanceHeader, .showMessageSeconds, .editedIndicatorAsPencil, .regularEmojiFirst, .doubleTapToEdit, .showExactLastSeen, .showExactLastSeenSeconds, .wideChannelPosts, .showExactViewCounts, .showForwardCount, .appearanceFooter:
            return AyuCustomizationSection.appearance.rawValue
        case .chatsHeader, .hideAllChatsFolder, .chatsFooter:
            return AyuCustomizationSection.chats.rawValue
        case .bottomBarHeader, .foldersAtBottom, .hideBottomSearch, .compactBottomBar, .bottomBarFooter:
            return AyuCustomizationSection.bottomBar.rawValue
        case .profilesHeader, .showProfileId, .showProfileDC, .showRegistrationDate, .hideOwnPhoneNumber, .profilesFooter:
            return AyuCustomizationSection.profiles.rawValue
        case .mediaHeader, .roundVideoBackCamera, .showCameraTile, .cameraTileLivePreview, .mediaFooter:
            return AyuCustomizationSection.media.rawValue
        case .callsHeader, .confirmCalls, .callsFooter:
            return AyuCustomizationSection.calls.rawValue
        case .githubConfigHeader, .syncGithub, .githubConfigFooter:
            return AyuCustomizationSection.githubConfig.rawValue
        case .bannerHeader, .customBanner, .bannerChoose, .bannerFooter:
            return AyuCustomizationSection.banner.rawValue
        case .profileBackgroundHeader, .customProfileBackground, .customProfileBackgroundForOthers, .customProfileBackgroundForSettings, .profileBackgroundChoose, .profileBackgroundFooter:
            return AyuCustomizationSection.profileBackground.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .buildInfo: return -1
        case .appearanceHeader: return 0
        case .showMessageSeconds: return 1
        case .editedIndicatorAsPencil: return 2
        case .regularEmojiFirst: return 3
        case .doubleTapToEdit: return 4
        case .showExactLastSeen: return 5
        case .showExactLastSeenSeconds: return 6
        case .wideChannelPosts: return 7
        case .showExactViewCounts: return 8
        case .showForwardCount: return 9
        case .appearanceFooter: return 10
        case .chatsHeader: return 11
        case .hideAllChatsFolder: return 12
        case .chatsFooter: return 13
        case .bottomBarHeader: return 14
        case .foldersAtBottom: return 15
        case .hideBottomSearch: return 16
        case .compactBottomBar: return 17
        case .bottomBarFooter: return 18
        case .profilesHeader: return 19
        case .showProfileId: return 20
        case .showProfileDC: return 21
        case .showRegistrationDate: return 22
        case .hideOwnPhoneNumber: return 23
        case .profilesFooter: return 24
        case .mediaHeader: return 25
        case .roundVideoBackCamera: return 26
        case .showCameraTile: return 27
        case .cameraTileLivePreview: return 28
        case .mediaFooter: return 29
        case .callsHeader: return 30
        case .confirmCalls: return 31
        case .callsFooter: return 32
        case .githubConfigHeader: return 33
        case .syncGithub: return 34
        case .githubConfigFooter: return 35
        case .bannerHeader: return 36
        case .customBanner: return 37
        case .bannerChoose: return 38
        case .bannerFooter: return 39
        case .profileBackgroundHeader: return 40
        case .customProfileBackground: return 41
        case .customProfileBackgroundForOthers: return 42
        case .customProfileBackgroundForSettings: return 43
        case .profileBackgroundChoose: return 44
        case .profileBackgroundFooter: return 45
        }
    }

    static func <(lhs: AyuCustomizationEntry, rhs: AyuCustomizationEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuCustomizationArguments
        switch self {
        case .buildInfo:
            let bundle = Bundle.main
            let bundleVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
            let bundleBuild = (bundle.infoDictionary?[kCFBundleVersionKey as String] as? String) ?? ""
            return ItemListTextItem(presentationData: presentationData, text: .plain("Shadow \(bundleVersion) (build \(bundleBuild))"), sectionId: self.section)
        case .appearanceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОФОРМЛЕНИЕ", sectionId: self.section)
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Секунды в метках времени", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowMessageSeconds(value)
            })
        case let .editedIndicatorAsPencil(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Значок ✎ вместо «Изменено»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateEditedIndicatorAsPencil(value)
            })
        case let .regularEmojiFirst(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Обычные эмодзи в начале клавиатуры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRegularEmojiFirst(value)
            })
        case let .doubleTapToEdit(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Двойной тап — редактирование", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateDoubleTapToEdit(value)
            })
        case let .showExactLastSeen(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Точное время последнего захода", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactLastSeen(value)
            })
        case let .showExactLastSeenSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Секунды у последнего захода", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactLastSeenSeconds(value)
            })
        case let .wideChannelPosts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Широкие посты в каналах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateWideChannelPosts(value)
            })
        case let .showExactViewCounts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Точные просмотры на постах", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowExactViewCounts(value)
            })
        case let .showForwardCount(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Счётчик пересылок", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowForwardCount(value)
            })
        case .appearanceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Секунды в метках времени» показывают ЧЧ:ММ:СС вместо ЧЧ:ММ. «Двойной тап — редактирование» открывает редактирование при двойном нажатии на своё сообщение. «Точное время последнего захода» вместо «был в сети час назад» показывает точное время, например «был в сети сегодня в 12:10»; дополнительный переключатель «Секунды у последнего захода» добавляет к нему секунды («12:10:12»). «Широкие посты в каналах» отображают сообщения каналов на увеличенную ширину — удобно для длинных постов и статей. Влияет только на каналы: личные чаты и группы не меняются. «Точные просмотры на постах» показывают полное число просмотров (5678) вместо сокращённого (5.6K). «Счётчик пересылок» показывает рядом со временем, сколько раз сообщение переслали (приходит только для постов в каналах, как и просмотры)."), sectionId: self.section)
        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧАТЫ", sectionId: self.section)
        case let .hideAllChatsFolder(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть папку «Все чаты»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideAllChatsFolder(value)
            })
        case .chatsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Убирает вкладку «Все чаты» из списка чатов. Остальные папки продолжают работать."), sectionId: self.section)
        case .bottomBarHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НИЖНИЙ ИНТЕРФЕЙС", sectionId: self.section)
        case let .foldersAtBottom(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Папки снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateFoldersAtBottom(value)
            })
        case let .hideBottomSearch(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Убрать поиск снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideBottomSearch(value)
            })
        case let .compactBottomBar(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Уменьшить интерфейс снизу", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCompactBottomBar(value)
            })
        case .bottomBarFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Папки снизу» показывают папки чатов над нижней панелью. «Убрать поиск снизу» скрывает нижнюю кнопку поиска, чтобы поиск не дублировался (верхняя строка поиска не затрагивается). «Уменьшить интерфейс снизу» делает нижнюю панель компактнее. Все три переключателя работают независимо."), sectionId: self.section)
        case .profilesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПРОФИЛЬ", sectionId: self.section)
        case let .showProfileId(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "ID профиля (Bot API)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileId(value)
            })
        case let .showProfileDC(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Дата-центр (DC)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowProfileDC(value)
            })
        case let .showRegistrationDate(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Дата регистрации", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowRegistrationDate(value)
            })
        case let .hideOwnPhoneNumber(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрыть свой номер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideOwnPhoneNumber(value)
            })
        case .profilesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Показывать в профилях пользователей, ботов и каналов дополнительные поля: числовой ID (в формате Bot API, копируется по удержанию), дата-центр фото профиля и примерную дату регистрации. Дата регистрации приблизительная — Telegram не раскрывает точную.\n\n«Скрыть свой номер» полностью убирает плашку с вашим номером телефона в настройках/профиле."), sectionId: self.section)
        case .mediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МЕДИА", sectionId: self.section)
        case let .roundVideoBackCamera(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кружки на заднюю камеру", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateRoundVideoBackCamera(value)
            })
        case let .showCameraTile(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Камера в галерее", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowCameraTile(value)
            })
        case let .cameraTileLivePreview(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Живой предпросмотр камеры", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCameraTileLivePreview(value)
            })
        case .mediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Начинать запись видеосообщений («кружков») с задней камеры. Во время записи можно переключиться на фронтальную. «Камера в галерее» показывает плитку камеры первой ячейкой в галерее вложений. «Живой предпросмотр камеры» запускает в этой плитке видео с камеры вживую вместо статичной иконки."), sectionId: self.section)
        case .callsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗВОНКИ", sectionId: self.section)
        case let .confirmCalls(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подтверждение звонков", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateConfirmCalls(value)
            })
        case .callsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Перед аудио- или видеозвонком запрашивать подтверждение — защита от случайного нажатия. Не влияет на входящие звонки."), sectionId: self.section)
        case .githubConfigHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КОНФИГУРАЦИЯ GITHUB", sectionId: self.section)
        case .syncGithub:
            return ItemListActionItem(presentationData: presentationData, title: "Синхронизировать с GitHub", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.syncGitConfig()
            })
        case .githubConfigFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Загружает актуальные значки профилей и каналов из конфигурации GitHub. Значки также обновляются при запуске; эта кнопка обновляет их немедленно."), sectionId: self.section)
        case .bannerHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "БАННЕР", sectionId: self.section)
        case let .customBanner(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кастомный баннер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomBanner(value)
            })
        case .bannerChoose:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать изображение", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.chooseBanner()
            })
        case .bannerFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Отображает выбранное изображение как фон верхней части списка чатов (за историями, заголовком и поиском). Внизу баннера — затемнение для читаемости текста. Выключите переключатель, чтобы вернуть стандартный вид."), sectionId: self.section)
        case .profileBackgroundHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ФОН ПРОФИЛЯ", sectionId: self.section)
        case let .customProfileBackground(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Кастомный фон профиля", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackground(value)
            })
        case let .customProfileBackgroundForOthers(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Применять для всех профилей", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackgroundForOthers(value)
            })
        case let .customProfileBackgroundForSettings(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Применять в Settings", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateCustomProfileBackgroundForSettings(value)
            })
        case .profileBackgroundChoose:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать изображение", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.chooseProfileBackground()
            })
        case .profileBackgroundFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Отображает выбранное изображение как фон верхней части экрана «Мой профиль» (за аватаром и именем), с затемнением по всей области для читаемости и плавным переходом в обычный фон внизу. Работает только визуально в интерфейсе Shadow и видно только вам — другие пользователи и другие устройства видят обычный профиль. Заменяет собой стандартный цвет/эмодзи-статус профиля, если он у вас включён."), sectionId: self.section)
        }
    }
}

private func ayuCustomizationEntries(settings: AyuGramSettings) -> [AyuCustomizationEntry] {
    var entries: [AyuCustomizationEntry] = []

    entries.append(.buildInfo)
    entries.append(.appearanceHeader)
    entries.append(.showMessageSeconds(settings.showMessageSeconds))
    entries.append(.editedIndicatorAsPencil(settings.editedIndicatorAsPencil))
    entries.append(.regularEmojiFirst(settings.regularEmojiFirst))
    entries.append(.doubleTapToEdit(settings.doubleTapToEdit))
    entries.append(.showExactLastSeen(settings.showExactLastSeen))
    if settings.showExactLastSeen {
        entries.append(.showExactLastSeenSeconds(settings.showExactLastSeenSeconds))
    }
    entries.append(.wideChannelPosts(settings.wideChannelPosts))
    entries.append(.showExactViewCounts(settings.showExactViewCounts))
    entries.append(.showForwardCount(settings.showForwardCount))
    entries.append(.appearanceFooter)

    entries.append(.chatsHeader)
    entries.append(.hideAllChatsFolder(settings.hideAllChatsFolder))
    entries.append(.chatsFooter)

    entries.append(.bottomBarHeader)
    entries.append(.foldersAtBottom(settings.foldersAtBottom))
    entries.append(.hideBottomSearch(settings.hideBottomSearch))
    entries.append(.compactBottomBar(settings.compactBottomBar))
    entries.append(.bottomBarFooter)

    entries.append(.profilesHeader)
    entries.append(.showProfileId(settings.showProfileId))
    entries.append(.showProfileDC(settings.showProfileDC))
    entries.append(.showRegistrationDate(settings.showRegistrationDate))
    entries.append(.hideOwnPhoneNumber(settings.hideOwnPhoneNumber))
    entries.append(.profilesFooter)

    entries.append(.mediaHeader)
    entries.append(.roundVideoBackCamera(settings.roundVideoUseBackCamera))
    entries.append(.showCameraTile(settings.showCameraTile))
    entries.append(.cameraTileLivePreview(settings.cameraTileLivePreview))
    entries.append(.mediaFooter)

    entries.append(.callsHeader)
    entries.append(.confirmCalls(settings.confirmCalls))
    entries.append(.callsFooter)

    entries.append(.githubConfigHeader)
    entries.append(.syncGithub)
    entries.append(.githubConfigFooter)

    entries.append(.bannerHeader)
    entries.append(.customBanner(settings.customBannerEnabled))
    if settings.customBannerEnabled {
        entries.append(.bannerChoose)
    }
    entries.append(.bannerFooter)

    entries.append(.profileBackgroundHeader)
    entries.append(.customProfileBackground(settings.customProfileBackgroundEnabled))
    if settings.customProfileBackgroundEnabled {
        entries.append(.customProfileBackgroundForOthers(settings.customProfileBackgroundForOthers))
        entries.append(.customProfileBackgroundForSettings(settings.customProfileBackgroundForSettings))
        entries.append(.profileBackgroundChoose)
    }
    entries.append(.profileBackgroundFooter)

    return entries
}

private func ayuCustomizationController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var presentBannerImagePickerImpl: (() -> Void)?
    var presentProfileBackgroundImagePickerImpl: (() -> Void)?

    let arguments = AyuCustomizationArguments(
        updateShowMessageSeconds: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showMessageSeconds = value; return s }
        },
        updateEditedIndicatorAsPencil: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.editedIndicatorAsPencil = value; return s }
        },
        updateRegularEmojiFirst: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.regularEmojiFirst = value; return s }
        },
        updateDoubleTapToEdit: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.doubleTapToEdit = value; return s }
        },
        updateShowExactLastSeen: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactLastSeen = value; return s }
        },
        updateShowExactLastSeenSeconds: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactLastSeenSeconds = value; return s }
        },
        updateWideChannelPosts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.wideChannelPosts = value; return s }
        },
        updateShowExactViewCounts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showExactViewCounts = value; return s }
        },
        updateShowForwardCount: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showForwardCount = value; return s }
        },
        updateRoundVideoBackCamera: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.roundVideoUseBackCamera = value; return s }
        },
        updateShowCameraTile: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showCameraTile = value; return s }
        },
        updateCameraTileLivePreview: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.cameraTileLivePreview = value; return s }
        },
        updateConfirmCalls: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.confirmCalls = value; return s }
        },
        updateHideAllChatsFolder: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideAllChatsFolder = value; return s }
        },
        updateFoldersAtBottom: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.foldersAtBottom = value; return s }
        },
        updateHideBottomSearch: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideBottomSearch = value; return s }
        },
        updateCompactBottomBar: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.compactBottomBar = value; return s }
        },
        updateShowProfileId: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showProfileId = value; return s }
        },
        updateShowProfileDC: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showProfileDC = value; return s }
        },
        updateShowRegistrationDate: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.showRegistrationDate = value; return s }
        },
        updateHideOwnPhoneNumber: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideOwnPhoneNumber = value; return s }
        },
        syncGitConfig: {
            refreshGitConfig(completion: { success in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let text = success ? "Значки обновлены с GitHub." : "Не удалось связаться с GitHub. Попробуйте позже."
                presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            })
        },
        updateCustomBanner: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customBannerEnabled = value; return s }
            if !value {
                // Turning the banner off also drops the stored image, so re-enabling
                // starts clean.
                let _ = AyuSavedMedia.removeBanner(basePath: context.account.postbox.mediaBox.basePath)
            }
        },
        chooseBanner: {
            presentBannerImagePickerImpl?()
        },
        updateCustomProfileBackground: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundEnabled = value; return s }
            if !value {
                let _ = AyuSavedMedia.removeProfileBackground(basePath: context.account.postbox.mediaBox.basePath)
            }
        },
        updateCustomProfileBackgroundForOthers: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundForOthers = value; return s }
        },
        updateCustomProfileBackgroundForSettings: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundForSettings = value; return s }
        },
        chooseProfileBackground: {
            presentProfileBackgroundImagePickerImpl?()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Кастомизация"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuCustomizationEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }

    // Shadow: present the system photo picker, then persist the picked image as
    // the custom banner via AyuSavedMedia. The delegate keeps a strong reference
    // to itself until the picker finishes, so it isn't deallocated mid-flow.
    presentBannerImagePickerImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        let delegate = BannerImagePickerDelegate(completion: { image in
            guard let image = image, let data = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            let _ = AyuSavedMedia.saveBanner(basePath: context.account.postbox.mediaBox.basePath, jpegData: data)
            ayuUpdateSettings(context: context) { var s = $0; s.customBannerEnabled = true; return s }
        })
        delegate.retainSelf()
        picker.delegate = delegate
        controller.view.window?.rootViewController?.present(picker, animated: true)
    }

    // Same picker pattern for the "Мой профиль" custom background.
    presentProfileBackgroundImagePickerImpl = { [weak controller] in
        guard let controller = controller else {
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        let delegate = BannerImagePickerDelegate(completion: { image in
            guard let image = image, let data = image.jpegData(compressionQuality: 0.9) else {
                return
            }
            let _ = AyuSavedMedia.saveProfileBackground(basePath: context.account.postbox.mediaBox.basePath, jpegData: data)
            ayuUpdateSettings(context: context) { var s = $0; s.customProfileBackgroundEnabled = true; return s }
        })
        delegate.retainSelf()
        picker.delegate = delegate
        controller.view.window?.rootViewController?.present(picker, animated: true)
    }
    return controller
}

// Retained delegate for the banner photo picker: returns the picked image (or
// nil on cancel) and always dismisses the picker.
private final class BannerImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (UIImage?) -> Void
    // Self-retain cycle held only for the picker's lifetime (see retainSelf()).
    private var selfReference: BannerImagePickerDelegate?

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    // Keep this delegate alive (UIImagePickerController's delegate is weak) until
    // the picker finishes or is cancelled.
    func retainSelf() {
        self.selfReference = self
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true)
        self.completion(image)
        self.selfReference = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        self.completion(nil)
        self.selfReference = nil
    }
}

private final class AyuSpyArguments {
    let updateKeepDeleted: (Bool) -> Void
    let updateSaveEditHistory: (Bool) -> Void
    let updateKeepSelfDestructMedia: (Bool) -> Void
    let updateAllowSaveRestrictedContent: (Bool) -> Void
    let updateAskBeforeStoryView: (Bool) -> Void
    let updateSaveDestructingMedia: (Bool) -> Void
    let updateSaveAllIncomingMedia: (Bool) -> Void
    let selectAttachmentSizeLimit: () -> Void
    let selectAttachmentAge: () -> Void
    let updateKeepPinned: (Bool) -> Void
    let updateKeepChannels: (Bool) -> Void
    let updateKeepBots: (Bool) -> Void
    let openForkStorage: () -> Void

    init(
        updateKeepDeleted: @escaping (Bool) -> Void,
        updateSaveEditHistory: @escaping (Bool) -> Void,
        updateKeepSelfDestructMedia: @escaping (Bool) -> Void,
        updateAllowSaveRestrictedContent: @escaping (Bool) -> Void,
        updateAskBeforeStoryView: @escaping (Bool) -> Void,
        updateSaveDestructingMedia: @escaping (Bool) -> Void,
        updateSaveAllIncomingMedia: @escaping (Bool) -> Void,
        selectAttachmentSizeLimit: @escaping () -> Void,
        selectAttachmentAge: @escaping () -> Void,
        updateKeepPinned: @escaping (Bool) -> Void,
        updateKeepChannels: @escaping (Bool) -> Void,
        updateKeepBots: @escaping (Bool) -> Void,
        openForkStorage: @escaping () -> Void
    ) {
        self.updateKeepDeleted = updateKeepDeleted
        self.updateSaveEditHistory = updateSaveEditHistory
        self.updateKeepSelfDestructMedia = updateKeepSelfDestructMedia
        self.updateAllowSaveRestrictedContent = updateAllowSaveRestrictedContent
        self.updateAskBeforeStoryView = updateAskBeforeStoryView
        self.updateSaveDestructingMedia = updateSaveDestructingMedia
        self.updateSaveAllIncomingMedia = updateSaveAllIncomingMedia
        self.selectAttachmentSizeLimit = selectAttachmentSizeLimit
        self.selectAttachmentAge = selectAttachmentAge
        self.updateKeepPinned = updateKeepPinned
        self.updateKeepChannels = updateKeepChannels
        self.updateKeepBots = updateKeepBots
        self.openForkStorage = openForkStorage
    }
}

private enum AyuSpySection: Int32 {
    case deleted
    case edits
    case restricted
    case storyPrompt
    case savedMedia
}

private enum AyuSpyEntry: ItemListNodeEntry {
    case deletedHeader
    case keepDeleted(Bool)
    case keepSelfDestructMedia(Bool)
    case deletedFooter

    case editsHeader
    case saveEditHistory(Bool)
    case editsFooter

    case restrictedHeader
    case allowSaveRestrictedContent(Bool)
    case restrictedFooter

    case storyPromptHeader
    case askBeforeStoryView(Bool)
    case storyPromptFooter

    case savedMediaHeader
    case saveDestructingMedia(Bool)
    case saveAllIncomingMedia(Bool)
    case attachmentSizeLimit(Int64)
    case attachmentAge(Int32)
    case keepPinned(Bool)
    case keepChannels(Bool)
    case keepBots(Bool)
    case forkStorage
    case savedMediaFooter

    var section: ItemListSectionId {
        switch self {
        case .deletedHeader, .keepDeleted, .keepSelfDestructMedia, .deletedFooter:
            return AyuSpySection.deleted.rawValue
        case .editsHeader, .saveEditHistory, .editsFooter:
            return AyuSpySection.edits.rawValue
        case .restrictedHeader, .allowSaveRestrictedContent, .restrictedFooter:
            return AyuSpySection.restricted.rawValue
        case .storyPromptHeader, .askBeforeStoryView, .storyPromptFooter:
            return AyuSpySection.storyPrompt.rawValue
        case .savedMediaHeader, .saveDestructingMedia, .saveAllIncomingMedia, .attachmentSizeLimit, .attachmentAge, .keepPinned, .keepChannels, .keepBots, .forkStorage, .savedMediaFooter:
            return AyuSpySection.savedMedia.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .deletedHeader: return 0
        case .keepDeleted: return 1
        case .keepSelfDestructMedia: return 2
        case .deletedFooter: return 3
        case .editsHeader: return 4
        case .saveEditHistory: return 5
        case .editsFooter: return 6
        case .restrictedHeader: return 7
        case .allowSaveRestrictedContent: return 8
        case .restrictedFooter: return 9
        case .storyPromptHeader: return 10
        case .askBeforeStoryView: return 11
        case .storyPromptFooter: return 12
        case .savedMediaHeader: return 13
        case .saveDestructingMedia: return 14
        case .saveAllIncomingMedia: return 15
        case .attachmentSizeLimit: return 16
        case .attachmentAge: return 17
        case .keepPinned: return 18
        case .keepChannels: return 19
        case .keepBots: return 20
        case .forkStorage: return 21
        case .savedMediaFooter: return 22
        }
    }

    static func <(lhs: AyuSpyEntry, rhs: AyuSpyEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuSpyArguments
        switch self {
        case .deletedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "УДАЛЁННЫЕ СООБЩЕНИЯ", sectionId: self.section)
        case let .keepDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять удалённые", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepDeleted(value)
            })
        case let .keepSelfDestructMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять «одноразовые»", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepSelfDestructMedia(value)
            })
        case .deletedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Сообщения и медиа, которые удаляет собеседник, остаются в чате с меткой и временем удаления: текст, фото, видео, голосовые, видеосообщения и подписи. Ваши собственные удаления не затрагиваются. «Сохранять одноразовые» оставляет view-once / самоуничтожающиеся медиа доступными после просмотра и не сообщает отправителю, что вы их открыли. Работает во всех типах чатов, включая приватные каналы, защищённые и секретные чаты.\n\nУдалённые сообщения, медиа и файлы от ботов также сохраняются всегда. Переключатель «Исключить ботов» в разделе «Сохранённые вложения» влияет только на автоочистку локальной галереи и не отключает сохранение удалённого."), sectionId: self.section)
        case .editsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИЯ ИЗМЕНЕНИЙ", sectionId: self.section)
        case let .saveEditHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять историю правок", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveEditHistory(value)
            })
        case .editsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("При каждом изменении сообщения сохраняется предыдущая версия — старый текст, подписи и медиа. Историю можно открыть через контекстное меню сообщения: там показаны количество изменений, время каждой правки и все прежние версии."), sectionId: self.section)
        case .restrictedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЗАЩИЩЁННЫЙ КОНТЕНТ", sectionId: self.section)
        case let .allowSaveRestrictedContent(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Разрешить сохранение", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAllowSaveRestrictedContent(value)
            })
        case .restrictedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Снимает защиту от копирования: разрешает копировать, пересылать и сохранять в защищённых чатах и приватных каналах."), sectionId: self.section)
        case .storyPromptHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИСТОРИИ", sectionId: self.section)
        case let .askBeforeStoryView(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Спросить перед просмотром истории", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateAskBeforeStoryView(value)
            })
        case .storyPromptFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Если скрытие просмотров историй («Призрак») выключено, перед открытием чужой истории будет предложено включить его. Для собственных историй не спрашивается."), sectionId: self.section)
        case .savedMediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СОХРАНЁННЫЕ ВЛОЖЕНИЯ", sectionId: self.section)
        case let .saveDestructingMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять самоуничтожающиеся", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveDestructingMedia(value)
            })
        case let .saveAllIncomingMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять все входящие медиа", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveAllIncomingMedia(value)
            })
        case let .attachmentSizeLimit(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Лимит размера", label: attachmentSizeLabel(value), sectionId: self.section, style: .blocks, action: {
                arguments.selectAttachmentSizeLimit()
            })
        case let .attachmentAge(value):
            return ItemListDisclosureItem(presentationData: presentationData, title: "Срок хранения", label: attachmentAgeLabel(value), sectionId: self.section, style: .blocks, action: {
                arguments.selectAttachmentAge()
            })
        case let .keepPinned(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не очищать закреплённые", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepPinned(value)
            })
        case let .keepChannels(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Исключить каналы", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepChannels(value)
            })
        case let .keepBots(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Исключить ботов", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateKeepBots(value)
            })
        case .forkStorage:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Хранилище и размер папки", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openForkStorage()
            })
        case .savedMediaFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Приватная локальная копия медиа, которая переживает удаление. «Сохранять самоуничтожающиеся» копирует view-once / TTL-медиа до их исчезновения (и не уведомляет отправителя). «Сохранять все входящие медиа» сохраняет каждое входящее фото, видео, документ, голосовое и кружок — независимо от «Сохранения в галерею» и защиты от копирования.\n\nАвтоочистка работает по двум независимым лимитам, их можно использовать вместе: «Лимит размера» удаляет самые старые файлы при превышении общего размера папки; «Срок хранения» удаляет вложения старше выбранного срока, а также сами сохранённые удалённые сообщения, помеченные корзиной раньше этого срока. При очистке всегда удаляются самые старые файлы. Исключения (закреплённые, каналы, боты) никогда не очищаются. «Хранилище и размер папки» показывает занятое место по чатам."), sectionId: self.section)
        }
    }
}

private func ayuSpyEntries(settings: AyuGramSettings) -> [AyuSpyEntry] {
    var entries: [AyuSpyEntry] = []

    entries.append(.deletedHeader)
    entries.append(.keepDeleted(settings.keepDeletedMessages))
    entries.append(.keepSelfDestructMedia(settings.keepSelfDestructMedia))
    entries.append(.deletedFooter)

    entries.append(.editsHeader)
    entries.append(.saveEditHistory(settings.saveEditHistory))
    entries.append(.editsFooter)

    entries.append(.restrictedHeader)
    entries.append(.allowSaveRestrictedContent(settings.allowSaveRestrictedContent))
    entries.append(.restrictedFooter)

    entries.append(.storyPromptHeader)
    entries.append(.askBeforeStoryView(settings.askBeforeStoryView))
    entries.append(.storyPromptFooter)

    entries.append(.savedMediaHeader)
    entries.append(.saveDestructingMedia(settings.saveDestructingMedia))
    entries.append(.saveAllIncomingMedia(settings.saveAllIncomingMedia))
    entries.append(.attachmentSizeLimit(settings.attachmentSizeLimit))
    entries.append(.attachmentAge(settings.mediaAutoCleanInterval))
    entries.append(.keepPinned(settings.mediaAutoCleanKeepPinned))
    entries.append(.keepChannels(settings.mediaAutoCleanKeepChannels))
    entries.append(.keepBots(settings.mediaAutoCleanKeepBots))
    entries.append(.forkStorage)
    entries.append(.savedMediaFooter)

    return entries
}

private func ayuSpyController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = AyuSpyArguments(
        updateKeepDeleted: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.keepDeletedMessages = value; return s }
        },
        updateSaveEditHistory: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveEditHistory = value; return s }
        },
        updateKeepSelfDestructMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.keepSelfDestructMedia = value; return s }
        },
        updateAllowSaveRestrictedContent: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.allowSaveRestrictedContent = value; return s }
        },
        updateAskBeforeStoryView: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.askBeforeStoryView = value; return s }
        },
        updateSaveDestructingMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveDestructingMedia = value; return s }
        },
        updateSaveAllIncomingMedia: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.saveAllIncomingMedia = value; return s }
        },
        selectAttachmentSizeLimit: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for limit in attachmentSizeLimits {
                items.append(ActionSheetButtonItem(title: attachmentSizeLabel(limit), action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var s = $0; s.attachmentSizeLimit = limit; return s }
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        selectAttachmentAge: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            var items: [ActionSheetItem] = []
            for interval in attachmentAgeIntervals {
                items.append(ActionSheetButtonItem(title: attachmentAgeLabel(interval), action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanInterval = interval; return s }
                }))
            }
            actionSheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(actionSheet, nil)
        },
        updateKeepPinned: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepPinned = value; return s }
        },
        updateKeepChannels: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepChannels = value; return s }
        },
        updateKeepBots: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.mediaAutoCleanKeepBots = value; return s }
        },
        openForkStorage: {
            pushControllerImpl?(ayuForkStorageController(context: context))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Шпион"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuSpyEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Призрак

private final class AyuGhostArguments {
    let updateGhostMode: (Bool) -> Void
    let updateHideOnline: (Bool) -> Void
    let updateHideTyping: (Bool) -> Void
    let updateHideReadReceipts: (Bool) -> Void
    let updateHideStoryViews: (Bool) -> Void
    let updateSendViaScheduled: (Bool) -> Void
    let updateSendWithoutOnline: (Bool) -> Void

    init(
        updateGhostMode: @escaping (Bool) -> Void,
        updateHideOnline: @escaping (Bool) -> Void,
        updateHideTyping: @escaping (Bool) -> Void,
        updateHideReadReceipts: @escaping (Bool) -> Void,
        updateHideStoryViews: @escaping (Bool) -> Void,
        updateSendViaScheduled: @escaping (Bool) -> Void,
        updateSendWithoutOnline: @escaping (Bool) -> Void
    ) {
        self.updateGhostMode = updateGhostMode
        self.updateHideOnline = updateHideOnline
        self.updateHideTyping = updateHideTyping
        self.updateHideReadReceipts = updateHideReadReceipts
        self.updateHideStoryViews = updateHideStoryViews
        self.updateSendViaScheduled = updateSendViaScheduled
        self.updateSendWithoutOnline = updateSendWithoutOnline
    }
}

private enum AyuGhostSection: Int32 {
    case ghost
    case sending
}

private enum AyuGhostEntry: ItemListNodeEntry {
    case ghostHeader
    case ghostMode(Bool)
    case hideOnline(Bool)
    case hideTyping(Bool)
    case hideReadReceipts(Bool)
    case hideStoryViews(Bool)
    case ghostFooter

    case sendingHeader
    case sendViaScheduled(Bool)
    case sendWithoutOnline(Bool)
    case sendingFooter

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMode, .hideOnline, .hideTyping, .hideReadReceipts, .hideStoryViews, .ghostFooter:
            return AyuGhostSection.ghost.rawValue
        case .sendingHeader, .sendViaScheduled, .sendWithoutOnline, .sendingFooter:
            return AyuGhostSection.sending.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader: return 0
        case .ghostMode: return 1
        case .hideOnline: return 2
        case .hideTyping: return 3
        case .hideReadReceipts: return 4
        case .hideStoryViews: return 5
        case .ghostFooter: return 6
        case .sendingHeader: return 7
        case .sendViaScheduled: return 8
        case .sendWithoutOnline: return 9
        case .sendingFooter: return 10
        }
    }

    static func <(lhs: AyuGhostEntry, rhs: AyuGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGhostArguments
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "РЕЖИМ ПРИЗРАКА", sectionId: self.section)
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Режим призрака", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateGhostMode(value)
            })
        case let .hideOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не показывать онлайн", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideOnline(value)
            })
        case let .hideTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не показывать набор текста", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideTyping(value)
            })
        case let .hideReadReceipts(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Не отправлять прочтения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideReadReceipts(value)
            })
        case let .hideStoryViews(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Скрывать просмотры историй", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateHideStoryViews(value)
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Режим призрака» — главный переключатель. Пока он выключен, ни один из переключателей ниже не действует, даже если включён — онлайн, прочтения, набор текста, запись, загрузка и просмотры историй сообщаются как обычно. Включите «Режим призрака», чтобы переключатели ниже вступили в силу.\n\n«Не отправлять прочтения» не даёт чтению чата отмечать вас онлайн — вы остаётесь офлайн даже после открытия сообщений — и скрывает галочки прочтения от отправителя (счётчики непрочитанного при этом обнуляются локально). «Скрывать просмотры историй» убирает вас из списка зрителей. Чужой статус вы продолжаете видеть как обычно."), sectionId: self.section)
        case .sendingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ОТЛОЖЕННАЯ ОТПРАВКА", sectionId: self.section)
        case let .sendViaScheduled(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отправлять через отложенные сообщения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendViaScheduled(value)
            })
        case let .sendWithoutOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Отправлять без появления онлайн", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSendWithoutOnline(value)
            })
        case .sendingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Помогает отправлять сообщения, не появляясь онлайн.\n\nРаботает только при включённом режиме призрака. «Отправлять через отложенные сообщения» отправляет сообщения как запланированные (schedule_date): текст — с задержкой 12 секунд, медиа (фото, видео, документы, голосовые, видеосообщения) — с динамической задержкой. Сервер публикует их позже и не отмечает вас онлайн в момент отправки. «Отправлять без появления онлайн» дополнительно сразу переустанавливает статус «офлайн» после отправки."), sectionId: self.section)
        }
    }
}

private func ayuGhostEntries(settings: AyuGramSettings) -> [AyuGhostEntry] {
    return [
        .ghostHeader,
        .ghostMode(settings.ghostMode),
        .hideOnline(settings.hideOnlineStatus),
        .hideTyping(settings.hideTyping),
        .hideReadReceipts(settings.hideReadReceipts),
        .hideStoryViews(settings.hideStoryViews),
        .ghostFooter,
        .sendingHeader,
        .sendViaScheduled(settings.sendViaScheduled),
        .sendWithoutOnline(settings.sendWithoutOnline),
        .sendingFooter
    ]
}

private func ayuGhostController(context: AccountContext) -> ViewController {
    let arguments = AyuGhostArguments(
        updateGhostMode: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.ghostMode = value; return s }
        },
        updateHideOnline: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideOnlineStatus = value; return s }
        },
        updateHideTyping: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideTyping = value; return s }
        },
        updateHideReadReceipts: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideReadReceipts = value; return s }
        },
        updateHideStoryViews: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.hideStoryViews = value; return s }
        },
        updateSendViaScheduled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.sendViaScheduled = value; return s }
        },
        updateSendWithoutOnline: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.sendWithoutOnline = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Призрак"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuGhostEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}

// MARK: - Разное (visual profile spoofing for screenshots)

private enum AyuMiscSection: Int32 {
    case profileSpoof
}

private enum AyuMiscEntryTag: ItemListItemTag {
    case spoofId
    case spoofDc
    case spoofPhone

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? AyuMiscEntryTag, other == self {
            return true
        }
        return false
    }
}

private enum AyuMiscEntry: ItemListNodeEntry {
    case spoofHeader
    case spoofIdToggle(Bool)
    case spoofIdInput(String)
    case spoofDcToggle(Bool)
    case spoofDcInput(String)
    case spoofPhoneToggle(Bool)
    case spoofPhoneInput(String)
    case spoofFooter

    var section: ItemListSectionId {
        return AyuMiscSection.profileSpoof.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .spoofHeader: return 0
        case .spoofIdToggle: return 1
        case .spoofIdInput: return 2
        case .spoofDcToggle: return 3
        case .spoofDcInput: return 4
        case .spoofPhoneToggle: return 5
        case .spoofPhoneInput: return 6
        case .spoofFooter: return 7
        }
    }

    static func <(lhs: AyuMiscEntry, rhs: AyuMiscEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuMiscArguments
        switch self {
        case .spoofHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ВИЗУАЛЬНАЯ ПОДМЕНА ПРОФИЛЯ", sectionId: self.section)
        case let .spoofIdToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить ID", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofIdEnabled(value)
            })
        case let .spoofIdInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "ID", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Например: 2016", type: .number, clearType: .always, tag: AyuMiscEntryTag.spoofId, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofIdValue(updatedText)
            }, shouldUpdateText: { text in
                return text.allSatisfy { $0.isNumber }
            }, action: {})
        case let .spoofDcToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить DC", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofDcEnabled(value)
            })
        case let .spoofDcInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "DC", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Например: 5", type: .regular(capitalization: false, autocorrection: false), clearType: .always, tag: AyuMiscEntryTag.spoofDc, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofDcValue(updatedText)
            }, action: {})
        case let .spoofPhoneToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Подменить номер", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSpoofPhoneEnabled(value)
            })
        case let .spoofPhoneInput(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Номер", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "Только цифры, без +", type: .number, clearType: .always, tag: AyuMiscEntryTag.spoofPhone, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateSpoofPhoneValue(updatedText)
            }, shouldUpdateText: { text in
                return text.allSatisfy { $0.isNumber }
            }, action: {})
        case .spoofFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Работает только визуально в интерфейсе Shadow и предназначено для скриншотов. Реальные данные аккаунта, номер телефона и то, что отправляется на сервер, не меняются. Если поле пустое, показываются реальные данные."), sectionId: self.section)
        }
    }
}

private final class AyuMiscArguments {
    let updateSpoofIdEnabled: (Bool) -> Void
    let updateSpoofIdValue: (String) -> Void
    let updateSpoofDcEnabled: (Bool) -> Void
    let updateSpoofDcValue: (String) -> Void
    let updateSpoofPhoneEnabled: (Bool) -> Void
    let updateSpoofPhoneValue: (String) -> Void

    init(
        updateSpoofIdEnabled: @escaping (Bool) -> Void,
        updateSpoofIdValue: @escaping (String) -> Void,
        updateSpoofDcEnabled: @escaping (Bool) -> Void,
        updateSpoofDcValue: @escaping (String) -> Void,
        updateSpoofPhoneEnabled: @escaping (Bool) -> Void,
        updateSpoofPhoneValue: @escaping (String) -> Void
    ) {
        self.updateSpoofIdEnabled = updateSpoofIdEnabled
        self.updateSpoofIdValue = updateSpoofIdValue
        self.updateSpoofDcEnabled = updateSpoofDcEnabled
        self.updateSpoofDcValue = updateSpoofDcValue
        self.updateSpoofPhoneEnabled = updateSpoofPhoneEnabled
        self.updateSpoofPhoneValue = updateSpoofPhoneValue
    }
}

private func ayuMiscEntries(settings: AyuGramSettings) -> [AyuMiscEntry] {
    var entries: [AyuMiscEntry] = []
    entries.append(.spoofHeader)
    entries.append(.spoofIdToggle(settings.spoofProfileIdEnabled))
    if settings.spoofProfileIdEnabled {
        entries.append(.spoofIdInput(settings.spoofProfileIdValue))
    }
    entries.append(.spoofDcToggle(settings.spoofProfileDcEnabled))
    if settings.spoofProfileDcEnabled {
        entries.append(.spoofDcInput(settings.spoofProfileDcValue))
    }
    entries.append(.spoofPhoneToggle(settings.spoofProfilePhoneEnabled))
    if settings.spoofProfilePhoneEnabled {
        entries.append(.spoofPhoneInput(settings.spoofProfilePhoneValue))
    }
    entries.append(.spoofFooter)
    return entries
}

private func ayuMiscController(context: AccountContext) -> ViewController {
    let arguments = AyuMiscArguments(
        updateSpoofIdEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileIdEnabled = value; return s }
        },
        updateSpoofIdValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileIdValue = value; return s }
        },
        updateSpoofDcEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileDcEnabled = value; return s }
        },
        updateSpoofDcValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfileDcValue = value; return s }
        },
        updateSpoofPhoneEnabled: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfilePhoneEnabled = value; return s }
        },
        updateSpoofPhoneValue: { value in
            ayuUpdateSettings(context: context) { var s = $0; s.spoofProfilePhoneValue = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuGramSettings(postbox: context.account.postbox)
    )
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Разное"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuMiscEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
