#!/usr/bin/env bash
set -euo pipefail

# ローカル開発環境向けの実行指定が無い場合は失敗させ、誤実行を防止する。
if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "このテストは --env=localdev を指定して実行してください。" >&2
  exit 2
fi

# このテストファイルから見たプロジェクトルートを求める。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SCRIPT="$ROOT_DIR/.bin/install-karabiner.sh"

# インストール補助スクリプトが無い場合は、Karabiner の導入手順を再現できない。
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  echo "Karabiner のインストール補助スクリプトが見つかりません: $INSTALL_SCRIPT" >&2
  exit 1
fi

# 実行権限を確認し、手元のターミナルから直接呼び出せる状態を保つ。
if [[ ! -x "$INSTALL_SCRIPT" ]]; then
  echo "Karabiner のインストール補助スクリプトに実行権限がありません: $INSTALL_SCRIPT" >&2
  exit 1
fi

# 実際の Homebrew と常駐プログラムを呼ばないよう、一時配置した模擬環境で検証する。
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
FIXTURE="$TEMP_ROOT/dotfiles"
mkdir -p "$FIXTURE/.bin" "$FIXTURE/.config/karabiner/assets/complex_modifications" "$TEMP_ROOT/home" "$TEMP_ROOT/bin"
cp "$INSTALL_SCRIPT" "$FIXTURE/.bin/install-karabiner.sh"
printf '{}\n' > "$FIXTURE/.config/karabiner/karabiner.json"
printf '{}\n' > "$FIXTURE/.config/karabiner/assets/complex_modifications/f_hjkl_arrows.json"
cat > "$FIXTURE/.bin/karabiner-keymap-hud" <<'MOCK'
#!/usr/bin/env bash
# 常駐プログラムの代わりに、呼び出された引数を記録する。
printf '%s\n' "$*" >> "$HUD_CALLS"
MOCK
cat > "$TEMP_ROOT/bin/brew" <<'MOCK'
#!/usr/bin/env bash
# 未導入状態だけを再現し、実際のパッケージ管理には触れない。
printf '%s\n' "$*" >> "$BREW_CALLS"
[[ "${1:-}" != list ]]
MOCK
chmod +x "$FIXTURE/.bin/karabiner-keymap-hud" "$TEMP_ROOT/bin/brew"
export HOME="$TEMP_ROOT/home" HUD_CALLS="$TEMP_ROOT/hud-calls" BREW_CALLS="$TEMP_ROOT/brew-calls"
export PATH="$TEMP_ROOT/bin:$PATH"
OUTPUT="$(bash "$FIXTURE/.bin/install-karabiner.sh" --env=localdev --dry-run)"
if [[ -e "$HUD_CALLS" || -e "$BREW_CALLS" ]]; then
  echo "ドライランで Homebrew または常駐プログラムを実行しました。" >&2
  exit 1
fi

for expected in \
  "brew install --cask karabiner-elements" \
  "karabiner-elements"; do
  if ! grep -Fq "$expected" <<<"$OUTPUT"; then
    echo "ドライランに期待した手順が含まれていません: $expected" >&2
    echo "実際の出力:" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
done

# 通常の導入ではパッケージを導入し、常駐プログラムを一度だけ起動する。
bash "$FIXTURE/.bin/install-karabiner.sh" --env=localdev >/dev/null
if [[ "$(cat "$HUD_CALLS")" != start ]] || ! grep -Fxq 'install --cask karabiner-elements' "$BREW_CALLS"; then
  echo "通常導入で必要なパッケージ導入と一度だけの常駐起動が行われませんでした。" >&2
  exit 1
fi

echo "PASS: Karabiner のインストール補助スクリプトは Homebrew 導入手順を確認できます。"
