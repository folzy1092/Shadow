import Foundation

// Shadow: the «Лента» page (WKWebView in ShadowFeedController). Static HTML:
// the app feeds it through `Feed.*` calls (posts as ShadowFeed.Post JSON,
// media files as they download) and gets actions back through the `shadow`
// message handler. Media are files next to the page (loadFileURL with read
// access to the feed folder). Foundation only.
public enum ShadowFeedPage {
    public static let html = #"""
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<style>
:root {
  --page: #000; --card: #1c1c1e; --card2: #2c2c2e; --sep: #2c2c2e; --text: #fff; --sub: #8e8e93; --accent: #3e9bff; --green: #34c759; --red: #ff453a;
  --media: #1f2633; --sheet: #1c1c1e; --mine: rgba(62,155,255,.28);
}
:root[data-theme="light"] {
  --page: #fff; --card: #f2f2f7; --card2: #e5e5ea; --sep: #e3e3e8; --text: #000; --sub: #6d6d72; --media: #e5e9f0; --sheet: #fff; --mine: rgba(62,155,255,.18);
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--page); color: var(--text); font: 16px/1.38 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; padding-bottom: calc(110px + env(safe-area-inset-bottom)); -webkit-user-select: none; user-select: none; }
.top { position: sticky; top: 0; z-index: 5; background: color-mix(in srgb, var(--page) 86%, transparent); -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px); }
.navrow { display: flex; align-items: center; justify-content: space-between; height: 44px; padding: 0 12px; }
.navbtn { color: var(--accent); font-size: 17px; background: none; border: none; padding: 6px; font-family: inherit; }
.circle { width: 36px; height: 36px; border-radius: 18px; background: var(--card); display: grid; place-items: center; color: var(--text); border: none; font-size: 18px; line-height: 1; }
.title { font-size: 32px; font-weight: 700; margin: 0 18px 6px; display: flex; align-items: center; gap: 8px; }
.beta { font-size: 11px; font-weight: 700; letter-spacing: .04em; color: var(--accent); background: color-mix(in srgb, var(--accent) 18%, transparent); padding: 3px 7px; border-radius: 7px; }
.chips { display: flex; gap: 6px; overflow-x: auto; padding: 2px 16px 10px; scrollbar-width: none; }
.chips::-webkit-scrollbar { display: none; }
.chip { flex: none; font-size: 14px; padding: 6px 12px; border-radius: 16px; background: var(--card); color: var(--text); }
.chip.on { background: var(--accent); color: #fff; }
.chip .n { opacity: .65; margin-left: 4px; font-size: 12px; }
.post { display: flex; gap: 10px; padding: 12px 14px 10px; border-bottom: .5px solid var(--sep); }
.ava { width: 42px; height: 42px; border-radius: 21px; flex: none; display: grid; place-items: center; font-weight: 700; color: #fff; font-size: 15px; overflow: hidden; background-size: cover; background-position: center; }
.pbody { flex: 1; min-width: 0; }
.phead { display: flex; align-items: baseline; gap: 5px; white-space: nowrap; }
.phead b { font-size: 15px; overflow: hidden; text-overflow: ellipsis; }
.phead .t { color: var(--sub); font-size: 14px; flex: none; }
.phead .dot { width: 7px; height: 7px; border-radius: 4px; background: var(--accent); flex: none; align-self: center; }
.phead .more { margin-left: auto; color: var(--sub); padding: 0 2px 0 10px; font-size: 20px; line-height: 1; }
.fwd { color: var(--sub); font-size: 13px; margin-top: 1px; }
.fwd b { color: var(--accent); font-weight: 500; }
.ptext { margin-top: 3px; word-wrap: break-word; overflow-wrap: anywhere; -webkit-user-select: text; user-select: text; }
.ptext.clamp { display: -webkit-box; -webkit-line-clamp: 18; -webkit-box-orient: vertical; overflow: hidden; }
.ptext a { color: var(--accent); text-decoration: none; }
.ptext code, .ptext pre { font-family: ui-monospace, Menlo, monospace; font-size: 14px; background: var(--card); border-radius: 5px; padding: 0 4px; }
.ptext pre { padding: 8px; white-space: pre-wrap; margin: 6px 0; }
.ptext blockquote { margin: 6px 0; padding: 2px 10px; border-left: 3px solid var(--accent); background: color-mix(in srgb, var(--accent) 10%, transparent); border-radius: 4px; }
.spoiler { background: var(--sub); color: transparent; border-radius: 4px; }
.ce img { width: 1.25em; height: 1.25em; object-fit: contain; vertical-align: -0.25em; }
.spoiler.shown { background: none; color: inherit; }
.readmore { color: var(--accent); font-size: 15px; margin-top: 2px; }
.media { margin-top: 8px; border-radius: 14px; overflow: hidden; display: grid; gap: 2px; background: var(--media); }
.media.n2, .media.n4 { grid-template-columns: 1fr 1fr; }
.media.n3 { grid-template-columns: 1fr 1fr; }
.media.n3 .m:first-child { grid-column: span 2; }
.media.nmany { grid-template-columns: 1fr 1fr 1fr; }
.m { position: relative; background: var(--media); overflow: hidden; }
.m img, .m video { width: 100%; height: 100%; object-fit: cover; display: block; }
.m.single img, .m.single video { object-fit: cover; }
.m .badge { position: absolute; left: 8px; bottom: 8px; background: rgba(0,0,0,.55); color: #fff; font-size: 12px; padding: 2px 7px; border-radius: 9px; }
.m .play { position: absolute; inset: 0; display: grid; place-items: center; pointer-events: none; }
.m .play::after { content: "▶"; width: 52px; height: 52px; border-radius: 26px; background: rgba(0,0,0,.45); color: #fff; display: grid; place-items: center; font-size: 20px; padding-left: 4px; }
.m.playing .play { display: none; }
.m .more-n { position: absolute; inset: 0; background: rgba(0,0,0,.45); color: #fff; display: grid; place-items: center; font-size: 22px; font-weight: 600; }
.att { margin-top: 8px; background: var(--card); border-radius: 12px; padding: 10px 12px; color: var(--sub); font-size: 14px; display: flex; gap: 8px; align-items: center; }
.pfoot { display: flex; align-items: center; gap: 6px; margin-top: 8px; color: var(--sub); font-size: 13px; flex-wrap: wrap; }
.react { display: inline-flex; gap: 4px; align-items: center; background: var(--card); border-radius: 14px; padding: 4px 9px; color: var(--text); font-size: 13px; }
.react img { width: 18px; height: 18px; object-fit: contain; }
.react.mine { background: var(--mine); outline: 1.5px solid var(--accent); }
.react.add { color: var(--sub); padding: 4px 10px; }
.pfoot .sp { flex: 1; }
.pfoot .ic { display: inline-flex; align-items: center; gap: 4px; padding: 4px 2px 4px 8px; }
.pfoot .cm { color: var(--accent); }
.divider { display: flex; align-items: center; gap: 10px; color: var(--accent); font-size: 13px; padding: 10px 16px; }
.divider::before, .divider::after { content: ""; flex: 1; border-top: 1px solid color-mix(in srgb, var(--accent) 45%, transparent); }
.newpill { position: fixed; left: 50%; transform: translateX(-50%); z-index: 6; background: var(--accent); color: #fff; padding: 8px 16px; border-radius: 18px; font-size: 14px; font-weight: 600; box-shadow: 0 6px 18px rgba(0,0,0,.35); display: none; }
.empty { color: var(--sub); text-align: center; padding: 60px 30px; font-size: 15px; }
.loading { color: var(--sub); text-align: center; padding: 22px; font-size: 14px; }
.sheet-back { position: fixed; inset: 0; background: rgba(0,0,0,.45); opacity: 0; pointer-events: none; transition: opacity .2s; z-index: 20; }
.sheet-back.show { opacity: 1; pointer-events: auto; }
.sheet { position: fixed; left: 8px; right: 8px; bottom: calc(8px + env(safe-area-inset-bottom)); background: var(--sheet); border-radius: 26px; padding: 14px 0 12px; transform: translateY(130%); transition: transform .25s ease; z-index: 21; max-height: 86%; overflow-y: auto; -webkit-overflow-scrolling: touch; }
.sheet.show { transform: none; }
.sheet h3 { margin: 4px 20px 12px; font-size: 17px; text-align: center; }
.grp { background: var(--card); border-radius: 12px; margin: 0 12px 12px; overflow: hidden; }
.row { display: flex; align-items: center; min-height: 46px; padding: 0 14px; position: relative; gap: 10px; }
.row + .row::before { content: ""; position: absolute; top: 0; left: 14px; right: 0; border-top: .5px solid var(--sep); }
.row .label { flex: 1; padding: 10px 0; }
.row .label small { display: block; color: var(--sub); font-size: 12.5px; }
.row.act { color: var(--accent); }
.row.danger { color: var(--red); }
.row .arrows { display: flex; gap: 4px; }
.row .arrows button { width: 32px; height: 30px; border-radius: 8px; border: none; background: var(--card2); color: var(--text); font-size: 15px; }
.row input[type=text] { flex: 1; background: none; border: none; color: var(--text); font-size: 16px; padding: 12px 0; outline: none; font-family: inherit; -webkit-user-select: text; user-select: text; }
.row .check { width: 22px; height: 22px; border-radius: 11px; border: 2px solid var(--sub); flex: none; }
.row .check.on { background: var(--accent); border-color: var(--accent); }
.gtitle { color: var(--sub); font-size: 12.5px; text-transform: uppercase; margin: 4px 28px 6px; }
.sw { width: 51px; height: 31px; border-radius: 16px; background: #39393d; position: relative; flex: none; transition: background .2s; }
:root[data-theme="light"] .sw { background: #e9e9ea; }
.sw::after { content: ""; position: absolute; top: 2px; left: 2px; width: 27px; height: 27px; border-radius: 50%; background: #fff; box-shadow: 0 2px 4px rgba(0,0,0,.25); transition: left .2s; }
.sw.on { background: var(--green); }
.sw.on::after { left: 22px; }
.picker { display: flex; flex-wrap: wrap; gap: 8px; justify-content: center; padding: 0 14px 6px; }
.picker button { width: 48px; height: 48px; border-radius: 24px; border: none; background: var(--card); font-size: 26px; }
.btn { display: block; margin: 0 12px 8px; width: calc(100% - 24px); border: none; border-radius: 13px; height: 48px; background: var(--accent); color: #fff; font-size: 16px; font-weight: 600; font-family: inherit; }
.btn.sec { background: var(--card); color: var(--accent); font-weight: 500; }
</style>
</head>
<body>
<div class="top">
  <div class="navrow"><button class="navbtn" data-action="readAll">Прочитать всё</button><button class="circle" data-action="openSettings" aria-label="Настройки ленты">⋯</button></div>
  <div class="title">Лента <span class="beta">БЕТА</span></div>
  <div class="chips" id="chips"></div>
</div>
<div class="newpill" id="newpill" data-action="toTop"></div>
<div id="feed"></div>
<div class="sheet-back" id="sheetBack"></div>
<div class="sheet" id="sheet"></div>
<script>
const COLORS = ['#e17076', '#eda86c', '#a695e7', '#7bc862', '#6ec9cb', '#65aadd', '#ee7aae'];
const QUICK = ['👍', '❤️', '🔥', '🥰', '👏', '😁', '🤔', '🤯', '😱', '🎉', '🤩', '😢', '🙏', '👌', '💯', '🤡'];
const MONTHS = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
const S = { config: { theme: 'dark', chips: [], selected: 'all', lastSeen: 0, settings: {}, channels: [], collections: [] }, posts: [], hasMore: false, loadingMore: false, media: {}, expanded: {}, pendingNew: [], seen: new Set(), seenQueue: [], requested: new Set() };
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtN = n => n >= 1000000 ? (Math.round(n / 100000) / 10).toString().replace('.', ',') + 'M' : n >= 1000 ? (Math.round(n / 100) / 10).toString().replace('.', ',') + 'K' : String(n);
function post(message) { if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.shadow) window.webkit.messageHandlers.shadow.postMessage(message); }
function ago(ts) {
  const now = Date.now() / 1000, d = now - ts;
  if (d < 60) return 'сейчас';
  if (d < 3600) return Math.floor(d / 60) + ' мин';
  if (d < 86400) return Math.floor(d / 3600) + ' ч';
  const date = new Date(ts * 1000), today = new Date();
  const y = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
  if (date >= y) return 'вчера';
  return date.getDate() + ' ' + MONTHS[date.getMonth()] + (date.getFullYear() !== today.getFullYear() ? ' ' + date.getFullYear() : '');
}
function dur(s) { s = Math.round(s || 0); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }

function chipsHTML() {
  return S.config.chips.map(c => `<div class="chip ${c.id === S.config.selected ? 'on' : ''}" data-chip="${esc(c.id)}">${esc(c.title)}${c.id === 'unread' && S.config.unread ? `<span class="n">${S.config.unread}</span>` : ''}</div>`).join('');
}
function mediaHTML(p) {
  const visual = p.media.filter(m => m.kind === 'photo' || m.kind === 'video' || m.kind === 'gif');
  const other = p.media.filter(m => !(m.kind === 'photo' || m.kind === 'video' || m.kind === 'gif'));
  let html = '';
  if (visual.length) {
    const n = visual.length;
    const cls = n === 1 ? '' : n === 2 ? 'n2' : n === 3 ? 'n3' : n === 4 ? 'n4' : 'nmany';
    const shown = visual.slice(0, n > 6 ? 6 : n);
    html += `<div class="media ${cls}">` + shown.map((m, i) => {
      let style;
      if (n === 1) {
        const ratio = m.width > 0 && m.height > 0 ? m.height / m.width : 0.75;
        style = `aspect-ratio:${m.width || 4} / ${m.height || 3};max-height:${Math.round(window.innerHeight * 0.72)}px;` + (ratio > 1.4 ? 'width:100%;' : '');
      } else {
        style = n === 3 && i === 0 ? 'aspect-ratio:2 / 1;' : 'aspect-ratio:1 / 1;';
      }
      const src = S.media[m.key];
      const poster = S.media[m.key + ':poster'];
      let inner;
      if (m.kind === 'photo') inner = src ? `<img src="${src}" alt="">` : '';
      else inner = (src ? `<video src="${src}" ${poster ? `poster="${poster}"` : ''} muted playsinline loop preload="metadata" data-auto="1"></video>` : (poster ? `<img src="${poster}" alt="">` : '')) + (m.kind === 'video' ? '<div class="play"></div>' : '');
      const badge = m.kind === 'video' && m.duration ? `<span class="badge">${dur(m.duration)}</span>` : m.kind === 'gif' ? '<span class="badge">GIF</span>' : '';
      const rest = i === shown.length - 1 && n > shown.length ? `<div class="more-n">+${n - shown.length}</div>` : '';
      return `<div class="m ${n === 1 ? 'single' : ''}" style="${style}" data-key="${esc(m.key)}" data-kind="${m.kind}" data-post-id="${esc(p.id)}" data-media="${esc(m.key)}">${inner}${badge}${rest}</div>`;
    }).join('') + '</div>';
  }
  for (const m of other) {
    const icon = { voice: '🎤', round: '⏺', audio: '🎵', file: '📄', sticker: '🖼', poll: '📊', location: '📍' }[m.kind] || '📎';
    const text = m.title ? esc(m.title) : { voice: 'Голосовое', round: 'Видеосообщение', audio: 'Аудио', file: 'Файл', sticker: 'Стикер', poll: 'Опрос', location: 'Геопозиция' }[m.kind] || 'Вложение';
    html += `<div class="att" data-media="${esc(m.key)}">${icon} ${text}${m.duration ? ' · ' + dur(m.duration) : ''}</div>`;
  }
  return html;
}
function reactionsHTML(p) {
  const chips = p.reactions.map(r => {
    const face = r.image ? `<img src="${r.image}" alt="">` : (r.key === 'stars' ? '⭐️' : r.key.indexOf('custom:') === 0 ? '✨' : esc(r.key));
    return `<span class="react ${r.mine ? 'mine' : ''}" data-react="${esc(r.key)}" data-id="${esc(p.id)}">${face} ${fmtN(r.count)}</span>`;
  }).join('');
  return chips + `<span class="react add" data-picker="${esc(p.id)}">＋</span>`;
}
function postHTML(p) {
  const long = p.textLength > 900 && !S.expanded[p.id];
  const ava = S.media['avatar:' + p.peerId];
  return `<div class="post" data-post="${esc(p.id)}">
    <div class="ava" data-open="${esc(p.id)}" style="background-color:${COLORS[Math.abs(p.color) % COLORS.length]};${ava ? `background-image:url('${ava}')` : ''}">${ava ? '' : esc(p.initials)}</div>
    <div class="pbody">
      <div class="phead" data-open="${esc(p.id)}"><b>${esc(p.channel)}</b><span class="t">· ${ago(p.timestamp)}${p.edited ? ' · изм.' : ''}</span>${p.unread ? '<span class="dot"></span>' : ''}<span class="more" data-menu="${esc(p.id)}">⋯</span></div>
      ${p.forwardFrom ? `<div class="fwd">Переслано из <b>${esc(p.forwardFrom)}</b></div>` : ''}
      ${p.html ? `<div class="ptext ${long ? 'clamp' : ''}">${p.html}</div>` : ''}
      ${long ? `<div class="readmore" data-expand="${esc(p.id)}">Показать полностью</div>` : ''}
      ${mediaHTML(p)}
      <div class="pfoot">${reactionsHTML(p)}<span class="sp"></span>${p.comments != null ? `<span class="ic cm" data-comments="${esc(p.id)}">💬 ${fmtN(p.comments)}</span>` : ''}${p.views != null ? `<span class="ic">👁 ${fmtN(p.views)}</span>` : ''}</div>
    </div>
  </div>`;
}
function render() {
  document.getElementById('chips').innerHTML = chipsHTML();
  const feed = document.getElementById('feed');
  if (!S.posts.length) {
    feed.innerHTML = `<div class="empty">${S.loaded ? (S.config.selected === 'unread' ? 'Всё прочитано.' : 'Здесь пока пусто. В ленту попадают посты каналов, которые уже загружены на телефоне.') : 'Загрузка…'}</div>`;
    return;
  }
  let html = '';
  let dividerShown = false;
  const lastSeen = S.config.lastSeen || 0;
  S.posts.forEach((p, i) => {
    if (!dividerShown && lastSeen > 0 && i > 0 && p.timestamp <= lastSeen && S.posts[i - 1].timestamp > lastSeen) {
      html += '<div class="divider">Вы остановились здесь</div>';
      dividerShown = true;
    }
    html += postHTML(p);
  });
  html += S.hasMore ? '<div class="loading" id="more">Загрузка…</div>' : '<div class="loading">Дальше постов на телефоне нет</div>';
  feed.innerHTML = html;
  hydrateEmoji(feed);
  observe();
}
// Only the reactions row: the photos and a playing video stay as they are.
function updateReactionsRow(p) {
  const el = document.querySelector(`[data-post="${CSS.escape(p.id)}"] .pfoot`);
  if (!el) return;
  el.innerHTML = reactionsHTML(p) + '<span class="sp"></span>' + (p.comments != null ? `<span class="ic cm" data-comments="${esc(p.id)}">💬 ${fmtN(p.comments)}</span>` : '') + (p.views != null ? `<span class="ic">👁 ${fmtN(p.views)}</span>` : '');
}
// Premium emoji pictures that are already here.
function hydrateEmoji(root) {
  root.querySelectorAll('.ce[data-ce]').forEach(span => {
    const src = S.media['ce:' + span.dataset.ce];
    if (src && !span.querySelector('img')) span.innerHTML = `<img src="${src}" alt="">`;
  });
}
function replacePost(p) {
  const i = S.posts.findIndex(x => x.id === p.id);
  if (i < 0) return;
  S.posts[i] = p;
  const el = document.querySelector(`[data-post="${CSS.escape(p.id)}"]`);
  if (el) { el.outerHTML = postHTML(p); observe(); hydrateEmoji(document); }
}

// ---------- Visibility: media, seen, autoplay, more ----------
let io, playTimer = null, playing = null;
function observe() {
  if (io) io.disconnect();
  io = new IntersectionObserver(entries => {
    for (const e of entries) {
      const el = e.target;
      if (el.dataset.post) {
        if (e.isIntersecting) {
          requestMedia(el.dataset.post);
          if (e.intersectionRatio >= 0.5) markSeenLater(el.dataset.post);
        }
      } else if (el.id === 'more' && e.isIntersecting) {
        loadMore();
      }
    }
    autoplay();
  }, { rootMargin: '900px 0px 900px 0px', threshold: [0, 0.5, 1] });
  document.querySelectorAll('[data-post]').forEach(el => io.observe(el));
  const more = document.getElementById('more');
  if (more) io.observe(more);
}
function requestMedia(id) {
  const p = S.posts.find(x => x.id === id);
  if (!p) return;
  const keys = [];
  if (!S.media['avatar:' + p.peerId]) keys.push('avatar:' + p.peerId);
  p.media.forEach(m => { if (!S.media[m.key]) keys.push(m.key); });
  (p.html.match(/data-ce="(\d+)"/g) || []).forEach(x => { const k = 'ce:' + x.slice(9, -1); if (!S.media[k] && keys.indexOf(k) < 0) keys.push(k); });
  const fresh = keys.filter(k => !S.requested.has(k));
  if (fresh.length) { fresh.forEach(k => S.requested.add(k)); post({ action: 'need', keys: fresh }); }
}
const seenTimers = {};
function markSeenLater(id) {
  if (S.seen.has(id) || seenTimers[id]) return;
  seenTimers[id] = setTimeout(() => {
    delete seenTimers[id];
    const el = document.querySelector(`[data-post="${CSS.escape(id)}"]`);
    if (!el) return;
    const r = el.getBoundingClientRect();
    const visible = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
    if (visible > Math.min(r.height, window.innerHeight) * 0.4) {
      S.seen.add(id); S.seenQueue.push(id);
      const p = S.posts.find(x => x.id === id);
      if (p && p.unread) { p.unread = false; const dot = el.querySelector('.dot'); if (dot) dot.remove(); }
    }
  }, 700);
}
setInterval(() => { if (S.seenQueue.length) { post({ action: 'seen', ids: S.seenQueue.splice(0) }); } }, 1500);
function loadMore() {
  if (!S.hasMore || S.loadingMore) return;
  S.loadingMore = true;
  post({ action: 'more' });
}
function autoplay() {
  if (!S.config.settings.autoplay) return;
  const mid = window.innerHeight / 2;
  let best = null, bestDist = 1e9;
  document.querySelectorAll('video[data-auto]').forEach(v => {
    const r = v.getBoundingClientRect();
    if (r.bottom < 0 || r.top > window.innerHeight) return;
    const visible = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
    if (visible < r.height * 0.6) return;
    const dist = Math.abs((r.top + r.bottom) / 2 - mid);
    if (dist < bestDist) { best = v; bestDist = dist; }
  });
  if (best === playing) return;
  if (playing) { playing.pause(); playing.parentElement.classList.remove('playing'); }
  playing = null;
  clearTimeout(playTimer);
  if (best) {
    const v = best;
    // Like Instagram: starts after a second in the middle of the screen.
    playTimer = setTimeout(() => { playing = v; v.muted = false; v.play().then(() => v.parentElement.classList.add('playing')).catch(() => {}); }, 1000);
  }
}
let scrollTick = false;
window.addEventListener('scroll', () => {
  if (scrollTick) return;
  scrollTick = true;
  requestAnimationFrame(() => {
    scrollTick = false;
    autoplay();
    if (window.scrollY < 80) hideNewPill();
  });
}, { passive: true });

// ---------- Sheets ----------
function openSheet(html) { const s = document.getElementById('sheet'); s.innerHTML = html; s.classList.add('show'); document.getElementById('sheetBack').classList.add('show'); }
function closeSheet() { document.getElementById('sheet').classList.remove('show'); document.getElementById('sheetBack').classList.remove('show'); }
function sw(on) { return `<div class="sw ${on ? 'on' : ''}"></div>`; }
function settingsSheet() {
  const st = S.config.settings;
  openSheet(`<h3>Лента</h3>
    <div class="gtitle">Что показывать</div>
    <div class="grp">
      <div class="row" data-setting="feedIncludeMuted"><div class="label">Каналы без звука</div>${sw(st.feedIncludeMuted)}</div>
      <div class="row" data-setting="feedIncludeArchived"><div class="label">Каналы из архива</div>${sw(st.feedIncludeArchived)}</div>
      <div class="row" data-setting="feedShowFolders"><div class="label">Папки Telegram как вкладки</div>${sw(st.feedShowFolders)}</div>
    </div>
    <div class="gtitle">Чтение</div>
    <div class="grp">
      <div class="row" data-setting="feedMarkRead"><div class="label">Отмечать прочитанным в канале<small>Пролистали пост — в канале он тоже прочитан</small></div>${sw(st.feedMarkRead)}</div>
      <div class="row" data-setting="autoplay"><div class="label">Автозапуск видео<small>Со звуком, через секунду в середине экрана</small></div>${sw(st.autoplay)}</div>
    </div>
    <div class="grp">
      <div class="row act" data-action="collections"><div class="label">Подборки и порядок вкладок</div><span>›</span></div>
    </div>
    <button class="btn sec" data-action="closeSheet">Готово</button>`);
}
function collectionsSheet() {
  const chips = S.config.chips;
  openSheet(`<h3>Подборки</h3>
    <div class="gtitle">Порядок вкладок</div>
    <div class="grp">${chips.map((c, i) => `<div class="row"><div class="label">${esc(c.title)}</div><div class="arrows"><button data-move="${i}" data-dir="-1" ${i === 0 ? 'disabled' : ''}>↑</button><button data-move="${i}" data-dir="1" ${i === chips.length - 1 ? 'disabled' : ''}>↓</button></div></div>`).join('')}</div>
    <div class="gtitle">Свои подборки — только в ленте</div>
    <div class="grp">
      ${S.config.collections.map(c => `<div class="row act" data-edit="${esc(c.id)}"><div class="label">${esc(c.title)}<small>${c.peerIds.length} кан.</small></div><span>›</span></div>`).join('')}
      <div class="row act" data-edit=""><div class="label">＋ Новая подборка</div></div>
    </div>
    <button class="btn sec" data-action="closeSheet">Готово</button>`);
}
let editing = null;
function editSheet(id) {
  const existing = S.config.collections.find(c => c.id === id);
  editing = { id: existing ? existing.id : String(Date.now()), title: existing ? existing.title : '', peerIds: new Set(existing ? existing.peerIds : []) };
  renderEdit(existing != null);
}
function renderEdit(exists) {
  openSheet(`<h3>${exists ? 'Подборка' : 'Новая подборка'}</h3>
    <div class="grp"><div class="row"><input type="text" id="colTitle" maxlength="32" placeholder="Название, например СМИ" value="${esc(editing.title)}"></div></div>
    <div class="gtitle">Каналы</div>
    <div class="grp">${S.config.channels.map(c => `<div class="row" data-pick="${c.id}"><div class="label">${esc(c.title)}</div><div class="check ${editing.peerIds.has(c.id) ? 'on' : ''}"></div></div>`).join('') || '<div class="row"><div class="label">Каналов пока нет</div></div>'}</div>
    <button class="btn" data-action="saveCollection">Сохранить</button>
    ${exists ? '<button class="btn sec" data-action="removeCollection" style="color:var(--red)">Удалить подборку</button>' : ''}
    <button class="btn sec" data-action="collections">Назад</button>`);
}
function menuSheet(id) {
  const p = S.posts.find(x => x.id === id);
  if (!p) return;
  openSheet(`<h3>${esc(p.channel)}</h3>
    <div class="grp">
      <div class="row act" data-open="${esc(id)}"><div class="label">Открыть в канале</div></div>
      ${p.comments != null ? `<div class="row act" data-comments="${esc(id)}"><div class="label">Комментарии</div></div>` : ''}
      <div class="row act" data-action="copyLink" data-id="${esc(id)}"><div class="label">Скопировать ссылку</div></div>
    </div>
    <div class="grp"><div class="row danger" data-action="hideChannel" data-peer="${p.peerId}"><div class="label">Убрать «${esc(p.channel)}» из ленты</div></div></div>
    <button class="btn sec" data-action="closeSheet">Отмена</button>`);
}
function pickerSheet(id) {
  openSheet(`<h3>Реакция</h3><div class="picker">${QUICK.map(e => `<button data-react="${e}" data-id="${esc(id)}">${e}</button>`).join('')}</div><button class="btn sec" data-action="closeSheet">Отмена</button>`);
}
function showNewPill() {
  const pill = document.getElementById('newpill');
  if (!S.pendingNew.length) { pill.style.display = 'none'; return; }
  const n = S.pendingNew.length;
  pill.textContent = `↑ ${n} ${n % 10 === 1 && n % 100 !== 11 ? 'новый пост' : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) ? 'новых поста' : 'новых постов'}`;
  pill.style.top = (document.querySelector('.top').getBoundingClientRect().bottom + 8) + 'px';
  pill.style.display = 'block';
}
function hideNewPill() {
  if (!S.pendingNew.length) return;
  S.posts = S.pendingNew.concat(S.posts);
  S.pendingNew = [];
  document.getElementById('newpill').style.display = 'none';
  render();
}

// ---------- Events ----------
document.addEventListener('click', e => {
  const t = e.target;
  const q = sel => t.closest(sel);
  let el;
  if ((el = q('.spoiler'))) { el.classList.add('shown'); return; }
  if ((el = q('[data-url]'))) { post({ action: 'url', url: el.dataset.url }); return; }
  if ((el = q('[data-chip]'))) { if (el.dataset.chip !== S.config.selected) { S.config.selected = el.dataset.chip; S.posts = []; S.loaded = false; render(); window.scrollTo(0, 0); post({ action: 'chip', id: el.dataset.chip }); } return; }
  if ((el = q('[data-expand]'))) { S.expanded[el.dataset.expand] = true; const p = S.posts.find(x => x.id === el.dataset.expand); if (p) replacePost(p); return; }
  if ((el = q('[data-menu]'))) { menuSheet(el.dataset.menu); return; }
  if ((el = q('[data-picker]'))) { pickerSheet(el.dataset.picker); return; }
  if ((el = q('[data-react]'))) {
    closeSheet();
    // Instant: the count and the highlight change right away; the app
    // confirms with the real counts later (Feed.updateReactions).
    const p = S.posts.find(x => x.id === el.dataset.id), key = el.dataset.react;
    if (p) {
      const had = p.reactions.find(r => r.mine);
      p.reactions.forEach(r => { if (r.mine) { r.mine = false; r.count -= 1; } });
      if (!had || had.key !== key) {
        const r = p.reactions.find(x => x.key === key);
        if (r) { r.mine = true; r.count += 1; } else p.reactions.push({ key: key, count: 1, mine: true });
      }
      p.reactions = p.reactions.filter(r => r.count > 0);
      updateReactionsRow(p);
    }
    post({ action: 'react', id: el.dataset.id, key: key });
    return;
  }
  if ((el = q('[data-comments]'))) { closeSheet(); post({ action: 'comments', id: el.dataset.comments }); return; }
  // Media open right here: photos and videos in the viewer, voice and round
  // videos play in the player; the post opens only from its header.
  if ((el = q('[data-media]'))) { if (playing) { playing.pause(); } post({ action: 'media', key: el.dataset.media }); return; }
  if ((el = q('[data-open]'))) { closeSheet(); post({ action: 'open', id: el.dataset.open }); return; }
  if ((el = q('[data-setting]'))) {
    const key = el.dataset.setting;
    S.config.settings[key] = !S.config.settings[key];
    el.querySelector('.sw').classList.toggle('on', S.config.settings[key]);
    post({ action: 'setting', key: key, value: S.config.settings[key] });
    if (key === 'autoplay' && !S.config.settings.autoplay && playing) { playing.pause(); playing = null; }
    return;
  }
  if ((el = q('[data-move]'))) {
    const i = Number(el.dataset.move), d = Number(el.dataset.dir), chips = S.config.chips, j = i + d;
    if (j < 0 || j >= chips.length) return;
    [chips[i], chips[j]] = [chips[j], chips[i]];
    post({ action: 'order', ids: chips.map(c => c.id) });
    render(); collectionsSheet();
    return;
  }
  if ((el = q('[data-edit]'))) { editSheet(el.dataset.edit); return; }
  if ((el = q('[data-pick]'))) { const id = Number(el.dataset.pick); if (editing.peerIds.has(id)) editing.peerIds.delete(id); else editing.peerIds.add(id); el.querySelector('.check').classList.toggle('on'); return; }
  if ((el = q('[data-action]'))) {
    const a = el.dataset.action;
    if (a === 'readAll') { S.posts.forEach(p => p.unread = false); render(); post({ action: 'readAll' }); }
    else if (a === 'openSettings') settingsSheet();
    else if (a === 'collections') collectionsSheet();
    else if (a === 'closeSheet') closeSheet();
    else if (a === 'toTop') { window.scrollTo({ top: 0, behavior: 'smooth' }); hideNewPill(); }
    else if (a === 'copyLink') { closeSheet(); post({ action: 'copyLink', id: el.dataset.id }); }
    else if (a === 'hideChannel') { closeSheet(); const peer = Number(el.dataset.peer); S.posts = S.posts.filter(p => p.peerId !== peer); render(); post({ action: 'hideChannel', peerId: peer }); }
    else if (a === 'saveCollection') {
      editing.title = document.getElementById('colTitle').value.trim();
      if (!editing.title || !editing.peerIds.size) { document.getElementById('colTitle').focus(); return; }
      post({ action: 'saveCollection', collection: { id: editing.id, title: editing.title, peerIds: Array.from(editing.peerIds) } });
      closeSheet();
    }
    else if (a === 'removeCollection') { post({ action: 'removeCollection', id: editing.id }); closeSheet(); }
  }
});
document.addEventListener('input', e => { if (e.target.id === 'colTitle' && editing) editing.title = e.target.value; });
document.getElementById('sheetBack').addEventListener('click', closeSheet);

// ---------- API for the app ----------
window.Feed = {
  init(config) {
    S.config = Object.assign(S.config, config);
    document.documentElement.dataset.theme = config.theme || 'dark';
    render();
  },
  setChips(chips, selected, unread) { S.config.chips = chips; if (selected) S.config.selected = selected; S.config.unread = unread; document.getElementById('chips').innerHTML = chipsHTML(); },
  setConfig(config) { S.config = Object.assign(S.config, config); },
  setPosts(posts, hasMore) { S.posts = posts; S.hasMore = hasMore; S.loaded = true; S.loadingMore = false; S.pendingNew = []; render(); },
  appendPosts(posts, hasMore) {
    const known = new Set(S.posts.map(p => p.id));
    S.posts = S.posts.concat(posts.filter(p => !known.has(p.id)));
    S.hasMore = hasMore; S.loadingMore = false; render();
  },
  prependPosts(posts) {
    const known = new Set(S.posts.map(p => p.id).concat(S.pendingNew.map(p => p.id)));
    const fresh = posts.filter(p => !known.has(p.id));
    if (!fresh.length) return;
    if (window.scrollY < 80) { S.posts = fresh.concat(S.posts); render(); }
    else { S.pendingNew = fresh.concat(S.pendingNew); showNewPill(); }
  },
  updatePost(p) { replacePost(p); },
  updateReactions(p) { const i = S.posts.findIndex(x => x.id === p.id); if (i < 0) return; S.posts[i].reactions = p.reactions; updateReactionsRow(S.posts[i]); },
  removeChannel(peerId) { S.posts = S.posts.filter(p => p.peerId !== peerId); render(); },
  mediaReady(key, url) {
    S.media[key] = url;
    let kind = key.endsWith(':poster') ? 'poster' : key.indexOf('avatar:') === 0 ? 'avatar' : 'media';
    const baseKey = kind === 'poster' ? key.slice(0, -7) : key;
    if (key.indexOf('ce:') === 0) {
      hydrateEmoji(document);
      return;
    }
    if (kind === 'avatar') {
      const peer = key.slice(7);
      document.querySelectorAll('.ava').forEach(a => {
        const postEl = a.closest('[data-post]');
        const p = postEl && S.posts.find(x => x.id === postEl.dataset.post);
        if (p && String(p.peerId) === peer) { a.style.backgroundImage = `url('${url}')`; a.textContent = ''; }
      });
      return;
    }
    document.querySelectorAll(`.m[data-key="${CSS.escape(baseKey)}"]`).forEach(m => {
      const p = S.posts.find(x => x.id === m.dataset.postId);
      if (p) replacePost(p);
    });
  }
};
post({ action: 'ready' });
</script>
</body>
</html>
"""#
}
