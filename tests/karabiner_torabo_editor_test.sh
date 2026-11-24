#!/usr/bin/env bash
set -euo pipefail

# 実機の設定を変更しない検証であることを明示した場合だけ実行する。
if [[ "${1:-}" != --env=localdev ]]; then
  echo "--env=localdev を指定してください。" >&2
  exit 2
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d /private/tmp/torabo-editor-test.XXXXXX)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

# 無効な入力だけを渡し、機器の接続処理へ到達する前に拒否されることを確認する。
python3 - "$ROOT_DIR" "$TEMP_ROOT" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
source = root / '.config/karabiner/scripts/torabo-keymap-device.swift'
binary = temporary / 'torabo-keymap-device'
subprocess.run(['swiftc', '-module-cache-path', str(temporary / 'modules'), str(source), '-o', str(binary)],
               check=True, timeout=180)
fixture = json.loads((root / '.config/karabiner/torabo-vial-keymap.json').read_text())
display = json.loads((root / '.config/karabiner/torabo-tsuki-s.json').read_text())
assert len(fixture['layers']) == 8, '旧BMP/Vial向けの取得済み設定を8層のまま保存する'
assert fixture['layers'][2]['matrix'][2][5] == '0x0073', '実機から取得したキー割り当てを保持する'
config = temporary / 'settings.json'


def reject(arguments, message):
    result = subprocess.run([str(binary), *arguments], capture_output=True, text=True, timeout=5)
    assert result.returncode != 0, f'無効な指定を成功として扱いました: {arguments}'
    assert message in result.stderr, result.stderr
    assert not result.stdout, '失敗した処理が機器データを出力しました。'


def write_fixture(value):
    config.write_text(json.dumps(value))


reject([], '使い方')
reject(['write'], '使い方')
reject(['read', 'extra'], '使い方')
reject(['apply-key'], '使い方')
write_fixture(fixture)
base = ['apply-key', str(config), '2', '2', '5', '0x0001']
for index, value in [(2, '8'), (2, '-1'), (3, '10'), (3, '-1'), (4, '7'), (4, '-1')]:
    arguments = base.copy()
    arguments[index] = value
    reject(arguments, '範囲')
for value in ['0x10000', '0xGGGG', '1', '0x1']:
    reject([*base[:-1], value], 'キーコード')
reject(['apply-key', str(config), '2', '3', '0', '0x0001'], '物理キー')

# 表示用のZMKデータはレイヤーを減らしてもVial設定として使えない。
write_fixture(display)
reject(base, 'ZMK')
display['layers'] = display['layers'][:8]
write_fixture(display)
reject(base, 'ZMK')

# 他のセルに不正な値があっても、設定全体を検証してから一件の反映を開始する。
for mutation, expected in [
    (lambda value: value.__setitem__('layers', value['layers'][:7]), '8'),
    (lambda value: value['layers'].append(copy.deepcopy(value['layers'][0])), '8'),
    (lambda value: value['layers'][0]['matrix'].pop(), '10'),
    (lambda value: value['layers'][0]['matrix'][0].pop(), '7'),
    (lambda value: value['layers'][0]['matrix'][0].__setitem__(0, '0x10000'), 'キーコード'),
    (lambda value: value['keys'].append({'id': '3,0'}), '物理キー'),
    (lambda value: value['keys'].append(copy.deepcopy(value['keys'][0])), '物理キー'),
]:
    invalid = copy.deepcopy(fixture)
    mutation(invalid)
    write_fixture(invalid)
    reject(base, expected)
config.write_text('{')
reject(base, 'JSON')

# 本番と同じ反映処理にメモリー上の読取・保存を渡し、不一致時や失敗時の操作回数を確認する。
harness = temporary / 'main.swift'
harness.write_text(source.read_text() + '\n' + r'''
import Foundation
let configuration = CommandLine.arguments[1]
let operation = try parseArguments(["apply-key", configuration, "2", "2", "5", "0x0001"])
if case let .apply(layer, row, column, expected, desired) = operation {
    precondition(layer == 2 && row == 2 && column == 5 && expected == 1 && desired == 0x73)
} else {
    preconditionFailure("旧BMP/Vial設定から指定した1件を読み込めませんでした。")
}

func scenario(_ initial: UInt16, _ expected: UInt16, _ value: UInt16, _ stored: UInt16?, _ succeeds: Bool, _ writes: Int) {
    var current = initial, saves: [UInt16] = []
    do {
        try applyKey(expected: expected, value: value, get: { current }, set: {
            saves.append($0)
            current = stored ?? $0
        })
        precondition(succeeds, "失敗するはずの反映が成功しました。")
    } catch { precondition(!succeeds, "成功するはずの反映が失敗しました。") }
    precondition(saves.count == writes, "書き込み回数が期待と一致しません。")
    if writes > 0 { precondition(saves == [value], "指定値以外を保存しました。") }
}
scenario(1, 2, 0x73, nil, false, 0)
scenario(1, 1, 1, nil, true, 0)
scenario(1, 1, 0x73, nil, true, 1)
scenario(1, 1, 0x73, 2, false, 1)
print("成功: 変更前の不一致は保存ゼロ、同値は保存ゼロ、変更は一度だけで直後に照合しました。")
''')
simulation = temporary / 'offline-scenarios'
subprocess.run(['swiftc', '-D', 'TORABO_OFFLINE_TEST', '-module-cache-path', str(temporary / 'modules'),
                str(harness), '-o', str(simulation)], check=True, timeout=180)
subprocess.run([str(simulation), str(root / '.config/karabiner/torabo-vial-keymap.json')], check=True, timeout=5)
print('成功: Toraboの無効な操作、範囲外、物理キー以外、不正な設定を実機接続前に拒否しました。')
PY
