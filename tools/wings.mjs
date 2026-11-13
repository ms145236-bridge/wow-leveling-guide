// tools/dungeon-wings.md（Codex 從永恆客戶端 AreaTable／WMOAreaTable 查的各區域名）→ addon/ShengLeveling/Data/Wings.lua
// 多區共用同一個副本編號時，用遊戲回傳的區域名（GetSubZoneText／GetMinimapZoneText）判斷在哪一區
import { readFileSync, writeFileSync } from "node:fs";
const rows = readFileSync(new URL("./dungeon-wings.md", import.meta.url), "utf8").split(/\r?\n/).filter((l) => /^05-d\d+｜/.test(l));
const W = {};
for (const l of rows) {
  const [id, , , , loc, names] = l.split("｜");
  const list = (names || "").split(";").map((s) => s.trim()).filter((s) => s && !/[?？]|查無|待/.test(s));
  if (!list.length) continue;
  const t = ((W[id] ||= {})[loc] ||= []);
  for (const n of list) if (!t.includes(n)) t.push(n);
}
const q = (s) => JSON.stringify(s); // 名稱只有一般文字，JSON 字串跟 Lua 字串相容
let out = "-- 由 tools/wings.mjs 產生，勿手改。來源：tools/dungeon-wings.md\nlocal _, MG = ...\nMG.Wings = {\n";
for (const id of Object.keys(W).sort()) {
  out += `  [${q(id)}] = {\n`;
  for (const loc of Object.keys(W[id]).sort()) out += `    ${loc} = { ${W[id][loc].map(q).join(", ")} },\n`;
  out += "  },\n";
}
out += "}\n";
writeFileSync(new URL("../addon/ShengLeveling/Data/Wings.lua", import.meta.url), out);
console.log("wings", Object.keys(W).length);
