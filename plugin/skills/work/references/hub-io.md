# ハブの読み書き（hub コマンドの使い方）

道具は `"${CLAUDE_PLUGIN_ROOT}/tools/hub.cmd"`（以下 `hub`）。ゲームのリポジトリの中で実行する。どの作品かは、リポジトリの `origin` から自動で決まる。項目の一覧は `data-model.md`。

- 読む：`hub sync` で `.hikari-hub/cache/<コレクション>/<id>.json` に写し、そのファイルを Read / Grep で読む。
- 書く：`.hikari-hub/out/<コレクション>/<id>.json` を Write で作り、`hub push` で送る。送れたファイルは `out` から消え、`cache` に入る。

## id と時刻

- id：`<接頭辞>-<16 進 6 文字>`。作り方（Git Bash）：

```bash
echo "c-$(date +%s%N | git hash-object --stdin | cut -c1-6)"
```

  接頭辞は `data-model.md` の各コレクションに書いてある（カード `c`、報告 `r`、調整ガイド `g`、不具合 `b`、質問 `q`、ナレッジ `k`、ミス `m`、決めること `d`、編集中 `l`、ルール提案 `p`、エンジン要望 `e`、回答 `a`）。まとめて要るときは 1 回のコマンドで必要な数だけ作る。
- 時刻：`date -Iseconds`（例 `2026-11-10T13:05:00+09:00`）。

## 送るファイルの約束（`hub push`）

- ファイルは JSON のオブジェクト 1 つ（UTF-8）。場所が行き先：`.hikari-hub/out/cards/c-3fa9c1.json` → `cards` の `c-3fa9c1`。
- **書いた項目だけが変わる。** 記録が無ければ新しく作られ、あれば書いた項目だけ置き換わる（書いていない項目は残る）。
  - 入れ子のマップ（質問の `answers` など）は中身ごとに合わさるので、自分の分だけ書けばよい。
  - 配列（`progress`、`paths` など）は**丸ごと置き換わる**。足すときは、これまでの分も全部入れる。
- `_` で始まる項目はハブに入らない。`cache` のファイルにある `_time` は「最後に書かれた時刻」。
- **取り合いになる書き込み**（既にあるカードを始める、編集中を宣言する）は、直前に `hub get` で読み、その `_time` を `"_if_time"` に入れる。その間に誰かが書いていたら `changed` で失敗する（上書きしない）。
- 結果は 1 件ずつ出る：`ok  cards/c-3fa9c1`。失敗は `NG  <記録>  <理由>` で、そのファイルは `out` に残る。
  - `denied`：オーナー領域（`settings`・`rules`・`engine`）に書こうとしている。ファイルを消す。
  - `changed`：`hub get` で読み直し、内容を見てから書き直す（相手が先に取っていたら、取らない）。
  - `offline`：ハブに届かない。下の「届かないとき」。

## 同期（会話の最初、`/hub:today`・`/hub:start` の前）

```bash
hub sync
```

- `settings`・`rules`・`engine`・`members`・`cards`・`locks`・`guides`・`decisions`・`questions`・`knowledge`・`mistakes` が `.hikari-hub/cache` に入る（消された記録は消える）。例：`Grep "敵" .hikari-hub/cache/knowledge`。
- `reports` は多くなるので全部は読まない。カードの前回の報告だけ読む：`hub find reports card <カード id>`。
- `bugs`・`engine_requests`・`proposals` は、同じものを出していないか確かめるときに読む：`hub list bugs`。
- `settings/plan` の `ready` は、オーナーがおすすめするカードの順番（参考）。入っていないカードも、自分で作ったカードも、そのまま始めてよい。

## カードを作って始める・既にあるカードを始める

自分で作るとき（最初から `作業中` で作ってよい）。`.hikari-hub/out/cards/c-3fa9c1.json`：

