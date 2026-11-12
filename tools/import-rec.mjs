// 讀遊戲內記錄 → tools/rec-report.md。不改路線 md，只列建議。
// 用法：node tools/import-rec.mjs <MetroGuide.lua 存檔 或 /metro rec export 貼出的文字檔>
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const src = process.argv[2];
if (!src) {
  console.error("用法：node tools/import-rec.mjs <WTF\\Account\\<帳號>\\SavedVariables\\MetroGuide.lua 或匯出文字檔>");
  process.exit(1);
}

// Lua 表格常值解析（存檔與 Route.lua 共用）
function parseLua(text, start) {
  let i = start;
  const ws = () => {
    for (;;) {
      while (/\s/.test(text[i])) i++;
      if (text.startsWith("--", i)) { while (i < text.length && text[i] !== "\n") i++; continue; }
      return;
    }
  };
  const str = () => {
    const q = text[i++];
    let out = "";
    while (text[i] !== q) {
      if (text[i] === "\\") {
        const c = text[++i];
        if (/\d/.test(c)) { const m = text.slice(i).match(/^\d{1,3}/)[0]; out += String.fromCharCode(+m); i += m.length; continue; }
        out += { n: "\n", t: "\t", r: "\r", "\n": "\n" }[c] ?? c;
        i++;
        continue;
      }
      out += text[i++];
    }
    i++;
    return out;
  };
  const value = () => {
    ws();
    const c = text[i];
    if (c === "{") return table();
    if (c === '"' || c === "'") return str();
    const m = text.slice(i).match(/^(true|false|nil|-?[\d.]+(?:e[-+]?\d+)?)/i);
    if (!m) throw new Error("看不懂的值，位置 " + i + "：" + text.slice(i, i + 40));
    i += m[0].length;
    return m[0] === "true" ? true : m[0] === "false" ? false : m[0] === "nil" ? null : Number(m[0]);
  };
  const table = () => {
    i++;
    const arr = [], obj = {};
    for (;;) {
      ws();
      if (text[i] === "}") { i++; break; }
      let key;
      if (text[i] === "[") { i++; key = value(); ws(); i++; ws(); i++; }
      else {
        const m = text.slice(i).match(/^([A-Za-z_]\w*)\s*=(?!=)/);
        if (m) { key = m[1]; i += m[0].length; }
      }
      const v = value();
      if (key === undefined) arr.push(v); else obj[key] = v;
      ws();
      if (text[i] === "," || text[i] === ";") i++;
    }
    return Object.keys(obj).length ? Object.assign(obj, arr.length ? { _: arr } : {}) : arr;
  };
  return value();
}
// 字串的 Lua 存檔是 UTF-8 位元組逐一跳脫時，要轉回 UTF-8
const utf8 = (s) => (/[\u0080-ÿ]/.test(s) && !/[Ā-￿]/.test(s) ? Buffer.from(s, "latin1").toString("utf8") : s);

const raw = readFileSync(src, "utf8");
let lines;
const at = raw.indexOf("MetroGuideRecDB");
if (at >= 0) {
  const db = parseLua(raw, raw.indexOf("{", at));
  lines = (db.log || []).map(utf8);
} else {
  lines = raw.split(/\r?\n/).filter((l) => l.includes("\t@\t")).map((l) => l.replace(/\|\|/g, "|"));
}

const routeText = readFileSync(join(ROOT, "addon", "MetroGuide", "Data", "Route.lua"), "utf8");
const route = parseLua(routeText, routeText.indexOf("{", routeText.indexOf("MG.Route")));
const quests = {};
for (const [k, v] of Object.entries(route.quests)) if (k !== "_") quests[k] = v;
const routeSteps = {}; // q → { accept: [step+station], turnin: [...] }
for (const st of [...(route.stations || []), ...(route.dungeons || [])]) {
  for (const s of st.steps || []) {
    if (!s.q || (s.t !== "accept" && s.t !== "turnin")) continue;
    ((routeSteps[s.q] ??= {})[s.t] ??= []).push({ ...s, station: st.id });
  }
}

const rows = lines.map((l) => {
  const [key, rest] = l.split("\t@\t");
  const k = key.split("\t"), r = rest.split("\t");
  return { kind: k[0], k: k.slice(1), ts: +r[0], lv: +r[1], x: r.slice(2) };
});
const by = (kind) => rows.filter((r) => r.kind === kind);

