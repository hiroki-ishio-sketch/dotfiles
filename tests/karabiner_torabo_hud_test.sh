#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "--env=localdev を指定してください。" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 実際のキー一覧と同じJavaScriptを隔離した環境で動かし、キー入力や画面操作を行わずに表示内容を検証する。
node - "$ROOT_DIR/.config/karabiner" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class Element {
  constructor() {
    this.children = [];
    this.classes = new Set();
    this.dataset = {};
    this.style = { setProperty: (name, value) => { this.style[name] = value; } };
    this.classList = {
      add: (name) => this.classes.add(name),
      remove: (name) => this.classes.delete(name),
      toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name),
    };
  }

  appendChild(element) { this.children.push(element); }
  replaceChildren() { this.children = []; }
}

function openKeymap(definition) {
  const config = process.argv[2];
  const html = fs.readFileSync(path.join(config, 'scripts/keymap-hud.html'), 'utf8');
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  const layers = new Element();
  const heading = new Element();
  const sub = new Element();
  const document = {
    body: new Element(),
    createElement: () => new Element(),
    getElementById: () => layers,
    querySelector: (selector) => selector === '#keymap-sub' ? sub : heading,
  };
  const window = {
    __KEYMAP_LAYERS__: JSON.parse(fs.readFileSync(path.join(config, 'keymap-layers.json'), 'utf8')),
    __TORABO_KEYMAP__: definition,
  };
  vm.runInNewContext(script, { window, document }, { timeout: 5000 });
  return { window, layers, heading, sub };
}

const options = {
  name: 'Torabo-tsuki (S)',
  summary: 'キーボードに保存した割り当て',
  keys: [{ id: 'left', x: -1, y: 1 }, { id: 'right', x: 5.25, y: 0 }],
  layers: [{ name: '通常', bindings: { left: 'F', right: 'B' } }, { name: '数字', bindings: { left: '1', right: '0' } }],
};
const { window, layers, heading, sub } = openKeymap(options);
assert.equal(layers.children.length, 4, '最初は従来のJISレイヤーを表示する');
window.__TORABO_BATTERY_SUBTITLE__ = '右 80% · 左 70%';
window.showKeymap('torabo');
assert.equal(heading.textContent, 'Torabo-tsuki (S)');
assert.match(sub.textContent, /右 80%/);
assert.equal(layers.children.length, 2, '設定にあるレイヤーをすべて表示する');
const [firstBoard, secondBoard] = layers.children;
assert.equal(firstBoard.children[0].children[0].textContent, '通常');
assert.equal(secondBoard.children[0].children[0].textContent, '数字');
const [left, right] = firstBoard.children[1].children;
assert.equal(left.textContent, 'F');
assert.equal(right.textContent, 'B');
assert.equal(left.style['--key-x'], '0');
assert.equal(right.style['--key-x'], '6.25');
assert.equal(right.style['--key-y'], '0');
assert.equal(secondBoard.children[1].children[0].textContent, '1');

window.showKeymap('jis');
assert.match(heading.textContent, /JIS/);
assert.equal(layers.children.length, 4, '切断後は従来のJISレイヤーへ戻る');

const manyLayers = openKeymap({ ...options, layers: Array.from({ length: 16 }, (_, index) => ({
  name: `レイヤー${index}`, bindings: { left: '<設定>', right: 'F12' },
})) });
manyLayers.window.showKeymap('torabo');
assert.equal(manyLayers.layers.children.length, 16);
assert.equal(manyLayers.layers.style['--torabo-columns'], '4');
assert.equal(manyLayers.layers.style['--torabo-rows'], '4');
assert.equal(manyLayers.layers.children[15].children[1].children[0].textContent, '<設定>');

for (const definition of [undefined, { ...options, keys: [] }, { ...options, layers: [] }, { ...options, layers: [null] }]) {
  const hud = openKeymap(definition);
  hud.window.showKeymap('torabo');
  assert.match(hud.heading.textContent, /JIS/);
  assert.equal(hud.layers.children.length, 4, 'Toraboの表示データがなければJISを維持する');
}
console.log('成功: 接続状態に応じてTorabo-tsuki (S)とJISの表示が切り替わります。');
JS