```json
{"title": "敵のノックバック", "kind": "機能", "summary": "被弾した敵を後ろへ押し出す。",
 "acceptance": ["距離と時間をエディタで調整できる", "壁を抜けない"],
 "paths": ["Source/Runtime/Enemy/"], "areas": ["敵"],
 "state": "作業中", "assignee": "kato", "started_at": "2026-11-10T13:05:00+09:00",
 "branch": "feat/c-3fa9c1-enemy-knockback",
 "by": "kato", "by_agent": "claude-code", "at": "2026-11-10T13:05:00+09:00",
 "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}
```

既にあるカードを始めるとき：先に `hub get cards/c-3fa9c1` で読み直し、`state` を確かめる（ほかの人が `作業中` なら始めない）。出てきた `_time` を入れて書く：

```json
{"_if_time": "2026-11-10T04:01:22.123456Z",
 "state": "作業中", "assignee": "kato", "started_at": "2026-11-10T13:05:00+09:00",
 "branch": "feat/c-3fa9c1-enemy-knockback",
 "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}
```

## いま作業中のカードを手元に書く（`.hikari-hub/active.json`）

カードを作業中にして（`hub push` が `ok`）、ブランチを切って、報告を作ったあとに書く。フックがこれを読む。

```json
{"card": "c-3fa9c1", "title": "敵のノックバック", "report": "r-91c2aa",
 "branch": "feat/c-3fa9c1-enemy-knockback",
 "paths": ["Source/Runtime/Enemy/", "Assets/Prefabs/Enemy.prefab"],
 "started_at": "2026-11-10T13:05:00+09:00"}
```

- 終わったら消す。ハブに登録せずにこのファイルだけ書くことはしない。

## 作業の報告を作る・進捗を足す・終える

作る。`.hikari-hub/out/reports/r-91c2aa.json`：

```json
{"kind": "作業", "card": "c-3fa9c1", "title": "敵のノックバック", "state": "作業中",
 "model": "<自分のモデル id>", "started_at": "2026-11-10T13:05:00+09:00",
 "branch": "feat/c-3fa9c1-enemy-knockback", "progress": [],
 "by": "kato", "by_agent": "claude-code", "at": "2026-11-10T13:05:00+09:00",
 "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}
```

進捗を足す（同じ場所にもう一度書く。`progress` は配列ごと置き換わるので、これまでの分も全部入れる）：

```json
{"progress": [{"at": "2026-11-10T13:40:00+09:00", "note": "距離をフィールドにした。次は空中で当たったときの動き"}],
 "updated_at": "2026-11-10T13:40:00+09:00", "updated_by": "kato"}
```

終える：調整ガイド・学んだこと・ミス・質問のファイルも一緒に `out` に書き、その id を入れて報告を閉じる。**全部の項目を書く。ないものは `[]`。**

```json
{"state": "終了", "ended_at": "2026-11-10T15:10:00+09:00",
 "conclusion": "距離と時間をコンポーネントのフィールドにした。空中での被弾はまだ地上と同じ動き。",
 "changes": ["Source/Runtime/Enemy/EnemyHit.cpp ほか 3 ファイル", "敵プレハブ 2 つ"],
 "evidence": ["ビルド：警告 0", "テスト用シーンでの確認は未実施（人に依頼）"],
 "unverified": ["実機での動き", "ボス戦"],
 "remaining": ["空中被弾の動き（カード c-7b20e4 にした）"],
 "tuning": ["g-2c7e15"],
 "learned": ["k-55d0c1"], "mistakes": ["m-0a91f3"], "questions": [],
 "cost_hours": 1.6, "cost_tokens": "0.9M", "pr": "https://github.com/<owner>/<repo>/pull/12",
 "updated_at": "2026-11-10T15:10:00+09:00", "updated_by": "kato"}
```

カードも同じ `hub push` で更新する。`.hikari-hub/out/cards/c-3fa9c1.json`：`{"state": "確認待ち", "waiting": "レビュー", "pr": "...", "updated_at": "…", "updated_by": "kato"}`。完了条件を満たしていなければ `{"state": "あとで", "assignee": "", …}`。

## まとめて作る（調整ガイド・学んだこと・ミス・質問・不具合など）

記録ごとに 1 ファイルを書き、最後に 1 回 `hub push`。

