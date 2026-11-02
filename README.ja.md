# rm9-windows-arm64(日本語版)

[English](README.md)

**RedMagic 9 Pro(ZTE/nubia NX769J、Snapdragon 8 Gen 3 / SM8650)** で Windows 11 ARM64 を動かすプロジェクトです。スマホの Android から、自作の UEFI 経由で Windows を起動します。このリポジトリは、その作業台です。UEFI の中で動く下回りのコード、Windows 用に書いたカーネルドライバ、ACPI のパッチ、PC 側のリンク、そして「何が壊れて、なぜ壊れたか」の記録を置いています。

製品ではなく、研究の記録です。端末固有のオフセットや一回限りのスクリプトが多く、書かれた 1 台の端末でしか動かないものもあります。

## 状況(2026-11)

| 領域 | 状態 |
|---|---|
| 起動 | スマホ単体で Windows 11 ARM64 が起動する(Android で `su -c boot_windows.sh`、Windows を再起動すると Android に戻る)。ゲストは 2 つ: ビルド 28000(26H1)と、VHDX に入れたきれいな 24H2(ビルド 26100) |
| ストレージ | UFS の全 6 LUN。Android 側の LUN は書込み保護([docs/ja/gpt-incident.md](docs/ja/gpt-incident.md)) |
| CPU | 8 コア。Windows 標準の電力管理が読み込まれないため、`drivers/dbgcap` に自作のガバナーを入れた |
| 画面 | ファームウェアの GOP フレームバッファ経由で、デスクトップとログオンを表示(CPU 描画、GPU ドライバなし) |
| 入力 | タッチ(HID)、電源・音量キー(PMIC を SPMI で読む) |
| 電池・温度 | ACPI と ADSP 経由のライブ電池状態、TSENS 温度、電池温度による停止 |
| USB | PC へのデバイスモード(自作リンク `tools/pc-link`)とホストモード |
| Wi-Fi | PCIe 接続の WCN7850。接続、DHCP、インターネットまで可。割り込み駆動([docs/ja/wifi-bringup.md](docs/ja/wifi-bringup.md)) |
| 未実装 | GPU、音声、Bluetooth、カメラ、モデム、センサー、本当の電源オフ(Windows のシャットダウンは Android への再起動になる) |
| 未解決 | 無人の長時間運転は、まだ信頼できない([docs/ja/safety-lessons.md](docs/ja/safety-lessons.md)) |

## 先にお読みください: 端末を壊す可能性があります

ここにあるツールには、UFS のパーティションへの書き込み、ブートローダーとのやり取り、温度や電力の管理を持たない Windows の実機実行が含まれます。初期には、Windows の起動で全 LUN の GPT が書き換わり、EDL から復旧しました。固まった Windows が電池を過熱させたこともあります。うまくいかなかった事例は [docs/ja/safety-lessons.md](docs/ja/safety-lessons.md) にすべて書いてあります。何かを実行する前に読み、失ってよい端末以外では動かさないでください。

## 中身

```
src/muchain/         MuChain.c: Windows の前に UEFI 内で動くハードウェアの立ち上げ(PCIe0、RPMh、SPMI、UFS 書込み保護、
                     ウォッチドッグ維持、電池の受け渡し、起動前のタッチ検査)とビルド用の取り込み設定
tools/uefi-patch/    UEFI イメージと純正ファームへのパッチ、イメージ作成のスクリプト
tools/acpi/          DSDT/MCFG/IORT/MADT の生成: 電池、熱、PCIe ルート、ITS、割り込みデバイス RM9I0001
tools/android-trace/ レジスタ手順を調べた方法: 動作中の Android での MMIO の ftrace、DT 調査、ダンプ
tools/pc-link/       rm9link(UsbDk 経由でスマホと通信)、サイクル実行、EDL/Sahara の補助、ESP へのファイル転送
tools/gpt/           事故の原因となった GPT/一意 GUID の分析
tools/windows-image/ Windows イメージを外から読む・直す(NTFS/VHDX/レジストリハイブ、BCD、更新の無効化)
guest/               Windows の中で動くもの: 段階式の run.cmd、keypoll/keyinject、タッチ、電池、Wi-Fi
host-scripts/        2 台目の PC と 26100 ゲスト用の PC 側補助
drivers/             dbgcap(ウォッチドッグ、ガバナー、Wi-Fi のポーリング)、rm9io(ユーザーモードからの MMIO)、
                     rm9irq(SPI から ISR)、rm9hid(HID タッチ)
docs/                解説(英語)。docs/ja/ に日本語版
```

## 入っていないもの

ファームウェア、パーティションのダンプ、Windows イメージ、他社のドライバ、署名鍵、端末固有のデータ(シリアル、較正値、ネットワークの資格情報)は入れていません。必要なものは、ご自身のスマホと Windows のメディアから読み出してください。作者の環境由来のパスや識別子は、次のプレースホルダーに置き換えてあります。

| プレースホルダー | 意味 |
|---|---|
| `<RM9_WORKDIR>` | スクリプトを実行した作業フォルダー |
| `<PROJECTS>` | 他のチェックアウトの親フォルダー |
| `<PHONE_SERIAL>` | スマホの adb/fastboot のシリアル |
| `<EDL_SN>` | EDL の USB 名に出るシリアル(`QUSB_BULK_CID:0448_SN:...`) |
| `<LAB_SSID>`、`<PASSPHRASE>` | 試験用のアクセスポイントとその鍵 |
| `<second-pc>`、`<user>`、`<email>` | マシンとアカウント |

スクリプトは、そのままでは動きません。方法を示すために置いてあります。

## 読む順番

1. [docs/ja/boot-flow.md](docs/ja/boot-flow.md): スマホが Android から Windows に入り、戻るまでの流れ
2. [docs/ja/wifi-bringup.md](docs/ja/wifi-bringup.md): いちばん長い作業で、いちばん再利用しやすい部分
3. [docs/ja/gpt-incident.md](docs/ja/gpt-incident.md) と [docs/ja/safety-lessons.md](docs/ja/safety-lessons.md)

## 土台にしたもの

起動部分のUEFIの土台は Project Mu と [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) です。Linux の `qcom` ドライバ(pinctrl、クロック、PCIe、SPMI)のレジスタ配置には、全体を通して頼っています。
