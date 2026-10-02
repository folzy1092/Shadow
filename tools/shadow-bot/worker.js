// Shadow access-request bot (Cloudflare Worker).
//
// The "Доступ ограничен" screen in Shadow posts the device id here
// (POST /request, JSON: id, name, model, system, build). The worker sends the
// owners a Telegram message with the id and a button that opens
// "Доступ устройств" in Shadow with the id filled in. Nothing is stored and
// nothing is changed: adding the device stays a manual step in the app.
//
// Settings (Workers → Settings → Variables and Secrets):
//   BOT_TOKEN      secret — token from @BotFather
//   OWNER_CHAT_ID  text   — who gets requests; several ids separated by commas
//   THROTTLE       KV binding, optional — one request per device per 10 minutes

const ID_PATTERN = /^[0-9A-F]{4}(-[0-9A-F]{4}){3}$/;
const THROTTLE_SECONDS = 600;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function clean(value, limit) {
  return String(value ?? "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, limit);
}

async function sendMessage(env, chatId, text, keyboard) {
  const payload = {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
  };
  if (keyboard) {
    payload.reply_markup = { inline_keyboard: keyboard };
  }
  return fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET") {
      return new Response("Shadow access bot is running", { status: 200 });
    }
    if (request.method !== "POST" || url.pathname !== "/request") {
      return json({ ok: false, error: "not_found" }, 404);
    }
    if (!env.BOT_TOKEN || !env.OWNER_CHAT_ID) {
      return json({ ok: false, error: "not_configured" }, 500);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ ok: false, error: "bad_json" }, 400);
    }

    const id = clean(body.id, 32).toUpperCase();
    if (!ID_PATTERN.test(id)) {
      return json({ ok: false, error: "bad_id" }, 400);
    }

    const throttleKey = `request:${id}`;
    if (env.THROTTLE && (await env.THROTTLE.get(throttleKey))) {
      return json({ ok: false, error: "too_many" }, 429);
    }

    const name = clean(body.name, 64);
    const model = clean(body.model, 32);
    const system = clean(body.system, 32);
    const build = clean(body.build, 16);

    const text = [
      "🔐 <b>Запрос доступа к Shadow</b>",
      "",
      `ID: <code>${escapeHtml(id)}</code>`,
      `Кто: ${name ? escapeHtml(name) : "не указал"}`,
      `Устройство: ${escapeHtml(model || "?")}, ${escapeHtml(system || "?")}`,
      `Сборка: ${escapeHtml(build || "?")}`,
      "",
      `Открыть в Shadow: shadow://access?id=${escapeHtml(id)}`,
    ].join("\n");
    const keyboard = [[{ text: "Открыть в Shadow", url: `tg://shadow/access?id=${id}` }]];

    const chatIds = String(env.OWNER_CHAT_ID).split(",").map((value) => value.trim()).filter(Boolean);
    let delivered = 0;
    for (const chatId of chatIds) {
      let response = await sendMessage(env, chatId, text, keyboard);
      if (!response.ok) {
        // A client that refuses the tg:// button still gets the text link.
        response = await sendMessage(env, chatId, text, null);
      }
      if (response.ok) {
        delivered += 1;
      }
    }
    if (delivered === 0) {
      return json({ ok: false, error: "telegram" }, 502);
    }

    if (env.THROTTLE) {
      await env.THROTTLE.put(throttleKey, "1", { expirationTtl: THROTTLE_SECONDS });
    }
    return json({ ok: true });
  },
};
