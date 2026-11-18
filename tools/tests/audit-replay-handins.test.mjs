import assert from "node:assert/strict";
import test from "node:test";
import { auditTrace, classify } from "../audit-replay-handins.mjs";

const objective = {
  groups: [[], [], [[5536]], [], [], []], materials: [5536], source: 0,
  starts: [], text: "Retrieve the book.", extra: false,
};
const remaining = new Map([[59, 200], [60, 0]]);
function event(action, id = 1050, level = 59, progress = 0) {
  return ["05-d8", level, progress, action, id, "Quest", "", action === "turned" ? 100 : ""];
}
function trace(events) {
  return auditTrace(events, new Map(), () => objective, remaining);
}

test("work before the acceptance belongs to an earlier lifetime", () => {
  const result = trace([event("worked"), event("accepted"), event("turned")]);
  assert.equal(result.length, 1);
  assert.equal(result[0].accepted, "05-d8");
});

test("a repeated acceptance resets progress; working another ID does not count", () => {
  const result = trace([
    event("accepted"), event("worked"), event("turned"),
    event("accepted"), event("worked", 5848), event("turned"),
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].id, 1050);
});

test("a matching item supplied on acceptance remains distinct from an untraced drop", () => {
  assert.equal(classify({ ...objective, source: 5536 }, [], [], []), "接取配發同一物品，另核數量");
  assert.equal(classify(objective, [], [], []), "單種材料，核實來源與數量");
  assert.equal(classify({ ...objective, source: 5536, materials: [5536, 14679] }, [], [], []), "多種材料，逐物查");
});

test("clamp the actual XP at the cap; preserve the nominal reward in the evidence", () => {
  const result = trace([event("turned", 1050, 59, 170), event("turned", 5848, 60)]);
  assert.deepEqual(result.map(r => [r.nominal, r.xp]), [[100, 30], [100, 0]]);
});