// 來源路徑不寫帳號資料夾名（報告可能被分享）
const shownSrc = src.replace(/([\\/]Account[\\/])[^\\/]+/i, "$1<帳號>");
const out = [`# 遊戲內記錄報告`, ``, `來源：${shownSrc}｜${rows.length} 筆`, ``];
const patches = [];

// 任務：接／交
out.push(`## 任務接交`, ``);
const seenQ = {};
const qRows = [...by("detail"), ...by("accept"), ...by("complete"), ...by("turnin")];
for (const r of qRows) {
  const [id] = r.k;
  const [title, npc, kind, map, x, y] = r.x;
  const t = r.kind === "detail" || r.kind === "accept" ? "accept" : "turnin";
  const e = ((seenQ[id] ??= { id, title: "", accept: [], turnin: [] }));
  if (title) e.title = title;
  if (npc || x) e[t].push({ npc, npcId: r.k[1], kind, map: +map, x: +x, y: +y, src: r.kind });
}
const issues = [];
for (const e of Object.values(seenQ)) {
  const q = quests[e.id];
  if (!q) { issues.push(`- ${e.id} ${e.title}：路線資料沒有這個任務`); continue; }
  if (e.title && q.n && e.title !== q.n) {
    issues.push(`- ${e.id}：名稱 路線「${q.n}」→ 實測「${e.title}」`);
    patches.push(`- 任務 ${e.id} 改名「${q.n}」→「${e.title}」`);
  }
  for (const t of ["accept", "turnin"]) {
    const got = e[t].filter((g) => g.x || g.npc);
    const want = routeSteps[e.id]?.[t] || [];
    if (!got.length || !want.length) continue;
    const g = got[0];
    for (const w of want) {
      const where = `${w.station} ${t === "accept" ? "接" : "交"} ${e.id} ${q.n}`;
      if (g.npc && w.npc && !w.npc.startsWith("物品") && g.npc !== w.npc) {
        issues.push(`- ${where}：NPC 路線「${w.npc}」→ 實測「${g.npc}」（${g.kind || "?"} ${g.npcId}）`);
        patches.push(`- ${where}：NPC 改「${g.npc}」`);
      }
      if (g.x && w.x != null) {
        if (w.map !== g.map) issues.push(`- ${where}：地圖 路線 ${w.map} → 實測 ${g.map}（${g.x}, ${g.y}）`);
        else if (Math.hypot(w.x - g.x, w.y - g.y) > 2) {
          issues.push(`- ${where}：座標 路線 ${w.x}, ${w.y} → 實測 ${g.x}, ${g.y}（差 ${Math.hypot(w.x - g.x, w.y - g.y).toFixed(1)}%）`);
          patches.push(`- ${where}：座標改 ${g.map} ${g.x}, ${g.y}`);
        }
      } else if (g.x && w.x == null) {
        patches.push(`- ${where}：路線沒有座標，實測 ${g.map} ${g.x}, ${g.y}`);
      }
    }
  }
}
out.push(`看到 ${Object.keys(seenQ).length} 個任務，不一致 ${issues.length} 項。`, ``, ...issues, ``);

// 任務經驗：交件事件給的實際經驗 vs 路線
const xpDiff = by("turnin")
  .filter((r) => r.x[6] && quests[r.k[0]]?.xp)
  .map((r) => ({ id: r.k[0], got: +r.x[6], lv: r.lv, want: quests[r.k[0]].xp }))
  .filter((d) => d.got && d.got !== d.want);
if (xpDiff.length) {
  out.push(`## 任務經驗與路線不同`, ``, `（等級高於任務時遊戲會打折，只供參考）`, ``);
  for (const d of xpDiff) out.push(`- ${d.id} ${quests[d.id].n}：路線 ${d.want} → 實得 ${d.got}（${d.lv} 級交）`);
  out.push(``);
}

