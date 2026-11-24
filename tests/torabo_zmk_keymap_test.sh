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
# Studioに渡す日本語レイヤー名は、終端文字を含めて本体の格納領域に収める。
config = Path(sys.argv[1]).with_name("torabo_tsuki.conf").read_text(encoding="utf-8")
capacity = re.search(r"^CONFIG_ZMK_KEYMAP_LAYER_NAME_MAX_LEN=(\d+)$", config, re.M)
for name in re.findall(r'display-name\s*=\s*"([^"]+)"', source):
    assert len(name.encode("utf-8")) < (int(capacity[1]) if capacity else 20), name
layers = {}
for name, bindings in re.findall(r"(layer_\d+|drag_scroll|media)\s*\{[^{}]*?bindings\s*=\s*<([^>]+)>;", source, re.S):
    layer = [" ".join(binding.split()) for binding in re.findall(r"&[^&]+", bindings)]
    assert len(layer) == 42, f"{name}はS配列の42キーに対応する"
    layers[name] = layer
assert list(layers) == [*(f"layer_{index}" for index in range(8)), "drag_scroll", "media"]

base = layers["layer_0"]
assert base[13] == "&lt 2 F", "F長押しでキー一覧のレイヤーに入る"
assert layers["layer_2"][24] == "&kp F24", "F長押しとBでキー一覧を開く"
# 通常の割り当てを編集しても、READMEに載せた接続復旧手順は使える。
assert base[24] == "&lt 6 B"
assert layers["layer_6"][12:14] == ["&bt BT_CLR", "&bt BT_SEL 0"]
assert layers["layer_6"][19] == "&bootloader"
assert all(binding == "&trans" for binding in layers["drag_scroll"]), "スクロール中も他のキー操作を透過する"
print("成功: ZMKのS配列と主要なキー操作を確認しました。")
PY
