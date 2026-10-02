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
остаётся «Добавить в список» → «Скопировать JSON» → «Открыть файл на GitHub»
→ вставить → Commit. Воркер ничего не хранит и сам список не меняет.

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