// 經驗增益：交件時實得÷預期 ≈1.03 的那幾次都有、≈1.00 的都沒有的增益
{
  const hi = [], lo = [];
  for (const r of by("auras")) {
    const ratio = +r.x[0];
    const auras = (r.x[1] || "").split(";").filter(Boolean).map((a) => a.split("#"));
    if (ratio >= 1.02 && ratio <= 1.05) hi.push(auras); else if (ratio >= 0.99 && ratio <= 1.01) lo.push(auras);
  }
  const ids = new Map();
  for (const list of [...hi, ...lo]) for (const [name, id] of list) ids.set(id || name, name);
  const cands = [...ids].map(([key, name]) => ({ key, name,
    inHi: hi.filter((l) => l.some(([n, i]) => (i || n) === key)).length,
    inLo: lo.filter((l) => l.some(([n, i]) => (i || n) === key)).length }))
    .filter((c) => c.inHi > 0).sort((a, b) => (b.inHi - b.inLo) - (a.inHi - a.inLo));
  out.push(`## 經驗增益候選（交件 ≈1.03 有 ${hi.length} 次、≈1.00 有 ${lo.length} 次）`, ``);
  for (const c of cands.slice(0, 10)) out.push(`- ${c.name || "?"}（法術 ${c.key}）：≈1.03 時 ${c.inHi}/${hi.length} 次在身上，≈1.00 時 ${c.inLo}/${lo.length} 次${c.inHi === hi.length && c.inLo === 0 ? "　← 最可能" : ""}`);
  if (!cands.length) out.push("（還沒有資料）");
  out.push(``);
}

// 目標進度位置
const objs = {};
for (const r of by("obj")) {
  const [id, idx] = r.k;
  const [need, text, x, y] = r.x;
  const o = (objs[`${id}#${idx}`] ??= { id, text, need, map: r.k[3], pts: [] });
  if (x) o.pts.push([+x, +y]);
}
out.push(`## 目標推進位置（約略的怪／物件位置）`, ``);
for (const o of Object.values(objs)) {
  if (!o.pts.length) continue;
  const cx = o.pts.reduce((a, p) => a + p[0], 0) / o.pts.length, cy = o.pts.reduce((a, p) => a + p[1], 0) / o.pts.length;
  out.push(`- ${o.id} ${quests[o.id]?.n || ""}｜${o.text}（共 ${o.need}）：地圖 ${o.map} 中心 ${cx.toFixed(1)}, ${cy.toFixed(1)}，${o.pts.length} 點`);
}
out.push(``);

// 經驗表
const xpTable = {};
for (const r of by("xp")) xpTable[r.k[0]] = +r.k[1];
out.push(`## 真實經驗表（升到下一級所需）`, ``, `| 等級 | 經驗 |`, `|---|---|`);
for (const lv of Object.keys(xpTable).sort((a, b) => a - b)) out.push(`| ${lv} | ${xpTable[lv]} |`);
out.push(``);

// 飛行點
out.push(`## 飛行管理員`, ``);
for (const r of by("fp")) out.push(`- ${r.x[0] || r.k[0]}（${r.k[0]}）：地圖 ${r.x[1]} ${r.x[2]}, ${r.x[3]}`);
out.push(``, `## 已知飛行點（依飛行地圖）`, ``);
const known = (s) => s === "0" || s === "1" || s === "CURRENT" || s === "REACHABLE";
const nodes = {};
for (const r of by("taxi")) {
  const [tm, nodeId, name, state] = r.k;
  if (/^zzOLD/.test(name)) continue; // 遊戲裡的舊飛行點資料
  const n = ((nodes[tm] ??= {})[nodeId] ??= { name, known: false, x: r.x[0], y: r.x[1] });
  n.known ||= known(state);
}
for (const [tm, list] of Object.entries(nodes)) {
  out.push(`- 地圖 ${tm}：` + Object.entries(list).map(([id, n]) => `${n.name}${n.known ? "" : "（未開）"} #${id} ${n.x},${n.y}`).join("；"));
}
out.push(``);

// 爐石、副本、事件參數
out.push(`## 爐石綁定`, ``);
for (const r of by("bind")) out.push(`- ${r.k[0]}（${r.k[1] === "bound" ? "綁定時" : "登入時"}）${r.x[0] ? `：地圖 ${r.x[0]} ${r.x[1]}, ${r.x[2]}` : ""}`);
out.push(``, `## 進過的副本`, ``);
for (const r of by("inst")) out.push(`- ${r.x[0]}：instanceID ${r.k[0]}，${r.x[1]}，難度 ${r.x[2]}`);
out.push(``, `## 事件參數形狀`, ``);
for (const r of by("args")) out.push(`- ${r.k[0]}(${r.k[1]})：例 ${r.x[0]}`);
out.push(``, `## 建議修改（不會自動改 route/*.md）`, ``, ...(patches.length ? patches : ["（無）"]), ``);

writeFileSync(join(ROOT, "tools", "rec-report.md"), out.join("\n"));
console.log(`記錄 ${rows.length} 筆；任務 ${Object.keys(seenQ).length}；不一致 ${issues.length}；經驗表 ${Object.keys(xpTable).length} 級；建議 ${patches.length} 項 → tools/rec-report.md`);
