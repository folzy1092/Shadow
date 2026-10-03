# Бот запросов доступа Shadow (Cloudflare Worker)

Когда устройство не в вайтлисте, на экране «Доступ ограничен» есть поле
«Имя или @username» и кнопка «Запросить доступ». Shadow отправляет ID
устройства этому воркеру, а воркер присылает тебе в Telegram сообщение:

```
🔐 Запрос доступа к Shadow

ID: AB12-CD34-EF56-7890
Кто: Вася
Устройство: iPhone16,1, iOS 26.0
Сборка: 34731

Открыть в Shadow: shadow://access?id=AB12-CD34-EF56-7890
[ Открыть в Shadow ]
```

Кнопка (и ссылка) открывают в Shadow «Доступ устройств» с уже вставленным ID —
остаётся «Добавить в список» → «Сохранить» (коммит делается через этот же воркер,
если задан ключ администратора, см. ниже). Сам запрос воркер нигде не хранит.

## Что умеет воркер

| Путь | Метод | Что делает |
|---|---|---|
| `/` | GET | `Shadow access bot is running` |
| `/request` | POST | запрос доступа от устройства → сообщение админам |
| `/whitelist` | GET | живой `shadow-whitelist.json` через GitHub API, без кэша (нужен `GITHUB_TOKEN`) |
| `/admin` | POST | «Сохранить» вайтлист и «Объявить сборку» (нужны `ADMIN_SECRET` и `GITHUB_TOKEN`) |

Приложение при каждом заходе читает список с `/whitelist` (запасной путь —
raw GitHub), поэтому добавленное устройство пускается сразу, без ожидания кэша
GitHub. Кнопки «Принять» в сообщении бота нет.

## Настройка (один раз, ~10 минут)

1. **Бот.** В Telegram открой @BotFather → `/newbot` → придумай имя и username.
   Скопируй токен вида `123456:ABC…`. Потом найди своего бота и нажми **Start** —
   иначе бот не сможет тебе писать.
2. **Cloudflare.** Зарегистрируйся на https://dash.cloudflare.com (бесплатно).
3. **Воркер.** Workers & Pages → Create → Create Worker → имя `shadow-access-bot`
   → Deploy → Edit code → удали шаблон, вставь содержимое `worker.js` → Deploy.
4. **Переменные.** Воркер → Settings → Variables and Secrets → Add:
   - `BOT_TOKEN`, тип **Secret** — токен из шага 1;
   - `OWNER_CHAT_ID`, тип **Text** — `7878830498` (чтобы запросы приходили и
     matey, через запятую: `7878830498,1068369028`; matey тоже должен нажать
     Start у бота).
5. **Защита от спама (по желанию).** Storage & Databases → KV → Create
   namespace `shadow-throttle`; воркер → Settings → Bindings → Add → KV
   namespace, имя переменной `THROTTLE`. Тогда с одного устройства — не чаще
   раза в 10 минут.
6. **Адрес.** Скопируй адрес воркера (`https://shadow-access-bot.<ты>.workers.dev`)
   и пропиши его в `shadow-whitelist.json` в репо **folzy1092/tgfork**:

   ```json
   {
     "enabled": true,
     "request_url": "https://shadow-access-bot.<ты>.workers.dev/request",
     "devices": [ … ]
   }
   ```

   Кнопка «Запросить доступ» появляется только когда `request_url` задан.
   «Скопировать JSON» в админ-меню его сохраняет.

Проверка: открой адрес воркера в браузере — должно быть
`Shadow access bot is running`.

Через wrangler вместо панели: `npx wrangler deploy` в этой папке, затем
`npx wrangler secret put BOT_TOKEN`.

## Автокоммит из админ-меню (кнопка «Сохранить» и «Объявить»)

Чтобы «Доступ устройств» в приложении коммитил список и объявлял сборки сам,
воркеру нужны ещё два секрета:

- `GITHUB_TOKEN` — fine-grained токен GitHub: https://github.com/settings/personal-access-tokens/new
  → Repository access: Only select repositories → `folzy1092/tgfork` →
  Permissions → Contents: **Read and write**. Скопируй токен (`github_pat_…`).
- `ADMIN_SECRET` — любая длинная строка-пароль, придумай сам.

Добавь оба в Workers → shadow-access-bot → Settings → Variables and Secrets
(тип **Secret**).

В приложении: «Доступ устройств» → поле «Ключ администратора» → введи тот же
`ADMIN_SECRET` → «Сохранить ключ» (хранится в Keychain этого устройства).
После этого:

- «Сохранить» коммитит `shadow-whitelist.json` в tgfork сразу, без копирования
  JSON вручную.
- «Объявить сборку» (появляется под ключом) пишет `shadow-update.json`: номер
  сборки, версия, заголовок, заметки и тумблер «В бету» (stable или beta).

Чтобы в вайтлисте появились кнопки, в `shadow-whitelist.json` должен быть адрес
админ-эндпоинта:

```json
{
  "enabled": true,
  "request_url": "https://shadow-access-bot.<ты>.workers.dev/request",
  "admin_url": "https://shadow-access-bot.<ты>.workers.dev/admin",
  "devices": [ … ]
}
```

Безопасность: `GITHUB_TOKEN` и `ADMIN_SECRET` живут только в секретах воркера и
в Keychain твоего телефона, в приложение не зашиты. Токен — строго на tgfork с
правом Contents, чтобы утечка не затронула другие репозитории.

## Админ по ID устройства

В списке можно пометить устройство как админа (тап по устройству → «Сделать
админом»). Админ-устройство видит «Доступ устройств» и может править список,
даже если его Telegram-аккаунт не владелец. Владельцы по аккаунту (Folzy,
matey) остаются админами всегда.
