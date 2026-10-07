# Sentence-line issues

Spec: [`sentence-design.md`](sentence-design.md).
One issue is one commit, in this order. The default binary
stays vi until step 21.

## Milestones

| Milestone | Issue | Steps |
|---|---:|---|
| M18 — Open a real module, edit, save, and hear the engine | [#7](https://github.com/cybrid-systems/aura-pad/issues/7) | 1–21 |
| M19 — Save the projection, not query:code | [#5](https://github.com/cybrid-systems/aura-pad/issues/5) | 22–23 |
| M20 — Who wrote it survives save and reopen, or say soft-only | [#6](https://github.com/cybrid-systems/aura-pad/issues/6) | 24–35 |
| M21 — One sentence becomes one transaction | [#8](https://github.com/cybrid-systems/aura-pad/issues/8) | 36–42 |
| M22 — Two proposals, show the blast radius first | [#11](https://github.com/cybrid-systems/aura-pad/issues/11) | 43–48 |
| M23 — A child story uses the same path | [#10](https://github.com/cybrid-systems/aura-pad/issues/10) | 49–54 |
| M24 — Self-repair and one human-speed rule | [#9](https://github.com/cybrid-systems/aura-pad/issues/9) | 55–60 |

## Steps

| Step | Issue | Title |
|---:|---:|---|
| 1 | [#27](https://github.com/cybrid-systems/aura-pad/issues/27) | Gate sentence mode behind PAD_SENTENCE=1 without flipping aura-pad |
| 2 | [#28](https://github.com/cybrid-systems/aura-pad/issues/28) | Draw the sentence line only when PAD_SENTENCE=1 |
| 3 | [#22](https://github.com/cybrid-systems/aura-pad/issues/22) | Dispatch Tab, Esc, Enter, and inserts only under the flag |
| 4 | [#21](https://github.com/cybrid-systems/aura-pad/issues/21) | Add save, open, and quit sentences under the flag |
| 5 | [#13](https://github.com/cybrid-systems/aura-pad/issues/13) | Decode UTF-8 through pad:v-src, pad:line-text, and the paste decoder |
| 6 | [#29](https://github.com/cybrid-systems/aura-pad/issues/29) | Lazy-load the read stack and record pad:read-sane? before pad:q-sane? |
| 7 | [#30](https://github.com/cybrid-systems/aura-pad/issues/30) | Check a page inside a child workspace |
| 8 | [#23](https://github.com/cybrid-systems/aura-pad/issues/23) | Show cached engine meaning and accept a use count of zero |
| 9 | [#25](https://github.com/cybrid-systems/aura-pad/issues/25) | Raise buffer caps and keep the window cap |
| 10 | [#24](https://github.com/cybrid-systems/aura-pad/issues/24) | Pass the hard type gate from both aura-pad env sites |
| 11 | [#12](https://github.com/cybrid-systems/aura-pad/issues/12) | Refuse unsafe top-level forms and unsafe init heads |
| 12 | [#26](https://github.com/cybrid-systems/aura-pad/issues/26) | Place birth marks with pad:defs-for |
| 13 | [#14](https://github.com/cybrid-systems/aura-pad/issues/14) | Answer the where sentence from the cache |
| 14 | [#31](https://github.com/cybrid-systems/aura-pad/issues/31) | Log engine names against Soft names |
| 15 | [#32](https://github.com/cybrid-systems/aura-pad/issues/32) | Mark the meaning cache stale on the first edit |
| 16 | [#33](https://github.com/cybrid-systems/aura-pad/issues/33) | Keep a wide line inside the scrolling window |
| 17 | [#34](https://github.com/cybrid-systems/aura-pad/issues/34) | Save the original bytes when the page is clean |
| 18 | [#35](https://github.com/cybrid-systems/aura-pad/issues/35) | Re-encode scalars on a dirty save and keep comments |
| 19 | [#36](https://github.com/cybrid-systems/aura-pad/issues/36) | Keep look-only save refused with a named reason |
| 20 | [#37](https://github.com/cybrid-systems/aura-pad/issues/37) | Publish cold and post-check cursor times against the 16 ms frame |
| 21 | [#38](https://github.com/cybrid-systems/aura-pad/issues/38) | Flip the aura-pad default and replace the pty scenarios |
| 22 | [#39](https://github.com/cybrid-systems/aura-pad/issues/39) | Report query:dirty-nodes on the next check |
| 23 | [#40](https://github.com/cybrid-systems/aura-pad/issues/40) | Accept projection roundtrip on a real-module fixture |
| 24 | [#41](https://github.com/cybrid-systems/aura-pad/issues/41) | Replace string-split before sentence mode calls who or time |
| 25 | [#42](https://github.com/cybrid-systems/aura-pad/issues/42) | Stamp the agent fingerprint before a file rebind |
| 26 | [#43](https://github.com/cybrid-systems/aura-pad/issues/43) | Split pad:tx-gate from pad:pen-gate |
| 27 | [#44](https://github.com/cybrid-systems/aura-pad/issues/44) | Splice a kept define back into the projection |
| 28 | [#45](https://github.com/cybrid-systems/aura-pad/issues/45) | Run a fixture KEEP from the apply sentence |
| 29 | [#46](https://github.com/cybrid-systems/aura-pad/issues/46) | Answer who from query:node-provenance |
| 30 | [#47](https://github.com/cybrid-systems/aura-pad/issues/47) | Cross-check engine who against Soft row stamps |
| 31 | [#48](https://github.com/cybrid-systems/aura-pad/issues/48) | Serialize the file child before it is deleted |
| 32 | [#49](https://github.com/cybrid-systems/aura-pad/issues/49) | Accept reopen or an explicit soft-only sentence |
| 33 | [#50](https://github.com/cybrid-systems/aura-pad/issues/50) | Undo one KEEP as text plus authorship |
| 34 | [#51](https://github.com/cybrid-systems/aura-pad/issues/51) | Leave no sidecar and no page change on DROP |
| 35 | [#52](https://github.com/cybrid-systems/aura-pad/issues/52) | Accept who after save and reopen |
| 36 | [#53](https://github.com/cybrid-systems/aura-pad/issues/53) | Add a host proposer that returns rebind ops |
| 37 | [#54](https://github.com/cybrid-systems/aura-pad/issues/54) | Keep the sentence path from pasting model text |
| 38 | [#55](https://github.com/cybrid-systems/aura-pad/issues/55) | Split a model reply into ops or a SAY sentence |
| 39 | [#56](https://github.com/cybrid-systems/aura-pad/issues/56) | Apply one proposal with typed-mutate-atomic and the snapshot heal |
| 40 | [#57](https://github.com/cybrid-systems/aura-pad/issues/57) | Score the child and the page on the same checks |
| 41 | [#58](https://github.com/cybrid-systems/aura-pad/issues/58) | Draw the card and drive it from classic keys |
| 42 | [#59](https://github.com/cybrid-systems/aura-pad/issues/59) | Accept a fixture proposal end to end, including classic mode |
| 43 | [#60](https://github.com/cybrid-systems/aura-pad/issues/60) | Request two proposals for one sentence |
| 44 | [#61](https://github.com/cybrid-systems/aura-pad/issues/61) | Race the two children and print an honest WORLD line |
| 45 | [#62](https://github.com/cybrid-systems/aura-pad/issues/62) | Show a blast card before KEEP |
| 46 | [#63](https://github.com/cybrid-systems/aura-pad/issues/63) | DROP a tie without a trace |
| 47 | [#64](https://github.com/cybrid-systems/aura-pad/issues/64) | Refuse KEEP of the lower score |
| 48 | [#65](https://github.com/cybrid-systems/aura-pad/issues/65) | Accept the two-proposal race |
| 49 | [#66](https://github.com/cybrid-systems/aura-pad/issues/66) | Open story and text files as the sentence projection |
| 50 | [#67](https://github.com/cybrid-systems/aura-pad/issues/67) | Build child defines from sentences without showing them |
| 51 | [#68](https://github.com/cybrid-systems/aura-pad/issues/68) | Map engine refusals to kid sentences of at most eight words |
| 52 | [#69](https://github.com/cybrid-systems/aura-pad/issues/69) | Run the same card and undo on a story |
| 53 | [#70](https://github.com/cybrid-systems/aura-pad/issues/70) | Keep a fixture that makes the last line kinder |
| 54 | [#71](https://github.com/cybrid-systems/aura-pad/issues/71) | Accept the kid story loop |
| 55 | [#72](https://github.com/cybrid-systems/aura-pad/issues/72) | Replace string-split in fix_loop and kid_rules |
| 56 | [#73](https://github.com/cybrid-systems/aura-pad/issues/73) | Run intend with a child-world verifier |
| 57 | [#74](https://github.com/cybrid-systems/aura-pad/issues/74) | Reject a verifier that evals a generated closure |
| 58 | [#75](https://github.com/cybrid-systems/aura-pad/issues/75) | Swap a tab rule through pad:kr-cmd! from a sentence |
| 59 | [#76](https://github.com/cybrid-systems/aura-pad/issues/76) | Keep rule and intend loads off the arrow path |
| 60 | [#77](https://github.com/cybrid-systems/aura-pad/issues/77) | Accept repair and a live rule |
