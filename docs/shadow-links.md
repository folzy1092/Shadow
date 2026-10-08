# Быстрые ссылки Shadow

Две равнозначные формы — работают одинаково везде:

- `shadow://<команда>` — своя схема приложения (сообщения, заметки, Safari);
- `tg://shadow/<команда>` — для мест, где принимаются только `tg://` (кнопки ботов).

В сообщениях обе формы подсвечиваются и нажимаются как обычные ссылки
(подсветка делается в самом Shadow; в других клиентах это просто текст).
При включённой маскировке или в сеансе кода под принуждением ссылки ничего не открывают.

| Ссылка | Что открывает |
|---|---|
| `shadow://settings` | настройки Shadow |
| `shadow://updates` | настройки Shadow и сразу запускает проверку обновлений |
| `shadow://customization` | Кастомизация |
| `shadow://header` | Кастомизация → Кнопки шапки |
| `shadow://sync` | Синхронизация настроек между аккаунтами |
| `shadow://spy` | Сохранение |
| `shadow://ghost` | Призрак |
| `shadow://filters` | Фильтры |
| `shadow://shadowban` | Фильтры → список теневого бана |
| `shadow://profile` | Подмена профиля |
| `shadow://accounts` | Скрытие аккаунтов |
| `shadow://backup` | Резервная копия настроек |
| `shadow://misc` | Разное |
| `shadow://screenshot` | Скриншоты сообщений |
| `shadow://templates` | Шаблоны ответов |
| `shadow://locks` | Замки чатов |
| `shadow://space` | Второе пространство |
| `shadow://emergency` | Экстренная защита |
| `shadow://storage` | Хранилище форка |
| `shadow://deleted` | Архив: удалённые сообщения |
| `shadow://edited` | Архив: отредактированные сообщения |
| `shadow://access?id=<ID>` | Доступ устройств с подставленным ID (только админы: Folzy, matey) |
| `shadow://folzy` | профиль Folzy |
| `shadow://matey` | профиль matey |
| `shadow://me` | мой профиль |
| `shadow://user?id=<ID>` | профиль по ID Telegram (как `tg://user?id=`); только тех, кого аккаунт уже видел |
| `shadow://user?username=<name>`, `shadow://user/@name` | профиль по @username |
| `shadow://gift` | «Отправить подарок» (контакты, дни рождения, себе) |
| `shadow://versions` | Архив версий: объявленные сборки с текстом и IPA для отката |
| `shadow://autoupdate` | Автообновление: сертификат .p12, профиль и пароль для подписи обновлений на устройстве |

Неизвестная команда — это имя пасхалки (см. ниже); если пасхалки с таким
именем нет, открываются настройки Shadow. Код: разбор —
`TelegramCore/Sources/AyuGram/ShadowLinks.swift`, маршруты —
`SettingsUI/Sources/ShadowLinkRouter.swift`.

## Ссылки на тумблеры

У каждого тумблера Shadow есть ссылка `shadow://<экран>/<тумблер>`. Зажатие
тумблера в настройках копирует её (ссылка-переключатель, путь, текущее значение).

- без параметра — открыть экран, плавно прокрутить к тумблеру и один раз подсветить;
- `?on` / `?off` — включить / выключить;
- `?switch` — переключить;
- `?value=N` — для настройки с выбором (не вкл/выкл): поставить вариант N
  (нумерация с 0, как в списке выбора), например
  `shadow://customization/voice-time?value=2` — «Прошло / всего».

Настройки без вкл/выкл и вне `AyuGramSettings` (цвета, свои значки, кнопки
шапки, выбор картинок) тоже имеют ссылку, но она только открывает их.

Из сообщений, браузера и других приложений смена значения спрашивает
подтверждение; с кнопок шапки — без вопроса. Защитные тумблеры (замки чатов,
второе пространство) по ссылке только открываются. Список — в
`TelegramCore/Sources/AyuGram/ShadowSettingLinks.swift`.

**Призрак**

| Ссылка | Тумблер |
|---|---|
| `shadow://ghost/mode` | Режим призрака |
| `shadow://ghost/online` | Не показывать онлайн |
| `shadow://ghost/typing` | Не показывать набор текста |
| `shadow://ghost/read` | Не отправлять прочтения |
| `shadow://ghost/stories` | Скрывать просмотры историй |
| `shadow://ghost/offer-stories` | Предлагать призрак перед историями |
| `shadow://ghost/scheduled` | Отправлять через отложенные |
| `shadow://ghost/send-offline` | Отправлять без появления онлайн |

**Сохранение**

