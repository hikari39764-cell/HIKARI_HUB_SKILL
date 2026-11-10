---
description: （オーナー専用）新しい作品のハブのプロジェクトページを作る
argument-hint: "<作品名> [GitHub の owner/repo]"
---

**オーナー（ページを持つ人）だけが実行する。** いまいるフォルダが、ゲームのリポジトリの直下であること。リポジトリには何もコミットしない。

引数：$ARGUMENTS

1. **確かめる**：`.hikari-hub/link.json` がもうあれば、作らずに止まる（このリポジトリは既にハブに参加している）。次を人に確認する：作品名、GitHub リポジトリ（`owner/name`）、元にするブランチ（既定 `main`）、HIKARI SDK の版、領域の一覧（リポジトリを見て 4〜8 個を提案する。例：プレイヤー、敵、ステージ、UI、演出、音）。
2. **ページを用意する**：`.hikari-hub/page/` を作り、`${CLAUDE_PLUGIN_ROOT}/owner/hub.html` を `.hikari-hub/page/hub.html` にコピーして、中の `__PROJECT_NAME__` を全部作品名に置き換える（シェルのコマンドで行う）。`.git/info/exclude` に `.hikari-hub/` の行が無ければ足す。
3. **公開する**：`Artifact` ツールで `.hikari-hub/page/hub.html` を publish する。`capabilities` には `${CLAUDE_PLUGIN_ROOT}/owner/capabilities.json` の中身をそのまま渡す。`icon` は `team`。返ってきた URL を控える。
4. **初期データを入れる**（`ArtifactData` の batch、50 件までずつ）：
   - `settings/project`：`name`、`repo`、`hub_url`（ページの URL）、`base_branch`、`sdk`、`areas`、`budget_hours: 3`、`max_sessions: 2`、`require_card: true`、`protected_paths: ["ProjectSettings/", "CMakeLists.txt", "Project.hikari", ".github/", ".clang-format", ".gitattributes"]`
   - `settings/plan`：`{"ready": [], "assign": {}, "milestones": []}`
   - `rules`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/rules/*.json` を、ファイル名（拡張子なし）を id にして `file_path` で入れる
   - `engine`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/engine/*.json` を同じように入れる
5. **確かめる**：`rules` と `engine` を list して件数が合うこと。`as_level: "admin"` で `rules` に書こうとして拒否されること（編集者はルールを書けない）。
6. **自分も参加する**：`.hikari-hub/link.json` に `{"name": "<作品名>", "url": "<ページの URL>"}` を書く（`/hub:join` と同じ）。
7. **（任意）整形の設定**：リポジトリに `.clang-format`・`.editorconfig` が無ければ、`${CLAUDE_PLUGIN_ROOT}/template/` のものを入れるか人に聞く（これはコードの設定なので、入れるならリポジトリにコミットする）。`gitattributes.txt` は LFS の設定の例。
8. **人に伝える**（この順で）：
   - ページを開いて、自分の呼び名を登録する。「ルール」と、「メンバー」のプロジェクト設定（保護するパス）を確かめる
   - ページの共有メニューから、メンバーをメールで**編集者**として招待する。**「リンクを知っている全員」にはしない**（外部の編集者が書けなくなる）
   - メンバーには、プラグインを入れてから、ゲームのリポジトリの中で `/hub:join <ページの URL>` を実行してもらう
