# ハブのデータ（自動生成：schema/schema.json から）

ハブのデータベース（作品ごと）にある記録の一覧。`hub` コマンドで読み書きする。
書き方の手順と例は `hub-io.md`。ここは「どのコレクションに、どんな項目があるか」。

## すべての記録に付ける項目

| 項目 | 意味 | 書き方 |
|---|---|---|
| `by` | 書いた人 | メンバーの呼び名（members の handle） |
| `by_agent` | エージェント | エージェントが書いたときだけ。例 claude-code。人がページで書いたときは空 |
| `at` | 作成 | ISO 8601（例 2026-11-10T13:05:00+09:00） |
| `updated_at` | 更新 | ISO 8601 |
| `updated_by` | 更新した人 | 呼び名 |

- 新しく作るとき：`by`・`at`・`updated_at`・`updated_by`、エージェントなら `by_agent` も。
- 直すとき：`updated_at`・`updated_by`。
- id は `<接頭辞>-<16 進 6 文字>`（例 `c-3fa9c1`）。

## 書ける人

- **メンバー**：オーナーに招待された人と、その人の鍵を使うエージェント。記録を作る・直すことができる（消せるのはオーナーだけ）。
- **オーナーだけ**：`settings`、`design`、`rules`、`engine`。ほかの人が書こうとすると拒否される（エージェントは書かない）。
- **本人だけ**：`members/<自分の uid>`（呼び名と自分のブランチ。ページで本人が登録する。まだ無ければエージェントが登録する）。オーナーは全員の `branch` を決められる。
- **エージェントが作るだけ**：`map`（`hub map` が git から作って送る。手で書かない）。

## settings（オーナーだけが書く）

### `settings/project`

| 項目 | 意味 | 補足 |
|---|---|---|
| `name` | 作品名 |  |
| `summary` | どんな作品か |  |
| `skill_source` | スキルのリポジトリ | GitHub の owner/name。メンバーがエージェントに頼む文に入る |
| `repo` | GitHub リポジトリ | owner/name |
| `base_branch` | 元にするブランチ | 既定 develop。作業ブランチを切り、PR を向けるブランチ。マージは毎回人に確かめる |
| `release_branch` | 公開ブランチ | 既定 main。人が「main にマージ」と明言したときだけ、元ブランチから取り込む |
| `areas` | 領域の一覧 |  |
| `budget_hours` | カードの既定予算（時間） |  |
| `max_sessions` | 1 人が同時に進められる作業 |  |
| `require_card` | 作業を登録するまでファイルを変更させない | オンのとき、エージェントは /hub:start でやることを登録するまで（また元ブランチでは）ファイルを変更できない。オフにしても保護パスの確認は残る |
| `protected_paths` | 保護するパス | ここにあるファイルをエージェントが変えるときは、人の確認が要る。フォルダは末尾に /、ワイルドカードは *（例 ProjectSettings/、CMakeLists.txt、*.hikari） |

### `settings/plan`

ready: オーナーがおすすめするカード id の配列（上から順。入っていなくても誰でも始められる）。assign: {カード id: 呼び名}（おすすめの担当）。milestones: [{id, title, date}]

## `cards` — カード

作業の単位。何をやるかは各自が決めてよい：自分で作って、自分で始める。オーナーの「予定」は、おすすめの順番。

