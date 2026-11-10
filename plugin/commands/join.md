---
description: このリポジトリをハブのプロジェクトにつなぐ（手元だけの設定。リポジトリには何もコミットされない）
argument-hint: "<ハブのページの URL>"
---

ハブの URL：$ARGUMENTS

（空なら人に聞く。ハブのページの「メンバー」に `/hub:join <URL>` の形で書いてある。）

1. いまいるフォルダが git リポジトリの直下であることを確かめる（`git rev-parse --show-toplevel`）。違えば直下へ移る。
2. `ArtifactData` で、その URL の `settings` を読む（`action: "get"`、`collection: "settings"`、`doc_id: "project"`）。読めなければ、招待されていないか URL が違う。人に伝えて止まる。
3. `.hikari-hub/` を作り、`.hikari-hub/link.json` を書く：`{"name": "<settings/project の name>", "url": "<URL>"}`。
4. **git に入らないようにする**：`.git/info/exclude` に `.hikari-hub/` の行が無ければ足す（`.gitignore` は触らない）。
5. 呼び名：`git config --global hikarihub.handle` が空なら人に聞いて設定する。ハブの `members` にその呼び名が無ければ、ページを開いて登録するよう伝える。
6. `hub:work` スキルの「0. 準備」の同期を行い、「1. 今日の状況」を見せる。

これで、このリポジトリではプラグインのフックが働く：会話の最初に案内が出て、やることを登録するまでファイルは変更できなくなる。やめるときは `.hikari-hub/` を消す。