| Ссылка | Тумблер |
|---|---|
| `shadow://spy/deleted` | Сохранять удалённые |
| `shadow://spy/deleted-secret` | Сохранять удалённые в секретных чатах |
| `shadow://spy/view-once` | Сохранять «одноразовые» |
| `shadow://spy/edit-history` | Сохранять историю правок |
| `shadow://spy/edit-compare` | Показывать «Сравнить правки» |
| `shadow://spy/save-restricted` | Разрешить сохранение |
| `shadow://spy/ask-story-view` | Спросить перед просмотром истории |
| `shadow://spy/save-destructing` | Сохранять самоуничтожающиеся |
| `shadow://spy/save-all-media` | Сохранять все входящие медиа |
| `shadow://spy/clean-keep-pinned` | Не очищать закреплённые |
| `shadow://spy/clean-skip-channels` | Исключить каналы |
| `shadow://spy/clean-skip-bots` | Исключить ботов |
| `shadow://spy/online-history` | Записывать, когда контакты в сети |
| `shadow://spy/save-stories` | Сохранять просмотренные истории |

**Кастомизация**

| Ссылка | Тумблер |
|---|---|
| `shadow://customization/seconds` | Секунды в метках времени |
| `shadow://customization/edited-pencil` | Значок ✎ вместо «Изменено» |
| `shadow://customization/emoji-first` | Обычные эмодзи в начале клавиатуры |
| `shadow://customization/double-tap-edit` | Двойной тап — редактирование |
| `shadow://customization/exact-last-seen` | Точное время последнего захода |
| `shadow://customization/last-seen-seconds` | Секунды у последнего захода |
| `shadow://customization/wide-posts` | Широкие посты в каналах |
| `shadow://customization/exact-views` | Точные просмотры на постах |
| `shadow://customization/forward-count` | Счётчик пересылок |
| `shadow://customization/username` | @username вместо имени незнакомых |
| `shadow://customization/username-bots` | @username также для ботов |
| `shadow://customization/mono-icons` | Одноцветные иконки |
| `shadow://customization/hide-all-chats` | Скрыть папку «Все чаты» |
| `shadow://customization/hide-stories` | Скрыть истории |
| `shadow://customization/hide-gift` | Скрыть кнопку подарка |
| `shadow://customization/hide-greeting` | Скрыть приветственный стикер |
| `shadow://customization/hide-premium` | Скрыть значки Premium у имён |
| `shadow://customization/hide-ads` | Скрыть рекламу в каналах |
| `shadow://customization/unlimited-pins` | Безлимитные закрепы |
| `shadow://customization/compact-chats` | Компактный список чатов |
| `shadow://customization/voice-transcription` | Расшифровка голосовых на устройстве |
| `shadow://customization/voice-time` | Время на голосовых, `?value=0…5`: по умолчанию, текущий таймкод, прошло / всего, осталось / всего, прошло и процент, процент |
| `shadow://customization/voice-time-round` | Время на голосовых: также на кружках |
| `shadow://customization/voice-time-player` | Время в верхнем плеере |
| `shadow://customization/reply-timecode` | Тайм-код в ответах |
| `shadow://customization/reply-timecode-mode` | Тайм-код в ответах: режим, `?value=0…1`: всегда, спрашивать |
| `shadow://customization/chat-voice-speed` | Своя скорость для чатов |
| `shadow://customization/chat-voice-speeds` | Чаты со своей скоростью (только открыть) |
| `shadow://customization/folders-bottom` | Папки снизу |
| `shadow://customization/hide-bottom-search` | Убрать поиск снизу |
| `shadow://customization/compact-bottom` | Уменьшить интерфейс снизу |
| `shadow://customization/bottom-bar-hiding` | Скрытие нижней панели, `?value=0…3` |
| `shadow://customization/profile-id` | ID профиля (Bot API) |
| `shadow://customization/profile-dc` | Дата-центр (DC) |
| `shadow://customization/registration-date` | Дата регистрации |
| `shadow://customization/chat-streak` | Дни подряд в профиле |
| `shadow://customization/hide-phone` | Скрыть свой номер |
| `shadow://customization/round-back-camera` | Кружки на заднюю камеру |
| `shadow://customization/camera-tile` | Камера в галерее |
| `shadow://customization/camera-live` | Живой предпросмотр камеры |
| `shadow://customization/camera-compact` | Компактная плитка камеры |
| `shadow://customization/round-speed` | Кастомная скорость кружков |
| `shadow://customization/confirm-calls` | Подтверждение звонков |
| `shadow://customization/banner` | Кастомный баннер |
| `shadow://customization/profile-background` | Кастомный фон профиля |
| `shadow://customization/profile-background-all` | Фон для всех профилей |
| `shadow://customization/profile-background-settings` | Фон в настройках |
| `shadow://customization/icon-background` | Цвет фона иконок (только открывает) |
| `shadow://customization/icon-glyph` | Цвет значков (только открывает) |
| `shadow://customization/edited-text` | Свой значок правки (только открывает) |
| `shadow://customization/deleted-text` | Свой значок удалёнки (только открывает) |
| `shadow://customization/message-screenshots` | Скриншоты сообщений (только открывает) |
| `shadow://customization/header-buttons` | Кнопки шапки (только открывает) |
| `shadow://customization/banner-image` | Изображение баннера (только открывает) |
| `shadow://customization/profile-background-image` | Изображение фона профиля (только открывает) |