- 書ける人：メンバー　／　id：`c-xxxxxx`
- 状態（`state`）：`あとで` → `作業中` → `確認待ち` → `完了`（終わり） → `やらない`（終わり）。新しく作るときは `あとで`
- 作るときに書く項目：`title`、`kind`、`summary`、`acceptance`、`paths`、`areas`、`budget_hours`、`milestone`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 | 何ができるようになるかを短く（例「敵のノックバック」） |
| `kind` | choice：機能／修正／素材／レベル／調整／調査 | 種類 |  |
| `summary` | longtext | 何をするか |  |
| `acceptance` | list | 完了条件 | 1 行に 1 つ |
| `paths` | list | 関連ファイル | 触りそうなファイル・フォルダ・シーン。1 行に 1 つ。ぶつかり予報に使う |
| `areas` | areas | 領域 |  |
| `budget_hours` | number | 予算（時間） | 空ならプロジェクト設定の既定値 |
| `milestone` | milestone | 締切 |  |
| `state` | state | 状態 | 「予定」はオーナーの計画（settings/plan の ready）で決まる。カードの state には書かない |
| `waiting` | choice：決定／レビュー／検収 | 何を待つか | state が 確認待ち のとき |
| `assignee` | member | 担当 | 作業中・確認待ちのときにやっている人 |
| `branch` | text | ブランチ |  |
| `pr` | text | PR | URL か番号 |
| `workflow` | ref | 使うワークフロー |  |
| `bug` | ref | 元の不具合 |  |
| `started_at` | time | 着手 |  |

## `reports` — 報告

1 回の作業（開始〜終了）の記録と、人の日報。

- 書ける人：メンバー　／　id：`r-xxxxxx`
- 状態（`state`）：`作業中` → `終了`（終わり） → `中断`（終わり）。新しく作るときは `作業中`
- 終了のとき必ず書く項目：`conclusion`、`changes`、`evidence`、`unverified`、`remaining`、`tuning`、`learned`、`mistakes`、`questions`（ないときは空の配列か「なし」）
- 作るときに書く項目：`today`、`next`、`trouble`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `kind` | choice：作業／日報（必須） | 種類 |  |
| `card` | ref | カード |  |
| `title` | text | 件名 | 作業ならカード名、日報なら日付 |
| `state` | state | 状態 |  |
| `model` | text | モデル |  |
| `started_at` | time | 開始 |  |
| `ended_at` | time | 終了 |  |
| `progress` | log | 進捗 | [{at, note}] の配列。節目ごとに 1 件足す |
| `conclusion` | longtext | 結論 | 何ができて、何ができなかったか |
| `changes` | list | 変更 |  |
| `evidence` | list | 確認したこと | どのシーンで何を試したか、前後の数字や画像。試していなければそう書く |
| `unverified` | list | 未確認 |  |
| `remaining` | list | 残り |  |
| `tuning` | list | 調整できるところ | この作業で作った・変えた「人が調整できるところ」を書いた調整ガイドの id。調整できるところが無い作業なら「なし：理由」を 1 行 |
| `learned` | list | 学んだこと | ナレッジに書いたものの名前（id） |
| `mistakes` | list | ミス | ミス帳に書いたものの名前（id） |
| `questions` | list | 質問 | 質問板に出したものの名前（id） |
| `workflow` | ref | 使ったワークフロー |  |
| `params` | list | ワークフローのパラメータ |  |
| `repeat` | longtext | ワークフローにする提案 | 前にも似た作業があり、また出てきそうなら：何を手順にするか、まとめるべき共通部品は何か |
| `repeat_done` | bool | 提案は片づけた |  |
| `cost_hours` | number | かかった時間 |  |
| `cost_tokens` | text | トークン |  |
| `branch` | text | ブランチ |  |
| `pr` | text | PR |  |
| `today` | longtext | 今日やったこと | 日報のとき |
| `next` | longtext | 次にやること | 日報のとき |
| `trouble` | longtext | 困っていること | 日報のとき |

## `bugs` — 不具合

見つけたけれど、いま直さない問題。現象の名前で登録する。

- 書ける人：メンバー　／　id：`b-xxxxxx`
- 状態（`state`）：`未対応` → `対応中` → `修正済み`（終わり） → `対応しない`（終わり）。新しく作るときは `未対応`
- 作るときに書く項目：`title`、`where`、`steps`、`expected`、`actual`、`frequency`、`severity`、`evidence`、`images`、`build`、`areas`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 | 現象そのまま（例「壁際で被弾すると床に埋まる」） |
| `where` | text | どこで |  |
| `steps` | list | 再現手順 |  |
| `expected` | longtext | 期待 |  |
| `actual` | longtext | 実際 |  |
| `frequency` | choice：毎回／ときどき／一度だけ | 頻度 |  |
| `severity` | choice：止まる／遊べるが困る／見た目だけ | 重さ |  |
| `evidence` | list | 証拠 | ログ、数値、ファイルの場所 |
| `images` | assets | 画像・動画 |  |
| `build` | text | ビルド | コミット（git rev-parse --short HEAD） |
| `areas` | areas | 領域 |  |
| `state` | state | 状態 |  |
| `card` | ref | 対応カード |  |

