#!/usr/bin/env bash
set -euo pipefail

readonly CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/config" && pwd -P)"
# 固定したZephyr 3.5用イメージには、ARM64版とx86_64版が含まれる。
readonly IMAGE='zmkfirmware/zmk-build-arm@sha256:840526f03c19c286b614d5cb97b11242ae19e468fc2ef2f095f6cf0465fa1c5b'
readonly WORKSPACE_MARKER='.torabo-zmk-workspace'

main() (
    if [[ "${1:-}" == --help ]]; then
        printf '使い方: bash %s [空のフォルダまたは前回のビルド作業フォルダ]\n' "$0"
        return
    fi
    if (( $# > 1 )); then
        printf '%s\n' '指定できる作業フォルダは1つです。' >&2
        return 2
    fi

    local docker_cli platform workspace lock_dir
    docker_cli="$(command -v docker || printf '%s' "$HOME/.docker/bin/docker")"
    if [[ ! -x "$docker_cli" ]]; then
        printf '%s\n' 'Dockerのコマンドが見つかりません。' >&2
        return 2
    fi
    platform="$(docker_platform "$docker_cli")" || return 2
    workspace="$(prepare_workspace "${1:-}")" || return 2

    # 同じ作業フォルダで同時にビルドすると取得済みソースと成果物が競合する。
    lock_dir="$workspace/.torabo-zmk-build.lock"
    if ! mkdir -- "$lock_dir" 2>/dev/null; then
        printf '%s\n' '作業フォルダは別のビルドが使用中です。' >&2
        return 2
    fi
    trap 'rmdir -- "$lock_dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf 'ビルド作業フォルダ %s\n' "$workspace"

    copy_configuration "$workspace"
    run_build "$docker_cli" "$platform" "$workspace"
)

docker_platform() {
    local server
    if ! server="$("$1" info --format '{{.OSType}}/{{.Architecture}}')"; then
        printf '%s\n' 'Dockerを起動し、ローカルのLinuxコンテナに接続してください。' >&2
        return 2
    fi
    case "$server" in
        linux/aarch64|linux/arm64) printf '%s\n' linux/arm64 ;;
        linux/x86_64|linux/amd64) printf '%s\n' linux/amd64 ;;
        *) printf 'このDocker環境には対応していません。%s\n' "$server" >&2; return 2 ;;
    esac
}

prepare_workspace() {
    local workspace="$1" parent
    if [[ -z "$workspace" ]]; then
        workspace="$(mktemp -d "${TMPDIR:-/tmp}/torabo-zmk-build.XXXXXX")" || return 2
    elif [[ ! -e "$workspace" && ! -L "$workspace" ]]; then
        # 明示された作業フォルダの親は既存のものを使用する。
        mkdir -- "$workspace" || return 2
    fi
    if [[ ! -d "$workspace" || -L "$workspace" || ! -O "$workspace" ]]; then
        printf '%s\n' '自分が所有する作業フォルダを指定してください。' >&2
        return 2
    fi
    workspace="$(cd -- "$workspace" && pwd -P)" || return 2
    parent="${workspace%/*}"
    while [[ -n "$parent" ]]; do
        if [[ -e "$parent/$WORKSPACE_MARKER" || -f "$parent/.west/config" ]]; then
            printf '%s\n' '別のビルド作業フォルダの内側は使用できません。' >&2
            return 2
        fi
        parent="${parent%/*}"
    done

    # 他用途のフォルダをコンテナに渡さない。以前の版で作成したフォルダは設定を照合する。
    shopt -s dotglob nullglob
    local entries=("$workspace"/*) marker="$workspace/$WORKSPACE_MARKER"
    if [[ -f "$marker" && ! -L "$marker" && "$(cat "$marker")" == 'torabo-zmk' ]]; then
        :
    elif [[ ${#entries[@]} == 0 ]] || {
        [[ "$workspace" == /private/tmp/torabo-zmk-build.* && -f "$workspace/.west/config" &&
            ! -e "$marker" && ! -L "$marker" ]] && cmp -s "$CONFIG_DIR/west.yml" "$workspace/config/west.yml"
    }; then
        printf '%s\n' torabo-zmk > "$marker" || return 2
    else
        printf '%s\n' '空のフォルダまたは前回のビルド作業フォルダを指定してください。' >&2
        return 2
    fi
    printf '%s\n' "$workspace"
}

copy_configuration() {
    local workspace="$1" path
    # リンク先への書き込みを避け、組み込み設定のソースだけを作業フォルダへコピーする。
    shopt -s nullglob
    for path in "$workspace"/* "$workspace/.west" "$workspace/config"/* "$workspace/firmware"/*; do
        if [[ -L "$path" ]]; then
            printf '%s\n' '作業フォルダにシンボリックリンクが含まれています。' >&2
            return 2
        fi
    done
    mkdir -p -- "$workspace/config" "$workspace/firmware"
    cp -- "$CONFIG_DIR/west.yml" "$CONFIG_DIR"/*.conf "$CONFIG_DIR"/*.dtsi \
        "$CONFIG_DIR"/*.keymap "$CONFIG_DIR"/*.overlay "$workspace/config/"
}

run_build() {
    local docker_cli="$1" platform="$2" workspace="$3" mount
    mount="type=bind,src=$workspace,dst=/workspace"
    if [[ "$workspace" == *,* || "$workspace" == *'"'* ]]; then
        mount="type=bind,\"src=${workspace//\"/\"\"}\",dst=/workspace"
    fi
    local -a sandbox=(--rm --platform "$platform" --cap-drop ALL --security-opt no-new-privileges
        --user "$(id -u):$(id -g)" --env HOME=/tmp --mount "$mount" -w /workspace)

    # 公式ソースを専用フォルダへ取得し、ビルドで使ったリビジョンを記録する。
    "$docker_cli" run "${sandbox[@]}" "$IMAGE" bash -ec '
        [[ -d .west ]] || west init -l config
        west update --narrow -o=--depth=1
        west manifest --freeze --active-only > resolved-west.yml
    '

    # ネットワークから切り離して、右のトラックボール側と左の子機をコンパイルする。
    "$docker_cli" run "${sandbox[@]}" --network none "$IMAGE" bash -ec '
        export ZEPHYR_BASE=/workspace/zephyr CMAKE_BUILD_PARALLEL_LEVEL=4
        west zephyr-export
        for half in right left; do
            role=()
            if [[ "$half" == right ]]; then
                role=(-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y)
            fi
            west build -p always -s zmk/app -d "build-$half" -b ble_micro_pro \
                -S studio-rpc-usb-uart -- -DZMK_CONFIG=/workspace/config \
                "-DSHIELD=torabo_tsuki_$half" "${role[@]}"
        done
        cp build-right/zephyr/zmk.uf2 firmware/torabo-tsuki-s-right-central.uf2
        cp build-left/zephyr/zmk.uf2 firmware/torabo-tsuki-s-left-peripheral.uf2
    '
    printf '左右のファームウェア %s/firmware\n' "$workspace"
}

main "$@"
