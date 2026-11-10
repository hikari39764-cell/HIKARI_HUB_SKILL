# ハブの読み書き（ArtifactData の使い方）

どの呼び出しにも `url` を付ける（`${CLAUDE_PLUGIN_ROOT}/projects.json` で、このリポジトリの `owner/name` に対応する `url`）。項目の一覧は `data-model.md`。

## id と時刻

- id：`<接頭辞>-<16 進 6 文字>`。作り方（Git Bash）：

```bash
echo "c-$(date +%s%N | git hash-object --stdin | cut -c1-6)"
```

  接頭辞は `data-model.md` の各コレクションに書いてある（カード `c`、報告 `r`、調整ガイド `g`、不具合 `b`、質問 `q`、ナレッジ `k`、ミス `m`、決めること `d`、編集中 `l`、ルール提案 `p`、エンジン要望 `e`、回答 `a`）。まとめて要るときは 1 回のコマンドで必要な数だけ作る。
- 時刻：`date -Iseconds`（例 `2026-11-10T13:05:00+09:00`）。

## 版（version）の約束

- 読んだ記録には `version` が付いてくる。**既にある記録に書くときは、最後に見た `version` を `if_version` に入れる。** 書き込みの結果にも新しい `version` が返るので、続けて書くときはそれを使う。
- 新しく作るときだけ `if_version` を省く。同じ id がもうあれば拒否されるので、id を作り直す。
- `if_version` が合わずに失敗したら、誰かが先に書いている。読み直して、内容を見てからやり直す（そのまま上書きしない）。

## 同期（会話の最初、`/hub:today`・`/hub:start` の前）

```bash
rm -rf .hikari-hub/cache
```

次を**1 つのメッセージで並行して**呼ぶ（`action: "list"`、`out_dir: ".hikari-hub/cache"`、`query: {"limit": 1000}`）：

`settings`、`rules`、`engine`、`members`、`cards`、`locks`、`guides`、`decisions`、`questions`、`knowledge`、`mistakes`

- 結果は `.hikari-hub/cache/<コレクション>/<id>.json` に入る。中身は Read / Grep で読む（例：`Grep "敵" .hikari-hub/cache/knowledge`）。
- ファイルには `version` が入らない（ツールの結果の一覧には出る）。書く直前に `get` で読み直して、その `version` を使う。
- `reports` は多くなるので全部は読まない。カードの前回の報告だけ読む：`action: "query"`、`collection: "reports"`、`query: {"where": [["card", "==", "<カード id>"]], "limit": 20}`。
- `bugs`・`engine_requests`・`proposals` は、同じものを出していないか確かめるときに読む。
- `settings/plan` の `ready` は、オーナーがおすすめするカードの順番（参考）。入っていないカードも、自分で作ったカードも、そのまま始めてよい。

## カードを作って始める・既にあるカードを始める

自分で作るとき（`if_version` なし。最初から `作業中` で作ってよい）：

```json
{"action": "set", "collection": "cards", "doc_id": "c-3fa9c1",
 "data": {"title": "敵のノックバック", "kind": "機能", "summary": "被弾した敵を後ろへ押し出す。",
          "acceptance": ["距離と時間をエディタで調整できる", "壁を抜けない"],
          "paths": ["Source/Runtime/Enemy/"], "areas": ["敵"],
          "state": "作業中", "assignee": "kato", "started_at": "2026-11-10T13:05:00+09:00",
          "branch": "feat/c-3fa9c1-enemy-knockback",
          "by": "kato", "by_agent": "claude-code", "at": "2026-11-10T13:05:00+09:00",
          "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}}
```

既にあるカードを始めるとき：

```json
{"action": "update", "collection": "cards", "doc_id": "c-3fa9c1", "if_version": 4,
 "data": {"state": "作業中", "assignee": "kato", "started_at": "2026-11-10T13:05:00+09:00",
          "branch": "feat/c-3fa9c1-enemy-knockback",
          "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}}
```

既にあるカードは、直前に `get` で読み直して `version` と `state` を確かめる。ほかの人が `作業中` なら始めない。

## いま作業中のカードを手元に書く（`.hikari-hub/active.json`）

カードを作業中にして、ブランチを切って、報告を作ったあとに書く。フックがこれを読む。

```json
{"card": "c-3fa9c1", "title": "敵のノックバック", "report": "r-91c2aa",
 "branch": "feat/c-3fa9c1-enemy-knockback",
 "paths": ["Source/Runtime/Enemy/", "Assets/Prefabs/Enemy.prefab"],
 "started_at": "2026-11-10T13:05:00+09:00"}
```

- 終わったら消す。ハブに登録せずにこのファイルだけ書くことはしない。

## 作業の報告を作る・進捗を足す・終える

作る（`if_version` なし）：

```json
{"action": "set", "collection": "reports", "doc_id": "r-91c2aa",
 "data": {"kind": "作業", "card": "c-3fa9c1", "title": "敵のノックバック", "state": "作業中",
          "model": "<自分のモデル id>", "started_at": "2026-11-10T13:05:00+09:00",
          "branch": "feat/c-3fa9c1-enemy-knockback", "progress": [],
          "by": "kato", "by_agent": "claude-code", "at": "2026-11-10T13:05:00+09:00",
          "updated_at": "2026-11-10T13:05:00+09:00", "updated_by": "kato"}}
```

進捗を足す（`progress` は配列ごと置き換わるので、これまでの分も全部入れる）：

```json
{"action": "update", "collection": "reports", "doc_id": "r-91c2aa", "if_version": 1,
 "data": {"progress": [{"at": "2026-11-10T13:40:00+09:00", "note": "距離をフィールドにした。次は空中で当たったときの動き"}],
          "updated_at": "2026-11-10T13:40:00+09:00", "updated_by": "kato"}}
```

