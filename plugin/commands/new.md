---
description: （オーナー専用）このリポジトリのために新しいハブのプロジェクトページを作る
argument-hint: "<作品名> [GitHub の owner/repo]"
---

**オーナー（ページを持つ人）だけが実行する。** いまいるフォルダが、ゲームのリポジトリの直下であること。

引数：$ARGUMENTS

1. **確かめる**：`.hikari-hub.toml` がもうあれば、作らずに止まる（そのプロジェクトは既にハブにつながっている）。次を人に確認する：作品名、GitHub リポジトリ（`owner/name`）、元にするブランチ（既定 `main`）、HIKARI SDK の版、領域の一覧（リポジトリを見て 4〜8 個を提案する。例：プレイヤー、敵、ステージ、UI、演出、音）。
2. **ページを用意する**：`.hikari-hub/page/` を作り、`${CLAUDE_PLUGIN_ROOT}/owner/hub.html` を `.hikari-hub/page/hub.html` にコピーして、中の `__PROJECT_NAME__` を全部作品名に置き換える。
3. **公開する**：`Artifact` ツールで `.hikari-hub/page/hub.html` を publish する。`capabilities` には `${CLAUDE_PLUGIN_ROOT}/owner/capabilities.json` の中身をそのまま渡す。`icon` は `team`。返ってきた URL を控える。
4. **初期データを入れる**（`ArtifactData` の batch、50 件までずつ）：
   - `settings/project`：`name`、`repo`、`base_branch`、`sdk`、`areas`、`budget_hours: 3`、`max_sessions: 2`
   - `settings/plan`：`{"ready": [], "assign": {}, "milestones": []}`
   - `rules`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/rules/*.json` を、ファイル名（拡張子なし）を id にして `file_path` で入れる
   - `engine`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/engine/*.json` を同じように入れる
5. **確かめる**：`rules` と `engine` を list して件数が合うこと。`as_level: "admin"` で `rules` に書こうとして拒否されること（編集者はルールを書けない）。
6. **リポジトリに置く**：
   - `.hikari-hub.toml`：`name = "<作品名>"` と `url = "<ページの URL>"`
   - `${CLAUDE_PLUGIN_ROOT}/template/` のファイルを、**既にあるものは上書きせずに**コピーする。`gitignore.txt` と `gitattributes.txt` は、`.gitignore` と `.gitattributes` に無い行だけ足す。
   - コミットはしない。変わったファイルを人に見せる。
7. **人に伝える**（この順で）：
   - ページを開いて、自分の呼び名を登録する
   - ページの共有メニューから、メンバーをメールで**編集者**として招待する。**「リンクを知っている全員」にはしない**（外部の編集者が書けなくなる）
   - GitHub リポジトリにも同じメンバーを招待し、`main` を保護する（PR 必須・承認 1 人）
   - メンバーにはリポジトリの README の「参加の手順」を見てもらう
