# GPT 事故: Windows の起動でスマホが EDL に落ちた件

2026-10-13 のことです。プロジェクトが終わりかけた事故で、似た構成の複数 LUN を持つ UFS スマホで Windows を起動する人なら、誰にでも起こりえます。English: [../gpt-incident.md](../gpt-incident.md)

## 何が起きたか

最初に Windows の起動が成功した後(UEFI から `bootmgfw`、`winload`、`ExitBootServices` まで)、スマホが戻ってきませんでした。EDL に入っていました。Windows の `storufs` ドライバーが、UFS の 6 つの LUN すべての GPT ヘッダーを書き換えていました。Android のデータは無傷でしたが、ブートチェーンがパーティションを見つけられなくなっていました。

## 原因

このスマホの LUN は、**パーティションの一意 GUID** を LUN 間で共有していました。同じ GUID が、複数の LUN のパーティションテーブルに現れます。Windows はこれを署名の衝突と見なし、ディスクをオンラインにするときに、衝突したディスクの GPT を書き直しました。QEMU 上の WinPE で、LUN のパーティションテーブルのコピーを使って、端末の外で再現しました(`tools/gpt/gpt_collisions.py`、`gpt_unique_guids.py`、`lun_dups.py`、`lun_guids.py`)。

## 復旧

EDL には、電池をつないだまま音量ボタンを押しながら USB をつなぐと入れます。EDL 経由で、影響を受けた各 LUN の LBA 1 の GPT ヘッダーを再構成しました。Android は普通に起動しました。

## 再発防止(適用した順)

1. **GUID を一意にする。** LUN0 と LUN5 のパーティション一意 GUID を書き換え、どの LUN とも重ならないようにしました。端末に適用し、確認済みです。
2. **Windows に触らせたくない LUN を書込み保護する。** UFS には電源投入時の書込み保護があります。ホストから立てるフラグで、次のリセットまで有効です。MuChain が `ExitBootServices` の直前にこれを立て、LUN1〜LUN4 を守ります。Windows が GPT を書き直そうとしても、デバイスが拒否します。端末で確認済みです。
3. **それ以外はオフラインにする。** Windows イメージの `SanPolicy=4`(全ディスクをオフライン)で、Windows に見えるディスクが勝手にオンラインにならないようにしました。
4. **観測。** UFS ホストコントローラーのレジスタを AML から記録(`UFSS`)し、起動に失敗しても後から読めるようにしました。また、スマホ上の Windows のハイブを外から読んで、どのデバイスが列挙されたかを見られます(`tools/windows-image/hive_enum.py`)。

## 別のスマホで確認すること

* 同じパーティションレベルの GUID が、複数の LUN に現れていないか(`tools/gpt`)
* OS が起動する前に、ブートチェーンから LUN に書込み保護を掛けられるか
* 最初の Windows 起動の前に、EDL に入れるか(または GPT を書き直す別の手段があるか)。後ではなく前に確認すること
