# Torabo-tsuki (S) のZMK設定

右手側にトラックボールがある通常版Torabo-tsuki (S) 用です。[製作者のZMK版](https://github.com/sekigon-gonnoc/zmk-keyboard-torabo-tsuki)を使い、右を親機、左を子機としてビルドします。

- [キー割り当て](config/torabo_tsuki.keymap) に8レイヤーと、ドラッグスクロール中だけ使うレイヤーを定義します。Fを保持してBを押すとF24が送られ、Macでキー一覧が開きます。
- [トラックボールの設定](config/torabo-pointing.dtsi) ではボールを動かしたときにレイヤー1へ入ります。[本体の設定](config/torabo_tsuki.conf) でカーソル分解能600、マウスレイヤーが有効な時間664ミリ秒、無操作から15分でのディープスリープを指定します。
- [記憶領域の設定](config/ble_micro_pro.overlay) はZMKの保存先を専用領域に移し、BMP/Vialの保存先と重なるのを防ぎます。Vialに戻すためのファームウェアと左右のバックアップは、ユーザー限定の `~/.local/share/torabo-firmware-backup/` に保管しました。
- Macのキー一覧は [Toraboの表示用データ](../karabiner/torabo-tsuki-s.json) を読みます。キーを変えるときはZMKのキー割り当てと表示データの両方に反映してください。ZMK StudioはUSB接続時に使えます。Studioで本体上だけを編集した変更はdotfilesに手動で反映してください。

## 設定を編集してビルドする

1. GitHubで `config/torabo_tsuki.keymap` を開き、変更するレイヤーのキーを書き換えます。カーソル速度や休止時間は `config/torabo_tsuki.conf` で変更できます。Macの一覧にも反映する場合は、同じ位置を [表示用のJSON](../karabiner/torabo-tsuki-s.json) に記録します。
2. mainに変更が入るとビルドが始まります。手動でビルドするときは [GitHub ActionsのToraboビルド](https://github.com/ishiooon/dotfiles/actions/workflows/torabo-zmk.yml) で「Run workflow」を選びます。
3. 成功した実行結果の「Artifacts」から `torabo-tsuki-s-firmware` をダウンロードします。ZIPには右親機と左子機の `.uf2` と、使った依存関係の一覧が入っています。

ブラウザからの編集・ビルドはMac、Windows、Linuxで同じ手順です。MacのF長押し＋Bによるキー一覧にはKarabiner-Elementsが必要です。Torabo本体では `F` 押し込み中の `N` が英数（ABC）、`M` がかな（あいう）です。内蔵キーボードでは Karabiner の `f+n` / `f+m` が同じ役割です。

### 手元でビルドする

MacはDocker Desktop、LinuxはDocker Engine、WindowsはDocker DesktopのWSL 2連携を有効にしたLinuxシェルを使います。Arm64とx86-64のDockerに対応しています。dotfilesのルートで実行します。

```sh
bash .config/torabo-zmk/build-local.sh
```

作業フォルダは実行時に表示されます。左右の `.uf2` はその中の `firmware/` に生成され、使ったソースの版は `resolved-west.yml` に残ります。以前の作業フォルダを引数にすると、取り込んだソースを再利用できます。

ZMK Studioで入力を保存したことがある場合は、再書き込み後も保存済みの割り当てが使われます。リポジトリの割り当てに戻すにはStudioで「Restore Stock Settings」を選びます。[ZMK Studioの公式手順](https://zmk.dev/docs/features/studio)

## ファームウェアの切り替え

左右を1台ずつUSB接続し、書き込みモードの `BLEMICROPRO` に、それぞれの役割の `.uf2` を転送します。この実機では転送後も書き込みドライブが残りました。転送が終わってからUSBを抜いて電源を切り、キーを押さずに挿し直すと、左右とも `Torabo-tsuki S` として起動しました。右だけがUSBキーボードとして入力を送ります。

左右の電源を入れ、最初は右をUSBで給電したままMacのBluetooth設定から `Torabo-tsuki S` に接続します。旧 `(BMP)torabo-tsuki` の登録と競合する場合は、Macでその機器の登録を解除してから再検索します。[ZMKのBluetooth接続の切り分け](https://zmk.dev/docs/troubleshooting/connection-issues)

接続がくるくるのまま進まないときは、Macから機器を削除したうえで、右をUSB接続したまま `B` を押しながら `D`（BT消去）→ `F`（プロファイル0）を押し、再度ペアします。settings reset ファームは、ブートローダに戻れないと復帰できないため常用しません。

### Bluetoothが繋がらないとき（settings reset）

Macの一覧に出ても接続がくるくるのまま進まないときは、左右のBluetooth記憶を消してから通常ファームを書き直します。ビルド成果物の `settings-reset-ble-micro-pro.uf2` を使います。

1. MacのBluetoothから `Torabo-tsuki S` を削除する。
2. 右をUSB接続し、ブートローダ（`BLEMICROPRO`）を起動して `settings-reset-ble-micro-pro.uf2` を入れる。
3. **USBを抜き → 電源オン → もう一度USBを挿す**（書き込みだけではリセットが完了しない）。
4. 左も同じ手順で settings reset する。
5. 右に `torabo-tsuki-s-right-central.uf2`、左に `torabo-tsuki-s-left-peripheral.uf2` を書き込む。
6. 左右の電源を入れ、右をUSB給電したままBluetoothで再ペアする。

ブートローダの出し方:

- **常用:** `B` を押しながら `P` でブートローダ（`BLEMICROPRO`）に入ります。通常の `P` 単体は文字入力のままです。
- **予備:** USB接続中にシリアルを1200bpsで開いて閉じる。`ls /dev/tty.usb*` でポートを確認し、`screen /dev/tty.usbmodem… 1200` のあと `Ctrl+a` → `k` → `y`。
- **settings reset 直後など、通常起動しないとき:** マイコンの BOOT と GND をショートしたままUSB接続します。

Bluetooth接続ではZMK版がキーボードとマウスの両方として認識されます。Karabinerはマウスを既定で処理対象から外すため、[Karabinerの設定](../karabiner/karabiner.json)ではこのToraboだけを明示的に処理対象にしています（F24のキー一覧以外の変換は掛けません）。ToraboのFを長押ししながらBを押すと、Bを押している間にキー一覧と左右の電池残量が表示されます。初回は Bluetooth 許可が必要なことがあり、残量は次回表示から埋まる場合があります。

## Vialに戻すとき

保持している `torabo-tsuki-vial-1.3.3.uf2` は、この実機と同じ版の純正ファームウェアです。左右を1台ずつ書き込みモードにしてこのファイルを転送し、起動後に同じ側のバックアップと `CONFIG.BIN`、`EEPROM.BIN` を照合します。EEPROMを再転送すると初期値の保存内容も現在値に更新されるため、再転送が必要か判断する前に `DEFAULT.BIN` も照合します。Bluetoothの再ペアリングが必要な場合は、Macに表示される機器を確認して接続します。[EEPROMの保存処理](https://github.com/sekigon-gonnoc/vial-qmk/blob/45aa1bf436/tmk_core/protocol/bmp/bmp_file.c#L31-L47)

## 実機で確認した操作

2026年11月24日、左右がZMKで起動し、USBを外した状態で左右の文字入力、ボールによるカーソル移動、Fを保持してBを押したときのToraboのキー一覧を確認しました。クリック、ドラッグスクロール、Consumer HIDに置き換えた電源・スリープキーは、個別の実機確認が残っています。

Toraboの操作直後にMacをスリープさせた試験では、30秒間画面が勝手に点きませんでした。ログにはバックグラウンド復帰がありましたが、前回のToraboのBluetooth通信による画面点灯は記録されませんでした。ディープスリープの15分はToraboの無操作時間で進みます。詳しい再現条件は [Macの復帰の調査記録](../karabiner/torabo-tsuki-s.md) を参照してください。
