#!/usr/bin/env bash
# build.yaml の全ターゲットを、CI (build-user-config.yml) と同じ手順で Docker 上でビルドする。
#
#   bash scripts/build-local.sh            # 差分ビルド
#   PRISTINE=1 bash scripts/build-local.sh # ビルドディレクトリを作り直す
#
# west のワークスペースと成果物は、リポジトリの外の $ZMK_WS に置く
# （既定は ~/zmk-ws/<リポジトリ名>）。uf2 は $ZMK_WS/out に出る。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="${ZMK_WS:-$HOME/zmk-ws/$(basename "$REPO")}"
# ZMK フォークが Zephyr 3.5 系なので、イメージも 3.5 に固定する
IMAGE="${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:3.5}"

mkdir -p "$WS/out" "$WS/.home"

# 作業ツリーを CI の checkout と同じ状態（LF）にしてワークスペースへ写す。
# Windows 側の git が CRLF で展開していても、Kconfig や devicetree が壊れないようにする。
STAGE="$WS/.stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
(cd "$REPO" && git ls-files -z --cached --others --exclude-standard) |
    while IFS= read -r -d '' f; do
        [ -f "$REPO/$f" ] || continue
        case "$f" in firmware/*|*.uf2) continue ;; esac
        mkdir -p "$STAGE/$(dirname "$f")"
        sed 's/\r$//' "$REPO/$f" > "$STAGE/$f"
    done
mkdir -p "$WS/config" "$WS/module"
rsync -a --delete --checksum "$STAGE/config/" "$WS/config/"
rsync -a --delete --checksum "$STAGE/" "$WS/module/"
rm -rf "$STAGE"

cat > "$WS/.build-inner.sh" <<'INNER'
set -euo pipefail
cd /ws

[ -d .west ] || west init -l config

# west.yml が変わったときだけ依存を取り直す
stamp=.west-update.sha
now="$(sha256sum config/west.yml | cut -d' ' -f1)"
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$now" ]; then
    west update --fetch-opt=--filter=tree:0
    echo "$now" > "$stamp"
fi
west zephyr-export >/dev/null

python3 - <<'PY' > .targets
import yaml
for t in yaml.safe_load(open("module/build.yaml")).get("include", []):
    print(t["board"], t.get("shield", "-"), t.get("snippet", "-"))
PY

pristine=auto
[ "${PRISTINE:-0}" = 1 ] && pristine=always

while read -r board shield snippet; do
    name="${shield}-${board}-zmk"
    [ "$shield" = - ] && name="${board}-zmk"
    args=(-s zmk/app -d "build/$name" -b "$board" -p "$pristine")
    [ "$snippet" != - ] && args+=(-S "$snippet")
    cmake_args=(-DZMK_CONFIG=/ws/config -DZMK_EXTRA_MODULES=/ws/module)
    [ "$shield" != - ] && cmake_args+=(-DSHIELD="$shield")
    echo "=== $name ==="
    west build "${args[@]}" -- "${cmake_args[@]}"
    cp "build/$name/zephyr/zmk.uf2" "out/$name.uf2"
done < .targets

echo
ls -l out/
INNER

docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME=/ws/.home \
    -e PRISTINE="${PRISTINE:-0}" \
    -v "$WS:/ws" \
    -w /ws \
    "$IMAGE" \
    bash /ws/.build-inner.sh
