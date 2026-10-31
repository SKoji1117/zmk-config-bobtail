# ローカルビルド

GitHub Actionsと同じDockerイメージ、同じ`west`の手順で、`build.yaml`の全ターゲットをMacでビルドする手順。
2026-10-31に、Release v8（`8ad6dde`のビルド）の3つのuf2とバイト単位で一致することを確かめた。

- Rancher Desktopを起動し、`bash scripts/build-local.sh`を実行するとuf2ができる。
- 初回は3分20秒、2回目以降の差分ビルドは16秒だった。
- イメージはCIが使う`zmkfirmware/zmk-build-arm:stable`をダイジェストで固定してある。CI側の`stable`が更新されたら、スクリプトのダイジェストを書き換える。

Windows（WSL）で回すときの手順はREADMEの「ビルド」にある。
スクリプトは同じものを使う。

## 前提

確かめた環境は次のとおり。

| 項目 | 内容 |
| --- | --- |
| Mac | Apple Silicon（arm64）、macOS 27.2 |
| Docker | Rancher Desktop。コンテナエンジンはdockerd（moby）、VMはCPU 2、メモリ6GB |
| シェルの設定 | `~/.zshrc`で`PATH`に`~/.rd/bin`を足し、`DOCKER_HOST`を`unix://$HOME/.rd/docker.sock`に向けている |
| ディスク | ワークスペースに2.2GB、イメージに3GB |

Dockerが動けばRancher Desktop以外でもよいが、確かめたのはRancher Desktopだけである。

## 初回の準備

Rancher Desktopを起動し、新しく開いたターミナルで`docker`がVMにつながることを確かめる。

```sh
docker info --format '{{.OperatingSystem}} {{.Architecture}} CPU={{.NCPU}}'
# Alpine Linux v3.24 aarch64 CPU=2
```

`docker`と`docker-credential-osxkeychain`は、Rancher Desktopが作る`~/.rd/bin`に入る。
`~/.zshrc`は`~/.rd/bin`があるときだけ`PATH`に足すので、`~/.rd/bin`ができる前に開いたターミナルでは`docker`が見つからない。
そのときはターミナルを開き直す。

ビルド用のイメージは、初回のビルドで自動で取得される（3GBほど）。

## ビルドする

リポジトリのルートで実行する。

```sh
ZMK_WS=~/zmk-ws/zmk-config-bobtail bash scripts/build-local.sh            # 差分ビルド
ZMK_WS=~/zmk-ws/zmk-config-bobtail PRISTINE=1 bash scripts/build-local.sh # ビルドディレクトリを作り直す
```

`ZMK_WS`はwestのワークスペースの置き場所で、既定は`~/zmk-ws/<リポジトリのディレクトリ名>`になる。
Orcaのworktreeのようにディレクトリ名がリポジトリ名と違う場所で実行すると、既定のままでは別のワークスペースができ、west updateからやり直しになる。
`ZMK_WS`を付けておけば、どこから実行しても同じワークスペースを使う。

uf2は`$ZMK_WS/out/`に出る。

```sh
open ~/zmk-ws/zmk-config-bobtail/out
```

かかった時間は次のとおり（Rancher Desktop、CPU 2）。

| 場面 | 時間 |
| --- | --- |
| 初回（west updateと3ターゲットのビルド） | 3分20秒 |
| 2回目以降の差分ビルド | 16秒 |
| `PRISTINE=1`で作り直す | 54秒 |

west updateは、`config/west.yml`が前回から変わったときだけ走る。

## CIとの対応

CIの手順は、`.github/workflows/blank.yml`から呼ぶ`zmkfirmware/zmk`の`build-user-config.yml`（v0.3.0、`edf5c08`）にある。
`scripts/build-local.sh`は、そのビルドジョブを次のように再現する。

| CIのステップ | ローカル |
| --- | --- |
| `zmkfirmware/zmk-build-arm:stable`のコンテナで動く | 同じイメージをダイジェストで固定して使う |
| `config/`を一時ディレクトリに写し、リポジトリ全体をモジュールとして渡す | `config/`を`$ZMK_WS/config`に、リポジトリ全体を`$ZMK_WS/module`に写す |
| `west init -l config` | 同じ |
| `west update --fetch-opt=--filter=tree:0` | 同じ。`west.yml`が変わったときだけ |
| `west zephyr-export` | 同じ |
| `west build -s zmk/app -b <board> [-S <snippet>] -- -DZMK_CONFIG=... -DSHIELD=<shield> -DZMK_EXTRA_MODULES=...` | 同じ引数。ビルドディレクトリは使い回す（`-p auto`） |
| `zmk.uf2`を`<shield>-<board>-zmk.uf2`に改名してアーティファクトに置く | 同じ名前で`$ZMK_WS/out/`に置く |

CIと違う点は次の4つ。

- CIのランナーはamd64で、Apple Siliconではarm64のイメージが使われる。どちらも同じダイジェストのマルチアーキテクチャのイメージで、Zephyr SDKは0.16.9で同じ。2026-10-31の時点で、できたuf2はCIと一致した。
- Releaseへのタグ付けとuf2の添付（`blank.yml`の`release`ジョブ）は、ローカルでは行わない。
- スクリプトは`build.yaml`の`board`、`shield`、`snippet`だけを読む。`cmake-args`と`artifact-name`を`build.yaml`に足すときは、スクリプトにも足す必要がある。
- コミットしていないファイルもビルドに入る。`.gitignore`で除外したファイルと`*.uf2`は入らない。

## CIと同じuf2ができたか確かめる

最新のReleaseのuf2を落とし、ローカルの成果物と比べる。
Releaseはmainの最新のビルドなので、手元がmainの最新と同じコミットのときだけ一致する。

```sh
gh release download -R SKoji1117/zmk-config-bobtail -p '*.uf2' -D /tmp/zmk-release --clobber
cd ~/zmk-ws/zmk-config-bobtail/out
for f in *.uf2; do cmp -s "$f" "/tmp/zmk-release/$f" && echo "一致 $f" || echo "不一致 $f"; done
```

## ビルドイメージを更新するとき

`scripts/build-local.sh`の`IMAGE`は、2026-10-15のCIのログにあった`stable`のダイジェスト（`sha256:edb1c953…`）で固定してある。
CIは`stable`タグをそのまま使うので、タグが更新されるとCIだけ新しいイメージに変わる。

CIが使ったダイジェストは、ビルドジョブのログの「Initialize containers」に出る。

```sh
gh run list -R SKoji1117/zmk-config-bobtail -L 1 --json databaseId -q '.[0].databaseId'
gh run view <上で出たID> -R SKoji1117/zmk-config-bobtail --log | grep -m1 'Digest:'
```

ダイジェストが変わっていたら、`IMAGE`を書き換え、上の比較で一致を確かめる。

`zmk-build-arm:3.5`タグは使わない。
ZMKのフォークがZephyr 3.5系でも、`3.5`タグのSDKは0.16.3で、CIと違うuf2ができる（2026-10-31に3ファイルとも不一致を確かめた）。

## つまずいたこと

`docker pull`か`docker run`で次のエラーが出たら、`PATH`に`~/.rd/bin`が無い。
ターミナルを開き直す。

```text
error getting credentials - err: exec: "docker-credential-osxkeychain": executable file not found in $PATH
```

`docker context use`で次の警告が出るのは、`~/.zshrc`の`DOCKER_HOST`がcontextより優先されるため。
Rancher Desktop以外のDockerを使うときは、`DOCKER_HOST`を外す。

```text
Warning: DOCKER_HOST environment variable overrides the active context.
```
