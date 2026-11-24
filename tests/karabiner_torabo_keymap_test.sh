#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "--env=localdev を指定してください。" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 読み出したキーマップを実機に送らず、キー一覧用の表示名と座標に変換する。
node - "$ROOT_DIR/.config/karabiner" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const configDir = process.argv[2];
const source = JSON.parse(fs.readFileSync(path.join(configDir, 'torabo-tsuki-s.json'), 'utf8'));
const model = {};
vm.runInNewContext(fs.readFileSync(path.join(configDir, 'scripts/torabo-keymap-model.js'), 'utf8'), model, { timeout: 5000 });
const render = (config) => model.buildToraboKeymap(config);
const copy = () => structuredClone(source);

const output = render(source);
assert.equal(output.name, 'Torabo-tsuki (S)');
assert.equal(output.keys.length, 42, 'Sの物理キーだけを表示する');
assert.equal(new Set(output.keys.map(({id}) => id)).size, 42);
assert.equal(output.layers.length, 9, '基本〜マウス固定とメディアを表示する（スクロール層は透過のみなので省く）');
assert.ok(output.keys.find(({id}) => id === '1,4').x < output.keys.find(({id}) => id === '6,3').x);
assert.ok(!output.keys.some(({id}) => id === '0,0'), '外列と仮想エンコーダを表示しない');
assert.equal(output.layers[0].bindings['1,4'], 'F\nL2');
assert.equal(output.layers[0].bindings['2,5'], 'B\nL6');
assert.equal(output.layers[0].bindings['2,2'], 'X\nL9', 'X長押しはメディア層');
assert.equal(output.layers[0].bindings['5,2'], 'O', 'Oは文字のみ');
assert.equal(output.layers[0].bindings['5,1'], 'L8\n長押し', 'Oの右・Pの上はスクロール');
assert.equal(output.layers[0].bindings['4,6'], '空白\n⇧');
assert.equal(output.layers[1].bindings['6,4'], 'クリック1');
assert.equal(output.layers[1].bindings['6,3'], 'クリック2');
assert.equal(output.layers[1].bindings['7,3'], 'L8\n長押し', 'マウス層のNはスクロール');
assert.equal(output.layers[3].bindings['5,1'], '×');
assert.equal(output.layers[3].bindings['0,1'], '▽');
assert.equal(output.layers[6].bindings['6,5'], '|');
assert.equal(output.layers[8].name, 'L9 メディア');
assert.equal(output.layers[8].bindings['5,5'], '音量+');

const edited = copy();
edited.layers[0].matrix[1][4] = '0xffff';
assert.equal(render(edited).layers[0].bindings['1,4'], '0xffff', '未知のキーコードを失わない');
edited.layers[2].matrix[2][5] = '0x0073';
assert.equal(render(edited).layers[2].bindings['2,5'], 'キー一覧', 'Torabo専用の表示操作と分かる名前にする');
edited.layers[7].matrix = edited.layers[7].matrix.map((row) => row.map(() => '0x0001'));
// L7とL8（スクロール）が省かれ、L0–L6とL9メディアが残る
assert.equal(render(edited).layers.length, 8, '透明キーだけのレイヤーは表示を省く');

const invalid = copy();
invalid.layers[0].matrix[1][4] = 'bad';
assert.throws(() => render(invalid), /キーコード/);
assert.throws(() => render({ ...source, model: '別のキーボード' }), /Torabo-tsuki/);
console.log('成功: Torabo-tsuki (S)の実機レイヤー、物理位置、キーコードの表示を確認しました。');
JS
