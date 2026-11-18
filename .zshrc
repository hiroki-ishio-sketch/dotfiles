# 分割された設定ファイルを読み込む
source ~/.zsh/env.zsh         # 環境変数の設定
source ~/.zsh/history.zsh     # 履歴設定
source ~/.zsh/keybindings.zsh # キーバインディング設定
source ~/.zsh/functions.zsh   # 関数定義
source ~/.zsh/aliases.zsh     # エイリアス定義

# starshipの呼び出し
eval "$(starship init zsh)"

alias gh='command gh'

# bun の補完。未インストールなら何もしない。
if [[ -n "$BUN_INSTALL" && -s "$BUN_INSTALL/_bun" ]]; then
  source "$BUN_INSTALL/_bun"
fi
