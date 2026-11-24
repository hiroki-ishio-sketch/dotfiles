// Vialプロトコル6のキーコード対応表を使い、保存済みの割り当てを表示名に変換する。
// https://github.com/vial-kb/vial-gui/blob/master/src/main/python/keycodes/keycodes_v6.py
const TORABO_BASIC_LABELS = {
  0x00: "×", 0x01: "▽", 0x28: "⏎", 0x29: "Esc", 0x2a: "⌫", 0x2b: "⇥", 0x2c: "空白",
  0x2d: "-", 0x2e: "=", 0x2f: "[", 0x30: "]", 0x31: "\\", 0x32: "非US #", 0x33: ";",
  0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/", 0x39: "Caps",
  0x46: "Print", 0x47: "Scroll", 0x48: "Pause", 0x49: "Insert", 0x4a: "Home", 0x4b: "PgUp",
  0x4c: "⌦", 0x4d: "End", 0x4e: "PgDn", 0x4f: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
  0x58: "テンキー⏎", 0x64: "非US \\", 0x87: "ろ", 0x88: "かな", 0x89: "¥", 0x8a: "変換", 0x8b: "無変換",
  0x90: "かな", 0x91: "英数", 0xa5: "電源", 0xa6: "スリープ", 0xa7: "復帰",
  0xa8: "消音", 0xa9: "音量+", 0xaa: "音量−", 0xae: "再生／停止", 0xb0: "⏏",
  0xcd: "マウス↑", 0xce: "マウス↓", 0xcf: "マウス←", 0xd0: "マウス→",
  0xd1: "クリック1", 0xd2: "クリック2", 0xd3: "クリック3", 0xd4: "クリック4", 0xd5: "クリック5",
  0xd9: "スクロール↑", 0xda: "スクロール↓", 0xdb: "スクロール←", 0xdc: "スクロール→",
  0xe0: "⌃", 0xe1: "⇧", 0xe2: "⌥", 0xe3: "⌘", 0xe4: "右⌃", 0xe5: "右⇧", 0xe6: "右⌥", 0xe7: "右⌘",
};

const TORABO_LAYER_ACTIONS = {
  0x5200: "切替", 0x5220: "長押し", 0x5240: "基本", 0x5260: "切替維持",
  0x5280: "次のキー", 0x52c0: "押下切替", 0x52e0: "基本を保存",
};

function buildToraboKeymap(configuration) {
  if (!configuration || configuration.model !== "Torabo-tsuki (S)" || configuration.source?.vial_protocol !== 6) {
    throw new Error("Torabo-tsuki (S)のVialプロトコル6の設定が必要です。");
  }
  const { keys, layers, custom_keycodes: custom = {} } = configuration;
  const coordinates = Array.isArray(keys) ? keys.map(toraboCoordinates) : [];
  if (coordinates.length !== 42 || new Set(keys.map((key) => key.id)).size !== 42) {
    throw new Error("Torabo-tsuki (S)の物理キー42個を重複なく指定してください。");
  }
  if (!Array.isArray(layers) || !layers.length || layers.length > 16) throw new Error("レイヤー数が不正です。");
  const visibleLayers = layers.map((layer, index) => {
    validateToraboLayer(layer);
    const codes = coordinates.map(([row, column]) => layer.matrix[row][column].toLowerCase());
    if (index > 0 && new Set(codes).size === 1 && ["0x0000", "0x0001"].includes(codes[0])) return null;
    const bindings = Object.fromEntries(keys.map(({id}, position) => [id, toraboKeyLabel(codes[position], custom)]));
    return { name: layer.name, bindings };
  }).filter(Boolean);
  return { name: configuration.model, summary: "▽ 透過 · × 未割り当て", keys, layers: visibleLayers };
}

function toraboCoordinates(key) {
  const match = /^([0-9]),([0-6])$/.exec(key?.id);
  if (!match || !Number.isFinite(key.x) || !Number.isFinite(key.y)) throw new Error("物理キーの座標が不正です。");
  return [Number(match[1]), Number(match[2])];
}

function validateToraboLayer(layer) {
  const matrix = layer?.matrix;
  if (typeof layer?.name !== "string" || !Array.isArray(matrix) || matrix.length !== 10 ||
      !matrix.every((row) => Array.isArray(row) && row.length === 7)) {
    throw new Error("各レイヤーには名前と、10行×7列のキーコードが必要です。");
  }
  if (!matrix.every((row) => row.every((code) => typeof code === "string" && /^0x[0-9a-f]{4}$/i.test(code)))) {
    throw new Error("キーコードは0xから始まる16進数4桁で指定してください。");
  }
}

function toraboKeyLabel(hex, custom) {
  if (typeof custom?.[hex] === "string") return custom[hex];
  const code = Number(hex);
  // Toraboから送る単独のF24は、Karabinerがキー一覧の表示に使う。
  if (code === 0x73) return "キー一覧";
  if (code <= 0xff) return toraboBasicLabel(code) ?? hex;
  const tap = toraboBasicLabel(code & 0xff);
  if (code < 0x2000 && tap !== undefined) {
    const modifier = (code >> 8) & 0x1f;
    const shifted = toraboShiftedSymbol(code & 0xff);
    if ((modifier === 2 || modifier === 0x12) && shifted) return shifted;
    return `${toraboModifierLabel(modifier)}${tap}`;
  }
  if (code >= 0x2000 && code < 0x4000 && tap !== undefined) {
    return `${tap}\n${toraboModifierLabel((code >> 8) & 0x1f)}`;
  }
  if (code >= 0x4000 && code < 0x5000 && tap !== undefined) return `${tap}\nL${(code >> 8) & 0xf}`;
  const action = TORABO_LAYER_ACTIONS[code & 0xffe0];
  if (action) return `L${code & 0x1f}\n${action}`;
  if ((code & 0xff00) === 0x5700) return `タップダンス${code & 0xff}`;
  if ((code & 0xff00) === 0x7700) return `マクロ${code & 0xff}`;
  return hex;
}

function toraboBasicLabel(code) {
  if (code >= 0x04 && code <= 0x1d) return String.fromCharCode(65 + code - 0x04);
  if (code >= 0x1e && code <= 0x27) return "1234567890"[code - 0x1e];
  if (code >= 0x3a && code <= 0x45) return `F${code - 0x39}`;
  if (code >= 0x68 && code <= 0x73) return `F${code - 0x68 + 13}`;
  return TORABO_BASIC_LABELS[code];
}

function toraboModifierLabel(flags) {
  const symbols = ["⌃", "⇧", "⌥", "⌘"].filter((_, bit) => flags & (1 << bit)).join("");
  return (flags & 0x10 ? "右" : "") + symbols;
}

function toraboShiftedSymbol(code) {
  if (code >= 0x1e && code <= 0x27) return "!@#$%^&*()"[code - 0x1e];
  return { 0x2d: "_", 0x2e: "+", 0x2f: "{", 0x30: "}", 0x31: "|", 0x33: ":", 0x34: '"',
    0x35: "~", 0x36: "<", 0x37: ">", 0x38: "?" }[code];
}
