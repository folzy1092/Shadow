# Что Shadow меняет в Telegram-iOS

Файл собран автоматически: `bash tools/shadow-update.sh --inventory`

База сравнения: **release-12.9.2**
Дата: 2026-08-23 00:06

## Как это читать

- **Свои файлы** — созданы форком, в апстриме их нет.
  При обновлении они НИКОГДА не конфликтуют. Трогать не нужно.
- **Правки в файлах апстрима** — вот тут и бывают конфликты при
  обновлении. Большая часть таких правок помечена в коде
  комментарием со словом `Shadow:` или `AyuGram:` — по нему их
  удобно искать. Но помечено НЕ всё, поэтому единственный
  надёжный источник правды — сам diff:

  ```bash
  git diff release-12.9.2 HEAD -- <путь-к-файлу>
  ```

## Свои файлы форка (45)

- `Telegram/Telegram-iOS/Icons.xcassets/Shortcuts/Ghost.imageset/Contents.json`
- `Telegram/Telegram-iOS/Icons.xcassets/Shortcuts/Ghost.imageset/ghost.pdf`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Contents.json`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-1024.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-20.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-20@2x-ipad.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-20@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-20@3x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-29.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-29@2x-ipad.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-29@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-29@3x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-40.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-40@2x-ipad.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-40@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-40@3x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-60@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-60@3x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-76.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-76@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/AppIcon.appiconset/Icon-83.5@2x.png`
- `Telegram/Telegram-iOS/ShadowAppIcon.xcassets/Contents.json`
- `submodules/SettingsUI/Sources/AyuForkStorageController.swift`
- `submodules/SettingsUI/Sources/AyuGramSettingsController.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuBurnViewOnceMedia.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuDelayedSend.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuEditHistory.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuForkStore.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuGramAntiDelete.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuGramClientProfile.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuGramSettings.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuLastSeen.swift`
- `submodules/TelegramCore/Sources/AyuGram/AyuSavedMedia.swift`
- `submodules/TelegramCore/Sources/AyuGram/DeletedMessageAttribute.swift`
- `submodules/TelegramCore/Sources/AyuGram/GitConfig.swift`
- `submodules/TelegramCore/Sources/AyuGram/SavedMessageEditsAttribute.swift`
- `submodules/TelegramUI/Components/EntityKeyboard/Sources/AyuEmojiKeyboardOrder.swift`
- `submodules/TelegramUI/Images.xcassets/Chat List/GhostActiveIcon.imageset/Contents.json`
- `submodules/TelegramUI/Images.xcassets/Chat List/GhostActiveIcon.imageset/ghost_active.pdf`
- `submodules/TelegramUI/Images.xcassets/Chat List/GhostIcon.imageset/Contents.json`
- `submodules/TelegramUI/Images.xcassets/Chat List/GhostIcon.imageset/ghost.pdf`
- `submodules/TelegramUI/Images.xcassets/Chat/Input/Accessory Panels/MessageSelectionIncognito.imageset/Contents.json`
- `submodules/TelegramUI/Images.xcassets/Chat/Input/Accessory Panels/MessageSelectionIncognito.imageset/ic_incognito.pdf`
- `submodules/TelegramUI/Images.xcassets/Item List/Icons/Shadow.imageset/Contents.json`
- `submodules/TelegramUI/Images.xcassets/Item List/Icons/Shadow.imageset/shadow.pdf`

## Правки в файлах апстрима (88)

Отсортировано по объёму правок — сверху те, где форк влез сильнее всего.