## `questions` — 質問板

わからないこと。先にナレッジと過去の質問を探し、なければ出す。答えられる人・エージェントが答える。

- 書ける人：メンバー　／　id：`q-xxxxxx`
- 状態（`state`）：`未回答` → `回答あり` → `解決`（終わり）。新しく作るときは `未回答`
- 作るときに書く項目：`title`、`context`、`to`、`areas`、`paths`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 質問 |  |
| `context` | longtext | 背景・調べたこと |  |
| `to` | text | 誰に | 「エージェント」「オーナー」かメンバーの呼び名。方向・仕様・見た目はオーナーへ |
| `areas` | areas | 領域 |  |
| `paths` | list | 関連ファイル |  |
| `state` | state | 状態 |  |
| `answers` | answers | 回答 | {回答 id: {by, by_agent, at, text, evidence[]}} のマップ。update で自分の回答だけを足す（ほかの回答を消さない） |
| `conclusion` | longtext | 結論 |  |

## `guides` — 調整ガイド

作った機能を、人があとから調整できるようにする案内。機能ごとに 1 つ：エディタで変えられる値と、コードで微調整するところ。エージェントは機能を作る・変えるたびに必ず書く。

- 書ける人：メンバー　／　id：`g-xxxxxx`
- 状態（`state`）：`有効` → `古い`（終わり）。新しく作るときは `有効`
- 作るときに書く項目：`title`、`summary`、`params`、`code`、`check`、`areas`、`paths`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 機能の名前 | 人が探すときの言葉で（例「敵のノックバック」） |
| `summary` | longtext（必須） | 何をするものか | 仕組みを 2〜4 行で。どのコンポーネント・システムが何を持つか |
| `params` | list | エディタで調整できる値 | 1 行に 1 つ：コンポーネント名.項目名 — 何が変わるか（既定値・範囲・単位）。どのプレハブ・シーンに付いているかも |
| `code` | list | コードで微調整するところ | 1 行に 1 つ：ファイル:関数や定数 — そこを変えると何が変わるか。エディタに出せなかった理由も |
| `check` | longtext | 確かめ方 | どのシーンで、何をすると、調整の結果が見えるか |
| `areas` | areas | 領域 |  |
| `paths` | list | 関連ファイル |  |
| `card` | ref | 作ったカード |  |
| `state` | state | 状態 |  |

## `knowledge` — ナレッジ

作品で分かったやり方・ハマりどころ・仕様メモ。新しいものは「要確認」、別の人が確かめたら「有効」。

- 書ける人：メンバー　／　id：`k-xxxxxx`
- 状態（`state`）：`要確認` → `有効`（終わり） → `廃止`（終わり）。新しく作るときは `要確認`
- 作るときに書く項目：`title`、`body`、`areas`、`paths`、`source`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 | 一文で（例「物理の押し出しは FixedUpdate で入れる」） |
| `body` | longtext（必須） | 内容 |  |
| `areas` | areas | 領域 |  |
| `paths` | list | 関連ファイル |  |
| `source` | text | 出典 | 報告・質問・資料の id や URL |
| `state` | state | 状態 |  |
| `verified_by` | member | 確かめた人 |  |

## `mistakes` — ミス帳

やってしまった間違い。同じ領域・ファイルで作業する人の簡報に出る。

