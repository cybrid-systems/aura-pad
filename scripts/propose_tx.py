#!/usr/bin/env python3
"""Host proposer for a sentence-line transaction.

PAD_LIVE unset or 0 prints a fixture. It does not open the network and
it does not read a key file. PAD_LIVE=1 is the live adapter: DeepSeek
flash is the default model, MiniMax is only an adapter. The key stays
off stdout. Soft does not post.

Stdout is one or more name=(lambda ...) lines and check lines.
--two SENTENCE asks for exactly two ideas. Offline, that is
propose_two.txt. A count other than 2 is refused.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

DEFAULT_MODEL = "deepseek-flash"
DEFAULT_URL = "https://api.deepseek.com/chat/completions"
ADAPTERS = ("minimax",)
TWO_COUNT = 2
TWO_FIXTURE = "propose_two.txt"
TWO_SEP = "---"
ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "soft" / "pad" / "fixtures"


def live_requested() -> bool:
    return os.environ.get("PAD_LIVE", "0") == "1"


def model_name(adapter: str) -> str:
    if adapter == "minimax":
        return os.environ.get("MINIMAX_MODEL", "").strip() or "minimax"
    return DEFAULT_MODEL


def fixture_path(name: str) -> Path | None:
    if not name or name != Path(name).name or "/" in name or "\\" in name:
        return None
    path = FIXTURES / name
    if not path.is_file():
        return None
    return path


def emit_fixture(name: str) -> int:
    path = fixture_path(name)
    if path is None:
        print("PROPOSE_FAIL fixture", file=sys.stderr)
        return 1
    sys.stdout.write(path.read_text(encoding="utf-8"))
    return 0


def live(adapter: str) -> int:
    # The key is read only here. It is never written to stdout.
    model = model_name(adapter)
    if adapter == "minimax":
        url = os.environ.get("MINIMAX_BASE_URL", "").strip()
    else:
        url = DEFAULT_URL
    key_file = Path.home() / "code" / "keys" / "deepseek"
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not key and adapter != "minimax" and key_file.is_file():
        key = key_file.read_text(encoding="utf-8").strip()
    if not key:
        print("PROPOSE_FAIL no-key", file=sys.stderr)
        return 2
    # This step does not post. Naming the model keeps the adapter honest.
    print("PROPOSE_FAIL live model=" + model, file=sys.stderr)
    if url:
        return 2
    return 2


def emit_two(sentence: str) -> int:
    if not sentence.strip():
        print("PROPOSE_FAIL sentence", file=sys.stderr)
        return 1
    return emit_fixture(TWO_FIXTURE)


def main(argv: list[str]) -> int:
    adapter = ""
    args = argv[1:]
    if args and args[0] == "--adapter":
        if len(args) < 2 or args[1] not in ADAPTERS:
            print("PROPOSE_FAIL adapter", file=sys.stderr)
            return 1
        adapter = args[1]
        args = args[2:]
    if args and args[0] == "--two":
        sentence = " ".join(args[1:]).strip()
        if not live_requested():
            return emit_two(sentence)
        if not sentence:
            print("PROPOSE_FAIL sentence", file=sys.stderr)
            return 1
        return live(adapter)
    if args and args[0] == "--count":
        if len(args) != 2 or args[1] != str(TWO_COUNT):
            print("PROPOSE_FAIL count", file=sys.stderr)
            return 1
        if not live_requested():
            return emit_fixture(TWO_FIXTURE)
        return live(adapter)
    name = args[0] if args else "propose_ok.txt"
    if not live_requested():
        return emit_fixture(name)
    return live(adapter)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
