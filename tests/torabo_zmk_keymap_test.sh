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
assert base[18] == "&kp L", "Lは単純なL"
assert base[20] == "&mt LCTRL Z", "Z長押しはControl"
assert base[30] == "&kp CAPSLOCK", "一番左下はCaps"
assert base[31] == "&kp LGUI", "Capsの右はCommand"
assert base[32] == "&kp LALT", "左親指の内側はOption"
assert base[33] == "&kp LALT", "左Enterの左はOption"
assert base[41] == "&to 0", "一番右下は基本レイヤーへ強制復帰"
assert layers["layer_2"][24] == "&kp F24", "F長押しとBでキー一覧を開く"
# L4記号はKarabinerのv長押しと同じ配置。
symbols = layers["layer_4"]
assert symbols[5:9] == ["&kp INTERNATIONAL_3", "&kp MINUS", "&kp EQUAL", "&kp LBKT"], "v層 Y¥ U- I= O["
assert symbols[15:20] == ["&kp LS(GRAVE)", "&kp SEMI", "&kp SQT", "&kp BSLH", "&kp RBKT"], "v層 H~ J; K' L\\ P]"
assert symbols[26:29] == ["&kp COMMA", "&kp DOT", "&kp FSLH"], "v層 N, M. /"
assert all(binding == "&trans" for binding in layers["drag_scroll"]), "スクロール中も他のキー操作を透過する"
print("成功: ZMKのS配列と主要なキー操作を確認しました。")
PY