`.hikari-hub/out/guides/g-2c7e15.json`：

```json
{"title": "敵のノックバック", "summary": "被弾した敵を、当たった向きの反対へ押し出す。KnockbackComponent が値を持ち、KnockbackSystem が FixedUpdate で動かす。",
 "params": ["KnockbackComponent.distance — 飛ぶ距離（既定 1.5 m、0〜10）。敵プレハブ Enemy_Grunt・Enemy_Heavy に付いている",
            "KnockbackComponent.seconds — 飛んでいる時間（既定 0.2 秒、0〜2）"],
 "code": ["Source/Runtime/Enemy/KnockbackSystem.cpp:kWallMargin — 壁の手前で止まる余白（0.05 m）。物理の都合でエディタに出していない"],
 "check": "テスト用シーン EnemyTest で敵を攻撃する。distance を変えて Play し直すと飛ぶ距離が変わる。",
 "areas": ["敵"], "paths": ["Source/Runtime/Enemy/"], "card": "c-3fa9c1", "state": "有効",
 "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}
```

`.hikari-hub/out/knowledge/k-55d0c1.json`：

```json
{"title": "物理の押し出しは FixedUpdate で入れる", "body": "Update で入れると壁を抜ける。…",
 "areas": ["敵"], "paths": ["Source/Runtime/Enemy/"], "source": "r-91c2aa", "state": "要確認",
 "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}
```

`.hikari-hub/out/mistakes/m-0a91f3.json`：

```json
{"title": "ノックバックの距離をコードに直書きした", "what": "…", "root_cause": "…",
 "caught_by": "自分で読み直して", "fix": "…", "prevention": "…", "areas": ["敵"], "state": "記録",
 "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}
```

- 新しい記録の `state` は、そのコレクションの最初の状態（`data-model.md`）。
- 調整ガイドは機能ごとに 1 つ。同じ機能のガイドがもうあれば、新しく作らずに同じ id のファイルで直す。
- 不具合の名前は現象そのまま。質問の `to` は `エージェント`・`オーナー`・メンバーの呼び名。
- `決めること` の `options` は `[{"text": "…", "recommended": true}, {"text": "…", "recommended": false}]`。`recommended: true` はちょうど 1 つ。`decider` を書く。

## 質問に答える

回答は質問の中の `answers`（マップ）に、自分の分だけ書く。入れ子は合わさるので、ほかの回答は消えない。`.hikari-hub/out/questions/q-1d44b0.json`：

```json
{"state": "回答あり",
 "answers": {"a-6e02f7": {"by": "kato", "by_agent": "claude-code", "at": "…",
                          "text": "同じ距離でよい。企画書 3 章に記載。", "evidence": ["Docs/plan.md 3 章"]}},
 "updated_at": "…", "updated_by": "kato"}
```

`解決` にするのは、質問した側（人か、そのエージェント）。結論を `conclusion` に書き、残す価値があれば `knowledge` にも書く。

## 編集中を宣言する・解除する

宣言の前に `hub list locks` で読み直し、同じ対象が `編集中` でないか確かめる。`.hikari-hub/out/locks/l-b7730e.json`：

```json
{"target": "Assets/Scenes/Stage2.scene", "until": "18:00", "card": "c-3fa9c1", "state": "編集中",
 "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}
```

終わったら同じ id で `{"state": "解除", "updated_at": "…", "updated_by": "kato"}`。

## 届かないとき

- `offline`：作業は続ける。書くつもりの記録は、そのまま `.hikari-hub/out` にファイルで置いておく。届くようになったら `hub push` を 1 回実行すれば全部送られる。会話の最初に `out` にファイルが残っていたら、まず `hub push`。
- `hub sync` ができないとき：`.hikari-hub/cache` に前の控えがあればそれを読んで進める（古いかもしれないと人に伝える）。控えも無ければ `references/engine.md` を読み、ルールは人に確認する。
- `hub.cmd` が動かない環境（Windows 以外など）：ハブには書けない。終わりに**終了報告と調整できるところを文章で人に渡す**（人がページから入れる）。
