// T0.3 vocabulary tripwires. The single source of truth for the .guitkx language vocabulary is
// addons/reactive_ui_toolkit/guitkx/vocabulary.json (loaded by guitkx.gd); the LSP ships a copy at
// src/vocabulary.json. These tests keep the copy honest and pin every consumer table to it, so
// HOST_TAGS/hook-list drift between the compiler and the LSP (matrix §5.1 items 2-3's data half)
// is structurally impossible again. The GD-side twin lives in tests/guitkx_test.gd
// (_test_vocabulary: reflection-pins v_factories to core/v.gd's public statics).

import { test } from "node:test";
import * as assert from "node:assert";
import { readFileSync } from "fs";
import { join } from "path";

import { HOST_TAGS, VOCABULARY } from "../schema";
import { HOOK_STUBS } from "../virtualDoc";

const ROOT = join(__dirname, "..", "..", "..", "..");

test("vocabulary.json copy is byte-identical to the canonical addons/ file", () => {
  const canonical = readFileSync(join(ROOT, "addons", "reactive_ui_toolkit", "guitkx", "vocabulary.json"), "utf8").replace(/\r/g, "");
  const shipped = readFileSync(join(__dirname, "..", "..", "src", "vocabulary.json"), "utf8").replace(/\r/g, "");
  assert.strictEqual(shipped, canonical, "sync the copy: cp addons/reactive_ui_toolkit/guitkx/vocabulary.json ide-extensions/lsp-server/src/vocabulary.json");
});

test("schema HOST_TAGS covers every vocabulary tag with the vocabulary's factory (aliases included)", () => {
  const byTag = new Map(HOST_TAGS.map((t) => [t.tag, t]));
  for (const [tag, factory] of Object.entries(VOCABULARY.host_tags)) {
    const info = byTag.get(tag);
    assert.ok(info, `vocabulary tag <${tag}> missing from schema HOST_TAGS`);
    assert.strictEqual(info!.factory, `V.${factory}`, `<${tag}> factory drifted from the vocabulary`);
  }
  for (const t of HOST_TAGS) {
    assert.ok(VOCABULARY.host_tags[t.tag] !== undefined, `schema tag <${t.tag}> is not in vocabulary.json — add it there first`);
  }
});

test("virtualDoc HOOK_STUBS names are exactly the vocabulary hook list", () => {
  assert.deepStrictEqual(
    HOOK_STUBS.map((h) => h.name).sort(),
    [...VOCABULARY.hooks].sort(),
    "hook list drifted between vocabulary.json and virtualDoc HOOK_STUBS",
  );
});

// T3.2/T3.3: the severity table + live-code list are the single source for surface consistency.
// The GD twin (guitkx_test.gd _test_severity_table) regex-pins every compiler D.make() site to it.
test("T3.2: severity table covers the live-code list and pins the reconciled severities", () => {
  const sev = VOCABULARY.severities as Record<string, string>;
  assert.ok(sev && Object.keys(sev).length >= 30, "severities table present");
  for (const c of VOCABULARY.live as string[]) assert.ok(sev[c], `live code ${c} missing a severity`);
  assert.equal(sev["GUITKX0104"], "error"); // duplicate keys break reconciliation
  assert.equal(sev["GUITKX0107"], "hint"); // unreachable = dimmed dead code
  assert.equal(sev["GUITKX2203"], "warning"); // hook naming lint
});
