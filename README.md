# aura-pad

Aura Pad is a kid-friendly, AI-native Soft editor. Soft owns the buffer
(a FlatAST-friendly list of character codes), the point, a tiny command
table, and a seeded key sequence. Two keymap worldlines — gentle and
bold — race the same keys. A Soft gate rejects bad commands with short
friendly reasons. The better score is stamped KEEP; the other is DROP.
From M6 a thin C viewport draws the pad: Soft owns the editor and the
HL/marks/kid words, C only blits Soft's `SNAP v1 pad` blocks.

## Install & run

Build and install once, then start the pad with one command, like
`vi` or `emacs` (no script in between):

```sh
bash scripts/build_c.sh --install          # -> ~/.local (or: --install /opt/aura-pad, PREFIX=...)
export PATH="$HOME/.local/bin:$PATH"       # if ~/.local/bin is not on PATH yet
aura-pad hello.txt                         # opens hello.txt; a new page if it does not exist
aura-pad                                   # no FILE: the play page, as before
```

The same install with CMake:
`cmake -S c -B out/cmake && cmake --build out/cmake && cmake --install out/cmake`
(default prefix `~/.local`; `-DCMAKE_INSTALL_PREFIX=...` to change it).
It installs one binary, `bin/aura-pad`, and the pad's Soft files in
`share/aura-pad/soft/pad/`.