- 書ける人：メンバー　／　id：`m-xxxxxx`
- 状態（`state`）：`記録` → `防止済み`（終わり）。新しく作るときは `記録`
- 作るときに書く項目：`title`、`what`、`root_cause`、`caught_by`、`fix`、`prevention`、`areas`、`paths`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 |  |
| `what` | longtext（必須） | 何が起きたか |  |
| `root_cause` | longtext（必須） | 原因 |  |
| `caught_by` | text | どう気づいたか |  |
| `fix` | longtext | どう直したか |  |
| `prevention` | longtext（必須） | 再発防止 |  |
| `areas` | areas | 領域 |  |
| `paths` | list | 関連ファイル |  |
| `state` | state | 状態 |  |

## `decisions` — 決めること

仕様・見た目・方針・予算超過など、人が決めること。選択肢を 2 つ以上、推奨はちょうど 1 つ。

- 書ける人：メンバー　／　id：`d-xxxxxx`
- 状態（`state`）：`未決定` → `決定`（終わり） → `取り下げ`（終わり）。新しく作るときは `未決定`
- 作るときに書く項目：`title`、`context`、`options`、`decider`、`card`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 問い | 疑問文で（例「ボス第2形態に入る HP は何％？」） |
| `context` | longtext | わかっていること・わからないこと |  |
| `options` | options（必須） | 選択肢 | [{text, recommended}]。recommended が true のものはちょうど 1 つ |
| `decider` | text | 決める人 | メンバーの呼び名か「オーナー」 |
| `card` | ref | 関係するカード |  |
| `state` | state | 状態 |  |
| `choice` | text | 決めたこと |  |
| `decided_by` | member | 決めた人 |  |
| `note` | longtext | ひとこと |  |

## `locks` — 編集中

シーン・プレハブ・結合できない素材を触る前に宣言する。終わったら解除。

- 書ける人：メンバー　／　id：`l-xxxxxx`
- 状態（`state`）：`編集中` → `解除`（終わり）。新しく作るときは `編集中`
- 作るときに書く項目：`target`、`until`、`note`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `target` | text（必須） | 対象 | プロジェクト内のパス（例 Assets/Scenes/Stage2.scene） |
| `until` | text | いつまで | 目安（例 18:00、明日まで） |
| `card` | ref | カード |  |
| `note` | text | メモ |  |
| `state` | state | 状態 |  |

## `proposals` — ルール提案

ルールを変えたい・足したいときの提案。オーナーが採用するとルールに反映される。

- 書ける人：メンバー　／　id：`p-xxxxxx`
- 状態（`state`）：`提案` → `採用`（終わり） → `却下`（終わり）。新しく作るときは `提案`
- 作るときに書く項目：`title`、`rule`、`category`、`body`、`reason`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 |  |
| `rule` | ref | 対象のルール | 空なら新しいルール |
| `category` | rulecategory | 分類 | 新しいルールのとき |
| `body` | longtext（必須） | 提案する本文 | そのままルールになる文章 |
| `reason` | longtext（必須） | 理由 | 何が起きたから必要か |
| `state` | state | 状態 |  |
| `reply` | longtext | オーナーの返事 |  |

## `engine_requests` — エンジンへの要望

エンジンの機能不足・不具合。ゲーム側でエンジンを直さず、ここに出す。オーナーがエンジン中枢へ送る。

- 書ける人：メンバー　／　id：`e-xxxxxx`
- 状態（`state`）：`未送付` → `受付済み` → `対応済み`（終わり） → `対応しない`（終わり）。新しく作るときは `未送付`
- 作るときに書く項目：`title`、`kind`、`detail`、`workaround`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 | 足りないこと・起きていることをそのまま |
| `kind` | choice：機能不足／不具合／使い方の質問／知識の訂正 | 種類 | 「知識の訂正」は、ハブのエンジン知識が SDK のヘッダと食い違っていたとき |
| `detail` | longtext（必須） | 詳しく | 何をしたくて、どの API・画面で、何が足りないか |
| `workaround` | longtext | 今の回避策 |  |
| `state` | state | 状態 |  |
| `engine_ref` | text | エンジン側の記録 |  |
| `fixed_in` | text | 直った版 |  |

