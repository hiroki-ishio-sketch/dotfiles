#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "--env=localdev を指定してください。" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# S配列の位置とキー一覧の起動に必要な割り当てを、実機への書き込みなしで照合する。
python3 - "$ROOT_DIR/.config/torabo-zmk/config/torabo_tsuki.keymap" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "zmk,physical-layout = &physical_layout_s;" in source, "起動時にS配列を選択する"
layers = {}
for name, bindings in re.findall(r"(layer_\d+|drag_scroll)\s*\{[^{}]*?bindings\s*=\s*<([^>]+)>;", source, re.S):
    layer = [" ".join(binding.split()) for binding in re.findall(r"&[^&]+", bindings)]
    assert len(layer) == 42, f"{name}はS配列の42キーに対応する"
    layers[name] = layer
assert list(layers) == [*(f"layer_{index}" for index in range(8)), "drag_scroll"]

# 通常キーは変更できる。Macのキー一覧とドラッグスクロールに必要な予約位置だけを検証する。
base = layers["layer_0"]
assert base[13] == "&lt 2 F", "F長押しでキー一覧のレイヤーに入る"
assert layers["layer_2"][24] == "&kp F24", "F長押しとBでキー一覧を開く"
assert all(binding == "&trans" for binding in layers["drag_scroll"]), "スクロール中も他のキー操作を透過する"
print("成功: ZMKのS配列と主要なキー操作を確認しました。")
PY
