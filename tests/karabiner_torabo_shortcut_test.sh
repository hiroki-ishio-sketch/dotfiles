#!/usr/bin/env bash
set -euo pipefail

# 内蔵と外付けで別の経路を使い、無関係なキーボードの F24 を変換しないことを確認する。
[[ "${1:-}" == --env=localdev ]] || { echo "--env=localdev を指定してください。" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
import json
from pathlib import Path
import sys

directory = Path(sys.argv[1]) / ".config/karabiner"
config = json.loads((directory / "karabiner.json").read_text())
active = next(profile for profile in config["profiles"] if profile["selected"])
rules = active["complex_modifications"]["rules"]
asset = directory / "assets/complex_modifications/f_hjkl_arrows.json"
assert rules == json.loads(asset.read_text())["rules"]
changes = [m for rule in rules for m in rule["manipulators"]]
external = [m for m in changes if m["from"].get("key_code") == "f24"]
assert len(external) == 1, "Torabo からの表示用キーが一意ではありません。"
shortcut = external[0]
assert shortcut["conditions"] == [{"type": "device_if", "identifiers": [
    {"vendor_id": 65261, "product_id": 48301, "is_keyboard": True}
]}], "Torabo 以外にも表示用キーが適用されています。"
assert shortcut["to"][0]["shell_command"].endswith("keymap-hud show'")
assert shortcut["to_after_key_up"][0]["shell_command"].endswith("keymap-hud hide'")
assert any(m["from"].get("key_code") == "b" and m.get("to", [{}])[0].get("shell_command", "").endswith("keymap-hud show'") for m in changes)

# ZMK ではキー入力とカーソル操作が一つの機器として届くため、その Torabo の入力が変換の対象になることを確認する。
torabo_identifiers = {
    "vendor_id": 65261, "product_id": 48301, "is_keyboard": True, "is_pointing_device": True
}
torabo_devices = [device for device in active.get("devices", []) if device["identifiers"] == torabo_identifiers]
assert len(torabo_devices) == 1 and torabo_devices[0].get("ignore") is False, "ZMK 版 Torabo のキー入力が変換の対象になっていません。"
print("成功: 既存の f + b と、Torabo の入力設定および表示・非表示指示を確認しました。")
PY
