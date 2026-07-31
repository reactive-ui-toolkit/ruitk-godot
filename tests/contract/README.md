# GD ↔ TS grammar contract harness (SYNTAX_PARITY_EXECUTION_PLAN T0.1)

The `.guitkx` grammar is implemented twice — in GDScript for the compiler
(`addons/reactive_ui_toolkit/guitkx/*.gd`) and in TypeScript for the LSP
(`ide-extensions/lsp-server/src/{markup,formatGuitkx,scanner}.ts`). This harness makes that
duplication safe: **the GDScript compiler is the grammar of record**, and every fixture here pins
that both implementations agree on real files.

## How it works

- `fixtures/*.guitkx` — the corpus: every shipped demo (flattened copies, taken from git HEAD) plus
  `t*_…` targeted cases pinning tricky shapes (bare returns, early returns, `#elif`, digit tags,
  unterminated strings, modules, spreads). The directory holds a `.gdignore` so neither the Godot
  editor nor the codegen ever compiles fixtures (several are deliberately broken).
- `golden/*.json` — one per fixture, dumped by the compiler of record:
  `{ ok, diagnostics:[{code,severity,off,len}], windows:[{start,end}], markup:[{error, error_code,
  error_at, tree}] }`. `windows` are the absolute component markup windows (the same walk the LSP's
  `markupWindows()` performs); `markup[i]` is `guitkx_markup.gd`'s AST of `windows[i]` with node
  offsets absolute in the fixture.
- `tests/contract_dump.gd` — regenerates the goldens; `-- --check` re-derives in memory and fails
  on drift (CI runs this in `test.yml`, so a grammar change on the GD side without a regen is red).
- `ide-extensions/lsp-server/src/test/contract.test.ts` — asserts `markupWindows()` +
  `parseMarkup()` reproduce every golden exactly (runs in `test.yml`'s `extensions` job), so
  a grammar change on the TS side without its GD mirror is red too.

## Offsets are Unicode code points

All offsets in goldens (and in the `.diags.json` sidecar) count **Unicode code points** — GDScript
`String` indices. JavaScript indexes UTF-16 code units, which diverge on astral-plane characters
(the emoji in several demos caught this on the harness's first run). The TS side converts at the
boundary via `src/codePoints.ts`; never compare raw JS offsets against golden offsets.

## Pending fixtures (known divergences)

`*.pending.guitkx` marks a divergence we know about and plan to fix (e.g.
`t05_typo_header.pending.guitkx`: the LSP's decl scan recovers a typo'd `component` header and
finds a markup window; the exact-keyword compiler does not). For these the TS test asserts the
divergence **still exists** — when a phase fixes one, the test fails with "now agrees", and the fix
PR renames the fixture (drop `.pending`) and regens. A Phase of SYNTAX_PARITY_EXECUTION_PLAN is not
done while it owns a pending fixture.

## Workflow for any grammar change

1. Change `guitkx_markup.gd`/`guitkx.gd` AND the TS mirror in the same commit.
2. Add a fixture exercising the change (broken inputs welcome — that's the point).
3. Regen: `godot --headless --path . --script res://tests/contract_dump.gd`
4. `cd ide-extensions/lsp-server && npm test` — the contract suite must be green (or the fixture
   is explicitly `.pending`).
