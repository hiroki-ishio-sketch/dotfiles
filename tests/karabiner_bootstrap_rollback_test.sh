#!/usr/bin/env bash
set -euo pipefail

# 実際の Homebrew やユーザー設定を変更せず、失敗時の復元を検証する。
if [[ "${1:-}" != "--env=localdev" ]]; then
  echo "このテストは --env=localdev を指定して実行してください。" >&2
  exit 2
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import itertools
import os
import pathlib
import subprocess
import sys
import tempfile


def main():
    # 関数の本体をそのまま読み込み、実環境へ接続する入口だけを取り除く。
    source = pathlib.Path(sys.argv[1], ".bin/bootstrap-macos.sh").read_text()
    functions = source.rsplit('main "$@"', 1)[0]
    failures = []
    with tempfile.TemporaryDirectory(prefix="karabiner-bootstrap-test-") as temporary:
        root = pathlib.Path(temporary)
        for existing_cask, existing_hud, installer_failure in itertools.product((False, True), repeat=3):
            label = f"既存cask={existing_cask}, 既存HUD={existing_hud}, 導入途中失敗={installer_failure}"
            case = root / str(len(list(root.iterdir())))
            prepare_case(case, functions, existing_cask, existing_hud)
            result = run_case(case, installer_failure)
            if result.returncode != 23:
                failures.append(f"{label}: 想定外の終了コード {result.returncode}\n{result.stdout}{result.stderr}")
            if (case / "cask-karabiner-elements").exists() != existing_cask:
                failures.append(f"{label}: Karabiner の導入状態が復元されていません。")
            if (case / "hud-running").exists() != existing_hud:
                failures.append(f"{label}: HUD の起動状態が復元されていません。")
            if existing_hud and "stop" in (case / "hud-calls").read_text().splitlines():
                failures.append(f"{label}: 導入前から動いていた HUD を停止しています。")
    if failures:
        raise SystemExit("\n".join(failures))
    print("PASS: 初期構成の失敗時は新規 Karabiner と今回起動した HUD だけを復元します。")


def prepare_case(case, functions, existing_cask, existing_hud):
    # ホーム、実行コマンド、導入先をすべて一時フォルダーへ隔離する。
    (case / "bin").mkdir(parents=True)
    (case / "home").mkdir()
    (case / "dotfiles/.bin").mkdir(parents=True)
    (case / "bootstrap-functions.sh").write_text(functions)
    for name in ("wezterm", "font-udev-gothic-nf"):
        (case / f"cask-{name}").touch()
    if existing_cask:
        (case / "cask-karabiner-elements").touch()
    if existing_hud:
        (case / "hud-running").touch()
    (case / "hud-calls").touch()
    write_command(case / "bin/brew", '''
case "$1 $2" in
  "list --formula") [[ "$3" != "borders" ]] ;;
  "list --cask") [[ -f "$REVIEW_CASE/cask-$3" ]] ;;
  "install --cask") shift 2; for package in "$@"; do touch "$REVIEW_CASE/cask-$package"; done ;;
  "uninstall --cask") mv "$REVIEW_CASE/cask-$3" "$REVIEW_CASE/removed-$3" ;;
  *) exit 1 ;;
esac
''')
    write_command(case / "bin/nvim", "exit 23\n")
    write_command(case / "dotfiles/.bin/karabiner-keymap-hud", '''
printf '%s\\n' "$1" >> "$REVIEW_CASE/hud-calls"
case "$1" in
  status) if [[ -f "$REVIEW_CASE/hud-running" ]]; then echo 'running pid=123'; else echo stopped; fi ;;
  start) touch "$REVIEW_CASE/hud-running" ;;
  stop) if [[ -f "$REVIEW_CASE/hud-running" ]]; then mv "$REVIEW_CASE/hud-running" "$REVIEW_CASE/hud-stopped"; fi ;;
esac
''')
    write_command(case / "dotfiles/.bin/install-karabiner.sh", '''
if ! brew list --cask karabiner-elements; then brew install --cask karabiner-elements; fi
"$REVIEW_CASE/dotfiles/.bin/karabiner-keymap-hud" start
if [[ "$REVIEW_INSTALLER_FAILURE" == true ]]; then exit 23; fi
''')


def write_command(path, body):
    # 外部プログラムの代わりに、一時ファイルだけを更新する模擬コマンドを配置する。
    path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
    path.chmod(0o755)


def run_case(case, installer_failure):
    environment = os.environ.copy()
    environment.update(HOME=str(case / "home"), REVIEW_CASE=str(case),
                       REVIEW_INSTALLER_FAILURE=str(installer_failure).lower(),
                       PATH=str(case / "bin") + ":/usr/bin:/bin")
    # 実際と同じ失敗処理へ入り、今回取得した導入先を削除する前に HUD を停止できるかも確認する。
    script = '''
source "$REVIEW_CASE/bootstrap-functions.sh"
DOTFILES_DIR="$REVIEW_CASE/dotfiles"
DOTFILES_CREATED=true
trap 'handle_failure "$?" "$LINENO"' ERR
install_packages
install_karabiner
install_neovim_plugins
'''
    return subprocess.run(["/bin/bash", "-c", script], env=environment,
                          text=True, capture_output=True, timeout=180)


main()
PY
