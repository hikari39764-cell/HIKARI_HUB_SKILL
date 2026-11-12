---
description: （オーナー専用）新しい作品をハブに作る
argument-hint: "<作品名> [GitHub の owner/repo]"
---

**オーナーだけが実行する**（`hub whoami` が `owner: true`）。いまいるフォルダが、ゲームのリポジトリの直下であること。ゲームのリポジトリには何もコミットしない。

引数：$ARGUMENTS

1. **確かめる**：このリポジトリの `owner/name` がスキルのリポジトリの `plugin/projects.json` にもうあれば、作らずに止まる。次を人に確認する：作品名、作品 id（半角の小文字・数字・`-` `_`。URL に使う。例 `td2_2`）、GitHub リポジトリ（`owner/name`）、元にするブランチ（既定 `develop`）と公開ブランチ（既定 `main`）。リポジトリに `develop` が無ければ、`main` から作って push してよいか人に聞く、領域の一覧（リポジトリを見て 4〜8 個を提案する。例：プレイヤー、敵、ステージ、UI、演出、音）。
2. **スキルに登録する**：スキルのリポジトリ（オーナーの手元の HIKARI-Hub。場所は `git config --global hikarihub.source`、無ければ人に聞いて覚える）の `plugin/projects.json` に `{"repo": "<owner/name>", "name": "<作品名>", "id": "<作品 id>"}` を 1 行足し、`python -I -X utf8 tools/build.py` でサイトを作り直してコミットする。**push の前に人に確認する。** push すると、サイトの作品一覧に出て、メンバーのエージェントはスキルを更新するだけでこのリポジトリを見分けられる。
3. **初期データを入れる**：`.hikari-hub/out/` に次のファイルを作り、`hub push -Project <作品 id>` で送る（スキルの更新がまだ手元に届いていなくても `-Project` で送れる）。
   - `settings/project.json`：`name`、`repo`、`skill_source`（スキルのリポジトリ。GitHub の `owner/name`）、`base_branch`、`release_branch`、`areas`、`budget_hours: 3`、`max_sessions: 2`、`require_card: true`、`protected_paths: ["ProjectSettings/", "CMakeLists.txt", "Project.hikari", ".github/", ".clang-format", ".gitattributes"]`
   - `settings/plan.json`：`{"ready": [], "assign": {}, "milestones": []}`
   - `rules/`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/rules/*.json` をそのままコピーする
   - `engine/`：`${CLAUDE_PLUGIN_ROOT}/owner/seed/engine/*.json` をそのままコピーする
4. **確かめる**：`hub sync -Project <作品 id>` で `rules` と `engine` の件数が合うこと。
5. **（任意）整形の設定**：リポジトリに `.clang-format`・`.editorconfig` が無ければ、`${CLAUDE_PLUGIN_ROOT}/template/` のものを入れるか人に聞く（これはコードの設定なので、入れるならリポジトリにコミットする）。`gitattributes.txt` は LFS の設定の例。
6. **人に伝える**（この順で）：
   - サイト（`hub whoami` の `page`）を開いて、「ルール」と、「メンバー」のプロジェクト設定（保護するパス）を確かめる
   - 「メンバー」の「招待する」に、メンバーの **Google アカウントのメール**を足す
   - メンバーには、サイトの URL を伝え、スキルを入れてもらう（もう入っている人は更新する：`claude plugin marketplace update hikari-hub` と `claude plugin update hub@hikari-hub`）
