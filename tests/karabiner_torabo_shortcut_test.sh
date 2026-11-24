#!/usr/bin/env bash
set -euo pipefail

# キーボードごとに設定が適用され、Torabo のファームウェアの割り当てが保たれることを確認する。
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

# ZMK ではキー入力とカーソル操作が一つの機器として届くため、両方を Karabiner で受け取る。
torabo_identifiers = {
    "vendor_id": 65261, "product_id": 48301, "is_keyboard": True, "is_pointing_device": True
}
torabo_devices = [device for device in active.get("devices", []) if device["identifiers"] == torabo_identifiers]
assert len(torabo_devices) == 1 and torabo_devices[0].get("ignore") is False, "ZMK 版 Torabo のキー入力が変換の対象になっていません。"

def targets_torabo_only(manipulator):
    for condition in manipulator.get("conditions") or []:
        if condition.get("type") != "device_if":
            continue
        for ident in condition.get("identifiers") or []:
            if ident.get("vendor_id") == 65261 and ident.get("product_id") == 48301:
                return True
    return False

def excludes_torabo(manipulator):
    for condition in manipulator.get("conditions") or []:
        if condition.get("type") != "device_unless":
            continue
        for ident in condition.get("identifiers") or []:
            if ident.get("vendor_id") == 65261 and ident.get("product_id") == 48301:
                return True
    return False

for manipulator in changes:
    if targets_torabo_only(manipulator):
        continue
    assert excludes_torabo(manipulator), "Torabo 向け以外の Karabiner 変換が Torabo にも掛かっています。"

# 右 Shift の左隣のキーは、Torabo ではファームウェアの割り当てをそのまま使う。
assert not any(m["from"].get("key_code") == "international1" for m in active.get("simple_modifications", [])), (
    "全キーボードに適用されるハイフン変換が Torabo の INTERNATIONAL_1 を上書きしています。"
)
hyphen = [m for m in changes if m["from"].get("key_code") == "international1"]
assert len(hyphen) == 1 and excludes_torabo(hyphen[0]) and hyphen[0]["to"] == [{"key_code": "hyphen"}], (
    "Torabo 以外で右 Shift の左隣のキーがハイフンに変換されません。"
)
assert not any(c["type"] == "device_if" for c in hyphen[0]["conditions"]), (
    "右 Shift の左隣のキーの変換に追加の機種制限があります。"
)

fkeys_setting = "system.use_fkeys_as_standard_function_keys"

def matches_fkeys_setting(conditions, standard_fkeys):
    for condition in conditions:
        if condition.get("name") == fkeys_setting:
            equals = condition["value"] is standard_fkeys
            if equals != (condition["type"] == "variable_if"):
                return False
    return True

def check_function_key(manipulators, key, source):
    # macOS の設定のどちらでも、標準ファンクションキーになる出力が一つだけ必要。
    for standard_fkeys, modifiers in [(True, []), (False, ["fn"])]:
        outputs = [(event["key_code"], event.get("modifiers", []))
                   for m in manipulators if matches_fkeys_setting(m.get("conditions", []), standard_fkeys)
                   for event in m.get("to", []) if "key_code" in event
                   and matches_fkeys_setting(event.get("conditions", []), standard_fkeys)]
        assert outputs == [(key, modifiers)], f"{source}: {key} の出力が macOS の設定 {standard_fkeys} と合いません。"

# Torabo の標準 F キーと、他のキーボードの C レイヤーでの二通りの押し方を確認する。
c_layer_keys = ["n", "m", "comma", "j", "k", "l", "u", "i", "o", "p", "h", "y"]
for number, c_layer_key in enumerate(c_layer_keys, 1):
    fkey = f"f{number}"
    check_function_key([m for m in changes if targets_torabo_only(m) and m["from"].get("key_code") == fkey],
                       fkey, "Torabo")
    check_function_key([m for m in changes if m["from"].get("key_code") == c_layer_key
                        and any(c.get("name") == "c_held" and c["type"] == "variable_if" and c["value"] is True
                                for c in m.get("conditions", []))], fkey, "C を先に長押し")
    check_function_key([m for m in changes if m["from"].get("simultaneous") == [
        {"key_code": "c"}, {"key_code": c_layer_key}
    ]], fkey, "C と対象キーを続けて押す")

print("成功: キー一覧、ハイフン、標準ファンクションキーのキーボード別設定を確認しました。")
PY
