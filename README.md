# aura-pad

Aura Pad is a kid-friendly, AI-native Soft editor. Soft owns the buffer
(a FlatAST-friendly list of character codes), the point, a tiny command
table, and a seeded key sequence. Two keymap worldlines — gentle and
bold — race the same keys. A Soft gate rejects bad commands with short
friendly reasons. The better score is stamped KEEP; the other is DROP.
There is no C viewport in this tree.

Design: [`docs/DESIGN.md`](docs/DESIGN.md).
Milestones: [`docs/m0.md`](docs/m0.md).
Repo: https://github.com/cybrid-systems/aura-pad

中文简介：Aura Pad 是给小朋友也能玩的 Soft 小编辑器。缓冲区、光标、按键
表都在 Soft 里。两种键位策略（温柔 / 大胆）赛跑同一串按键；Soft 门卫用
简短理由拒绝坏命令；分数高的 KEEP，另一条 DROP。M0 没有 C 画面。

- **M0** races `map-gentle` (mid 1) and `map-bold` (mid 2) on 24 seeded
  key steps toward the goal fixture `"hi aura"`. Score is
  `edits_ok - 2*rejects - distance_from_goal`. The gate prints
  `REJECT mid=.. reason=..` with kid-friendly reasons (`too-far`,
  `empty-line`, `need-space`, `not-print`). `fiber_live` only when both
  fiber joins return scores (`joins` equals spawned, backend > 0).
  Otherwise `host-sequential`. No C viewport. No `hot-strategy`.
- **M1** (next) will hot-swap keymap packs mid-run.
- **Propose** (later) will gate an AI-proposed keymap and KEEP only on a
  strictly better score.

## Soft smoke

Image `ghcr.io/cybrid-systems/dev:v1.0.9`, Soft tip binary
`/workspace/aura-grok/build/aura` (host GLIBC is often too old — smoke
always runs Soft inside Docker with `--entrypoint /usr/local/bin/gosu`).
Soft runs natively in that container (no nested docker). Never
`build_soft4132`. Needs `AURA_SANDBOX=off`.

```bash
bash scripts/smoke_soft.sh    # M0 → PAD_M0_OK
bash scripts/smoke.sh         # same entry for M0
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

## License

Apache-2.0. Soft tip: `/workspace/aura-grok/build/aura`.