**Скриншоты сообщений**

| Ссылка | Тумблер |
|---|---|
| `shadow://screenshot/button` | Кнопка скриншота при выделении |
| `shadow://screenshot/anonymize` | Анонимный скриншот |
| `shadow://screenshot/avatars` | Скриншот: аватары |
| `shadow://screenshot/names` | Скриншот: имена авторов |
| `shadow://screenshot/badges` | Скриншот: значки у имени |
| `shadow://screenshot/time` | Скриншот: время и статус |
| `shadow://screenshot/reactions` | Скриншот: реакции |
| `shadow://screenshot/own-name` | Скриншот: своё имя |
| `shadow://screenshot/peer-names` | Скриншот: имена собеседников |
| `shadow://screenshot/own-avatar` | Скриншот: своя аватарка |
| `shadow://screenshot/peer-avatars` | Скриншот: аватарки собеседников |

**Фильтры**

| Ссылка | Тумблер |
|---|---|
| `shadow://filters/placeholder` | Плашка «Скрыто локальным фильтром» |
| `shadow://filters/ads-channels` | Реклама в каналах |
| `shadow://filters/ads-groups` | Реклама в группах |
| `shadow://filters/ads-forwarded` | Реклама в пересланных |
| `shadow://filters/ads-hide-completely` | Скрывать рекламу полностью |

**Лента**

| Ссылка | Тумблер |
|---|---|
| `shadow://feed/enabled` | Лента (бета) |
| `shadow://feed/position` | Где кнопка ленты (`?value=0` левее контактов, `1` между чатами и профилем, `2` правее профиля) |
| `shadow://feed/autoplay` | Автозапуск видео в ленте |
| `shadow://feed/folders` | Папки Telegram в ленте |
| `shadow://feed/muted` | Каналы без звука в ленте |
| `shadow://feed/archived` | Каналы из архива в ленте |
| `shadow://feed/mark-read` | Лента отмечает прочитанным |

**Подмена профиля**

| Ссылка | Тумблер |
|---|---|
| `shadow://profile/spoof-id` | Подменить ID |
| `shadow://profile/spoof-dc` | Подменить DC |
| `shadow://profile/spoof-phone` | Подменить номер |

**Разное**

| Ссылка | Тумблер |
|---|---|
| `shadow://misc/story-camera-swipe` | Отключить свайп к камере |
| `shadow://misc/beta` | Бета-версии |

**Замки чатов**

| Ссылка | Тумблер |
|---|---|
| `shadow://locks/hide-preview` | Прятать последнее сообщение (только открыть) |
| `shadow://locks/intruder-photo` | Фото при неверном пароле (только открыть) |

**Второе пространство**

| Ссылка | Тумблер |
|---|---|
| `shadow://space/exclusive` | Во втором — только его чаты (только открыть) |

## Пасхалки

`shadow://<имя>` — если `<имя>` не команда из таблицы выше, Shadow ищет пост с
видео или гифкой, подпись которого начинается с `shadow://<имя>` или
`tg://ayu/<имя>`, в публичных каналах из `easter_egg_channels`
(`shadow-whitelist.json` в tgfork, правится в «Доступ устройств»). Видео
открывается на весь экран, закрыть его нельзя, после конца само исчезает.
Код — `TelegramUI/Sources/ShadowEasterEggs.swift`.

**Добавлены в 1.9.1** (открывают строку настройки)

| Ссылка | Настройка |
|---|---|
| `shadow://ghost/account-mode` | Призрак для аккаунта |
| `shadow://spy/attachment-size` | Лимит размера вложений |
| `shadow://spy/attachment-age` | Срок хранения вложений |
| `shadow://profile/spoof-id-value` | Подменённый ID |
| `shadow://profile/spoof-dc-value` | Подменённый DC |
| `shadow://profile/spoof-phone-value` | Подменённый номер |
