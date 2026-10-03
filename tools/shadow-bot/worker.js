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

async function answerCallbackQuery(env, callbackQueryId, text) {
  return fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/answerCallbackQuery`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ callback_query_id: callbackQueryId, text: text || "" }),
  });
}

// Replace the message text and drop its buttons (plain text — the original had
// none a user name could break, and we re-send the untrusted text verbatim).
async function editMessageText(env, chatId, messageId, text) {
  return fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/editMessageText`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, message_id: messageId, text, disable_web_page_preview: true }),
  });
}

// --- GitHub (the public data repo folzy1092/tgfork, branch main) ---

const GH_REPO = "folzy1092/tgfork";
const GH_BRANCH = "main";

function b64encode(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

function b64decode(b64) {
  const bin = atob(b64.replace(/\n/g, ""));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function ghHeaders(env) {
  return {
    "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
    "Accept": "application/vnd.github+json",
    "User-Agent": "shadow-bot",
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

async function ghGetJSON(env, path) {
  const r = await fetch(`https://api.github.com/repos/${GH_REPO}/contents/${path}?ref=${GH_BRANCH}`, { headers: ghHeaders(env) });
  if (r.status === 404) return { sha: null, json: {} };
  if (!r.ok) throw new Error(`github read ${r.status}`);
  const data = await r.json();
  let parsed = {};
  try { parsed = JSON.parse(b64decode(data.content)); } catch { parsed = {}; }
  return { sha: data.sha, json: parsed };
}

async function ghPutJSON(env, path, obj, message, sha) {
  const body = {
    message,
    content: b64encode(JSON.stringify(obj, null, 2) + "\n"),
    branch: GH_BRANCH,
  };
  if (sha) body.sha = sha;
  const r = await fetch(`https://api.github.com/repos/${GH_REPO}/contents/${path}`, {
    method: "PUT",
    headers: ghHeaders(env),
    body: JSON.stringify(body),
  });
  return r.ok;
}

async function handleRequest(request, env) {
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
  const rows = [];
  // "Принять" commits the device straight away (needs the GitHub token + webhook).
  if (env.GITHUB_TOKEN) {
    rows.push([{ text: "✅ Принять", callback_data: `a:${id}` }]);
  }
  rows.push([{ text: "Открыть в Shadow", url: `tg://shadow/access?id=${id}` }]);
  const keyboard = rows;
  const chatIds = String(env.OWNER_CHAT_ID).split(",").map((value) => value.trim()).filter(Boolean);
  let delivered = 0;
  for (const chatId of chatIds) {
    let response = await sendMessage(env, chatId, text, keyboard);
    if (!response.ok) {
      response = await sendMessage(env, chatId, text, null);
    }
    if (response.ok) delivered += 1;
  }
  if (delivered === 0) {
    return json({ ok: false, error: "telegram" }, 502);
  }
  if (env.THROTTLE) {
    await env.THROTTLE.put(throttleKey, "1", { expirationTtl: THROTTLE_SECONDS });
  }
  return json({ ok: true });
}

// Admin writes from the app's "Доступ устройств" menu. Auth is the shared
// ADMIN_SECRET; the worker commits to the tgfork repo with the owner's token.
async function handleAdmin(request, env) {
  if (!env.ADMIN_SECRET || !env.GITHUB_TOKEN) {
    return json({ ok: false, error: "not_configured" }, 500);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, error: "bad_json" }, 400);
  }
  if (clean(body.secret, 200) !== env.ADMIN_SECRET) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  if (body.action === "save_whitelist") {
    const devices = [];
    for (const entry of Array.isArray(body.devices) ? body.devices : []) {
      const id = clean(entry && entry.id, 32).toUpperCase();
      if (!ID_PATTERN.test(id)) continue;
      const device = { id, note: clean(entry.note, 64) };
      if (entry.admin === true) device.admin = true;
      devices.push(device);
    }
    const current = await ghGetJSON(env, "shadow-whitelist.json");
    const next = current.json && typeof current.json === "object" ? current.json : {};
    next.enabled = body.enabled === true;
    next.devices = devices;
    // Keep the endpoints that live only in the file.
    const ok = await ghPutJSON(env, "shadow-whitelist.json", next, "Shadow: update device whitelist [skip ci]", current.sha);
    return ok ? json({ ok: true }) : json({ ok: false, error: "github" }, 502);
  }

  if (body.action === "announce") {
    const build = Number(body.build) | 0;
    if (build <= 0) return json({ ok: false, error: "bad_build" }, 400);
    const channel = body.channel === "beta" ? "beta" : "stable";
    const version = clean(body.version, 40);
    const title = clean(body.title, 200);
    const notes = clean(body.notes, 2000);
    const url = `https://github.com/${GH_REPO}/releases/tag/build-${build}`;
    const ipaURL = `https://github.com/${GH_REPO}/releases/download/build-${build}/Shadow.ipa`;
    const channelObj = { build, version, title, notes, url, ipa_url: ipaURL };
    const current = await ghGetJSON(env, "shadow-update.json");
    const next = current.json && typeof current.json === "object" ? current.json : {};
    next.enabled = true;
    if (typeof next.minimum_build !== "number") next.minimum_build = 0;
    next[channel] = channelObj;
    if (channel === "stable") {
      // Mirror into the flat fields old builds read.
      next.build = build;
      next.version = version;
      next.title = title;
      next.notes = notes;
      next.url = url;
      next.ipa_url = ipaURL;
    }
    const ok = await ghPutJSON(env, "shadow-update.json", next, `Shadow: announce ${channel} ${build} [skip ci]`, current.sha);
    return ok ? json({ ok: true }) : json({ ok: false, error: "github" }, 502);
  }

  return json({ ok: false, error: "bad_action" }, 400);
}

// Add one device to the whitelist (used by the "Принять" button). Returns
// "added", "exists", or "error".
async function appendDevice(env, id, note) {
  const current = await ghGetJSON(env, "shadow-whitelist.json");
  const next = current.json && typeof current.json === "object" ? current.json : {};
  if (!Array.isArray(next.devices)) next.devices = [];
  if (next.devices.some((d) => String((d && d.id) || "").toUpperCase() === id)) {
    return "exists";
  }
  const device = { id };
  if (note) device.note = note;
  next.devices.push(device);
  if (typeof next.enabled !== "boolean") next.enabled = true;
  const ok = await ghPutJSON(env, "shadow-whitelist.json", next, `Shadow: accept device ${id} [skip ci]`, current.sha);
  return ok ? "added" : "error";
}

// Telegram webhook: the "Принять" button. Only the owners (OWNER_CHAT_ID) may
// accept; the device id is in callback_data, the name is read from the message.
async function handleTelegram(request, env) {
  if (env.WEBHOOK_SECRET && request.headers.get("X-Telegram-Bot-Api-Secret-Token") !== env.WEBHOOK_SECRET) {
    return json({ ok: false }, 401);
  }
  let update;
  try {
    update = await request.json();
  } catch {
    return json({ ok: true });
  }
  const cq = update.callback_query;
  if (!cq) {
    return json({ ok: true });
  }
  const admins = String(env.OWNER_CHAT_ID || "").split(",").map((v) => v.trim()).filter(Boolean);
  const fromId = String((cq.from && cq.from.id) || "");
  const data = String(cq.data || "");
  const message = cq.message;

  if (!admins.includes(fromId)) {
    await answerCallbackQuery(env, cq.id, "Нет прав");
    return json({ ok: true });
  }
  if (!data.startsWith("a:") || !env.GITHUB_TOKEN) {
    await answerCallbackQuery(env, cq.id, env.GITHUB_TOKEN ? "" : "Бот не настроен");
    return json({ ok: true });
  }
  const id = data.slice(2).toUpperCase();
  if (!ID_PATTERN.test(id)) {
    await answerCallbackQuery(env, cq.id, "Плохой ID");
    return json({ ok: true });
  }

  let note = "";
  const text = (message && message.text) || "";
  const match = text.match(/Кто:\s*(.+)/);
  if (match) {
    const value = match[1].trim();
    if (value && value !== "не указал") {
      note = value.slice(0, 64);
    }
  }

  let result;
  try {
    result = await appendDevice(env, id, note);
  } catch {
    result = "error";
  }
  if (result === "error") {
    await answerCallbackQuery(env, cq.id, "Ошибка GitHub");
    return json({ ok: true });
  }

  await answerCallbackQuery(env, cq.id, result === "added" ? "Принято" : "Уже в списке");
  if (message) {
    const who = (cq.from && (cq.from.first_name || cq.from.username)) || fromId;
    const mark = result === "added" ? "✅ Принято" : "☑️ Уже в списке";
    await editMessageText(env, message.chat.id, message.message_id, `${text}\n\n${mark} — ${who}`);
  }
  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET") {
      return new Response("Shadow access bot is running", { status: 200 });
    }
    if (request.method === "POST" && url.pathname === "/request") {
      return handleRequest(request, env);
    }
    if (request.method === "POST" && url.pathname === "/admin") {
      return handleAdmin(request, env);
    }
    if (request.method === "POST" && url.pathname === "/telegram") {
      return handleTelegram(request, env);
    }
    return json({ ok: false, error: "not_found" }, 404);
  },
};
