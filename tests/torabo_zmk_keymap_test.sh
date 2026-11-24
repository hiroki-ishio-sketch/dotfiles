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
for name, bindings in re.findall(r"(layer_\d+|drag_scroll|media)\s*\{[^{}]*?bindings\s*=\s*<([^>]+)>;", source, re.S):
    layer = [" ".join(binding.split()) for binding in re.findall(r"&[^&]+", bindings)]
    assert len(layer) == 42, f"{name}はS配列の42キーに対応する"
    layers[name] = layer
assert list(layers) == [*(f"layer_{index}" for index in range(8)), "drag_scroll", "media"]

base = layers["layer_0"]
assert base[13] == "&lt 2 F", "F長押しでキー一覧のレイヤーに入る"
assert base[5] == "&kp Y", "Yは単純なY"
assert base[7] == "&kp I", "Iは単純なI"
assert base[8] == "&kp O", "Oは単純なO"
assert base[9] == "&mo 8", "Oの右・Pの上はスクロール層"
assert base[17] == "&kp K", "Kは単純なK"
assert base[18] == "&kp L", "Lは単純なL"
assert base[21] == "&media_x 9 X", "X長押しはメディア層"
assert "media_x: media_hold_tap" in source, "X用の短いhold-tapがある"
assert "CONFIG_ZMK_KEYMAP_SETTINGS_STORAGE=n" in Path(sys.argv[1]).with_name("torabo_tsuki.conf").read_text(encoding="utf-8"), "Studio保存で上書きしない"
assert base[20] == "&mt LCTRL Z", "Z長押しはControl"
assert base[30] == "&kp CAPSLOCK", "一番左下はCaps"
assert base[31] == "&kp LGUI", "Capsの右はCommand"
assert base[32] == "&kp LALT", "左親指の内側はOption"
assert base[33] == "&kp LALT", "左Enterの左はOption"
assert base[37] == "&mt RGUI RET", "右親指の左から2番目はEnter/⌘"
assert base[41] == "&to 0", "一番右下は基本レイヤーへ強制復帰"
assert layers["layer_2"][24] == "&kp F24", "F長押しとBでキー一覧を開く"
mouse = layers["layer_1"]
assert mouse[15:19] == ["&mkp MB4", "&mkp LCLK", "&mkp RCLK", "&mkp MB5"], "マウス層 H戻る J左 K右 L進む"

fns = layers["layer_5"]
assert fns[5:9] == ["&kp F12", "&kp F7", "&kp F8", "&kp F9"], "C層 YF12 UF7 IF8 OF9"
assert fns[15:20] == ["&kp F11", "&kp F4", "&kp F5", "&kp F6", "&kp F10"], "C層 HF11 JF4 KF5 LF6 PF10"
assert fns[26:29] == ["&kp F1", "&kp F2", "&kp F3"], "C層 NF1 MF2 F3"

media = layers["media"]
assert media[5] == "&kp C_VOL_UP", "X層 Yは音量+"
assert media[6] == "&kp C_PREV", "X層 Uは前の曲"
assert media[7] == "&kp C_PP", "X層 Iは再生/停止"
assert media[8] == "&kp C_NEXT", "X層 Oは次の曲"

symbols = layers["layer_4"]
assert symbols[5:9] == ["&kp INTERNATIONAL_3", "&kp MINUS", "&kp EQUAL", "&kp LBKT"], "v層 Y¥ U- I= O["
assert symbols[15:20] == ["&kp LS(GRAVE)", "&kp SEMI", "&kp SQT", "&kp BSLH", "&kp RBKT"], "v層 H~ J; K' L\\ P]"
assert symbols[26:29] == ["&kp COMMA", "&kp DOT", "&kp FSLH"], "v層 N, M. /"
assert all(binding == "&trans" for binding in layers["drag_scroll"]), "スクロール中も他のキー操作を透過する"
print("成功: ZMKのS配列と主要なキー操作を確認しました。")
PY