## `design` — 設定集

このゲームの遊び方と全体の設定。オーナーが書く。エージェントは作業の前に「必読」のページと、自分のカードの領域に関係するページを読み、このゲームらしさを外さない。

- 書ける人：オーナーだけ　／　id：`ds-xxxxxx`
- 状態（`state`）：`下書き` → `確定`。新しく作るときは `下書き`
- 作るときに書く項目：`title`、`section`、`body`、`areas`、`must`、`order`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 見出し |  |
| `section` | choice：コンセプト／遊び方／操作／キャラクター／敵／ステージ／UI／演出／音／アート／その他 | 章 |  |
| `body` | longtext | 内容 |  |
| `areas` | areas | 関係する領域 |  |
| `must` | bool | 必読（全員が作業の前に読む） |  |
| `order` | number | 章の中の順番 |  |
| `state` | state | 状態 |  |
| `source` | text | 根拠 | エージェントが下書きしたとき：どのファイル・報告から書いたか |

## `workflows` — ワークフロー

何度もやる作業の、確かめた手順（必ずやること、必ず書くコード、確かめ方）。エージェントが下書きし、オーナーが試して「検証済み」にする。カードに合うワークフローがあれば、エージェントはその手順どおりに作業する。

- 書ける人：メンバー　／　id：`wf-xxxxxx`
- 状態（`state`）：`下書き` → `試してほしい` → `検証済み` → `使わない`（終わり）。新しく作るときは `下書き`
- 作るときに書く項目：`title`、`summary`、`params`、`steps`、`checks`、`stops`、`refactor`、`model`、`areas`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 |  |
| `summary` | longtext | いつ使う・何ができあがる・やらないこと |  |
| `params` | list | パラメータ | 1 行に 1 つ：名前：説明。既定値があれば 名前=既定値：説明。手順の中で {名前} と書く |
| `steps` | list | 手順 | 1 行に 1 手順：どのファイルを作る・変える、何を書く、終わったら何を確かめる |
| `checks` | list | 終わったときの確かめ方 |  |
| `stops` | list | ここで止まってオーナーに聞く |  |
| `refactor` | list | 量産の前に共通部品にまとめること | 同じコードを毎回書くなら、先に共通のコンポーネント・定義アセットにまとめる。まとめた後はデータを足して調整するだけになる |
| `model` | text | 向いているモデル |  |
| `areas` | areas | 領域 |  |
| `scope` | choice：共通／この作品 | 範囲 | 共通：スキルに入っていて新しい作品にも入る。この作品：この作品だけ |
| `state` | state | 状態 |  |
| `runs` | number | 使った回数 |  |
| `last_run` | time | 最後に使った |  |
| `fixes` | log | 使ったときの改善案 |  |
| `history` | log | 変更の記録 |  |
| `source` | text | 元にした報告 |  |

## `rules` — ルール

この作品の決まり。オーナーだけがページで書き換えられる。エージェントは作業の前に必ず読む。

- 書ける人：オーナーだけ　／　id：`rule-xxxxxx`
- 作るときに書く項目：`title`、`category`、`body`、`core`、`areas`、`order`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 |  |
| `category` | rulecategory（必須） | 分類 |  |
| `body` | longtext（必須） | 本文 |  |
| `core` | bool | 必ず簡報に入れる |  |
| `areas` | areas | 領域 | 空なら全体に効く |
| `order` | number | 並び順 |  |

## `engine` — エンジン知識

HIKARI エンジンでゲームを作るときの考え方と進め方。API の名前や引数は、エージェントがいま入っている SDK のヘッダを自分で読んで確かめる。

- 書ける人：オーナーだけ　／　id：`eng-xxxxxx`
- 作るときに書く項目：`title`、`area`、`body`、`must`、`order`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `title` | text（必須） | 名前 |  |
| `area` | choice：はじめに／コード／エディタ／ビルド／落とし穴／資料 | 分類 |  |
| `body` | longtext（必須） | 本文 |  |
| `must` | bool | 必読 |  |
| `order` | number | 並び順 |  |

