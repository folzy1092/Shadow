import Foundation

// Shadow: the «Итоги чата» page. One self-contained HTML document (data inside,
// no network) for three uses: the screen in the app (WKWebView, mode .app — its
// buttons post to the `shadow` message handler), the shared .html file (mode
// .file — tabs work, no app buttons) and the share picture (mode .card — only
// the card, snapshotted by the app). Foundation only.
public enum ShadowChatStatsPage {
    public enum Mode: String {
        case app
        case file
        case card
    }

    public enum CardKind: String {
        case compare = "cmp"
        case me
        case other
    }

    public struct Options {
        public var mode: Mode
        public var dark: Bool?
        public var card: CardKind
        public var hideName: Bool

        public init(mode: Mode, dark: Bool? = nil, card: CardKind = .compare, hideName: Bool = false) {
            self.mode = mode
            self.dark = dark
            self.card = card
            self.hideName = hideName
        }
    }

    public static func render(_ report: ShadowChatStats.Report, options: Options) -> String {
        var data = "{}"
        if let encoded = try? JSONEncoder().encode(report), let string = String(data: encoded, encoding: .utf8) {
            // Never let the data close the <script> element.
            data = string.replacingOccurrences(of: "</", with: "<\\/")
        }
        var config: [String: Any] = [
            "mode": options.mode.rawValue,
            "card": options.card.rawValue,
            "hideName": options.hideName
        ]
        if let dark = options.dark {
            config["theme"] = dark ? "dark" : "light"
        }
        let configData = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])) ?? Data("{}".utf8)
        let configString = String(data: configData, encoding: .utf8) ?? "{}"
        let title = htmlEscaped("Итоги — " + report.title)
        return template
            .replacingOccurrences(of: "__TITLE__", with: title)
            .replacingOccurrences(of: "__CONFIG__", with: configString)
            .replacingOccurrences(of: "__REPORT__", with: data)
    }

    public static func fileName(_ report: ShadowChatStats.Report) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let title = report.title.components(separatedBy: forbidden).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "Итоги — \(title.isEmpty ? "чат" : title).html"
    }

    public static func htmlEscaped(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let template = #"""
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<title>__TITLE__</title>
<style>
:root {
  --page: #000; --card: #1c1c1e; --card2: #2c2c2e; --sep: #38383a;
  --text: #fff; --sub: #8e8e93; --muted: #636366; --accent: #3e9bff; --green: #34c759;
  --me: #3987e5; --them: #d95926; --grid: rgba(255,255,255,.08);
  --heat0: #1f2633; --heat1: #1d3b66; --heat2: #1f5aa6; --heat3: #3987e5; --heat4: #8fbaf2;
  --sheet: #1c1c1e;
}
@media (prefers-color-scheme: light) {
  :root:not([data-theme="dark"]) {
    --page: #f2f2f7; --card: #fff; --card2: #e9e9ee; --sep: #d1d1d6;
    --text: #000; --sub: #6d6d72; --muted: #8e8e93; --me: #2a78d6; --them: #eb6834; --grid: rgba(0,0,0,.07);
    --heat0: #eef2f8; --heat1: #c6daf5; --heat2: #8db7ec; --heat3: #4a8fe0; --heat4: #1f5aa6; --sheet: #fff;
  }
}
:root[data-theme="light"] {
  --page: #f2f2f7; --card: #fff; --card2: #e9e9ee; --sep: #d1d1d6;
  --text: #000; --sub: #6d6d72; --muted: #8e8e93; --me: #2a78d6; --them: #eb6834; --grid: rgba(0,0,0,.07);
  --heat0: #eef2f8; --heat1: #c6daf5; --heat2: #8db7ec; --heat3: #4a8fe0; --heat4: #1f5aa6; --sheet: #fff;
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--page); color: var(--text); font: 15px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; padding-bottom: calc(24px + env(safe-area-inset-bottom)); }
.wrap { max-width: 520px; margin: 0 auto; }
.head { padding: 14px 20px 4px; }
.head h1 { margin: 0; font-size: 28px; font-weight: 700; }
.head .p { color: var(--sub); font-size: 13px; margin-top: 2px; }
.tabs { position: sticky; top: 0; z-index: 4; display: flex; gap: 6px; padding: 8px 16px 10px; background: color-mix(in srgb, var(--page) 86%, transparent); -webkit-backdrop-filter: blur(18px); backdrop-filter: blur(18px); }
.tab { flex: 1; text-align: center; padding: 8px 4px; border-radius: 18px; background: var(--card); font-size: 14px; font-weight: 600; cursor: pointer; user-select: none; -webkit-user-select: none; display: flex; align-items: center; justify-content: center; gap: 6px; white-space: nowrap; overflow: hidden; }
.tab .sw { width: 9px; height: 9px; border-radius: 5px; flex: none; }
.tab.on { background: var(--text); color: var(--page); }
.tab.cmp { flex: 0 0 auto; padding: 8px 12px; }
.hero { margin: 4px 16px 0; background: var(--card); border-radius: 16px; padding: 16px; }
.hero .num { font-size: 44px; font-weight: 800; letter-spacing: -.02em; line-height: 1.05; font-variant-numeric: tabular-nums; }
.hero .cap { color: var(--sub); font-size: 14px; }
.balance { display: flex; height: 10px; border-radius: 5px; overflow: hidden; gap: 2px; margin: 12px 0 6px; }
.balance div { height: 100%; }
.balance-l { display: flex; justify-content: space-between; font-size: 12.5px; color: var(--sub); }
.balance-l b { color: var(--text); font-weight: 600; }
.key { display: inline-block; width: 8px; height: 8px; border-radius: 2px; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin: 8px 16px 0; }
.tile { background: var(--card); border-radius: 14px; padding: 12px 12px 10px; }
.tile .t { color: var(--sub); font-size: 12.5px; }
.tile .v { font-size: 22px; font-weight: 700; margin-top: 3px; font-variant-numeric: tabular-nums; }
.tile .s { color: var(--sub); font-size: 12px; margin-top: 1px; }
.tile.wide { grid-column: span 2; }
.gtitle { color: var(--sub); font-size: 13px; text-transform: uppercase; margin: 22px 32px 7px; letter-spacing: .02em; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.echip { background: var(--card2); border-radius: 14px; padding: 4px 10px; font-size: 15px; display: inline-flex; align-items: center; gap: 4px; min-height: 30px; }
.echip img { width: 24px; height: 24px; object-fit: contain; }
.echip small { color: var(--sub); font-size: 12px; }
.box { background: var(--card); border-radius: 14px; padding: 12px 14px; margin: 8px 16px 0; }
.box h4 { margin: 0 0 8px; font-size: 15px; display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.box h4 small { color: var(--sub); font-weight: 400; font-size: 12.5px; text-align: right; }
.hint { color: var(--sub); font-size: 12px; margin-top: 6px; }
.empty { color: var(--sub); font-size: 14px; }
.bars { display: flex; align-items: flex-end; gap: 3px; height: 96px; border-bottom: 1px solid var(--grid); position: relative; margin-top: 18px; }
.bars .c { flex: 1; height: 100%; display: flex; align-items: flex-end; justify-content: center; position: relative; }
.bars .b { width: 62%; border-radius: 4px 4px 0 0; min-height: 2px; }
.bars.days .b { width: 46%; }
.axis { display: flex; justify-content: space-between; color: var(--muted); font-size: 11px; margin-top: 4px; }
.axis.days span { flex: 1; text-align: center; }
.peak { position: absolute; font-size: 11.5px; color: var(--text); font-weight: 600; transform: translateX(-50%); white-space: nowrap; bottom: calc(100% + 2px); }
.cmprow { padding: 10px 0; border-bottom: .5px solid var(--sep); }
.cmprow:last-child { border-bottom: none; padding-bottom: 2px; }
.cmprow .h { display: flex; justify-content: space-between; font-size: 13px; color: var(--sub); margin-bottom: 6px; gap: 8px; }
.cmprow .h b { color: var(--text); font-weight: 600; }
.legend { display: flex; gap: 14px; font-size: 12.5px; color: var(--sub); margin-bottom: 8px; align-items: center; }
.legend i { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 5px; vertical-align: -1px; }
.heat { display: grid; grid-template-columns: 20px repeat(24, minmax(0, 1fr)); gap: 1px; font-size: 10px; color: var(--muted); width: 100%; }
.heat .cell { aspect-ratio: 1; border-radius: 2px; min-width: 0; }
.heat .d { display: flex; align-items: center; }
.awards { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.award { background: var(--card2); border-radius: 12px; padding: 10px; }
.award .e { font-size: 22px; }
.award b { display: block; font-size: 13.5px; margin-top: 2px; }
.award span { display: block; color: var(--sub); font-size: 12px; }
.award .who { display: inline-block; margin-top: 6px; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 10px; color: #fff; }
.facts .f { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: .5px solid var(--sep); font-size: 14px; gap: 12px; }
.facts .f:last-child { border-bottom: none; }
.facts .f span:first-child { color: var(--sub); }
.facts .f span:last-child { text-align: right; font-variant-numeric: tabular-nums; }
.leader .lr { display: flex; align-items: center; gap: 10px; padding: 7px 0; cursor: pointer; }
.leader .lr .nm { width: 96px; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.leader .lr .bar { flex: 1; height: 10px; background: var(--card2); border-radius: 5px; overflow: hidden; }
.leader .lr .bar div { height: 100%; border-radius: 5px; }
.leader .lr .n { width: 64px; text-align: right; color: var(--sub); font-size: 13px; font-variant-numeric: tabular-nums; }
.actions { margin: 18px 16px 0; display: grid; gap: 8px; }
.btn { border: none; border-radius: 13px; height: 50px; width: 100%; background: var(--accent); color: #fff; font-size: 16px; font-weight: 600; cursor: pointer; font-family: inherit; }
.btn.sec { background: var(--card); color: var(--accent); font-weight: 500; }
.foot { color: var(--sub); font-size: 12px; text-align: center; margin: 18px 24px 0; }
.tip { position: fixed; z-index: 50; pointer-events: none; background: rgba(20,20,22,.96); color: #fff; font-size: 12.5px; padding: 6px 9px; border-radius: 8px; opacity: 0; transition: opacity .1s; white-space: nowrap; }
.tip.show { opacity: 1; }
.sheet-back { position: fixed; inset: 0; background: rgba(0,0,0,.45); opacity: 0; pointer-events: none; transition: opacity .2s; z-index: 20; }
.sheet-back.show { opacity: 1; pointer-events: auto; }
.sheet { position: fixed; left: 8px; right: 8px; bottom: calc(8px + env(safe-area-inset-bottom)); max-width: 520px; margin: 0 auto; background: var(--sheet); border-radius: 26px; padding: 18px 16px 14px; transform: translateY(130%); transition: transform .25s ease; z-index: 21; max-height: 92%; overflow-y: auto; }
.sheet.show { transform: none; }
.sheet h3 { margin: 0 0 10px; font-size: 18px; text-align: center; }
.opts { display: flex; gap: 6px; justify-content: center; margin: 0 0 12px; flex-wrap: wrap; }
.opt { background: var(--card2); border-radius: 14px; padding: 6px 12px; font-size: 13.5px; cursor: pointer; }
.opt.on { background: var(--accent); color: #fff; }
.swrow { display: flex; align-items: center; justify-content: space-between; padding: 12px 4px; font-size: 15px; }
.switch { width: 51px; height: 31px; border-radius: 16px; background: #39393d; position: relative; flex: none; cursor: pointer; transition: background .2s; }
:root[data-theme="light"] .switch { background: #e9e9ea; }
.switch::after { content: ""; position: absolute; top: 2px; left: 2px; width: 27px; height: 27px; border-radius: 50%; background: #fff; box-shadow: 0 2px 4px rgba(0,0,0,.25); transition: left .2s; }
.switch.on { background: var(--green); }
.switch.on::after { left: 22px; }
.preview { display: flex; justify-content: center; }
.preview .share { width: 230px; font-size: 10px; }
/* Share card: 9:16, designed at 360x640 CSS px. */
.share { width: 360px; aspect-ratio: 9 / 16; overflow: hidden; position: relative; color: #fff; padding: 26px 22px; background: radial-gradient(120% 70% at 0% 0%, #1d3f78 0%, transparent 60%), radial-gradient(120% 70% at 100% 100%, #6b2a12 0%, transparent 60%), #0b0d12; display: flex; flex-direction: column; font-size: 14px; border-radius: 22px; }
.share .brand { font-size: .78em; letter-spacing: .14em; text-transform: uppercase; opacity: .7; }
.share .ttl { font-size: 1.6em; font-weight: 800; margin-top: .4em; line-height: 1.15; }
.share .pp { display: flex; align-items: center; gap: .6em; margin-top: .9em; opacity: .8; font-size: .9em; }
.share .bign { font-size: 3em; font-weight: 800; letter-spacing: -.02em; margin-top: .4em; line-height: 1; }
.share .bigc { opacity: .7; }
.share .bal { display: flex; height: .6em; border-radius: .3em; overflow: hidden; gap: 2px; margin: .8em 0 .3em; }
.share .ball { display: flex; justify-content: space-between; opacity: .85; font-size: .85em; }
.share .sg { display: grid; grid-template-columns: 1fr 1fr; gap: .5em; margin-top: 1em; }
.share .sg div { background: rgba(255,255,255,.07); border-radius: .8em; padding: .55em .65em; }
.share .sg b { display: block; font-size: 1.3em; }
.share .sg span { opacity: .7; font-size: .82em; }
.share .em { font-size: 1.6em; margin-top: .7em; letter-spacing: .1em; }
.share .aw { opacity: .85; margin-top: .4em; font-size: .9em; }
.share .cf { display: flex; gap: .5em; margin-top: .6em; flex-wrap: wrap; }
.share .cf span { display: inline-flex; align-items: center; gap: .25em; background: rgba(255,255,255,.07); border-radius: .8em; padding: .2em .5em; font-size: 1.1em; }
.share .cf img { width: 1.5em; height: 1.5em; object-fit: contain; }
.share .cf small { font-size: .7em; opacity: .75; }
.share .ft { margin-top: auto; display: flex; justify-content: space-between; opacity: .55; font-size: .78em; }
body.cardmode { background: transparent; padding: 0; }
body.cardmode .share { border-radius: 0; }
</style>
</head>
<body>
<div class="wrap" id="root"></div>
<div class="tip" id="tip"></div>
<div class="sheet-back" id="sheetBack"></div>
<div class="sheet" id="shareSheet"></div>
<script>
const CONFIG = __CONFIG__;
const R = __REPORT__;
if (CONFIG.theme) document.documentElement.dataset.theme = CONFIG.theme;

const MONTHS_GEN = ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря'];
const DAY_LABELS = ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'];
const DAY_FULL = ['понедельник','вторник','среда','четверг','пятница','суббота','воскресенье'];
const PERIOD_FOR = ['за неделю','за месяц','за год','за 5 лет'];
const fmt = n => Number(n || 0).toLocaleString('ru-RU');
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
function plural(n, one, few, many) {
  const a = Math.abs(n) % 100, b = a % 10;
  if (a > 10 && a < 20) return many;
  if (b > 1 && b < 5) return few;
  if (b === 1) return one;
  return many;
}
function dur(seconds) {
  seconds = Math.round(seconds || 0);
  if (seconds < 60) return seconds + ' сек';
  const h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60);
  if (h === 0) return m + ' мин';
  return h + ' ч ' + m + ' мин';
}
function shortDur(seconds) {
  if (seconds == null) return '—';
  if (seconds < 60) return seconds + ' сек';
  if (seconds < 3600) return Math.round(seconds / 60) + ' мин';
  const h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60);
  return h + ' ч' + (m ? ' ' + m + ' мин' : '');
}
function gapText(seconds) {
  const days = Math.floor(seconds / 86400);
  if (days >= 1) return days + ' ' + plural(days, 'день', 'дня', 'дней');
  const h = Math.floor(seconds / 3600);
  if (h >= 1) return h + ' ' + plural(h, 'час', 'часа', 'часов');
  return Math.max(1, Math.round(seconds / 60)) + ' мин';
}
function dayDate(day, withYear) {
  const d = new Date(day * 86400000);
  return d.getUTCDate() + ' ' + MONTHS_GEN[d.getUTCMonth()] + (withYear ? ' ' + d.getUTCFullYear() : '');
}
function tsDate(ts, withYear) { return dayDate(Math.floor((ts + R.timeZoneOffset) / 86400), withYear); }
const pct = (a, b) => b ? Math.round(a / b * 100) : 0;

const me = R.people.find(p => p.id === R.meId) || null;
const other = R.isGroup ? null : (R.people.find(p => p.id !== R.meId) || null);
function displayName(p) {
  if (!p) return '';
  if (p.id === R.meId) return 'Я';
  return CONFIG.hideName && CONFIG.mode === 'card' ? 'Собеседник' : p.name;
}
function colorOf(p) { return p && p.id === R.meId ? 'var(--me)' : 'var(--them)'; }

function chip(item) {
  const img = R.images && R.images[item.key];
  let face;
  if (img) face = `<img src="${img}" alt="">`;
  else if (item.key === 'stars') face = '⭐️';
  else if (item.key.indexOf('custom:') === 0 || item.key.indexOf('sticker:') === 0) face = esc(item.label || '🖼');
  else face = esc(item.key);
  return `<span class="echip">${face}<small>${fmt(item.count)}</small></span>`;
}
function chipsBox(title, items, hint) {
  if (!items || !items.length) return '';
  return `<div class="box"><h4>${title}${hint ? `<small>${hint}</small>` : ''}</h4><div class="chips">${items.map(chip).join('')}</div></div>`;
}

function barChart(values, color, labels, unit, days) {
  const max = Math.max(1, ...values);
  const peakIndex = values.indexOf(Math.max(...values));
  const cols = values.map((v, i) => `<div class="c" data-tip="${labels[i]} — ${fmt(v)} ${unit}"><div class="b" style="height:${Math.max(2, v / max * 100)}%;background:${color}"></div></div>`).join('');
  const left = (peakIndex + .5) / values.length * 100;
  const peak = values[peakIndex] > 0 ? `<div class="peak" style="left:${left}%">${labels[peakIndex]}</div>` : '';
  const axis = days
    ? `<div class="axis days">${DAY_LABELS.map(d => `<span>${d}</span>`).join('')}</div>`
    : '<div class="axis"><span>00</span><span>06</span><span>12</span><span>18</span><span>23</span></div>';
  return `<div class="bars ${days ? 'days' : ''}">${cols}${peak}</div>${axis}`;
}
const HOUR_LABELS = Array.from({ length: 24 }, (_, i) => String(i).padStart(2, '0') + ':00');

function personView(p) {
  if (!p) return '<div class="box empty">Нет данных.</div>';
  const mine = p.id === R.meId;
  const total = Math.max(1, R.total);
  const share = pct(p.messages, total);
  const voiceShare = p.messages ? Math.round(p.voiceCount / p.messages * 1000) / 10 : 0;
  const peakHour = p.hours.indexOf(Math.max(...p.hours));
  const peakDay = p.weekdays.indexOf(Math.max(...p.weekdays));
  const balance = R.isGroup ? '' : `
    <div class="balance"><div style="width:${pct(me ? me.messages : 0, total)}%;background:var(--me);${mine ? '' : 'opacity:.35'}"></div><div style="flex:1;background:var(--them);${mine ? 'opacity:.35' : ''}"></div></div>
    <div class="balance-l"><span>Я <b>${pct(me ? me.messages : 0, total)}%</b></span><span>${esc(displayName(other))} <b>${pct(other ? other.messages : 0, total)}%</b></span></div>`;
  return `
  <div class="hero">
    <div class="cap">${mine ? 'Вы написали' : esc(p.name) + ' — написано'}</div>
    <div class="num">${fmt(p.messages)}</div>
    <div class="cap">${plural(p.messages, 'сообщение', 'сообщения', 'сообщений')} — ${share}% переписки</div>
    ${balance}
  </div>
  <div class="grid2">
    <div class="tile"><div class="t">Слов</div><div class="v">${fmt(p.words)}</div><div class="s">${p.messages ? (p.words / p.messages).toFixed(1).replace('.', ',') : 0} в сообщении</div></div>
    <div class="tile"><div class="t">Голосовые</div><div class="v">${dur(p.voiceSeconds)}</div><div class="s">${fmt(p.voiceCount)} шт.</div></div>
    <div class="tile"><div class="t">Кружки</div><div class="v">${dur(p.roundSeconds)}</div><div class="s">${fmt(p.roundCount)} шт.</div></div>
    <div class="tile"><div class="t">Стикеры</div><div class="v">${fmt(p.stickers)}</div><div class="s">и ${fmt(p.gifs)} GIF</div></div>
    <div class="tile"><div class="t">Фото и видео</div><div class="v">${fmt(p.photos + p.videos)}</div><div class="s">${fmt(p.photos)} фото · ${fmt(p.videos)} видео</div></div>
    <div class="tile"><div class="t">Ссылки и пересланное</div><div class="v">${fmt(p.links + p.forwards)}</div><div class="s">${fmt(p.links)} ссылок · ${fmt(p.forwards)} пересл.</div></div>
  </div>
  <div class="gtitle">${mine ? 'Как вы пишете' : 'Как пишет ' + esc(p.name)}</div>
  <div class="grid2" style="margin-top:0">
    <div class="tile"><div class="t">Пишет первым за день</div><div class="v">${pct(p.firstOfDay, R.firstOfDayDays)}%</div><div class="s">${fmt(p.firstOfDay)} из ${fmt(R.firstOfDayDays)} дней</div></div>
    <div class="tile"><div class="t">Обычно отвечает за</div><div class="v">${shortDur(p.replySeconds)}</div><div class="s">медиана, паузы больше 6 ч не в счёт</div></div>
    <div class="tile"><div class="t">Ночью, 0:00–6:00</div><div class="v">${pct(p.night, p.messages)}%</div><div class="s">${fmt(p.night)} сообщ.</div></div>
    <div class="tile"><div class="t">Удалено · изменено</div><div class="v">${fmt(p.deleted)} · ${fmt(p.edited)}</div><div class="s">удалённые сохранены Shadow</div></div>
    <div class="tile wide"><div class="t">Ответов на сообщения · звонков</div><div class="v">${fmt(p.replies)} · ${fmt(p.calls)}</div><div class="s">звонки: ${dur(p.callSeconds)} всего</div></div>
  </div>
  ${chipsBox('Любимые реакции', p.reactions, 'вместе с премиум')}
  ${chipsBox('Любимые эмодзи', p.emoji)}
  ${chipsBox('Любимые стикеры', p.topStickers, 'топ-5')}
  ${p.topWords.length ? `<div class="box"><h4>Любимые слова<small>без предлогов и частиц</small></h4><div class="chips">${p.topWords.map(w => `<span class="echip">${esc(w.key)}<small>${fmt(w.count)}</small></span>`).join('')}</div></div>` : ''}
  <div class="box"><h4>По часам<small>чаще всего в ${HOUR_LABELS[peakHour]}</small></h4>${barChart(p.hours, colorOf(p), HOUR_LABELS, 'сообщ.', false)}</div>
  <div class="box"><h4>По дням недели<small>больше всего — ${DAY_FULL[peakDay]}</small></h4>${barChart(p.weekdays, colorOf(p), DAY_LABELS, 'сообщ.', true)}</div>
  <div class="box facts">
    ${p.bestDay ? `<div class="f"><span>Самый активный день</span><span>${dayDate(p.bestDay.day, true)} — ${fmt(p.bestDay.count)}</span></div>` : ''}
    <div class="f"><span>Голосовые среди сообщений</span><span>${String(voiceShare).replace('.', ',')}%</span></div>
  </div>`;
}

function cmpRow(title, a, b, aLabel, bLabel, aWins) {
  const total = a + b;
  const aw = total ? a / total * 100 : 50;
  if (aWins === undefined) aWins = a >= b;
  return `<div class="cmprow"><div class="h"><span><b>${aLabel}</b></span><span>${title}</span><span><b>${bLabel}</b></span></div>
    <div class="balance" style="margin:0" data-tip="${title}: я ${aLabel} · ${esc(displayName(other))} ${bLabel}"><div style="width:${aw}%;background:var(--me);${aWins ? '' : 'opacity:.5'}"></div><div style="flex:1;background:var(--them);${aWins ? 'opacity:.5' : ''}"></div></div></div>`;
}

function lineChart(series) {
  const labels = R.timelineLabels;
  const n = labels.length;
  const W = 330, H = 150, pl = 34, pr = 8, pt = 12, pb = 22;
  const max = Math.max(4, ...series.flatMap(s => s.values));
  const nice = Math.ceil(max / 4 / Math.pow(10, Math.floor(Math.log10(max / 4)))) * Math.pow(10, Math.floor(Math.log10(max / 4))) * 4;
  const x = i => n > 1 ? pl + i * (W - pl - pr) / (n - 1) : pl + (W - pl - pr) / 2;
  const y = v => pt + (1 - v / nice) * (H - pt - pb);
  const path = arr => arr.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join('');
  const short = v => v >= 1000 ? (Math.round(v / 100) / 10).toString().replace('.', ',') + 'K' : String(v);
  let grid = '';
  for (let k = 0; k <= 4; k++) {
    const v = nice / 4 * k;
    grid += `<line x1="${pl}" x2="${W - pr}" y1="${y(v)}" y2="${y(v)}" stroke="var(--grid)"/><text x="${pl - 6}" y="${y(v) + 3}" text-anchor="end" font-size="10" fill="var(--muted)">${short(v)}</text>`;
  }
  const every = Math.max(1, Math.ceil(n / 6));
  let xl = '';
  labels.forEach((l, i) => { if (i % every === 0 || i === n - 1 && n <= 8) xl += `<text x="${x(i)}" y="${H - 6}" text-anchor="middle" font-size="10" fill="var(--muted)">${esc(l)}</text>`; });
  let hits = '';
  const step = n > 1 ? (W - pl - pr) / (n - 1) : 40;
  labels.forEach((l, i) => {
    const tip = series.map(s => `${s.name} ${fmt(s.values[i])}`).join(' · ');
    hits += `<rect x="${x(i) - step / 2}" y="${pt}" width="${step}" height="${H - pt - pb}" fill="transparent" data-tip="${esc(l)}: ${esc(tip)}" data-cross="${x(i)}"/>`;
  });
  const lines = series.map(s => `<path d="${path(s.values)}" fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`).join('');
  const ends = series.map(s => `<circle cx="${x(n - 1)}" cy="${y(s.values[n - 1] || 0)}" r="4" fill="${s.color}" stroke="var(--card)" stroke-width="2"/>`).join('');
  return `<svg viewBox="0 0 ${W} ${H}" width="100%" style="display:block;overflow:visible">${grid}${xl}<line class="cross" x1="0" x2="0" y1="${pt}" y2="${H - pb}" stroke="var(--sub)" stroke-dasharray="3 3" opacity="0"/>${lines}${ends}${hits}</svg>`;
}

function heatmap() {
  const max = Math.max(1, ...R.heatmap.flat());
  const step = v => v === 0 ? 0 : v / max < .25 ? 1 : v / max < .5 ? 2 : v / max < .75 ? 3 : 4;
  let html = '<div class="heat">';
  R.heatmap.forEach((row, di) => {
    html += `<div class="d">${DAY_LABELS[di]}</div>` + row.map((v, hi) => `<div class="cell" style="background:var(--heat${step(v)})" data-tip="${DAY_LABELS[di]}, ${HOUR_LABELS[hi]} — ${fmt(v)} сообщ."></div>`).join('');
  });
  html += '</div><div class="axis" style="margin-left:24px"><span>00</span><span>06</span><span>12</span><span>18</span><span>23</span></div>';
  html += `<div class="legend" style="margin:8px 0 0">меньше&nbsp;${[0, 1, 2, 3, 4].map(i => `<i style="background:var(--heat${i});margin-right:2px"></i>`).join('')}&nbsp;больше</div>`;
  let bestD = 0, bestH = 0;
  R.heatmap.forEach((row, d) => row.forEach((v, h) => { if (v > R.heatmap[bestD][bestH]) { bestD = d; bestH = h; } }));
  return { html, peak: `${DAY_LABELS[bestD].toLowerCase()}, ${HOUR_LABELS[bestH]}` };
}

function awards() {
  if (!me || !other) return [];
  const list = [];
  const add = (e, title, a, b, text, higherWins) => {
    if (a === b || (a <= 0 && b <= 0)) return;
    const meWins = higherWins ? a > b : a < b;
    const winner = meWins ? me : other;
    list.push(`<div class="award"><div class="e">${e}</div><b>${title}</b><span>${text(winner)}</span><div class="who" style="background:${colorOf(winner)}">${esc(displayName(winner))}</div></div>`);
  };
  add('🦉', 'Ночная сова', pct(me.night, me.messages), pct(other.night, other.messages), w => `${pct(w.night, w.messages)}% сообщений ночью`, true);
  if (me.replySeconds != null && other.replySeconds != null) add('⚡️', 'Быстрый ответ', me.replySeconds, other.replySeconds, w => `обычно за ${shortDur(w.replySeconds)}`, false);
  add('🎙', 'Голосовой', me.voiceSeconds, other.voiceSeconds, w => `${dur(w.voiceSeconds)} голосовых`, true);
  add('✍️', 'Писатель', me.words, other.words, w => `${fmt(w.words)} слов`, true);
  add('🐸', 'Король стикеров', me.stickers, other.stickers, w => `${fmt(w.stickers)} стикеров`, true);
  add('☀️', 'Начинает день', me.firstOfDay, other.firstOfDay, w => `первым в ${pct(w.firstOfDay, R.firstOfDayDays)}% дней`, true);
  add('📸', 'Фотограф', me.photos + me.videos, other.photos + other.videos, w => `${fmt(w.photos + w.videos)} фото и видео`, true);
  add('🔗', 'Почтальон', me.forwards + me.links, other.forwards + other.links, w => `${fmt(w.forwards)} пересланных, ${fmt(w.links)} ссылок`, true);
  return list;
}

// Both sides' favourites in «Сравнение» (they were only on the personal tabs).
function favorites(title, field) {
  const rows = [me, other].filter(p => p && p[field] && p[field].length);
  if (!rows.length) return '';
  return `<div class="box"><h4>${title}</h4>${rows.map(p => `<div style="margin:6px 0"><div class="hint" style="margin:0 0 4px"><i class="key" style="background:${colorOf(p)}"></i> ${esc(displayName(p))}</div><div class="chips">${p[field].slice(0, 5).map(chip).join('')}</div></div>`).join('')}</div>`;
}

function compareView() {
  if (!me || !other) return personView(me);
  const total = Math.max(1, R.total);
  const hm = heatmap();
  const aw = awards();
  const rows = [
    cmpRow('сообщения', me.messages, other.messages, fmt(me.messages), fmt(other.messages)),
    cmpRow('слова', me.words, other.words, fmt(me.words), fmt(other.words)),
    cmpRow('голосовые', me.voiceSeconds, other.voiceSeconds, dur(me.voiceSeconds), dur(other.voiceSeconds)),
    cmpRow('кружки', me.roundCount, other.roundCount, fmt(me.roundCount), fmt(other.roundCount)),
    cmpRow('стикеры', me.stickers, other.stickers, fmt(me.stickers), fmt(other.stickers)),
    cmpRow('фото и видео', me.photos + me.videos, other.photos + other.videos, fmt(me.photos + me.videos), fmt(other.photos + other.videos)),
    cmpRow('пишет первым', me.firstOfDay, other.firstOfDay, pct(me.firstOfDay, R.firstOfDayDays) + '%', pct(other.firstOfDay, R.firstOfDayDays) + '%')
  ];
  if (me.replySeconds != null && other.replySeconds != null) {
    // Faster wins: the bar shows speed, not seconds.
    rows.push(cmpRow('отвечает быстрее', 1 / Math.max(1, me.replySeconds), 1 / Math.max(1, other.replySeconds), shortDur(me.replySeconds), shortDur(other.replySeconds), me.replySeconds <= other.replySeconds));
  }
  rows.push(cmpRow('ночью', pct(me.night, me.messages), pct(other.night, other.messages), pct(me.night, me.messages) + '%', pct(other.night, other.messages) + '%'));
  rows.push(cmpRow('удалено', me.deleted, other.deleted, fmt(me.deleted), fmt(other.deleted)));
  const timeline = R.timelineLabels.length > 1 ? `<div class="box"><h4>${R.period >= 2 ? 'По месяцам' : 'По дням'}<small>сообщений</small></h4>
    <div class="legend"><span><i style="background:var(--me)"></i>Я</span><span><i style="background:var(--them)"></i>${esc(displayName(other))}</span></div>
    ${lineChart([{ name: 'я', values: me.timeline, color: 'var(--me)' }, { name: displayName(other), values: other.timeline, color: 'var(--them)' }])}</div>` : '';
  const calls = me.calls + other.calls;
  return `
  <div class="hero">
    <div class="cap">Вместе написали</div>
    <div class="num">${fmt(R.total)}</div>
    <div class="cap">${plural(R.total, 'сообщение', 'сообщения', 'сообщений')} · переписывались ${fmt(R.daysWithMessages)} ${plural(R.daysWithMessages, 'день', 'дня', 'дней')} из ${fmt(R.daysInPeriod)}</div>
    <div class="balance"><div style="width:${pct(me.messages, total)}%;background:var(--me)"></div><div style="flex:1;background:var(--them)"></div></div>
    <div class="balance-l"><span><i class="key" style="background:var(--me)"></i> Я <b>${pct(me.messages, total)}%</b></span><span>${esc(displayName(other))} <b>${pct(other.messages, total)}%</b> <i class="key" style="background:var(--them)"></i></span></div>
  </div>
  <div class="box"><h4>Кто больше<small>ярче — у кого больше</small></h4>${rows.join('')}</div>
  ${timeline}
  <div class="box"><h4>Когда вы общаетесь<small>чаще всего ${hm.peak}</small></h4>${hm.html}</div>
  ${aw.length ? `<div class="box"><h4>Награды</h4><div class="awards">${aw.join('')}</div></div>` : ''}
  ${favorites('Любимые реакции', 'reactions')}
  ${favorites('Любимые эмодзи', 'emoji')}
  ${favorites('Любимые стикеры', 'topStickers')}
  <div class="box facts">
    <div class="f"><span>Общаетесь подряд</span><span>${fmt(R.streakCurrent)} ${plural(R.streakCurrent, 'день', 'дня', 'дней')} · рекорд ${fmt(R.streakBest)}</span></div>
    ${R.longestBreak > 0 ? `<div class="f"><span>Самый длинный перерыв</span><span>${gapText(R.longestBreak)} (${tsDate(R.longestBreakFrom)} — ${tsDate(R.longestBreakTo)})</span></div>` : ''}
    ${R.bestDay ? `<div class="f"><span>Самый активный день</span><span>${dayDate(R.bestDay.day, true)} — ${fmt(R.bestDay.count)}</span></div>` : ''}
    <div class="f"><span>Звонков</span><span>${fmt(calls)} · ${dur(me.callSeconds + other.callSeconds)}</span></div>
    ${R.firstMessage ? `<div class="f"><span>Первое сообщение периода</span><span>${tsDate(R.firstMessage, true)}</span></div>` : ''}
  </div>`;
}

let selectedMember = null;
function groupView() {
  const people = R.people.filter(p => p.messages > 0);
  const max = Math.max(1, ...people.map(p => p.messages));
  const voiceMax = Math.max(1, ...people.map(p => p.voiceSeconds));
  const byVoice = people.filter(p => p.voiceSeconds > 0).sort((a, b) => b.voiceSeconds - a.voiceSeconds).slice(0, 10);
  const row = (p, value, maxValue, label) => `<div class="lr" data-member="${p.id}"><div class="nm">${esc(displayName(p))}</div><div class="bar"><div style="width:${value / maxValue * 100}%;background:${p.id === R.meId ? 'var(--me)' : 'var(--muted)'}"></div></div><div class="n">${label}</div></div>`;
  const hours = Array.from({ length: 24 }, (_, h) => R.heatmap.reduce((a, r) => a + r[h], 0));
  return `
  <div class="hero"><div class="cap">В группе ${PERIOD_FOR[R.period] || ''}</div><div class="num">${fmt(R.total)}</div><div class="cap">${plural(R.total, 'сообщение', 'сообщения', 'сообщений')} от ${fmt(people.length)} ${plural(people.length, 'участника', 'участников', 'участников')}</div></div>
  <div class="box leader"><h4>Кто больше пишет<small>нажмите — итоги участника</small></h4>${people.slice(0, 30).map(p => row(p, p.messages, max, fmt(p.messages))).join('')}</div>
  ${byVoice.length ? `<div class="box leader"><h4>Голосовые</h4>${byVoice.map(p => row(p, p.voiceSeconds, voiceMax, shortDur(p.voiceSeconds))).join('')}</div>` : ''}
  <div class="box"><h4>По часам<small>вся группа</small></h4>${barChart(hours, 'var(--me)', HOUR_LABELS, 'сообщ.', false)}</div>`;
}

let tab = R.isGroup ? 'group' : 'cmp';
function tabsHTML() {
  const t = R.isGroup
    ? [['me', '<span class="sw" style="background:var(--me)"></span>Я'], ['group', 'Участники']]
    : [['me', '<span class="sw" style="background:var(--me)"></span>Я'], ['other', `<span class="sw" style="background:var(--them)"></span>${esc(displayName(other))}`], ['cmp', '⇄ Сравнение']];
  if (R.isGroup && selectedMember != null) {
    const p = R.people.find(x => x.id === selectedMember);
    if (p && p.id !== R.meId) t.push(['member', esc(p.name)]);
  }
  return `<div class="tabs">${t.map(x => `<div class="tab ${x[0] === 'cmp' ? 'cmp' : ''} ${tab === x[0] ? 'on' : ''}" data-tab="${x[0]}">${x[1]}</div>`).join('')}</div>`;
}
function body() {
  if (tab === 'me') return personView(me);
  if (tab === 'other') return personView(other);
  if (tab === 'member') return personView(R.people.find(p => p.id === selectedMember));
  if (tab === 'group') return groupView();
  return compareView();
}
function actionsHTML() {
  if (CONFIG.mode !== 'app') return `<div class="foot">Посчитано в Shadow на телефоне · ${tsDate(R.generated, true)}</div>`;
  return `<div class="actions">
    <button class="btn" data-action="openShare">Поделиться картинкой</button>
    <button class="btn sec" data-action="shareFile">Поделиться файлом</button>
    <button class="btn sec" data-action="recalculate">Пересчитать</button>
    <button class="btn sec" data-action="openChat">Открыть чат</button>
  </div><div class="foot">Посчитано ${tsDate(R.generated, true)}. Всё считается на телефоне.</div>`;
}
function render() {
  const from = tsDate(R.from, true), to = tsDate(R.to, true);
  document.getElementById('root').innerHTML = `
    <div class="head"><h1>${esc(R.title)}</h1><div class="p">${PERIOD_FOR[R.period] || ''} · ${from} — ${to}</div></div>
    ${tabsHTML()}${body()}${actionsHTML()}`;
}

// ---------- Share card ----------
let shareKind = R.isGroup ? 'me' : 'cmp';
let hideName = false;
function cardHTML(kind, hide) {
  const name = p => p && p.id !== R.meId && hide ? 'Собеседник' : (p ? (p.id === R.meId ? 'Я' : p.name) : '');
  const period = (PERIOD_FOR[R.period] || '').replace('за ', 'итоги: ');
  let h = `<div class="brand">Shadow · ${period}</div>`;
  if (kind === 'cmp' && me && other) {
    const total = Math.max(1, R.total);
    const topEmoji = [...me.emoji, ...other.emoji].sort((a, b) => b.count - a.count).map(e => e.key).filter((v, i, a) => a.indexOf(v) === i).slice(0, 5).join('');
    const aw = [];
    if (me.night !== other.night) { const w = pct(me.night, me.messages) > pct(other.night, other.messages) ? me : other; aw.push('🦉 Ночная сова — ' + esc(name(w))); }
    if (me.replySeconds != null && other.replySeconds != null && me.replySeconds !== other.replySeconds) { const w = me.replySeconds < other.replySeconds ? me : other; aw.push('⚡️ Быстрый ответ — ' + esc(name(w))); }
    let peakH = 0; const hours = Array.from({ length: 24 }, (_, x) => R.heatmap.reduce((a, r) => a + r[x], 0)); hours.forEach((v, i) => { if (v > hours[peakH]) peakH = i; });
    h += `<div class="ttl">Я и ${esc(name(other))}</div>
      <div class="pp">${tsDate(R.from, true)} — ${tsDate(R.to, true)}</div>
      <div class="bign">${fmt(R.total)}</div><div class="bigc">${plural(R.total, 'сообщение', 'сообщения', 'сообщений')} на двоих</div>
      <div class="bal"><div style="width:${pct(me.messages, total)}%;background:#3987e5"></div><div style="flex:1;background:#d95926"></div></div>
      <div class="ball"><span>Я ${pct(me.messages, total)}%</span><span>${esc(name(other))} ${pct(other.messages, total)}%</span></div>
      <div class="sg">
        <div><b>${fmt(R.daysWithMessages)}</b><span>дней из ${fmt(R.daysInPeriod)} на связи</span></div>
        <div><b>${fmt(R.streakBest)}</b><span>дней подряд — рекорд</span></div>
        <div><b>${dur(me.voiceSeconds + other.voiceSeconds)}</b><span>голосовых</span></div>
        <div><b>${HOUR_LABELS[peakH]}</b><span>любимый час</span></div>
        <div><b>${fmt(Math.round(R.total / Math.max(1, R.daysWithMessages)))}</b><span>сообщений в день</span></div>
        <div><b>${R.longestBreak > 0 ? gapText(R.longestBreak) : '—'}</b><span>самый длинный перерыв</span></div>
        <div><b>${fmt(me.stickers + other.stickers)}</b><span>стикеров</span></div>
        <div><b>${fmt(me.calls + other.calls)}</b><span>звонков · ${dur(me.callSeconds + other.callSeconds)}</span></div>
      </div>
      ${R.bestDay ? `<div class="aw">🔥 Самый активный день: ${dayDate(R.bestDay.day, true)} — ${fmt(R.bestDay.count)} сообщ.</div>` : ''}
      ${cardFaces([...me.reactions, ...other.reactions])}
      ${cardFaces([...me.topStickers, ...other.topStickers])}
      ${topEmoji ? `<div class="em">${topEmoji}</div>` : ''}
      ${aw.length ? `<div class="aw">${aw.join(' · ')}</div>` : ''}`;
  } else {
    const p = kind === 'other' ? other : me;
    if (!p) return '';
    const who = name(p);
    h += `<div class="ttl">${esc(who)} в чате${p.id === R.meId && !R.isGroup ? ' с ' + esc(name(other)) : (R.isGroup ? ' «' + esc(R.title) + '»' : '')}</div>
      <div class="pp">${tsDate(R.from, true)} — ${tsDate(R.to, true)}</div>
      <div class="bign">${fmt(p.messages)}</div><div class="bigc">${plural(p.messages, 'сообщение', 'сообщения', 'сообщений')} · ${pct(p.messages, Math.max(1, R.total))}% переписки</div>
      <div class="sg">
        <div><b>${fmt(p.words)}</b><span>слов</span></div>
        <div><b>${dur(p.voiceSeconds)}</b><span>голосовых</span></div>
        <div><b>${pct(p.firstOfDay, R.firstOfDayDays)}%</b><span>дней пишет первым</span></div>
        <div><b>${shortDur(p.replySeconds)}</b><span>обычно отвечает</span></div>
        <div><b>${fmt(p.stickers)}</b><span>стикеров</span></div>
        <div><b>${pct(p.night, p.messages)}%</b><span>ночью</span></div>
      </div>
      ${p.emoji.length ? `<div class="em">${p.emoji.slice(0, 5).map(e => e.key).join('')}</div>` : ''}`;
  }
  h += '<div class="ft"><span>Посчитано в Shadow</span><span>только на телефоне</span></div>';
  return `<div class="share">${h}</div>`;
}
// A row of the top stickers or reactions on the share card (pictures when the
// report has them, else their emoji).
function cardFaces(items) {
  const merged = {};
  items.forEach(i => { merged[i.key] = merged[i.key] ? { key: i.key, label: i.label, count: merged[i.key].count + i.count } : { key: i.key, label: i.label, count: i.count }; });
  const top = Object.values(merged).sort((a, b) => b.count - a.count).slice(0, 5);
  if (!top.length) return '';
  return `<div class="cf">${top.map(i => { const img = R.images && R.images[i.key]; const face = img ? `<img src="${img}" alt="">` : (i.key === 'stars' ? '⭐️' : (i.key.indexOf(':') > 0 ? esc(i.label || '✨') : esc(i.key))); return `<span>${face}<small>${fmt(i.count)}</small></span>`; }).join('')}</div>`;
}

function renderShareSheet() {
  const kinds = R.isGroup ? [['me', 'Только я']] : [['cmp', 'Сравнение'], ['me', 'Только я'], ['other', 'Только ' + esc(other ? other.name : '')]];
  document.getElementById('shareSheet').innerHTML = `
    <h3>Картинка итогов</h3>
    ${kinds.length > 1 ? `<div class="opts">${kinds.map(k => `<div class="opt ${shareKind === k[0] ? 'on' : ''}" data-kind="${k[0]}">${k[1]}</div>`).join('')}</div>` : ''}
    <div class="preview">${cardHTML(shareKind, hideName)}</div>
    ${R.isGroup ? '' : `<div class="swrow">Скрыть имя собеседника <div class="switch ${hideName ? 'on' : ''}" data-action="toggleHide"></div></div>`}
    <div class="actions" style="margin:6px 0 0"><button class="btn" data-action="shareImage">Поделиться</button><button class="btn sec" data-action="closeShare">Отмена</button></div>`;
}
function openShare() { renderShareSheet(); document.getElementById('sheetBack').classList.add('show'); document.getElementById('shareSheet').classList.add('show'); }
function closeShare() { document.getElementById('sheetBack').classList.remove('show'); document.getElementById('shareSheet').classList.remove('show'); }
function post(message) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.shadow) window.webkit.messageHandlers.shadow.postMessage(message);
}

// ---------- Events ----------
document.addEventListener('click', e => {
  const t = e.target.closest('[data-tab]');
  if (t) { tab = t.dataset.tab; render(); window.scrollTo(0, 0); return; }
  const m = e.target.closest('[data-member]');
  if (m) { const id = Number(m.dataset.member); selectedMember = id; tab = id === R.meId ? 'me' : 'member'; render(); window.scrollTo(0, 0); return; }
  const k = e.target.closest('[data-kind]');
  if (k) { shareKind = k.dataset.kind; renderShareSheet(); return; }
  const a = e.target.closest('[data-action]');
  if (!a) return;
  const action = a.dataset.action;
  if (action === 'openShare') openShare();
  else if (action === 'closeShare') closeShare();
  else if (action === 'toggleHide') { hideName = !hideName; renderShareSheet(); }
  else if (action === 'shareImage') { closeShare(); post({ action: 'shareImage', kind: shareKind, hideName: hideName }); }
  else post({ action: action });
});
document.getElementById('sheetBack').addEventListener('click', closeShare);
const tip = document.getElementById('tip');
function showTip(e) {
  const el = e.target.closest ? e.target.closest('[data-tip]') : null;
  document.querySelectorAll('.cross').forEach(c => c.setAttribute('opacity', 0));
  if (!el) { tip.classList.remove('show'); return; }
  tip.textContent = el.dataset.tip;
  tip.classList.add('show');
  const w = tip.offsetWidth;
  tip.style.left = Math.min(window.innerWidth - w - 8, Math.max(8, e.clientX - w / 2)) + 'px';
  tip.style.top = Math.max(4, e.clientY - 40) + 'px';
  if (el.dataset.cross) {
    const cross = el.closest('svg').querySelector('.cross');
    cross.setAttribute('x1', el.dataset.cross); cross.setAttribute('x2', el.dataset.cross); cross.setAttribute('opacity', 1);
  }
}
document.addEventListener('mousemove', showTip);
document.addEventListener('pointerdown', showTip);

if (CONFIG.mode === 'card') {
  document.body.classList.add('cardmode');
  document.getElementById('root').innerHTML = cardHTML(CONFIG.card, CONFIG.hideName);
} else {
  render();
}
</script>
</body>
</html>
"""#
}
