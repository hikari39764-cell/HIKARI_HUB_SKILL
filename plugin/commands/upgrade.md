---
description: （オーナー専用）このプロジェクトのハブのページを、プラグインの新しい雛形に更新する
---

**オーナーだけが実行する。** データ（カードや報告、ルール）は変わらない。変わるのはページの画面だけ。

1. `${CLAUDE_PLUGIN_ROOT}/projects.json` から、このリポジトリの `name` と `url` を読む。
2. `Artifact` ツールの `action: "read"` で、いまのページを読む（publish の前に必要）。
3. `${CLAUDE_PLUGIN_ROOT}/owner/hub.html` を `.hikari-hub/page/hub.html` にコピーし、`__PROJECT_NAME__` を作品名に置き換える。
4. `Artifact` ツールで publish する（`url` にいまのページを指定）。`capabilities` は、`${CLAUDE_PLUGIN_ROOT}/owner/capabilities.json` がいまの宣言と違うときだけ渡す。同じなら省く（省くと今の宣言が引き継がれる）。
5. エンジン知識の更新：`${CLAUDE_PLUGIN_ROOT}/owner/seed/engine/*.json` とハブの `engine` を比べ、違い（新しい項目・本文が変わった項目）を一覧で人に見せる。**人が選んだものだけ**書き込む（オーナーがページで直した内容を黙って上書きしない）。
6. ルールは上書きしない。既定のルール（`owner/seed/rules`）に新しい項目があれば、名前だけ知らせる。
7. ページを開いて、ホームが出ることを人に確かめてもらう。