## `members` — メンバー

ドキュメント id は本人の uid（ログインした Google アカウントごとの id。`hub whoami` で分かる）。本人が自分のものを書く。オーナーは全員の「自分のブランチ」を決められる。

- 書ける人：本人だけ
- 作るときに書く項目：`handle`、`branch`、`role`、`github`、`note`

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `handle` | text（必須） | 呼び名 | 半角英数字（例 hikari）。報告・担当に使う |
| `branch` | text | 自分のブランチ | その人の develop（例 develop_kou）。作業ブランチはここから切り、ここへ取り込む。元ブランチ（develop）へ入れるのはオーナーだけ。半角英数字と . _ - |
| `role` | text | 担当 | 例 プログラマー、デザイナー、プランナー |
| `github` | text | GitHub |  |
| `note` | text | ひとこと |  |

## `map` — 地図

ブランチごとの、ファイルのまとまり（区画）・区画どうしのつながり（#include、素材の GUID、シーンのコンポーネント）・元ブランチとの違い。ドキュメント id はブランチ名。エージェントが `hub map` で git から作って送る（手で書かない）。

- 書ける人：メンバー
- 作るときに書く項目：

| 項目 | 型 | 意味 | 補足 |
|---|---|---|---|
| `branch` | text（必須） | ブランチ |  |
| `role` | choice：base／release／personal | 役割 | base = 元ブランチ（develop）、release = 公開ブランチ（main）、personal = だれかの自分のブランチ |
| `member` | member | 持ち主 |  |
| `compare` | text | 比べた相手 | 自分のブランチは元ブランチと、元ブランチは公開ブランチと比べる |
| `ahead` | number | 相手に無いコミット |  |
| `behind` | number | 取り込んでいないコミット |  |
| `head` | object | 最新のコミット | {commit, subject, author, at} |
| `changed` | objects | 変わったファイル | 比べた相手との分かれ目からの違い。[{path, node, status（A/M/D）, add, del}]。多いときは先頭 500 件 |
| `changed_total` | number | 変わったファイルの数 |  |
| `last` | object | 最後の変更 | ページで強調する。自分のブランチは、比べた相手にまだ無い自分のコミットのうち最新（develop に追いつくためのマージは除く。カード 1 枚 = squash 1 つ）、develop・main は最新のコミット。{commit, subject, author, at, changed_total, changed: [{path, node, status, add, del}]}（先頭 200 件） |
| `nodes` | objects | 区画 | [{id, kind, files, bytes}]。id はフォルダ（例 Source/Runtime/Boss）かシーンのファイル。@ で始まるものはリポジトリの外（@sdk = エンジンの SDK、@type:<名前> = エンジンや外部モジュールのコンポーネント） |
| `edges` | objects | つながり | [{from, to, kind, n}]。kind：include（#include）、asset（素材の GUID で参照）、component（シーンがコンポーネントの型を使う）、engine（エンジンの SDK を使う）。n は参照の数 |
| `sdk` | objects | 使っているエンジンのヘッダ | [{header, n}] |
| `mapped_at` | time | 作った時刻 |  |
| `mapped_by` | member | 作った人 |  |

## 型の意味

- `text`・`longtext`：文字列（`longtext` は Markdown 可）　`number`：数値　`bool`：true / false
- `list`：文字列の配列　`areas`：`settings/project` の `areas` にある名前の配列
- `choice`：書いてある候補のどれか　`state`：そのコレクションの状態のどれか
- `member`：メンバーの呼び名　`ref`：ほかの記録の id　`milestone`：`settings/plan` の milestones の id
- `time`：ISO 8601 の日時　`log`：`[{at, note}]` の配列　`options`：`[{text, recommended}]` の配列
- `answers`：`{回答 id: {by, by_agent, at, text, evidence}}` のマップ　`assets`：ページで上げた画像の id の配列（エージェントは書かない）
- `object`・`objects`：形が決まったオブジェクトと、その配列（形は補足に書いてある）
