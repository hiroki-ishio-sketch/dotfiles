#!/usr/bin/env bash
set -euo pipefail

# ローカルの設定ファイルだけを読み、実機やBluetoothの接続は操作しない。
[[ "${1:-}" == --env=localdev ]] || { printf '%s\n' '--env=localdev を指定してください。' >&2; exit 2; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
settings = root / '.config/torabo-zmk/config'
qmk = root / '.config/karabiner'
config = dict(line.split('=', 1) for line in
              (settings / 'torabo_tsuki.conf').read_text().splitlines()
              if line.startswith('CONFIG_'))
# 編集する値は固定せず、ファームウェアが受け付ける形式と範囲を確認する。
assert config['CONFIG_ZMK_SLEEP'] in {'y', 'n'}
if config['CONFIG_ZMK_SLEEP'] == 'y':
    assert int(config['CONFIG_ZMK_IDLE_SLEEP_TIMEOUT']) > 0
cpi = int(config['CONFIG_PMW3610_CPI'])
assert 200 <= cpi <= 3200 and cpi % 200 == 0
assert int(config['CONFIG_PMW3610_AUTOMOUSE_TIMEOUT_MS']) > 0

# 右親機だけが左の電池残量を取得し、Studioの保存機能は上流設定に従う。
battery_options = ('CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY',
                   'CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING')
assert all(option not in config for option in battery_options)
assert 'CONFIG_ZMK_KEYMAP_SETTINGS_STORAGE' not in config
right = (settings / 'torabo_tsuki_right.conf').read_text().splitlines()
assert all(f'{option}=y' in right for option in battery_options)

# 新旧ファームウェアで同じToraboとしてキー一覧を開けるよう、既存の機器条件と照合する。
rules = json.loads((qmk / 'assets/complex_modifications/f_hjkl_arrows.json').read_text())
ids = next(item for rule in rules['rules'] for mapping in rule['manipulators']
           for condition in mapping.get('conditions', [])
           for item in condition.get('identifiers', []) if item.get('is_keyboard') and 'vendor_id' in item)
for prefix in ('CONFIG_USB_DEVICE', 'CONFIG_BT_DIS_PNP'):
    assert int(config[f'{prefix}_VID'], 0) == ids['vendor_id']
    assert int(config[f'{prefix}_PID'], 0) == ids['product_id']
assert config['CONFIG_BT_DIS_PNP_VID_SRC'] == '2'

pointing = (settings / 'torabo-pointing.dtsi').read_text()
# マウスレイヤーは実在する公開レイヤーに設定できる。
automouse = re.search(r'automouse-layer\s*=\s*<([1-7])>', pointing)
assert automouse is not None
assert re.search(r'scroll-layers\s*=\s*<8>', pointing)

# BMP/Vialの保存領域は0xd6000以降にある。コードもZMKの設定領域もその手前に収める。
flash = (settings / 'ble_micro_pro.overlay').read_text()
regions = [tuple(int(number, 16) for number in match)
           for match in re.findall(r'reg\s*=\s*<(0x[0-9a-f]+)\s+(0x[0-9a-f]+)>', flash)]
assert len(regions) == 2
(code_start, code_size), (settings_start, settings_size) = regions
assert code_start == 0x26000 and code_start + code_size <= settings_start
assert settings_size >= 0x2000 and settings_start + settings_size <= 0xd6000
print('成功: ディープスリープ、機器識別子、トラックボール設定、BMPの保存領域の保護を確認しました。')
PY
