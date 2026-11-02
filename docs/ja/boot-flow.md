# 起動の流れ

スマホが Android から Windows に入り、戻るまでの流れです(2026-11 時点)。すべて NX769J 固有の内容です。English: [../boot-flow.md](../boot-flow.md)

## スロット

スマホは A/B スロットです。スロット **b** が普段使いの Android です。スロット **a** は起動用のランチャーを持ちます。Mu ベースの UEFI(`boot_a`)が 1 回だけ動いて Windows を起動し、使い切られます。`su -c boot_windows.sh`(`tools/android-trace` にあります)で起動の準備をして再起動します。Windows のセッションが終わると、スマホは自動で Android に戻ります(Windows の再起動から約 4.5〜5 分後)。

痛い目に遭った注意が 2 つあります。

* `vendor_boot_a` は普通のパーティションではありません。改造した部品として使われる ext4 イメージで、スロット b の ramdisk の fstab 経由でマウントされます。上書きすると、Android が panic のループに入ります。スロット a の何かを上書きする前に、ramdisk の fstab を読んでください。
* アクティブスロットを切り替えると、スロット b の「successful」マークが下がります。Android が起動すると、また上がります。

## UEFI の段階: MuChain

`src/muchain/MuChain.c` は、Windows のブートマネージャーの直前に UEFI 内で動きます。Windows 自身がまだできないことを、代わりにやります。

* PCIe0 と WLAN チップを立ち上げる(RPMh 経由の電源、PMIC 経由のスリープクロック、PHY のシーケンス、リンクの訓練)。リンクは上げたまま Windows に渡す([wifi-bringup.md](wifi-bringup.md))
* ExitBootServices の直前に、LUN1〜LUN4 の UFS 電源投入時書込み保護を掛ける
* pmic_glink 経由で ADSP に電池の状態を問い合わせ、ACPI の電池デバイスが読む固定の RAM スロットに置く
* ADSP が起動する前に、タッチコントローラーを検査する
* ExitBootServices をまたいで、Gunyah のウォッチドッグを生かしておく([safety-lessons.md](safety-lessons.md))

ACPI テーブルは `tools/acpi` が書き換えます。電池と AC、熱、PCI ルートコンプレックス(`PCI0`)、MCFG、IORT/ITS、割り込みデバイス `RM9I0001` です。

## Windows の段階: 段階式の `run.cmd`

固定の起動スクリプト(`C:\rm9\diag.cmd`、毎回の起動でサービスが実行)が、EFI システムパーティションを `S:` にマウントして `S:\rm9\run.cmd` を実行します。ESP は FAT なので、`run.cmd` は Android から数秒で書き換えられ、実験のループが速くなります。どの `run.cmd` も、最後に起動スクリプトの保険の再起動を取り消し、自分で `shutdown /r` を出します。

きれいな 26100 ゲストは、段階式のラッパー(`guest/esp_run_26100_acct.cmd`)を使います。アカウントとコンピューター名、次にテスト署名のドライバー、USB ファンクションの設定、Wi-Fi ドライバー、そして本番の `run.cmd` の順です。各段階はフラグファイルを残して再起動するので、最初の起動は数回に分かれます。

本番の `run.cmd`(`guest/esp_run_prod_wifi.cmd`)は、PC リンク、電池の更新、Wi-Fi の補正、`guard.cmd`(安全用の `dbgcap` ドライバーを起動する)を開始し、最後の手段として 40 分後の再起動を設定します。

## スマホとの通信

`tools/pc-link/rm9link.py` は、Windows が出す USB ファンクション(VID 1209)の上で、UsbDk 経由の小さなプロトコルを話します(ping、exec、put、get、reboot)。`run_cycle_bg.ps1` と `two_cycle.ps1` が 1 サイクルを実行します。`run.cmd` を置き、Windows を起動し、Android に戻るのを待ち、ログを集めます。ログは、Windows のボリュームを外から読んで取ります(`tools/windows-image/ntfs_*.py`、`vhdx_ntfs_remote.py`)。クラッシュ直後に読むと、NTFS のジャーナルがまだ再生されておらず、最新の書き込みが見えないことがあります。