- `submodules/TelegramUI/Sources/ChatControllerForwardMessages.swift` — строк изменено: 213
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift` — строк изменено: 210
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift` — строк изменено: 190
- `submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/ChatMessageDateAndStatusNode.swift` — строк изменено: 127
- `submodules/TelegramUI/Components/Chat/ChatMessageSelectionInputPanelNode/Sources/ChatMessageSelectionInputPanelNode.swift` — строк изменено: 125
- `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` — строк изменено: 108
- `submodules/TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift` — строк изменено: 99
- `submodules/ChatListUI/Sources/ChatListControllerNode.swift` — строк изменено: 94
- `submodules/TelegramUI/Components/Chat/ChatMessageActionButtonsNode/Sources/ChatMessageActionButtonsNode.swift` — строк изменено: 93
- `submodules/ChatListUI/Sources/ChatListController.swift` — строк изменено: 84
- `submodules/TelegramUI/Components/Stories/StoryContainerScreen/Sources/OpenStories.swift` — строк изменено: 82
- `submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift` — строк изменено: 77
- `submodules/TelegramUI/Sources/TelegramRootController.swift` — строк изменено: 72
- `submodules/ItemListPeerItem/Sources/ItemListPeerItem.swift` — строк изменено: 68
- `submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift` — строк изменено: 66
- `submodules/ContactsPeerItem/Sources/ContactsPeerItem.swift` — строк изменено: 60
- `submodules/TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift` — строк изменено: 59
- `submodules/TelegramCore/Sources/State/ManagedAccountPresence.swift` — строк изменено: 57
- `submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleComponent.swift` — строк изменено: 55
- `submodules/TelegramCore/Sources/State/SynchronizePeerReadState.swift` — строк изменено: 54
- `submodules/TelegramUI/Sources/AppDelegate.swift` — строк изменено: 44
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift` — строк изменено: 43
- `submodules/MtProtoKit/Sources/MTApiEnvironment.m` — строк изменено: 40
- `submodules/TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift` — строк изменено: 39
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift` — строк изменено: 37
- `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift` — строк изменено: 37
- `submodules/MediaPickerUI/Sources/MediaPickerScreen.swift` — строк изменено: 37
- `submodules/TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift` — строк изменено: 36
- `submodules/TelegramStringFormatting/Sources/PresenceStrings.swift` — строк изменено: 35
- `submodules/ICloudResources/Sources/ICloudResources.swift` — строк изменено: 31
- `submodules/ChatListUI/Sources/Node/ChatListItem.swift` — строк изменено: 31
- `submodules/TelegramCore/Sources/Network/FetchedMediaResource.swift` — строк изменено: 29
- `submodules/ChatPresentationInterfaceState/Sources/ChatPanelInterfaceInteraction.swift` — строк изменено: 29
- `submodules/TelegramUI/Sources/AccountContext.swift` — строк изменено: 25
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` — строк изменено: 24
- `submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift` — строк изменено: 24
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/Stories.swift` — строк изменено: 24
- `submodules/TelegramCore/Sources/State/ManagedLocalInputActivities.swift` — строк изменено: 23
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoData.swift` — строк изменено: 21
- `Telegram/NotificationService/Sources/NotificationService.swift` — строк изменено: 20
- `Telegram/BUILD` — строк изменено: 18
- `submodules/TelegramUI/Sources/ApplicationShortcutItem.swift` — строк изменено: 16
- `submodules/TelegramUI/Sources/ChatControllerOpenMessageShareMenu.swift` — строк изменено: 15
- `submodules/TelegramCore/Sources/Utils/MessageUtils.swift` — строк изменено: 15
- `submodules/TelegramCore/Sources/Network/Network.swift` — строк изменено: 13
- `submodules/Camera/Sources/Camera.swift` — строк изменено: 13
- `submodules/TelegramCore/Sources/PendingMessages/EnqueueMessage.swift` — строк изменено: 11
- `submodules/TelegramCore/Sources/Account/Account.swift` — строк изменено: 11
- `submodules/TelegramUI/Sources/SharedWakeupManager.swift` — строк изменено: 10
- `submodules/TelegramUI/Sources/ChatController.swift` — строк изменено: 10
- `submodules/TelegramCore/Sources/State/PendingMessageManager.swift` — строк изменено: 10
- `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift` — строк изменено: 9
- `submodules/TelegramUI/Sources/ChatControllerContentData.swift` — строк изменено: 8
- `submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift` — строк изменено: 8
- `submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentComponent.swift` — строк изменено: 7
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift` — строк изменено: 7
- `submodules/TelegramCore/Sources/State/AccountViewTracker.swift` — строк изменено: 6
- `submodules/MtProtoKit/PublicHeaders/MtProtoKit/MTApiEnvironment.h` — строк изменено: 6
- `submodules/TelegramUI/Components/EntityKeyboard/Sources/EntityKeyboard.swift` — строк изменено: 5
- `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift` — строк изменено: 4
- `submodules/TelegramUI/Components/Chat/ChatMessageMediaBubbleContentNode/Sources/ChatMessageMediaBubbleContentNode.swift` — строк изменено: 4
- `submodules/TelegramUI/Components/Chat/ChatMessageInteractiveMediaNode/Sources/ChatMessageInteractiveMediaNode.swift` — строк изменено: 4
- `submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift` — строк изменено: 4
- `submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/VideoMessageCameraScreen.swift` — строк изменено: 3
- `submodules/TelegramUI/Components/ChatControllerInteraction/Sources/ChatControllerInteraction.swift` — строк изменено: 3
- `submodules/TgVoipWebrtc/tgcalls` — сабмодуль (сдвинут указатель)
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` — строк изменено: 2
- `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift` — строк изменено: 2
- `submodules/TelegramCore/Sources/State/ProcessSecretChatIncomingDecryptedOperations.swift` — строк изменено: 2
- `submodules/TelegramCore/Sources/Account/AccountManager.swift` — строк изменено: 2
- `submodules/TabBarUI/Sources/TabBarContollerNode.swift` — строк изменено: 2
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@87x87.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@80x80.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@80x80-1.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@58x58.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@58x58-1.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@40x40-1.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple@29x29.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Simple-iTunesArtwork.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueNotificationIcon@3x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueNotificationIcon@2x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueNotificationIcon@2x-1.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueNotificationIcon.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueIconLargeIpad@2x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueIconIpad@2x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueIcon@3x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueIcon@2x.png` — строк изменено: 0
- `Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/BlueIcon@2x-1.png` — строк изменено: 0
