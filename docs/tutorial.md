# 跟着做：M-x 的空格补全，和 set-code

两件事经常被说成一件。它们不是。

空格补全发生在状态行的 `M-x` 里。Soft 拿你打的前几个字母，去对一张命令表。它不读文件，也不碰工作区。

`set-code` 是引擎的原语。它把一整段源码装进当前工作区，换掉那里原来的程序。打字、补全、`:e` 都不调用它。

## 1. 打开 M-x

```sh
aura-pad hello.aura
```

标题上是 `[normal]` 才行。如果是 `[insert]`，先按 Esc。

Alt-x：终端要在同一次读取里送出 Esc 和 `x`。状态行变成：

```
M-x - space completes the word, enter runs it. ...
```

再按的字母出现在 `M-x ` 后面。ctrl-g 取消，回到 normal。

空的 M-x 直接回车，会运行当前页。这和 `:e` 是同一条路，走的是 `eval`，不是 `set-code`。

## 2. 空格补全命令词

补的是第一个词。规则和 Emacs 的 `minibuffer-complete-word` 同一类：能确定多少就补多少，不确定就把候选项写在状态行上。

打 `fi`，按空格。行变成：

```
M-x find-file 
```

末尾那个空格表示这个词已经结束。接下来打的是参数，比如文件名的一部分。回车之后，写对了就打开，写一部分也会挑最像的那个名字。

打 `f`，按空格。`f` 开头的命令不止一个（`find-file` 和 `flip`）。行还是 `f`，状态行把它们列出来：

```
M-x f  (find-file flip)
```

再打一个字母，缩小范围，然后再按空格。

打 `lay`，按空格。共同的开头是 `layout`，可是后面还有 `layout:story`、`layout:beside`、`layout:book`、`layout:undo`。第一次空格只把词长到 `layout`，并列出这些名字。再按一次空格，词才结束，行变成 `layout `，后面可以打参数。回车会跑 `layout`。

打 `de`，按空格。两个名字共享 `delete-`，行变成 `delete-`。再打 `w` 和空格，得到 `delete-window `。

打 `zz`，按空格。没有命令这样开头。字母留着，状态行说 `no command zz`。

第一个词已经结束后，再按的空格就是参数里的空格。`find-file a ` 不会再去补全 `a`。

什么都不打就按空格，状态行列出命令表。太长会被截成 160 个字符，末尾是 `...`。

冒号提示不是这条路。`:f` 再按空格，得到的是 `f `，不会变成 `find-file`。

短名字仍然要自己打完再回车，空格不把它们展开：`ff`、`q`、`w`。`gptel` 在表里。打 `gp` 再按空格，词长到 `gptel`（后面还有 `gptel-send` 和 `gptel-rewrite`）。这个词已经是一条命令，再按一次空格才变成 `gptel `，后面是参数。

`switch:故事` 这种带页名的命令不在表里。页名是你自己的，补全不会编一个。

C 只把空格的字节 `32` 交上来。补哪一个词，是 `soft/pad/emacs.aura` 里的 `pad:em-complete-space!` 决定的。

## 3. set-code 在玩什么

工作区是引擎里活着的那份程序。`query:code` 读它，`mutate:rebind` 改它的一个 define，`define-lookup` 告诉你名字诞生在哪。

`set-code` 是整份换上的那一步：

1. 你给它一段源码字符串。
2. 它答 `#t`，表示这段已经装进工作区。别的答案表示没换上，旧程序还在。
3. 接着调用一次 `eval-current`，这些 define 才能被调用。

pad 把这两步收成 `pad:ws-load!`（`soft/pad/ws.aura`）。一次检查做一次，不在每个按键上做。六十个 define 的 `set-code` 要两百多毫秒，绑在按键上，打字会顿。

检查之前还有一道门，门没过就不调用 `set-code`：

- 括号没闭：`close every ( before checking`
- 定义了 pad 自己的名字（`pad…`、`pd:`、`*…`）：`that name belongs to the pad, pick another`

装进去的字符串是两截。第一截是你页面上的文字。第二截是一个数据 define，把每一行存成字符码：

```
(define (hello x) (+ x 1))
(define pad-nb-rows (list (list 40 100 101 102 105 110 101 32 ...) ...))
#t
```

末尾的 `#t` 让这次 `eval-current` 的值是 `#t`，不是一个函数，也不是一对。`query:code` 会收成规范的一行，注释和你原来的空行、缩进都不保留，所以页面的行是从 `pad-nb-rows` 读回来的，不是从 `query:code` 的排版读回来的。

`:e`、空 M-x 回车，走的是另一扇门。`pad:vi-eval!` 用 `eval` 跑页面上的文字，结果写在状态行（`ran: 4`）。`eval` 能在 Soft 里多一个名字，可是 `query:code` 不变。工作区里的程序还是上一次 `set-code` 装上的那份。

你现在敲的 `aura-pad` 画面没有把「检查」接到 ctrl-s 上。那一键在这个循环里是保存。笔记本那条 `set-code` 路在 `scripts/smoke_m9.sh` 里，不在每一记按键上。

## 4. 自己跑一次 set-code

用 aura 直接跑仓库里的例子（不要在 M-x 里找一条叫 set-code 的命令，没有）：

```sh
AURA_PATH=/home/dev/code/grok-dev/aura-grok/lib \
AURA_PIPELINE_STRICT=0 AURA_SANDBOX=off \
  aura docs/examples/try-set-code.aura
```

`aura` 换成你机器上的二进制也行。在 `18b48dc` 上，输出是：

```
SET #t
EVAL #t
MAIN 4
CODE (begin (define hello (lambda (x) (+ x 1))) (define main (lambda () (hello 3))) #t)
SIDE 7
CODE2 (begin (define hello (lambda (x) (+ x 1))) (define main (lambda () (hello 3))) #t)
BAD (parse expected expression, reached end of input . 0)
STILL 4
```

对着看：

- `SET #t`：源码装上了。`(hello 3)` 的定义在工作区里。
- `EVAL #t`：`eval-current` 跑过了。末尾那个 `#t` 就是程序的值。
- `MAIN 4`：`(main)` 现在真的会算。
- `CODE`：引擎存的是规范形式，`(define (hello x) …)` 写成了 `(define hello (lambda (x) …))`。
- `SIDE 7`：`(eval "(define (side) 7)")` 在 Soft 里做出了 `side`。
- `CODE2` 和 `CODE` 相同。`eval` 没有改工作区。这就是 `:e` 和 `set-code` 的差别。
- `BAD` 不是 `#t`。`"(((("` 解析不了，工作区不动。
- `STILL 4`：`(main)` 还是刚才那个。

pad 看到的答案不是 `#t`，就停在失败，不再 `eval-current`。所以一次坏的装载不会把正在跑的定义换成半截。
