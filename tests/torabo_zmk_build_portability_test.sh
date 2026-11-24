#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != --env=localdev ]]; then
    printf '%s\n' '--env=localdev を指定してください。' >&2
    exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
builder="$root/.config/torabo-zmk/build-local.sh"
temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/torabo-zmk-test.XXXXXX")"
temp_dir="$(cd "$temp_dir" && pwd -P)"
trap 'rm -rf "$temp_dir"' EXIT
mkdir "$temp_dir/bin" "$temp_dir/自動作業先"
export PATH="$temp_dir/bin:$PATH" TMPDIR="$temp_dir/自動作業先"
export DOCKER_CALLS="$temp_dir/docker.log"

# Dockerの代わりに、サーバーの種類、マウント先、左右の出力とネットワーク設定を検証する。
cat > "$temp_dir/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    info) printf '%s\n' "$DOCKER_SERVER"; exit ;;
    run) shift ;;
    *) exit 2 ;;
esac
[[ "$*" == *"--platform $DOCKER_PLATFORM "* ]]
[[ "$*" == *'zmkfirmware/zmk-build-arm@sha256:840526f03c19c286b614d5cb97b11242ae19e468fc2ef2f095f6cf0465fa1c5b'* ]]
while [[ "$1" != --mount ]]; do shift; done
workspace="${2#type=bind,src=}"
workspace="${workspace%,dst=/workspace}"
[[ -f "$workspace/config/west.yml" ]]
if [[ "$DOCKER_WORKSPACE" == auto ]]; then
    [[ "$workspace" == "$TMPDIR"/torabo-zmk-build.* ]]
else
    [[ "$workspace" == "$DOCKER_WORKSPACE" ]]
fi
if [[ "$*" == *'west update'* ]]; then
    [[ "$*" != *'--network none'* ]]
    printf '%s\n' '取得' > "$workspace/resolved-west.yml"
else
    [[ "$*" == *'--network none'* ]]
    [[ "$*" == *'-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y'* ]]
    printf '%s\n' '右' > "$workspace/firmware/torabo-tsuki-s-right-central.uf2"
    printf '%s\n' '左' > "$workspace/firmware/torabo-tsuki-s-left-peripheral.uf2"
fi
printf '%s\n' "$workspace" >> "$DOCKER_CALLS"
MOCK
chmod +x "$temp_dir/bin/docker"

export DOCKER_SERVER=linux/x86_64 DOCKER_PLATFORM=linux/amd64
export DOCKER_WORKSPACE="$temp_dir/指定した 作業フォルダ"
bash "$builder" "$DOCKER_WORKSPACE" > "$temp_dir/success.log"
grep -Fq "$DOCKER_WORKSPACE/firmware" "$temp_dir/success.log"
test -s "$DOCKER_WORKSPACE/firmware/torabo-tsuki-s-right-central.uf2"
test -s "$DOCKER_WORKSPACE/firmware/torabo-tsuki-s-left-peripheral.uf2"
test -s "$DOCKER_WORKSPACE/resolved-west.yml"

# 一時作業先を安全に再利用でき、異なるアーキテクチャのDockerでも同じ成果物が得られる。
export DOCKER_SERVER=linux/aarch64 DOCKER_PLATFORM=linux/arm64
bash "$builder" "$DOCKER_WORKSPACE" > "$temp_dir/reused.log"
test "$(wc -l < "$DOCKER_CALLS" | tr -d ' ')" = 4

# 一時作業先の既定値には、実行環境で指定された一時ディレクトリを使う。
DOCKER_WORKSPACE=auto bash "$builder" > "$temp_dir/auto.log"
auto_workspace="$(tail -n 1 "$DOCKER_CALLS")"
test -s "$auto_workspace/firmware/torabo-tsuki-s-right-central.uf2"

refuse() {
    if bash "$builder" "$1" > "$temp_dir/refused.log" 2>&1; then
        printf '%s\n' "安全でない作業先またはDockerサーバーを受け入れました。$1" >&2
        exit 1
    fi
}

# 他用途のディレクトリやビルド作業先の子ディレクトリをコンテナに渡さない。
mkdir "$temp_dir/他の作業先" "$DOCKER_WORKSPACE/子ディレクトリ"
printf '%s\n' '保持する' > "$temp_dir/他の作業先/.設定"
refuse "$temp_dir/他の作業先"
refuse "$DOCKER_WORKSPACE/子ディレクトリ"
test "$(cat "$temp_dir/他の作業先/.設定")" = '保持する'
DOCKER_SERVER=windows/x86_64 refuse "$DOCKER_WORKSPACE"
DOCKER_SERVER=linux/s390x refuse "$DOCKER_WORKSPACE"
ln -s "$temp_dir/他の作業先/.設定" "$DOCKER_WORKSPACE/firmware/外部リンク"
refuse "$DOCKER_WORKSPACE"
test "$(cat "$temp_dir/他の作業先/.設定")" = '保持する'
test "$(wc -l < "$DOCKER_CALLS" | tr -d ' ')" = 6

printf '%s\n' '成功: Dockerのアーキテクチャの選択、作業フォルダの再利用、左右の出力を確認しました。'
