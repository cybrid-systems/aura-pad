# Aura vs Rust for a next-generation (AI-era) editor

What Aura offers an AI-era editor that Rust does not, what Rust does
better, and which aura-pad features build on the parts only Aura has.
Every Aura claim below was checked against the source at Aura tip
`c69e644` and, where a small probe was practical, run on the Soft binary
(`/workspace/aura-grok/build/aura`, `ghcr.io/cybrid-systems/dev:v1.0.9`,
`AURA_SANDBOX=off`). Measured negatives stay in the doc. Related pages:
[`perf.md`](perf.md), [`perf-aura.md`](perf-aura.md),
[`perf-emacs.md`](perf-emacs.md), [`DESIGN.md`](DESIGN.md).

**Re-check on `18b48dc` (2026-10-07).** Every aura-pad issue #4343–#4370
was re-run (`docs/ISSUES.md`). Changed claims:
- Child workspaces are now isolated and removable (#4368 / #4369):
  switch + conflicts-with + `workspace:delete`, no heal.
- A saved book reopens with authors and remapped node ids (#4365 /
  #4367), so who-wrote-what after an open comes from the engine.
- `char-ready?` exists (#4358), and fibers no longer corrupt `read-line`
  (#4356). A fiber still does not run while main waits in `read-line`.
- `mutate:atomic-batch` gates now (#4362, deprecated). The default soft
  gate commits caller arity mismatches, so hard mode stays required.
- Still true: the per-call cost (#4350) and `vector-set!` scaling (worse,
  R1); no relower gain at editor scale (#4357). New: a plain
  `ast:snapshot` invalidates workspace closures (R5), and workspace
  `#t` / `#f` evaluate to `1` / `0` (R6). Under the hard gate a rebind
  leaves callers with `invalid closure`, and an uncaught one re-runs the
  entry file (R7). The faster main
  `e7b236d` / `0ba8690` breaks captured `set!` (R4).

## 中文摘要

**一句话：Aura 不是更快的 Rust。下一代编辑器真正需要、而 Rust 生态
没有现成的，是“程序本身是活的、可查询、可事务修改、可追责的 AST”。
按键速度上 Rust 全面胜出。**

在 `c69e644` 上逐项实测（探针在 `out/aura-vs-rust/`，不入库）：

- **Aura 独有（Rust 没有现成对应物）：**
  - **活代码 AST。** 编辑器/笔记本的代码就是运行中的工作区 AST。
    `query:code` / `query:defines` / `query:node-types` /
    `define-lookup` 能直接查它，`mutate:rebind` 能热改它，改完调用方
    立刻看到新行为（p02：`left` → `right`）。
  - **事务式改代码。** `mutate:atomic-batch` 中途失败就整批回滚，
    源码回到批前（p03）。
  - **类型门卫。** 默认 Soft 门只拒绝参数个数错误；
    `AURA_MUTATE_TYPE_GATE=hard` 时，带类型错误的 AI 改动会被拒绝并
    回滚，同时给出 blame 文本，调用方不受影响（p08）。
  - **按节点溯源。** `mutate:set-agent-fingerprint` 之后，
    `query:mutations-since` / `query:node-provenance` 能说出每次改动
    是谁做的（孩子 = 1，助手 = 42）、做了什么（p04）。
  - **改动日志可持久化。** `serialize-workspace` 把代码和改动日志一起
    存下来（带 CRC），打开就是恢复（p05）。

  Rust 能做出类似效果，但每一项都要自己搭：git 检查点、salsa、
  wasm 插件、自定义撤销栈。
- **Aura 更省事（Rust 能做，但要多写很多）：**
  - 编辑器、配置、插件、用户程序同一种语言，可热换
    （`std/hot-strategy` 的 swap!/heal!）；
  - 快照 / 时间旅行（`ast:snapshot`/`ast:restore`/`ast:diff`）；
  - 工作区分支（`workspace :create/:switch/:merge`）；
  - 内建的 `intend` 提议—验证—修复循环；
  - 观测面（`engine:metrics`、`query:*`、`primitive:describe`
    能力探测）。
- **Rust 更好：**
  - **原始延迟。** 同一 pty 下 vim 每键 0.35 ms、Emacs 0.7 ms，
    pad 4.0 ms。
  - **算力。** Soft 解释循环每次迭代约 13 µs（p09）；
    `mutate:rebind` 2 个 define 时 17 ms，60 个 define 时 39–50 ms；
    `set-code` 60 个 define 要 247 ms。
  - **并行。** CLI 的 fiber 是 OS 线程：整数循环没有任何加速（p09），
    和 `read-line` 赛跑还会破坏堆（#4356）；也没有 stdin 轮询（#4358）。
  - **生态。** tree-sitter、LSP、GPU 渲染（Zed GPUI）。
  - **AI 代码隔离。** WASM 插件可以按实例做能力隔离。Aura 的沙箱是
    整个进程、单向的：开了就关不掉，`read-file` / `write-file` 也一起
    被禁。`with-capability` 只是词法标签，不是授权。
    `query:effects` 返回的是定义/使用/调用者三元组，不做副作用分析。
  - **静态保证。** 借用检查器。Aura 的 `define-linear` /
    `m4-borrow` / `m4-move` 在 Soft 上只是恒等桩。
- **语义增量 relower / dirty cascade：** `query:dirty-nodes` 能报出
  脏节点，但 `compile:relower-strategy` 是 `none`，工作区代码和文件
  代码一样快（#4357）。做分析，salsa/rust-analyzer 更成熟、更快；
  Aura 的不同只在于“脏集合属于正在运行的程序，而且白送”。
- **工作区分支 merge** 只是源码拼接，会出现重复 define。
- **本轮新提的 Soft bug：**
  - [#4359](https://github.com/cybrid-systems/aura/issues/4359)：
    调用 `eval` 出来的闭包会卡死或 SIGABRT；
  - [#4360](https://github.com/cybrid-systems/aura/issues/4360)：
    `mutate:rebind` 新名字时返回 `#t`，但新 define 不可见、也调不到；
  - [#4361](https://github.com/cybrid-systems/aura/issues/4361)：
    批量事务失败回滚后，所有 define 报 stale node，要再跑一次
    `eval-current`（#4349 的兄弟问题）。

给 aura-pad 的排序建议：

1. AI 提议 = 一个带类型门卫的引擎事务；
2. 引擎级“谁写的”；
3. 孩子能看懂的“为什么坏了”；
4. 时间机器 + 打开即恢复；
5. 分支沙盒世界；
6. 孩子现场改编辑器规则；
7. KEEP 之前先看“影响范围”；
8. `intend` 自修复循环。

1–4、7 今天就能做。5 要绕开 merge。6 受 #4355 和改动成本限制。
8 受 #4359 限制。

## Method

- Aura source: `/workspace/aura-grok` at `c69e644`. Function names and
  files are cited as `file:line` where it helps.
- Probes: `out/aura-vs-rust/p01…p10*.aura` with their `.out` next to
  them. Bug repros are in `out/aura-vs-rust/bug_*`. `out/` is
  git-ignored, so the probes are not committed. The outputs quoted here
  are copied from the `.out` files. Probes were run with
  `scripts/run_soft.sh`, or with `out/aura-vs-rust/run.sh`, which is
  the same container plus a hard timeout, a named container, and an
  `EXTRA` env hook (used only for `AURA_MUTATE_TYPE_GATE=hard`).
- `p01` asked `primitive:describe` about 95 names (83 registered).
  A registered name gives a meta record; an unknown name gives `()`.
  Registration is not the same as being callable. Some names (`query:ref-counts`,
  `query:incremental-relower-stats`) are reachable only through other
  faces (`std/query`, `engine:metrics`), so every claim below rests on
  a call, not on describe alone.
- Verdicts:
  - **Aura-unique**: no off-the-shelf Rust equivalent; you would build
    the mechanism yourself.
  - **Aura-easier**: Rust can do it with existing crates, but Aura has
    it built into one runtime.
  - **Rust-equivalent**: about the same.
  - **Rust-better**: Rust wins.

## Part 1: capability by capability

### 1. The editor's own code is a live, queryable, mutable AST

- **What it is.**
  - `set-code` + `eval-current` turn source into the *workspace*
    FlatAST. The program runs from that AST.
  - Read faces: `query:code` (canonical source), `query:defines`,
    `query:node-types`, `query:calls name`, `(query :def-use name)`,
    and `define-lookup`.
  - `mutate:rebind name body why` swaps a define, and its callers see
    the new body. Source: `add_mutate("mutate:rebind" …)` at
    `src/compiler/evaluator_primitives_mutate.cpp:3451`, plus
    `evaluator_primitives_query_workspace.cpp` and
    `evaluator_primitives_query_defuse.cpp`.
- **Verified on c69e644 (`p02_live_editor`).** A two-define keymap
  (`key->cmd`, `pad-handle`):
  - `CALL0 left`
  - `CODE (begin (define key->cmd …) …)`
  - `NODE_TYPES ((MacroDef . 2) (Set . 1) … (Call . 4) …)`
  - `REBIND #t`, `REBIND_MS 17`, then `CALL1 right`
  - `DIRTY (8 14)`, and `MUTS_SINCE0 (id=1 target=8 op=rebind sum=kid: swap arrows …)`

  The new source shows up in `query:code`.
- **What a next-gen editor gets.** Editor behaviour (keymaps, laws,
  helpers, highlighter rules) can live as data the engine understands:
  - a kid or an AI can ask "what calls this rule?" and get an AST answer;
  - the rule can be changed while the editor runs;
  - the change is logged, can be rolled back (§3, §7), and has an
    author (§8).
- **Caveats on the tip.**
  - A rebind costs 17 ms with 2 defines and **39–50 ms with 60 defines**
    (`p07_cost`); perf-aura measured 12–19 ms.
  - `set-code` of 60 defines takes 247 ms.
  - aura-pad's own key path is *not* in the workspace: `set-code`
    replaces it and can invalidate earlier closures (#4355). Today only
    the kid's notebook and the hot slots live there.
  - So "live editor AST" means live for *rules and notebooks*, changed
    at human speed. It does not happen per keystroke.
  - `mutate:rebind` on a *new* name returns `#t` but the define never
    becomes visible (filed as
    [#4360](https://github.com/cybrid-systems/aura/issues/4360)).
- **Closest Rust.**
  - Rust editors (Zed, Helix, Lapce) are compiled. Live behaviour comes
    through a plugin boundary: Zed's WebAssembly extensions behind a
    fixed WIT API, Lapce's WASI plugins, and Helix's Steel Scheme plugin
    branch (PR #8675, still a draft as of Sept 2026).
  - `subsecond` (Dioxus) hot-patches Rust functions through a jump
    table. It is a dev-time tool, tracks only the tip crate, needs the
    CLI to rebuild patches, and `apply_patch` is `unsafe`.
  - None of these lets the running editor *query its own code as an
    AST* and rebind a function with a mutation log.
  - Emacs Lisp is the honest precedent for "the editor is live code".
- **Verdict: Aura-unique** (live AST + query + rebind + log in one
  runtime). Elisp has the "live" part, not the rest. Rust is better at
  what it compiles.

### 2. Engine-level incremental relower + dirty cascade (semantics, not just syntax)

- **What it is.**
  - Dirty propagation over the program's def-use graph
    (`src/compiler/dirty_propagation.ixx`, `service_dirty.cpp`).
  - Per-define relower strategy (`compile:relower-strategy`).
  - Counters behind `engine:metrics` (`"query:incremental-relower-stats"`,
    `"query:dirty-cascade-stats"`, `"query:soa-dirty-stats"`).
  - `query:dirty-nodes reason` / `query:dirty-subtree id` /
    `query:dirty-impact`.
- **Verified.**
  - `p02`: `DIRTY (8 14)` after one rebind; `STRATEGY0 none`,
    `STRATEGY1 none`.
  - `p05`: the metrics hashes have 285 / 28 / 214 keys.
  - perf-aura and #4357: workspace code runs at file speed (230 vs
    258 ms for 3000 calls). Relower never specialises.
  - M10 already checks that `query:dirty-nodes` rows ⊆ Soft DIRTY ∪
    cursor row.
- **What a next-gen editor gets.** After an AI edit, the engine names
  the program nodes whose *meaning* is now stale, for free. The editor
  can recheck, re-test or re-explain only those, and can tell a kid
  "your change touched these two places".
- **Closest Rust.**
  - salsa / rust-analyzer: red-green memoized queries over a language's
    semantics. Mature, fast, and far ahead in analysis depth.
  - tree-sitter: incremental *syntax* only.
  - Both analyse source; neither tracks a *running* program.
- **Verdict: Rust-equivalent for analysis (salsa is better and
  faster), Rust-better for performance.** The Aura-specific part is
  narrow: the dirty set belongs to the live program the editor is
  running, and it costs no extra code. No speedup on the tip (#4357).

### 3. MutationBoundary: transactional edits with abort/rollback

- **What it is.**
  - `Evaluator::MutationBoundaryGuard` (`src/compiler/evaluator.ixx:15774`,
    body in `evaluator_mutation_boundary.cpp`): RAII boundary,
    generation restamp on success, rollback on abort. It also
    snapshots a panic checkpoint and enforces a hold budget
    (`mutation_hold_budget.h`, 100 ms default).
  - Soft faces:
    - `mutate:atomic-batch` / `(mutate :atomic …)`: all-or-nothing
      under one guard (`evaluator_primitives_mutate.cpp` ~5745);
    - `typed-mutate-atomic` (line 6336);
    - `ws:try-mutation expr` (`evaluator_primitives_workspace.cpp:1119`);
    - `mutate:boundary-safe?` / `mutate:boundary-depth`.
  - "mutation-hold / steal" are internal mechanisms. No Soft name
    `mutation-hold` / `mutation-steal` is bound (`p01`).
- **Verified (`p03_txn`).**
  - A batch whose second op fails gives
    `(batch-failed … batch rolled back to pre-batch state . 0)`, and
    `CODE_AFTER_BAD` is the original source.
  - A good batch commits (`(pipe 1)`: 4 → 33).
  - `typed-mutate-atomic` with a broken second sexpr returns `#f`, and
    the source is unchanged.
  - `ws:try-mutation` with a raising body returns `#f`.
  - **But** after a failed batch or try, every workspace define throws
    `stale node id (gen mismatch)` until `eval-current` (filed as
    [#4361](https://github.com/cybrid-systems/aura/issues/4361),
    sibling of #4349).
- **What a next-gen editor gets.** An AI's multi-step code change is
  one unit. Either all of it lands, or none does, and the log records
  `rolled-back`. That is the right primitive for "the robot tried
  something".
- **Closest Rust.**
  - Nothing at the language/runtime level for *live code*.
  - Editors do it for text: undo groups, Zed agent "Restore Checkpoint"
    (git-based, so unavailable outside a git repo; zed#61951).
  - Persistent data (`im`, `rpds`) gives cheap state snapshots inside
    your own program.
- **Verdict: Aura-unique** (a transaction over running code plus its
  bindings). Gap: you need `eval-current` after a failed batch (#4361).

### 4. Typed mutation gate

- **What it is.** After a mutate, a selective typecheck either passes
  the edit or rolls it back (`finish_mutate_hard_gate`,
  `src/compiler/mutate_type_gate.hh`).
  - **Soft mode** (the default with `AURA_SANDBOX=off`) only *observes*
    TypeErrors but still rejects arity mismatches.
  - **Hard mode** (`AURA_MUTATE_TYPE_GATE=hard`, the production default)
    rejects TypeErrors.
  - Also available: `typecheck-current`, `typecheck-incremental`,
    `query-type-of`.
- **Verified (`p08_typegate`, `p08b`).**
  - Soft mode: the AI typo `(string-append x 1)` gives `RB_STR #t`
    (accepted). The arity error `(add1 1 2 3)` gives
    `mutation rejected: … arity mismatch`.
  - Hard mode: the same typo gives
    `mutation rejected: … type error: argument 1: expected String, got Int … blamed: caller`.
    The source stays the old one, and `USE_AFTER_TYPE_REJECT 3`
    (callers still work).
  - Calling a number, `(5 2)`, passes both modes (gradual typing).
  - `p05`: `typecheck-incremental` after a rebind gives
    `re-inferred: 1` plus a diagnostic, in 7–11 ms on 60 defines.
- **What a next-gen editor gets.** AI edits that do not type-check
  never reach the running program. The rejection carries a
  machine-readable reason that a kid-facing layer can translate.
- **Closest Rust.**
  - rustc's type system is far stronger, but it guards *compile time*.
  - rust-analyzer shows diagnostics but cannot refuse a change into a
    running process.
- **Verdict: Aura-unique for live programs. Rust-better for static
  guarantees in general.** The pad's runner does not set
  `AURA_MUTATE_TYPE_GATE` today, so it gets the Soft gate.

### 5. Worldlines: Propose / race / KEEP / DROP

- **What it is.** Not an engine primitive. Worldlines are an
  **aura-pad pattern** built on engine pieces:
  - `soft/pad/rules.aura` (`pad:race-thunks!`, `pad:decide!`,
    `pad:stamp-world!`);
  - `pack.aura` / `helper.aura` / `macro.aura` / `goal.aura` (Propose →
    gate → probe → race → KEEP | `heal!` + DROP);
  - `pen.aura` (M9 rebind at boundaries).

  The engine pieces are:
  - `fiber:spawn` / `fiber:join`;
  - `ast:snapshot` / `ast:restore`;
  - `std/hot-strategy`;
  - `intend goal gen verify [fix] [max]`: an engine propose/verify/fix
    loop with a timeline (`evaluator_primitives_agent.cpp:1615`,
    `intend-history`);
  - the workspace tree (`workspace :create/:switch/:merge/:list`,
    `workspace:conflicts-with`, `workspace:merge-3way`,
    `evaluator_primitives_workspace.cpp`).
- **Verified.**
  - `p09` race: `BACKEND 2` (OS threads), `SEQ_MS 8080` vs
    `FIBER_MS 8059`. There was **no parallel speedup** on a pure
    integer loop. perf-aura measured 1.7× on allocation-heavy work.
    `bold KEEP gentle DROP`.
  - `p05c` / `p05e`: `intend` gives `#(status:"ok" … iterations:1)` and
    a timeline. A verifier that keeps failing gives `status:"failed"`
    after 3 attempts with `last-error`. A verifier that `eval`s the
    generated code hangs (filed as
    [#4359](https://github.com/cybrid-systems/aura/issues/4359)).
  - `p04`: a child workspace takes its own `set-code`, and switching
    back shows the root unchanged. `workspace:conflicts-with` gives
    `(greet)`.
  - `workspace :merge` **concatenates source**: the root ends up with
    two `greet` defines.
- **What a next-gen editor gets.** "AI proposes, the editor races it
  against what you have on the same goal, keeps it only if it is
  strictly better, with evidence and a one-key undo". The whole loop
  runs inside one runtime that can also roll the code back.
- **Closest Rust.**
  - `tokio` / `rayon` race candidates trivially, and really in parallel.
  - git worktrees or branches give isolated worlds.
  - Zed's agent panel has accept/reject per hunk.
  - What Rust lacks is the same-runtime rollback of the *program* that
    lost.
- **Verdict: Aura-easier** (all the pieces exist and compose). Not
  unique as a pattern. Rust-better for actual parallel speed. Don't
  use `workspace :merge` for KEEP; rebind the winner instead.

### 6. Hot-strategy swap

- **What it is.** `lib/std/hot-strategy.aura`: `register!`,
  `snapshot!`, `swap!` (snapshot → `mutate:rebind` → `eval-current`;
  only exact `#t` counts as success after #4275), `heal!` (restore the
  last good one), `call`. aura-pad uses it for slots `pd:law`,
  `pd:helper`, `pd:macro` and `pd:goal` (M1–M8). `hot-swap:fn` exists
  but returns `#f` on the CLI (it needs a CompilerService callback, `p05`).
- **What a next-gen editor gets.** Behaviour packs (keymaps, scoring
  laws, helpers) can be swapped while the editor runs, with a gate and
  automatic heal.
- **Closest Rust.** Reloading a WASM module (Zed extensions),
  `libloading` dlopen, or `subsecond`. All work. None comes with a
  gate, heal and log out of the box.
- **Verdict: Aura-easier.** Cost on the tip: one rebind, 12–50 ms.

### 7. Time travel: snapshot / restore / diff / mutation log / persist

- **What it is.**
  - `ast:snapshot`, `ast:restore`, `ast:diff`
    (`evaluator_primitives_ast.cpp:646`: a line diff of the workspace
    *canonical source* against a snapshot).
  - `workspace:snapshot` / `workspace:rollback-to`.
  - `query:mutations-since n` / `mutation-log:summary`.
  - `serialize-workspace` / `deserialize-workspace` /
    `workspace-persist-info` (`std/persist`).
- **Verified.**
  - `p03`: `ast:diff` gives `((:removed . <old program>) (:added . <new program>))`.
    The canonical source is one line, so the diff covers the whole
    program, not a single define.
  - `p03`: restore + `eval-current` brings back the snapshot's
    behaviour (`-991 → 24`).
  - `p07`: snapshot 3 ms; restore + `eval-current` 24–34 ms on
    60 defines.
  - `p05`: persist round trip gives `PERSIST_INFO (… mutation-count . 2 … crc-ok . 1 … schema . 1381)`,
    and the reload brings back the saved code.
  - Restore does not restore the env. You need `eval-current` after
    any restore that crosses a mutation (#4349, documented-error fix on
    Aura `main`).
- **What a next-gen editor gets.** A time machine over *code plus its
  edit history*, persisted together, so "open is restore" (M12) comes
  from one primitive.
- **Closest Rust.**
  - `im` / `rpds` / `ropey` give O(1)-ish snapshots of buffers or
    state, much faster than 24–34 ms.
  - xi-editor (archived) and Zed have CRDT text histories.
  - Zed checkpoints are git-based.
- **Verdict: Rust-equivalent (and faster) for buffer undo.
  Aura-unique for program-and-log time travel** persisted as one file.

### 8. Provenance: who wrote this

- **What it is.**
  - `mutate:set-agent-fingerprint n`
    (`evaluator_primitives_mutate.cpp:1331`; an identity write needs
    TenantAdmin in production, and is ungated with the sandbox off)
    stamps every later mutation.
  - Read faces:
    - `query:mutations-since` (one line per mutation:
      `author=… sum=…`);
    - `query:last-mutation-provenance` (hash, schema 1914);
    - `query:node-provenance node` (author, mutation id, fiber,
      generation).
  - `reflect:provenance-blame` covers macro-introduced nodes only.
  - `syntax:set-provenance` / `syntax:get-provenance` are bound.
- **Verified (`p04`).** Kid fingerprint 1 rebinds `greet`, AI
  fingerprint 42 rebinds `story`:
  - `MUTS (… sum=kid typed hello author=1 … sum=helper: closer to goal author=42 …)`;
  - `NODEPROV (… author-fingerprint . 42 … gen . 3 …)`;
  - `BLAME ()` (not a macro node).
- **What a next-gen editor gets.** Engine-checked authorship for every
  code change: kid, helper, macro or law, plus the reason text. You can
  ask it per define node, and it is saved with the workspace.
  aura-pad M10 keeps its *own* Soft row stamps and does not use
  fingerprints yet.
- **Closest Rust.** `git blame` (per commit, per line, after the fact)
  and CRDT replica ids in collaborative editors. Per-AST-node live
  authorship you build yourself.
- **Verdict: Aura-unique** (built in, per node, live). Limits: the
  fingerprint is an integer label, not a principal (source comment
  #4037), and the granularity is the define node.

### 9. Structural (AST-native) editing

- **What it is.**
  - `(mutate :replace target :pattern|:subtree|:value|:type …)`,
    `:move`, `:extract` (extract-function lifts free variables into
    parameters).
  - `mutate:replace-pattern old new`, `query:pattern`, `query:where`.
  - `query:stable-ref` / `query:ref-valid?`.
- **Verified (`p06`).**
  - `mutate:replace-pattern "(* 2 x)" "(+ x x)"` rewrote `twice`, and
    `(main)` still returns 34.
  - A `query:stable-ref` to `main`, taken before the edit, reports
    `valid #f` afterwards even though `main` was not touched. On Soft,
    validity is generation-based, so refs do not survive unrelated
    edits.
- **What a next-gen editor gets.** Refactors as program operations
  ("rename / extract / rewrite everywhere"), applied in a transaction
  to running code.
- **Closest Rust.**
  - rust-analyzer's structural search-and-replace (SSR) and assists.
  - tree-sitter queries plus paredit-style edits, e.g. `paredit.hx` on
    Helix/Steel.
  - Multi-language, mature and fast.
- **Verdict: Rust-equivalent** (Rust tooling is broader). The Aura
  edge is the transaction-plus-live part, not the tree editing. Stable
  anchors (bookmarks, comment threads) do not survive edits on Soft.
- aura-pad's buffer is char-code lists on purpose (a kid types text).
  Structure only enters at a notebook check (M9).

### 10. One language for editor, config, plugins and user programs

- **What it is.** aura-pad's logic, keymap, rules, AI-proposed lambdas
  and the kid's notebook are all Soft, and C only blits (DESIGN §1).
  Proposals arrive as Soft text, go through the gate, and are
  hot-swapped (§5–6).
- **What a next-gen editor gets.** No compile cycle and no plugin ABI.
  An AI's proposal is code in the same language and runtime as the
  editor, so it can be gated, typed, raced and rolled back with the
  same tools.
- **Closest Rust.** A Rust core plus TOML config plus WASM, Steel or
  Lua plugins: three or four languages with a serialization boundary
  between them. Emacs (Elisp) is the 40-year precedent for one
  language, and it has no transactions, typed gate or provenance.
- **Verdict: Aura-easier.** Not unique in itself (Elisp), but unique
  in combination with §3, §4 and §8.

### 11. Observability query surfaces

- **What it is.**
  - `engine:metrics "<face>"` (hashes with hundreds of counters).
  - `mutation-log:summary`, `mutate:summary`,
    `mutate:safety-snapshot`, `query:mutation-impact`,
    `query:dirty-impact`, `workspace-state`.
  - `primitive:describe` for capability detection. The pad already
    switches paths on `char-ready?` / relower strategy with it (#4357,
    #4358).
- **Verified.** `p01` (95 names, 83 registered), `p02` (`LOGSUM`,
  `LASTPROV`), `p05` (metric key counts), and perf-aura's `aura_facts.aura`.
- **What a next-gen editor gets.** An AI agent can introspect the
  editor's engine state with plain calls, and features can be gated on
  what the engine actually supports.
- **Closest Rust.** The `tracing` crate, `tokio-console`, custom
  metrics: as good as you build them.
- **Verdict: Aura-easier.**

### 12. Safety for AI-generated code

- **What it is.**
  - `capability?` / `check-capability` / `with-capability` / `capability-stack`
    (`evaluator_primitives_policy.cpp:148–240`).
  - `security:set-sandbox-mode!`, `security:set-effect-sandbox-mode! 0|1|2`,
    `security:check-effect` (`evaluator_primitives_security.cpp`).
  - `resource:quota-check` / `resource:quota-set`.
- **Verified (`p05b`).**
  - With the sandbox off, `capability? "fs"` and `"net"` are `#t`.
  - `with-capability "kid-pen"` makes `check-capability` `#t` inside
    only. It is a lexical label, *not* a grant (source comment #4058).
  - `security:set-sandbox-mode! #t`, then:
    - `read-file` gives `capability denied: io-read required`;
    - `write-file` gives `effect-denied: exec not granted`;
    - `getenv` still works;
    - `mutate:rebind` still works.
  - Turning the sandbox off again gives
    `explicit TenantAdmin required while sandboxed`. The sandbox is
    **one-way and process-wide**, so an editor that turns it on for AI
    code loses its own file I/O.
  - `query:effects name` returns `(defs uses callers)` node lists
    (`evaluator_defuse_index.cpp:928`). It is **not** a side-effect
    analysis.
  - `eval` of generated code is unsafe on the tip in a different way:
    the closures it returns hang or abort when called
    ([#4359](https://github.com/cybrid-systems/aura/issues/4359)).
- **What a next-gen editor gets today.** The strongest guards are the
  aura-pad word-list gate, the typed gate (§4) and transactions with
  rollback (§3). Effect isolation scoped to "just this AI proposal"
  does not exist on the CLI.
- **Closest Rust.** wasmtime/WASI: per-instance capabilities, fuel and
  epoch interruption, memory limits. Zed extensions run this way. That
  is real isolation *per plugin*.
- **Verdict: Rust-better** for isolating untrusted code. Aura is
  better at *checking and undoing* what the code did to the program.

### 13. Linear types / ownership

- **What it is.** The compiler lowers linear-type nodes (`Linear`,
  `Move`, `Borrow`, `MutBorrow`, `Drop` in
  `src/compiler/lowering_linear_types.ixx`). The Soft faces are stubs:
  `primitive:describe` says `define-linear`: "Define a linear binding
  (M4 stub)", and `m4-borrow` / `m4-move`: "M4 linear … stub
  (identity)" (`p01`).
- **Verdict: Rust-better.** The borrow checker is real and Aura's Soft
  surface is not.

### 14. Summary table

| capability | Aura faces (verified) | status on c69e644 | closest Rust | verdict |
|---|---|---|---|---|
| live, queryable, mutable code AST | `set-code`, `eval-current`, `query:code/defines/node-types/calls`, `define-lookup`, `mutate:rebind` | works; rebind 17–50 ms; add path broken (#4360) | WASM / Steel plugins, `subsecond` | **Aura-unique** |
| semantic dirty sets | `query:dirty-nodes/subtree/impact`, `engine:metrics` | reports nodes; relower `:none`, no speedup (#4357) | salsa / rust-analyzer | Rust-equivalent / Rust-better (perf) |
| transactional code edits | `mutate:atomic-batch`, `typed-mutate-atomic`, `ws:try-mutation` | rollback works; callers stale after a failed batch (#4361) | git checkpoints, undo groups | **Aura-unique** |
| typed mutation gate | selective typecheck in the mutate boundary, `AURA_MUTATE_TYPE_GATE=hard`, `typecheck-incremental` | arity always; types in hard mode; blame text | rustc (compile time only) | **Aura-unique** (live) |
| worldlines (Propose / race / KEEP / DROP) | pad pattern + `fiber:*`, `ast:snapshot`, `intend`, `workspace :create` | works; fibers no speedup on pure loops; merge concatenates | tokio / rayon + git | Aura-easier |
| hot-strategy swap | `std/hot-strategy` | works (one rebind each) | WASM reload, `subsecond` | Aura-easier |
| time travel + persist | `ast:snapshot/restore/diff`, `query:mutations-since`, `serialize-workspace` | works; restore needs `eval-current` | `im` / `rpds` / `ropey`, CRDT, git | Rust-equivalent (buffers) / **Aura-unique** (code + log) |
| provenance | `mutate:set-agent-fingerprint`, `query:node-provenance`, `query:mutations-since` | works per mutation / node | git blame, CRDT ids | **Aura-unique** |
| structural editing | `mutate :replace/:move/:extract`, `mutate:replace-pattern`, `query:pattern` | pattern rewrite works; stable refs die on any edit | rust-analyzer SSR, tree-sitter | Rust-equivalent |
| one language | Soft everywhere | yes | Rust + TOML + WASM / Lua | Aura-easier |
| observability | `engine:metrics`, `query:*`, `primitive:describe` | rich | `tracing`, `tokio-console` | Aura-easier |
| AI code isolation | `capability?`, sandbox modes | sandbox one-way, process-wide; `with-capability` not a grant | wasmtime / WASI per instance | **Rust-better** |
| ownership / linear | `define-linear`, `m4-*` | identity stubs | borrow checker | **Rust-better** |

## Part 2: where Rust wins (candidly)

**Keystroke latency.** Same pty harness, same 12-row file, ms per key,
from [`perf.md`](perf.md) (`out/bench/editors_aura.txt`, two runs):

| key | aura-pad | aura-pad `PAD_DEFER=1` first / done | vim | emacs -nw |
|---|---|---|---|---|
| insert | 4.0 / 4.1 | 3.9 / 4.0 | 0.39 / 0.35 | 0.69 / 0.71 |
| cursor | 1.75 / 1.83 | 1.81 / 1.78 | 0.31 / 0.23 | 0.67 / 0.66 |
| string open | 5.5 / 5.5 | 3.8 / 3.5, done 5.7 / 5.5 | 0.33 / 0.45 | 1.06 / 0.89 |
| string close | 5.8 / 5.4 | 4.0 / 4.1, done 6.1 / 5.9 | 0.33 / 0.32 | 0.62 / 0.50 |

A Rust editor sits at or below the vim row. Zed targets 120 fps
GPU-rendered frames (GPUI). The pad is a 4 ms terminal editor: under one
60 fps frame, and 3–17× slower than vim/Emacs.

**Compute and engine costs on the tip** (all measured):
- One Soft call costs ~0.26 ms in the pad (#4350).
- A named-let loop step costs ~13 µs (`p09`: 600 k steps take 8 s).
- `mutate:rebind` takes 17 ms with 2 defines and 39–50 ms with
  60 defines (`p07`).
- `set-code` takes 247 ms for 60 defines.
- Restore + `eval-current` takes 24–34 ms.
- `typecheck-incremental` takes 7–11 ms.
- Rust does the same kinds of work in µs.

**Concurrency.**
- CLI fibers are OS threads: `fiber:spawn-backend` = 2, and `p09`
  showed no speedup.
- They raced `read-line` and corrupted the heap (#4356, fixed in
  `18b48dc`); a fiber still does not run while main waits in `read-line`.
- `char-ready?` now exists (#4358, b8f008d); `fiber:yield` is a no-op
  and `eval:async` runs inline.
- tokio/rayon give real async I/O and data parallelism.

**Ecosystem.** Rust has tree-sitter grammars for hundreds of languages,
LSP clients, `ropey`, `cosmic-text`, `wgpu`, GPUI, wasmtime, and
collaborative CRDTs. Aura has one language and a young runtime with
open bugs and gaps (#4350–#4361).

**Safety.** The borrow checker and WASM isolation are real (§12–13).

**So:** build the *pixels and keystrokes* where speed decides (C today,
Rust would be the same choice), and put in Aura the *meaning, rules,
AI loop and history*. That split is what aura-pad already does: Soft
owns decisions, C owns pixels.

## Part 3: ranked aura-pad features that use Aura's unique parts

Every API named here was called on `c69e644` in the probe given.
Sizes: S < 150 lines Soft + test, M 150–400, L > 400.

1. **"Undo the robot": an AI proposal is one typed engine transaction.**
   - *Value:* a kid sees the helper's change land all at once or not at
     all, never half. A badly typed change is refused with a reason
     before it can break the story program. One key takes it back.
   - *APIs:* `mutate:atomic-batch` or `typed-mutate-atomic` (p03),
     `AURA_MUTATE_TYPE_GATE=hard` (p08 / p08b), `mutation-log:summary`
     (`rolled-back` count), `ast:snapshot` / `ast:restore` +
     `eval-current` for undo KEEP (p03).
   - *Feasibility:* works today. After a *failed* batch the pad must run
     `eval-current` (#4361). The runner needs the type-gate env var (a
     new runner, or a pad-side flag; `run_soft.sh` does not pass it).
   - *Size:* M.
2. **Engine-level "who wrote this".**
   - *Value:* ctrl-o on a notebook define answers from the engine log,
     not a Soft guess: "the helper wrote this, reason: closer to the
     goal, change #3". It survives save/open.
   - *APIs:* `mutate:set-agent-fingerprint` before each pen step (kid=1,
     helper=2, macro=3, law=4), `query:mutations-since`,
     `query:node-provenance`, `serialize-workspace` (p04, p05).
   - *Feasibility:* works today. The granularity is the define node, so
     keep M10's Soft row stamps for rows and cross-check them against
     the engine.
   - *Size:* S–M.
3. **"Why did it break?" in kid words.**
   - *Value:* when an AI or kid change is refused, the pad says "the
     helper tried to glue a number onto words" instead of failing
     silently.
   - *APIs:* the mutate rejection text (`type error … expected String, got Int … blamed: caller`,
     `arity mismatch`, p08), `typecheck-incremental` diagnostics (p05),
     `query-type-of`.
   - *Feasibility:* works today. Map a few error shapes to kid sentences
     with a Soft table, the same way kid-reasons already work.
   - *Size:* S.
4. **Time machine + "open is restore" (M12).**
   - *Value:* a history strip of every KEEP with who and why. Tap one to
     go back. Closing and reopening the pad brings back the code *and*
     its history.
   - *APIs:* `query:mutations-since`, `ast:snapshot` per KEEP,
     `ast:diff`, `ast:restore` + `eval-current`, `serialize-workspace` /
     `deserialize-workspace` / `workspace-persist-info` (p03, p05, p07).
   - *Feasibility:* works today. Restore costs 24–34 ms at 60 defines,
     which is fine on release but too slow to scrub at 60 fps.
     `ast:diff` is whole-program on one canonical line, so per-define
     diffs need a Soft diff of `query:code` slices.
   - *Size:* M.
5. **Sandbox worlds for AI tries.**
   - *Value:* the helper experiments in its own world. The kid's page
     never flickers. Only a strictly better result is brought back.
   - *APIs:* `workspace :create` / `:switch` / `:list`,
     `workspace:conflicts-with`, `set-code` in the child, then KEEP by
     `mutate:rebind` of the winning defines into root (p04).
   - *Feasibility:* works with a caveat. **Do not** use
     `workspace :merge`: it concatenates source and leaves duplicate
     defines. Every `set-code` in a child pays full load cost (247 ms
     at 60 defines).
   - *Size:* M–L.
6. **The kid changes the editor's rules live.**
   - *Value:* "make tab jump 4 spaces", "make the story law strict".
     The kid or the AI edits a rule, and the pad keeps running.
     `query:calls` shows what the rule affects. A bad rule heals.
   - *APIs:* `std/hot-strategy` `swap!` / `heal!` (M1–M4 slots),
     `query:calls`, `(query :def-use name)`, typed gate (p02, p08; p10:
     `query:calls "key->cmd"` gives `(16 11)`, its two call sites).
   - *Feasibility:* works for hot slots at human speed (12–50 ms per
     save). Blocked for the pad's *own key path* by #4355 (the pad is
     not in the workspace) and by rebind cost (#4357). Rules stay in
     slots, not in `play.aura`.
   - *Size:* M.
7. **"Blast radius" card before KEEP.**
   - *Value:* "this change touches 3 places: story, title, ending.
     Keep it?"
   - *APIs:* `query:dirty-nodes "general"` + `query:dirty-subtree` after
     the trial (M10 already maps nodes to rows), `query:calls name`,
     `(query :def-use name)` (p02).
   - *Feasibility:* works today (cheap reads, < 1 ms). Run it inside a
     snapshot or a child world and restore after.
   - *Size:* S.
8. **Self-repairing assistant loop with `intend`.**
   - *Value:* the helper retries with a fixer until the kid's goal
     check passes, and the pad shows the timeline ("try 1: too long,
     try 2: ok").
   - *APIs:* `intend goal gen verify fix max`, `intend-history`
     (p05c / p05e).
   - *Feasibility:* the loop works. A verifier must **not** `eval`
     generated code and then call it (hangs or aborts,
     [#4359](https://github.com/cybrid-systems/aura/issues/4359)).
     Verify by `mutate:rebind` into a child world, or run a pure Soft
     scorer over the proposal's plan, the way M3/M4 already probe
     plans.
   - *Size:* S–M.

**Not on the list, on purpose:**
- Per-key speedups from relower or rebind (#4357).
- Background settle on fibers (#4356, #4358).
- Effect isolation scoped to an AI proposal: the sandbox is one-way
  and process-wide, and `with-capability` is not a grant. This needs
  an Aura capability-scoping feature first.
- GPU rendering: that belongs on the C/Rust side.

## Issues filed from this round

- [aura#4359](https://github.com/cybrid-systems/aura/issues/4359):
  calling a closure made by `(eval "(lambda …)")` hangs or aborts
  (`free(): invalid size`); an eval'd define called through `eval`
  returns `()`. Repro `out/aura-vs-rust/bug_eval/`.
- [aura#4360](https://github.com/cybrid-systems/aura/issues/4360):
  `mutate:rebind` on a new name returns `#t` and logs `op=add`, but the
  define is missing from `query:code` and never callable. Repro
  `out/aura-vs-rust/bug_add/`.
- [aura#4361](https://github.com/cybrid-systems/aura/issues/4361): a
  failed `mutate:atomic-batch` / `ws:try-mutation` leaves every define
  throwing `stale node id` until `eval-current` (sibling of #4349).
  Repro `out/aura-vs-rust/bug_batch/`.