Keys: aura-pad starts in **vi normal mode** (evil-style). `i` types,
`a` appends, Esc returns to normal. Move with the arrows, `hjkl`, or
the emacs keys **ctrl-b / ctrl-f / ctrl-p / ctrl-n** (left / right /
up / down) in either mode. `x` / `X` delete a letter, `dd` deletes the
line, `D` deletes to the end of the line, `yy` copies it, `p` pastes,
`u` takes the last edit back. `0` / `$` are the ends of the line,
`gg` / `G` the top and the bottom, `w` / `b` the next and previous
word. `I` / `A` / `o` / `O` start typing at the start, the end, the
line below, or the line above. `r` replaces one letter.
**ctrl-x ctrl-s** saves (a lone ctrl-s is
still M9's "check", so saving uses the emacs pair). **ctrl-q** (or
ctrl-x ctrl-c) quits, with or without a file; with unsaved changes the
first press warns and the next ctrl-x ctrl-c, ctrl-q, or ctrl-c quits.
**`:e`** (or `:eval` / `:run`) runs the page and shows the result on
the status line. **Alt-x** then Enter does the same (the terminal must
send Esc and `x` in one read). **ctrl-x ctrl-e** runs it too. `:w`
saves, `:q` quits, `:wq` saves and quits. **ctrl-g** cancels a prefix
or a prompt. **ctrl-x ctrl-f** opens a file (a partial name is enough),
**ctrl-x ctrl-b** lists buffers, **ctrl-x b** switches to one.
**Alt-f** / **Alt-b** / **Alt-d** move by a word or delete one (Esc and
the letter in one read). **gd** jumps to where a name is born. **gD**
and **space c D** find every use, say which one and the line, and land
on the next. **space c N** goes back one use. **\*** finds the word
under the cursor; **n** and **N** walk forward and back. **/** searches,
and **ctrl-r** finds the previous match. **ctrl-a** and **ctrl-e** go to
the ends of the line. **M-x search** finds text; ctrl-s finds the
next match. **M-x find-file** opens a file.
In **M-x**, tab completes the command word (`fi` then tab becomes
`find-file `). Space shows the matches and types a space, so `ask what`
stays two words. It does not grow `fi` into `find-file`. **V** selects
lines and paints them blue. **y** copies them, **d** deletes them, and
**p** pastes. **d** then a motion deletes that text: **dG** through the
bottom, **dgg** through the top, **dw** a word. **c** changes it and
lets you type. A number repeats. **3dd** deletes three lines, **3j**
moves three lines, and **d3w** deletes three words. **d3j** deletes
this line and the next three, four lines in all. **f** and **t** find
a letter on this line. **F** and **T** look backward. **;** repeats
that find and **,** reverses it. **.** repeats the last change.
**diw** deletes the word under the cursor, **daw** the word and a
neighboring space, **di"** the inside of quotes, and **di(** the
inside of parentheses.
See [`docs/tutorial.md`](docs/tutorial.md).
**M-x ask** then some words chats about this page. The answer opens on
the chat page. **M-x chat** opens that page. **M-x rewrite** then how
you want it changed replaces the page, and **u** puts yours back. The
chat is DeepSeek v4.1 flash.
**M-x help** opens a page that is the map: split a page, move to the
other one, close one. **ctrl-x 2** splits below, **ctrl-x 3** beside,
**ctrl-x o** moves, **ctrl-x 0** closes this page, **ctrl-x 1** keeps
one. **M-x layout** races three pictures of the same pages (the story
alone, a helper beside it, or a stacked book) and keeps the one that
fits. **M-x layout:undo** puts the old picture back.
**M-x preview** then some words asks the helper for a page beside
yours. Unkind or not-allowed words make no page. **preview:keep**
keeps a better page, **preview:drop** puts it away.
**M-x story:grow** makes this page a little bigger. **story:cheer**
opens a celebration page when the story is ready. **flip** turns to
the next page. **story:undo** puts the old picture back. **ctrl-\** is the emergency
exit (nothing is saved).
`PAD_VI=0` keeps the old modeless map (ctrl-b jumps back, ctrl-p
copies). The title shows the file name and `[normal]` or `[insert]`.
The screen follows the terminal and scrolls, so the whole buffer can
be read. Problems are appended to `~/.local/state/aura-pad/aura-pad.log`
(or `$AURA_PAD_LOG`), rotated when the file reaches 256 KiB
(`$AURA_PAD_LOG_MAX`), keeping two older files. Files the pad cannot
hold byte for byte (longer than 400 columns, more than 500 lines, tabs or
non-ASCII letters) open in look-only mode and are never written.

How it starts: `aura-pad` is a small C program. It finds Aura (`$AURA_BIN`,
`aura` on `PATH`, then the usual build dirs), sets `AURA_PATH` (from
`$AURA_PATH`, `$AURA_HOME/lib`, or `lib/` next to the aura build),
`AURA_PIPELINE_STRICT=0` and `AURA_SANDBOX=off`, and execs aura on
`soft/pad/play.aura` directly. Soft reads and writes FILE
(`read-file` / `write-file`); C only forwards keys and draws. The Soft
files come from `$AURA_PAD_HOME`, else the installed share dir, else the
source tree next to the binary. `aura-pad --where` shows what would run.
Only when no aura runs natively (e.g. a build for a newer glibc) and
docker is installed does it run that aura build inside the
`ghcr.io/cybrid-systems/dev:v1.0.9` image, saying so in one line
(`AURA_PAD_NO_DOCKER=1` turns this off; `AURA_SRC` / `AURA_PAD_IMAGE`
pick the build dir / image). With no aura at all it says how to get one.

中文：先装一次（`bash scripts/build_c.sh --install`），以后像 vi / emacs
一样一条命令打开文件：`aura-pad hello.txt`。默认是 vi 的 normal 模式，
`i` 才打字，Esc 回到 normal；方向键、`hjkl`，以及 emacs 的 ctrl-b / ctrl-f /
ctrl-p / ctrl-n 都能上下左右移动。`dd` 删行，`x` 删字，`yy` 复制，`p` 粘贴，
`u` 撤销。`:e` 或 `:eval` 运行当前页（Alt-x 再回车、ctrl-x ctrl-e 也行），
结果出现在状态行。ctrl-x ctrl-s 保存，ctrl-q 或 ctrl-x ctrl-c 退出
（没保存时先提示，再按一次才退出）。ctrl-g 取消。ctrl-x ctrl-f 按文件名
打开（写一部分就行），ctrl-x ctrl-b 列出 buffer，ctrl-x b 切换。
Alt-f / Alt-b / Alt-d 按词移动或删除。gd 跳到名字诞生的地方。
gD 和空格 c D 找出每一处使用，状态行写出第几个和行号，并落到下一处。
空格 c N 回到上一处。* 搜光标上的词，n 和 N 前后走。/ 搜索，ctrl-r 找上一处。
ctrl-a 和 ctrl-e 到行首行尾。M-x search 搜文字，ctrl-s 找下一个。
M-x ask 再写几个字，就和这一页聊天，回答开在 chat 页。M-x chat 打开那一页。
M-x rewrite 再写想怎么改，会换掉这一页，u 把你的页换回来。聊天用的是 DeepSeek v4.1 flash。
在 M-x 里按 tab 会补全命令词（打 `fi` 再按 tab 变成 `find-file `）。
空格会弹出候选项，并把这个空格留在行里，所以 `ask what` 仍是两个词。
空格不会把 `fi` 补成 `find-file`。Shift-V 选中整行，选中的行是蓝底。
y 复制，d 删除选区，p 粘贴。d 再加一个动作会删掉那一段：dG 删到文末，
dgg 删到文首，dw 删一个词。c 改掉那一段并进入输入。
数字会重复。3dd 删三行，3j 下移三行，d3w 删三个词。d3j 删这一行再加下面三行，一共四行。
f 和 t 在这一行里找一个字母，F 和 T 往回找。; 按原方向再找，, 反方向找。
. 重复上一次修改。diw 删光标上的词，daw 连同旁边的空格一起删，di" 删引号里面，di( 删括号里面。
跟着做见 [`docs/tutorial.md`](docs/tutorial.md)。
M-x help 打开一页说明：ctrl-x 2 在下面分屏，ctrl-x 3 在旁边分屏，
ctrl-x o 换到另一页，ctrl-x 0 关掉这一页，ctrl-x 1 只留这一页。
M-x layout 让三种画面比赛（故事占满、旁边一页帮手、或者叠成一本），
留下更合适的那张。M-x layout:undo 把旧画面换回来。
M-x preview 再写几个字，帮手会在旁边开一页；不友善或不允许的话不会开页。
preview:keep 留下更好的那页，preview:drop 把它收起来。
M-x story:grow 让这一页稍微变大。story:cheer 在故事写好时打开庆祝页。
flip 翻到下一页。story:undo 把旧画面换回来。
画面跟着终端走，长文件可以滚动看完。
出错看 `~/.local/state/aura-pad/aura-pad.log`（会轮转）。

Tutorial: [`docs/tutorial.md`](docs/tutorial.md).
Requirements: [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md).
Design: [`docs/DESIGN.md`](docs/DESIGN.md).
Roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md).
Milestones: [`docs/m0.md`](docs/m0.md), [`docs/m1.md`](docs/m1.md),
[`docs/m2.md`](docs/m2.md), [`docs/m3.md`](docs/m3.md), [`docs/m35.md`](docs/m35.md),
[`docs/m4.md`](docs/m4.md), [`docs/m5.md`](docs/m5.md), [`docs/m6.md`](docs/m6.md),
[`docs/m7.md`](docs/m7.md), [`docs/m8.md`](docs/m8.md), [`docs/m9.md`](docs/m9.md),
[`docs/m10.md`](docs/m10.md).
Repo: https://github.com/cybrid-systems/aura-pad

中文简介：Aura Pad 是给小朋友也能玩的 Soft 小编辑器。缓冲区、光标、按键
表都在 Soft 里。两种键位策略（温和 / 大胆）赛跑同一串按键；Soft 门卫用
简短理由拒绝坏命令；分数高的 KEEP，另一条 DROP。M0 没有 C 画面。
M1 在运行中热换/自愈键位参数包；M2 让 MiniMax 提议参数包，Soft 门卫
把关，严格更高分才 KEEP。M3 让缓冲区变成多行（open-line / kill-line /
next-line / prev-line），并让 AI 提议“命令助手”（返回一串命令的 lambda），
在“hi / aura”两行目标上比主助手严格更高分才 KEEP。M3.5 加入 undo、
yank、indent/dedent、bob/eob、标记区域剪切/复制（每个都有小朋友能懂的
拒绝理由），三行第二目标，“撤销 KEEP”，以及 168 项 Soft 单元测试。
M4 变成小朋友的故事编辑器：两个本子（story / scratch）、查找/替换
（找不到、没给词、一次改太多处、不友好的词都会被温和地拒绝）、宏录制
（rec / stop / play）、两条规则在同一串按键上赛跑，以及 AI 提议“录好的宏”，
Soft 把关后严格更高分才 KEEP（30 → 44 → 51），可撤销；293 项 Soft 检查。
M5 加上 Soft 侧 Aura 语法高亮（HL 色带）、跳转/引用（goto-def /
find-refs / jump-back，小朋友拒绝理由），以及 tip 上真实可用的
query:* / mutate:* Soft 桥；没有的原语记成 GAPS 并向 Aura 提 issue。
M6 “加c”：一个很薄的 C 画面。编辑、高亮、跳转标记、按键表和所有给
小朋友看的话都在 Soft；Soft 把它们打包成 `SNAP v1 pad` 块，C 只负责
把字母换成颜色画到终端（以及把原始按键字节转发给 Soft）。
按键延迟：M6 缓存后小页面约 49/29 ms；M7 行级缓存后约 23/12 ms，
12 行页面插入约 230→26–30 ms；Soft tip `c69e644` 上约 33–35/17–19 ms
（#4343 关闭但没变快，#4350）。参考 Emacs 算法（直接命令、
try_cursor_movement、try_window_id、jit-lock、syntax-ppss）移植到 Soft
后：12 行插入约 3.6 ms、光标约 1.3 ms、只跑命令约 0.6 ms（见
docs/perf-emacs.md）。打开字符串约 24→7–9 ms，紧接着的关闭约 14→6–7 ms
（syntax-ppss / jit-lock-context 区域遍历）。同一 pty 计时下 vim/Emacs
每键快 10–30 倍，不声称比 vi/Emacs 快。
M8 欢迎卡 + 意图世界线：首帧欢迎词、`goal:` 命令、两条助手赛跑、
CARD 行、门卫（含 capability）、撤销 KEEP → `PAD_M8_OK`。
M9 工作区笔记本：ctrl-s 才 `set-code` + `eval-current`（打字零次），
引擎名字 ⊇ Soft 名字、标记/引用/节点类型、助手笔 KEEP/DROP/REJECT 与
`ast:restore` 修复 → `PAD_M9_OK`。
M10 谁写的：ctrl-o 回答"这一行是谁写的"（孩子 / 助手 / 宏 / 规则，
带原因和代数），助手 KEEP 盖章、撤销 KEEP 时 Soft 与引擎恢复必须一致，
引擎 `query:dirty-nodes` 行 ⊆ Soft DIRTY ∪ 光标行 → `PAD_M10_OK`。

- **M0** races `map-gentle` (mid 1) and `map-bold` (mid 2) on 24 seeded
  key steps toward the goal fixture `"hi aura"`. Score is
  `edits_ok - 2*rejects - distance_from_goal`. The gate prints
  `REJECT mid=.. reason=..` with kid-friendly reasons (`too-far`,
  `empty-line`, `need-space`, `not-print`). `fiber_live` only when both
  fiber joins return scores (`joins` equals spawned, backend > 0).
  Otherwise `host-sequential`. No C viewport. No `hot-strategy`.
- **M1** puts the keymap pack `(step room strict)` in a real
  `std/hot-strategy` slot `pd:law`. Mid-run on the live buffer it
  gate-rejects a `set!` body, `SWAP`s to `(2 12 0)` at key 10, `HEAL`s an
  ugly two-field pack at key 15, and prints `MUTATE key=8 room-boost=2`.
  Then the honest gentle vs bold race: bold 9 `KEEP`, gentle -2 `DROP`.
  `PAD_M1_OK`. See [`docs/m1.md`](docs/m1.md).
- **M2** lets MiniMax (host `scripts/propose_minimax.py`, api.minimax.cn)
  propose a pack lambda. Soft gates it (no `set!`/`display`/`eval`/`load`/
  `shell`/`http`), races it vs main (bold, 9) and `KEEP`s only on a
  strictly better score; otherwise `DROP` + `heal!`. Fixtures: worse -2
  DROP, better `(1 12 0)` 10 KEEP → `PAD_M2_PROPOSE_OK`; fixture burn
  `PAD_BURN_OK`. See [`docs/m2.md`](docs/m2.md).
- **M3** makes the buffer multi-line (list of char-code lines, point
  `(line col)`) with `open-line`, `kill-line`, `next-line`, `prev-line`
  and kid reasons `no-line`, `too-far`, `empty-buf`. A host proposes a
  **command helper** — `(lambda () (list "kill-line" "type:hi" ...))` in
  hot slot `pd:helper`. Soft gates it, probes the plan, races it vs the
  main helper (27) on the seeded `nwn` → `"hi"`/`"aura"` goal and KEEPs
  only on a strictly better score, else `heal!` + DROP. Fixtures: worse
  14 DROP, tie 27 DROP, better 31 KEEP → `PAD_M3_OK`. Live MiniMax helper
  via `propose_minimax.py --helper`. See [`docs/m3.md`](docs/m3.md).
- **M3.5** adds `undo` (8-deep snapshot stack), `yank` + kill text,
  `indent`/`dedent`, `bob`/`eob`, `set-mark` + `kill-region`/`copy-region`
  with kid reasons (`nothing-to-undo`, `nothing-to-yank`, `no-mark`,
  `empty-region`, `no-indent`, `already-there`) and `say="..."` text on
  every REJECT, a `SCORE` breakdown line, a three-line goal
  `"hi"`/`"  aura"`/`"pad"` for the helper race (28 → 43 KEEP → 45 KEEP),
  and `pd:helper-undo!` that honestly takes back a KEEP. Tests: paren
  check, Python model, `m35_test.aura` (168 checks, `PAD_TEST_OK`),
  `PAD_M35_OK`. See [`docs/m35.md`](docs/m35.md).
- **M4** adds two named pads (`story` / `scratch`, `switch:NAME`, the kill
  text travels), `find:WORD` / `find-next` / `replace:NEW` /
  `replace-all:OLD=NEW` with kid reasons (`not-found`, `empty-needle`,
  `too-many`, `not-kind`, `no-buffer`), a macro recorder (`rec` / `stop` /
  `play`), a **buffer-law race** (two laws on the same keys: `wrap-3`
  KEEP, `wrap-9` DROP) and **macro propose** (hot slot `pd:macro`: code-word
  and kind-word gate, shape probe + `heal!`, race on the kid story goal
  30 → 44 KEEP → 51 KEEP, tie DROP, `pd:macro-undo!`). Tests: Python model
  `PAD_M4_MODEL_OK`, `m4_test.aura` (293 checks, `PAD_M4_TEST_OK`),
  `PAD_M4_OK`, live `--macro`. See [`docs/m4.md`](docs/m4.md).
- **M5** adds Soft-side Aura syntax highlight (`hl.aura`: kind tags +
  kid HL color tape, no C viewport), Soft LSP-lite goto-def /
  find-refs / jump-back with kid reasons (`no-symbol`, `no-def`,
  `no-ref`, `nothing-to-back`), and an honest Soft bridge to tip
  `query:*` / `mutate:*` (`query.aura`: categories, help, find,
  def-use, mutate summary/rebind). The former gaps (`define-lookup`,
  `query:code`, `query:ref-counts`, `query:node-types`; filed as #4344 and
  #4345) are bound on Soft tip `c69e644`. The smoke prints `USED ...` and
  `GAPS none`. No fake Soft APIs.
  Tests: Python model, Soft checks, `PAD_M5_OK`. See
  [`docs/m5.md`](docs/m5.md).
- **M6** adds a **thin C viewport** ("加c"). Soft (`view.aura`) packs the
  editor lines, the M5 HL tape, def/use marks of the name under the
  cursor, the cursor and the kid SAY/LEGEND words into a `SNAP v1 pad`
  block (file or stdout stream — same `SNAP v1 … END` family as
  aura-parkour / aura-tetris). C (`c/pad_view`, `c/pad_play`) checks the
  shape (fail closed, last complete block wins) and blits ANSI or plain
  text; `pad_play` forwards raw key bytes and Soft's keymap (`keys.aura`)
  decides what they mean. **C never owns edit logic** — enforced by
  `PAD_C_THIN_OK`. Tests: 61 Soft checks, host model byte-for-byte,
  golden blits, fail-closed fixtures, soft_play → C → `PAD_C_OK`. See
  [`docs/m6.md`](docs/m6.md).
- **Key latency (M6)** — Soft no longer full-buffer re-HL on every key:
  one tokenize per text change, play cache for cursor moves, optional
  SNAP `DIRTY` for lighter C redraw. Before ~161/288 ms/key → after
  ~49/29 ms/key (insert/cursor); Soft kernel define-lookup still scales
  (#4343). See [`docs/perf.md`](docs/perf.md).
- **M7 snappy pad** — Soft line-incremental key path (`lc.aura`): only
  the edited line is re-tokenized; marks rebuild only on rows that hold
  the old/new name; DIRTY is exact (sound + tight, host-audited); list
  helpers on builtins; jump from cache. Twelve-row insert ~230 →
  ~26–30 ms/key (≥ 2× vs the M6 path), cursor ~13 ms; small page
  ~23/12 ms. Every cached frame equals the whole-page oracle (147 Soft
  checks). C unchanged. Soft floors published (#4343 + in-place
  `vector-set!` cost). Tests: `PAD_M7_TEST_OK`, `PAD_M7_DIRTY_OK`,
  `PAD_PERF_OK`, `PAD_M7_PERF_OK`, `PAD_M7_OK`. See
  [`docs/m7.md`](docs/m7.md), [`docs/m8.md`](docs/m8.md). On Soft tip
  `c69e644` the same keys measure ~33–35 / 17–19 ms. #4343 closed but did
  not speed up the file runner (#4350). The floor is ~0.3 ms per Soft
  call.
- **Emacs algorithms in Soft** — ported from Emacs:
  - direct commands (`command_loop_1`);
  - `try_cursor_movement`;
  - `try_window_id` row reuse;
  - jit-lock fontify of the changed line only, as one inline pass that resumes after the unchanged prefix;
  - a syntax-ppss start state per line, which replaces the whole-page fallback when a string is open.

  Twelve-row page: insert ~33 → **~3.6 ms**, cursor ~13 → **~1.3 ms**,
  command only ~9.5 → **~0.6 ms**, typing inside an open string ~220 →
  **~3.5 ms**, opening a string above many rows ~24 → **~7–9 ms** and the
  close after it ~14 → **~6–7 ms** (syntax-ppss / jit-lock-context region
  walk). Every fast path equals its reference or the whole-page oracle
  (43 checks, `PAD_PERF_EMACS_OK`). On the same pty harness
  (`scripts/bench_editors.sh`) vim and Emacs are 10–30× faster per key;
  we do not claim to beat vi/Emacs. See [`docs/perf-emacs.md`](docs/perf-emacs.md).
- **M9 workspace notebook** — `ws.aura`: ctrl-s (byte 19) runs one
  `set-code` + `eval-current` of the page plus a char-code row define.
  Typing makes zero `set-code` calls. Engine names (`define-lookup`) are
  compared with Soft find-defs names (missing/extra printed). Marks
  `name@row:col`, `query:ref-counts` and `query:node-types` lines are
  printed. Rows come back from `query:code`. `pen.aura`: helper/macro/law
  rebind steps are REJECTed (kid reasons, no writes), KEEPed (generation
  +1 exactly, page row re-projected, undo via `ast:restore`) or DROPped
  (`ast:restore` heal). Tests: 113 Soft checks, `M9_ACC 1..6 OK`,
  `PAD_M9_OK`. See [`docs/m9.md`](docs/m9.md).
- **M10 who wrote this** — `who.aura`: ctrl-o (byte 15) answers "who
  wrote this line?" from row stamps `(who why gen)` (kid / helper /
  macro / law), synced by row identity at ctrl-o and pen steps only, so
  typing pays nothing. `who_pen.aura`: pen KEEP stamps, pen undo =
  `ast:restore` + re-project with a loud agree check, and an engine
  `query:dirty-nodes` cross-check against Soft DIRTY. Tests: 58 Soft
  checks, `M10_ACC 1..4 OK`, `PAD_M10_OK`. See [`docs/m10.md`](docs/m10.md).

## Soft smoke

Image `ghcr.io/cybrid-systems/dev:v1.0.9`, Soft tip binary
`/workspace/aura-grok/build/aura`, built from aura **`18b48dc`** (main
`0ba8690` / `e7b236d` hang the pad, see [`docs/ISSUES.md`](docs/ISSUES.md))
(host GLIBC is often too old — smoke
always runs Soft inside Docker with `--entrypoint /usr/local/bin/gosu`).
Soft runs natively in that container (no nested docker). Never
`build_soft4132`. Needs `AURA_SANDBOX=off`. `scripts/run_soft.sh` sets
`AURA_MUTATE_TYPE_GATE=hard` unless told otherwise. Last full run:
`PAD_LIVE=0 bash scripts/smoke.sh` → `PAD_SMOKE_OK` on `18b48dc`
(2026-10-07, 15.5 min, M0–M13 + gap / perf / aura-perf / wire2 / cli).

```bash
bash scripts/smoke.sh         # M0..M10 (+ live MiniMax if keyed) → PAD_SMOKE_OK
bash scripts/smoke_soft.sh    # M0 → PAD_M0_OK
bash scripts/smoke_m1.sh      # M1 → PAD_M1_OK
bash scripts/smoke_m2.sh      # M2 fixtures → PAD_M2_PROPOSE_OK
PAD_PROPOSE=0 bash scripts/burn.sh   # fixture burn → PAD_BURN_OK
bash scripts/smoke_m3.sh      # M3 multi-line + helper → PAD_M3_OK (+ live if keyed)
bash scripts/smoke_m35.sh     # M3.5 PAREN_OK, PAD_MODEL_OK, PAD_TEST_OK, PAD_M35_OK (+ live if keyed)
bash scripts/smoke_m4.sh      # M4 PAREN_OK, PAD_M4_MODEL_OK, PAD_M4_TEST_OK, PAD_M4_OK (+ live if keyed)
bash scripts/smoke_m5.sh      # M5 PAREN_OK, PAD_M5_MODEL_OK, PAD_M5_TEST_OK, PAD_M5_OK
bash scripts/smoke_c.sh       # M6 Soft dump → thin C blit … PAD_C_OK (PAD_C_DOCKER=1 builds C in the image)
bash scripts/smoke_m7.sh      # M7 Soft tests + DIRTY audit + perf → PAD_M7_OK
bash scripts/smoke_m8.sh      # M8 welcome card + intent race → PAD_M8_OK
bash scripts/smoke_m9.sh      # M9 workspace notebook + pen → PAD_M9_OK
bash scripts/smoke_m10.sh     # M10 who wrote this + engine dirty → PAD_M10_OK
bash scripts/smoke_perf.sh    # key-path ms/key → PAD_PERF_OK + PAD_M7_PERF_OK + PAD_PERF_EMACS_OK
PAD_LIVE=0 bash scripts/smoke.sh     # skip live MiniMax (includes M8, M9, M10)
```

Scripts may be mode `100644` in git. Always invoke them with `bash`.

Manual Soft run:

```bash
sudo docker run --rm --entrypoint /usr/local/bin/gosu \
  -v /workspace/aura-grok:/workspace/aura-grok \
  -v "$PWD":/workspace/aura-pad \
  -w /workspace/aura-pad \
  -e AURA_PATH=/workspace/aura-grok/lib \
  -e AURA_PIPELINE_STRICT=0 \
  -e AURA_SANDBOX=off \
  -e AURA_BIN=/workspace/aura-grok/build/aura \
  ghcr.io/cybrid-systems/dev:v1.0.9 \
  dev /workspace/aura-grok/build/aura /workspace/aura-pad/soft/pad/m0_smoke.aura
```

`scripts/run_soft.sh` is the same invocation. The source path is `$1`.

On seed `20261005`, 24 steps, M0 keeps `map-bold` (mid 2, score `9`) and
drops `map-gentle` (mid 1, score `-2`). The gate rejects 6 gentle
commands (`too-far`, `not-print`, …) and 1 bold command (`empty-line`).
On the tip binary that race is `WORLD line=fiber_live backend=2 joins=2/2`
(`backend=2` is CLI thread fallback). If the joins do not land, the line
is `host-sequential` and `fiber_live` is not printed.

## Thin C viewport (M6)

```bash
bash scripts/build_c.sh                       # out/c/pad_view, out/c/pad_play (host cc, -Werror)
./out/c/pad_view out/m6.snap                  # blit the snapshot Soft wrote (after smoke_c.sh)
bash scripts/run_soft.sh /workspace/aura-pad/soft/pad/m6_smoke.aura | ./out/c/pad_view   # stream
./out/c/pad_play                              # interactive: Soft play child in docker, C blits
```

In `pad_play`: type, arrows move, ctrl-g finds where a name is born,
ctrl-r counts uses, ctrl-b jumps back, ctrl-o says who wrote the line,
ctrl-q says bye — all decided by
Soft (`soft/pad/keys.aura`). C forwards bytes and paints.

## License

Apache-2.0. Soft tip: `/workspace/aura-grok/build/aura`.

Aura vs Rust for a next-generation (AI-era) editor, verified on Soft tip `c69e644`, re-checked on `18b48dc`: [`docs/aura-vs-rust.md`](docs/aura-vs-rust.md).