終える：先に学んだこと・ミス・質問を作り（下の batch）、その id を入れて報告を閉じる。**全部の項目を書く。ないものは `[]`。**

```json
{"action": "update", "collection": "reports", "doc_id": "r-91c2aa", "if_version": 3,
 "data": {"state": "終了", "ended_at": "2026-11-10T15:10:00+09:00",
          "conclusion": "距離と時間をコンポーネントのフィールドにした。空中での被弾はまだ地上と同じ動き。",
          "changes": ["Source/Runtime/Enemy/EnemyHit.cpp ほか 3 ファイル", "敵プレハブ 2 つ"],
          "evidence": ["ビルド：警告 0", "テスト用シーンでの確認は未実施（人に依頼）"],
          "unverified": ["実機での動き", "ボス戦"],
          "remaining": ["空中被弾の動き（カード c-7b20e4 にした）"],
          "tuning": ["g-2c7e15"],
          "learned": ["k-55d0c1"], "mistakes": ["m-0a91f3"], "questions": [],
          "cost_hours": 1.6, "cost_tokens": "0.9M", "pr": "https://github.com/<owner>/<repo>/pull/12",
          "updated_at": "2026-11-10T15:10:00+09:00", "updated_by": "kato"}}
```

そのあとカードを更新する（`if_version` 付き）：`{"state": "確認待ち", "waiting": "レビュー", "pr": "..."}`。完了条件を満たしていなければ `{"state": "あとで", "assignee": ""}`。

## まとめて作る（調整ガイド・学んだこと・ミス・質問・不具合など）

```json
{"action": "batch", "writes": [
  {"op": "set", "collection": "guides", "doc_id": "g-2c7e15",
   "data": {"title": "敵のノックバック", "summary": "被弾した敵を、当たった向きの反対へ押し出す。KnockbackComponent が値を持ち、KnockbackSystem が FixedUpdate で動かす。",
            "params": ["KnockbackComponent.distance — 飛ぶ距離（既定 1.5 m、0〜10）。敵プレハブ Enemy_Grunt・Enemy_Heavy に付いている",
                       "KnockbackComponent.seconds — 飛んでいる時間（既定 0.2 秒、0〜2）"],
            "code": ["Source/Runtime/Enemy/KnockbackSystem.cpp:kWallMargin — 壁の手前で止まる余白（0.05 m）。物理の都合でエディタに出していない"],
            "check": "テスト用シーン EnemyTest で敵を攻撃する。distance を変えて Play し直すと飛ぶ距離が変わる。",
            "areas": ["敵"], "paths": ["Source/Runtime/Enemy/"], "card": "c-3fa9c1", "state": "有効",
            "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}},
  {"op": "set", "collection": "knowledge", "doc_id": "k-55d0c1",
   "data": {"title": "物理の押し出しは FixedUpdate で入れる", "body": "Update で入れると壁を抜ける。…",
            "areas": ["敵"], "paths": ["Source/Runtime/Enemy/"], "source": "r-91c2aa", "state": "要確認",
            "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}},
  {"op": "set", "collection": "mistakes", "doc_id": "m-0a91f3",
   "data": {"title": "ノックバックの距離をコードに直書きした", "what": "…", "root_cause": "…",
            "caught_by": "自分で読み直して", "fix": "…", "prevention": "…", "areas": ["敵"], "state": "記録",
            "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}}
]}
```

- 新しい記録の `state` は、そのコレクションの最初の状態（`data-model.md`）。
- 調整ガイドは機能ごとに 1 つ。同じ機能のガイドがもうあれば、新しく作らずに `update`（`if_version` 付き）で直す。
- 不具合の名前は現象そのまま。質問の `to` は `エージェント`・`オーナー`・メンバーの呼び名。
- `決めること` の `options` は `[{"text": "…", "recommended": true}, {"text": "…", "recommended": false}]`。`recommended: true` はちょうど 1 つ。`decider` を書く。

## 質問に答える

回答は質問の中の `answers`（マップ）に、自分の分だけ足す。`update` は入れ子を合わせてくれるので、ほかの回答は消えない。

```json
{"action": "update", "collection": "questions", "doc_id": "q-1d44b0", "if_version": 2,
 "data": {"state": "回答あり",
          "answers": {"a-6e02f7": {"by": "kato", "by_agent": "claude-code", "at": "…",
                                   "text": "同じ距離でよい。企画書 3 章に記載。", "evidence": ["Docs/plan.md 3 章"]}},
          "updated_at": "…", "updated_by": "kato"}}
```

`解決` にするのは、質問した側（人か、そのエージェント）。結論を `conclusion` に書き、残す価値があれば `knowledge` にも書く。

## 編集中を宣言する・解除する

```json
{"action": "set", "collection": "locks", "doc_id": "l-b7730e",
 "data": {"target": "Assets/Scenes/Stage2.scene", "until": "18:00", "card": "c-3fa9c1", "state": "編集中",
          "by": "kato", "by_agent": "claude-code", "at": "…", "updated_at": "…", "updated_by": "kato"}}
```

宣言の前に cache の `locks` で同じ対象が `編集中` でないか確かめる。終わったら `{"state": "解除"}`。

## 書けないとき

- `ArtifactData` が無い環境：ハブには書けない。`.hikari-hub/cache` があればそれを読んで作業し、終わりに**終了報告と調整できるところを文章で人に渡す**（人がページから入れる）。
- 書き込みが「見つからない」「拒否」で返るとき：オーナー領域（`settings`・`rules`・`engine`）に書こうとしているか、その人が編集者として招待されていない。人に伝える。
- ハブに届かないとき：作業は続け、報告の内容を `.hikari-hub/pending.md` に書いておき、次に届いたときに書き込む。
