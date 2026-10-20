// Спільні кейси з Python (tools/ingest/verdict_cases.json) без Deno: node supabase/functions/offer-check/verdict.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { eventsFromHtml, verdict } from "./verdict.ts";

const cases = JSON.parse(readFileSync(new URL("../../../tools/ingest/verdict_cases.json", import.meta.url), "utf8"));
for (const c of cases) {
  const nodes = "html" in c ? eventsFromHtml(c.html) : c.nodes;
  const got = verdict(c.status ?? 200, c.redirected ?? false, nodes, Date.parse(c.expected), c.policy ?? "source", "Europe/Kyiv");
  assert.deepEqual(got, [c.kind, c.detail], c.name);
}
console.log(`verdict: ${cases.length} кейсів OK`);
