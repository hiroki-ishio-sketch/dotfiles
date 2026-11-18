#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_NAME="karabiner-elements"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DOTFILES_CONFIG_FILE="$DOTFILES_DIR/.config/karabiner/karabiner.json"
readonly DOTFILES_RULE_FILE="$DOTFILES_DIR/.config/karabiner/assets/complex_modifications/f_hjkl_arrows.json"
readonly HOME_CONFIG_FILE="$HOME/.config/karabiner/karabiner.json"

DRY_RUN=false
PACKAGE_PREEXISTING=false

main() {
  parse_arguments "$@"
  ensure_dotfiles_config_exists
  ensure_homebrew_available
  ensure_config_available
  install_karabiner_elements
  print_completion_message
}

parse_arguments() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      --env=localdev)
        # テスト実行時に明示する環境指定。通常の導入処理には影響させない。
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        fail "未対応の引数です: $1"
        ;;
    esac
    shift
  done
}

ensure_dotfiles_config_exists() {
  if [[ ! -f "$DOTFILES_CONFIG_FILE" ]]; then
    fail "Karabiner の設定ファイルが見つかりません: $DOTFILES_CONFIG_FILE"
  fi
  if [[ ! -f "$DOTFILES_RULE_FILE" ]]; then
    fail "Karabiner の complex modification が見つかりません: $DOTFILES_RULE_FILE"
  fi
}

ensure_homebrew_available() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "ドライランのため Homebrew の存在確認を省略します。"
    return
  fi

  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew が見つかりません。先に Homebrew をインストールしてください。"
  fi
}

ensure_config_available() {
  # install.sh が ~/.config 全体をリンク済みなら、その状態を確認するだけでよい。
  if [[ -e "$HOME_CONFIG_FILE" && "$HOME_CONFIG_FILE" -ef "$DOTFILES_CONFIG_FILE" ]]; then
    log_info "Karabiner の設定ファイルは既に dotfiles を参照しています。"
    return
  fi

  if [[ -L "$HOME/.config" ]]; then
    local config_target
    config_target="$(readlink "$HOME/.config")"
    if [[ "$config_target" == "$DOTFILES_DIR/.config" ]]; then
      log_info "Karabiner の設定は ~/.config 経由で dotfiles を参照します。"
      return
    fi
  fi

  log_info "Karabiner 設定を有効にするには、先に bash .bin/install.sh を実行してください。"
}

install_karabiner_elements() {
  if [[ "$DRY_RUN" != "true" ]] && brew list --cask "$PACKAGE_NAME" >/dev/null 2>&1; then
    PACKAGE_PREEXISTING=true
    log_info "[スキップ] cask は導入済みです: $PACKAGE_NAME"
    return
  fi

  run_command brew install --cask "$PACKAGE_NAME"
}

run_command() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return
  fi

  "$@"
}

print_usage() {
  cat <<'USAGE'
Usage: bash .bin/install-karabiner.sh [--dry-run] [--env=localdev]

Karabiner-Elements を Homebrew で導入し、dotfiles 管理の f+hjkl 矢印キー設定を使えるようにします。
USAGE
}

print_completion_message() {
  if [[ -x "$DOTFILES_DIR/.bin/karabiner-keymap-hud" ]]; then
    log_info "キーマップ HUD デーモンを起動します。"
    # 通常は常駐プログラムを起動し、ドライランでは実行予定だけを表示する。
    run_command "$DOTFILES_DIR/.bin/karabiner-keymap-hud" start || true
  fi
  log_info "Karabiner-Elements の導入手順が完了しました。"
  log_info "初回はシステム設定で Input Monitoring とアクセシビリティの許可が必要です。"
  log_info "許可後に Karabiner-Elements を起動すると、f 長押し中の hjkl が矢印キーになります。"
  if [[ "$PACKAGE_PREEXISTING" == "true" ]]; then
    log_info "設定変更後は Karabiner-Elements を再起動するか、設定の Reload を実行してください。"
  fi
}

log_info() {
  printf '[INFO] %s\n' "$1"
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

main "$@"
