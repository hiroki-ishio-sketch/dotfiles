#!/usr/bin/env bash
set -euo pipefail

# 実環境での誤実行を防ぎ、プロセス操作を模擬したローカル検証だけを許可する。
[[ "${1:-}" == --env=localdev ]] || { echo "--env=localdev を指定してください。" >&2; exit 2; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
export XDG_CACHE_HOME="$TEMP_ROOT/cache" HUD_TEST_CALLS="$TEMP_ROOT/calls"
export BASH_ENV="$TEMP_ROOT/mock-environment"
STATE_DIR="$XDG_CACHE_HOME/karabiner-keymap-hud"
mkdir -p "$STATE_DIR"
cat > "$BASH_ENV" <<'MOCK'
# シグナルは送信せず、プロセスの照合結果と停止要求だけを再現する。
kill() { printf 'kill %s\n' "$*" >> "$HUD_TEST_CALLS"; return 0; }
ps() {
  # 長い実行コマンドは、幅制限を解除しない場合に端末幅で切り詰められる状態を再現する。
  case " $* " in
    *' -ww '*|*' ww '*) printf '%s\n' "$HUD_TEST_PROCESS" ;;
    *) printf '%.80s\n' "$HUD_TEST_PROCESS" ;;
  esac
}
pkill() { printf 'pkill %s\n' "$*" >> "$HUD_TEST_CALLS"; }
sleep() { :; }
MOCK
printf '12345\n' > "$STATE_DIR/daemon.pid"
printf 'idle\n' > "$STATE_DIR/command"

# 保存した番号が別のプロセスへ再利用されても、実行中と誤認しない。
export HUD_TEST_PROCESS='/usr/bin/sleep 100'
if [[ "$(bash "$ROOT_DIR/.bin/karabiner-keymap-hud" status)" != stopped ]]; then
  echo "無関係なプロセスを常駐プログラムと誤認しました。" >&2
  exit 1
fi
bash "$ROOT_DIR/.bin/karabiner-keymap-hud" stop
if grep -Eq '^kill 12345$|^pkill ' "$HUD_TEST_CALLS"; then
  echo "無関係なプロセスへの停止要求を出しました。" >&2
  exit 1
fi

# 一致する常駐プログラムには終了を通知し、その番号だけに停止要求を送る。
printf '12345\n' > "$STATE_DIR/daemon.pid"
export HUD_TEST_PROCESS="/usr/bin/osascript -l JavaScript $ROOT_DIR/.config/karabiner/scripts/keymap-hud.js daemon $ROOT_DIR/.config/karabiner/scripts/keymap-hud.html $ROOT_DIR/.config/karabiner/keymap-layers.json $STATE_DIR/daemon.pid $STATE_DIR/command"
if [[ "$(bash "$ROOT_DIR/.bin/karabiner-keymap-hud" status)" != 'running pid=12345 cmd=idle' ]]; then
  echo "対応する常駐プログラムを実行中と判定できませんでした。" >&2
  exit 1
fi
bash "$ROOT_DIR/.bin/karabiner-keymap-hud" stop
if ! grep -Fxq 'kill 12345' "$HUD_TEST_CALLS" || grep -q '^pkill ' "$HUD_TEST_CALLS"; then
  echo "対応する常駐プログラムだけに停止要求を送れませんでした。" >&2
  exit 1
fi
echo "PASS: キーマップ表示はプロセスの一致を確認して停止します。"
