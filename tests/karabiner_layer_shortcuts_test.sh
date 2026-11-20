#!/usr/bin/env bash
set -euo pipefail

# ローカル開発環境の指定を求め、設定ファイルの読み取りだけで検証する。
if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "このテストは --env=localdev を指定して実行してください。" >&2
  exit 2
fi

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import json
import sys
from pathlib import Path

# 数字と記号の出力は、設定ファイルの値ではなく利用者向けのキー配列から定義する。
LAYER_OUTPUTS = {
    "d": {
        "n": "1", "m": "2", "comma": "3", "j": "4", "k": "5",
        "l": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    },
    "v": {
        "n": "comma", "m": "period", "comma": "slash", "j": "semicolon",
        "k": "quote", "l": "backslash", "u": "hyphen", "i": "equal_sign",
        "o": "open_bracket", "p": "close_bracket", "h": "grave_accent_and_tilde",
        "y": "international3",
    },
}
SIDED_MODIFIERS = ("command", "control", "option", "shift")
ACCEPTED_MODIFIERS = (
    (), ("caps_lock",), ("left_shift",), ("right_shift",),
    ("caps_lock", "left_shift"), ("caps_lock", "right_shift"),
)


def main():
    # 有効なプロファイルと配布用ルールを照合し、片方だけ修正されることを防ぐ。
    directory = Path(sys.argv[1]) / ".config" / "karabiner"
    config = json.loads((directory / "karabiner.json").read_text(encoding="utf-8"))
    asset = directory / "assets" / "complex_modifications" / "f_hjkl_arrows.json"
    distributed = json.loads(asset.read_text(encoding="utf-8"))
    selected = next(profile for profile in config["profiles"] if profile["selected"])
    rules = selected["complex_modifications"]["rules"]
    assert rules == distributed["rules"], "有効な設定と配布用ルールが一致しません。"

    manipulators = [manipulator for rule in rules for manipulator in rule["manipulators"]]
    for layer, outputs in LAYER_OUTPUTS.items():
        for key, output in outputs.items():
            verify_chord(manipulators, layer, key, output)
    print("成功: d/v の同時押しで数字と記号を入力でき、通常のショートカットも維持されます。")


def verify_chord(manipulators, layer, key, output):
    # Shift の記号入力を維持し、左右の Command、Control、Option では同時押しを変換しない。
    expected = {"key_code": output}
    if (layer, key) == ("v", "h"):
        expected["modifiers"] = ["left_shift"]
    for modifiers in ACCEPTED_MODIFIERS:
        result = chord_outputs(manipulators, (layer, key), modifiers)
        assert result == [expected], f"{modifiers} {layer}+{key} の出力が {result} です。期待値は {expected} です。"

    for modifier in SIDED_MODIFIERS:
        if modifier == "shift":
            continue
        for side in ("left", "right"):
            named = f"{side}_{modifier}"
            for modifiers in ((named,), (named, "left_shift")):
                result = chord_outputs(manipulators, (layer, key), modifiers)
                assert not result, f"{modifiers} {layer}+{key} が {result} に変換され、ショートカットと競合します。"


def chord_outputs(manipulators, keys, modifiers):
    # キーが順に押されて重なった場合に一致するルールについて、変数設定を除いたキー出力を求める。
    chord = tuple(keys)
    for manipulator in manipulators:
        source = manipulator["from"]
        inputs = tuple(event.get("key_code") for event in source.get("simultaneous", ()))
        if inputs != chord or not modifiers_match(source.get("modifiers", {}), modifiers):
            continue
        return [event for event in manipulator["to"] if "key_code" in event]
    return []


def modifiers_match(specification, modifiers):
    # Karabiner の左右共通指定は左右どちらにも一致する。optional にない余分な修飾キーは許可されない。
    active = set(modifiers)
    optional = expand_sides(specification.get("optional", ()))
    mandatory = specification.get("mandatory", ())
    if any(not (active & expand_sides((modifier,))) for modifier in mandatory):
        return False
    return "any" in optional or active <= optional | expand_sides(mandatory)


def expand_sides(modifiers):
    return {
        name
        for modifier in modifiers
        for name in (
            (f"left_{modifier}", f"right_{modifier}")
            if modifier in SIDED_MODIFIERS else (modifier,)
        )
    }


if __name__ == "__main__":
    main()
PY
