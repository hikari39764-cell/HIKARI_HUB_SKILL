---
description: （オーナー専用）ハブのデータを手元のフォルダに書き出して控えを取る
argument-hint: "[控えを置くフォルダ]"
---

**オーナーだけが実行する。** 編集者は技術的には記録を消せるので、控えは定期的に取る。

1. 置き場所：引数、なければ `git config --global hikarihub.backup`。どちらも無ければ人に聞いて、`git config --global hikarihub.backup <フォルダ>` に覚える。ゲームのリポジトリの中には置かない。
2. `.hikari-hub/link.json` から `name` と `url` を読む。書き出し先は `<置き場所>/<作品名>/`。
3. 先に `<置き場所>/<作品名>/` の中の古い JSON を消す（消された記録が残らないように。`.git` は消さない）。
4. `data-model.md` にある全部のコレクションと `settings` を、`ArtifactData` の `list`（`out_dir` 付き、`query: {"limit": 1000}`）で書き出す。1000 件を超えたコレクションは `next_cursor` で続きを読む。
5. `<置き場所>` が git リポジトリでなければ `git init` する。`git add -A` して、`<作品名>: 控え <日付>` でコミットする（push はしない）。
6. 件数（コレクションごと）と、前回から減ったコレクションがあればそれを人に伝える。
