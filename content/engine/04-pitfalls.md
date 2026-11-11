<!-- area: 落とし穴 -->
<!-- id: eng-lifecycle; must: true; order: 10 -->
## ライフサイクル：Attach はゲーム開始ではない

- `OnWorldAttached` / コンポーネントの `OnAttach` は、エディタでの読み込み、オブジェクトの追加、World の作り直しでも呼ばれる。ここにゲームの副作用（スコアの初期化、敵の出現）を書かない。
- システムとコンポーネントの `Update` は**編集中にも**呼ばれることがある。ゲームのルールは Play 中だけ動かす：
  - `world.GetGameSession()` が `nullptr` でない（Play の外では `nullptr`）
  - または `world.GetRuntimeSession().IsPlayActive()`
- ゲーム開始・シーンの出入りの処理は `IGameProjectSession` に書く。順番は：`OnGameStarted` → 最初のシーンの `OnSceneEntered` → （切替のたびに `OnSceneExiting` → World の入れ替え → `OnSceneEntered`）→ `OnGameStopped`（引数なし。最後の World が外れたあと）。
- システムとコンポーネントのメンバーは、その World と一緒に消える。シーンをまたぐ状態をそこに置かない。

<!-- id: eng-lifetime; must: true; order: 20 -->
## 持ち出してはいけないもの

- `WorldView` から取ったサービスの View、クエリ中のコンポーネントへの参照、借りた文字列（`std::string_view`）は、**そのコールバックの中だけ**で使う。シーンが変わったら取り直す。
- オブジェクトを覚えておくなら `GameProjectObjectHandle`。使う前に `world.FindObject(handle).IsValid()` を確かめる。
- ハンドルは保存できない。セーブにはシーンの GUID とシーンオブジェクト id（`ObjectView::GetSceneObjectId()`）を書き、読み込んだあとで解決し直す。
- `world.GetGameSession()` のポインタは、その Play のあいだだけ有効。

<!-- id: eng-accepted; must: true; order: 30 -->
## 「受け付けた」は「終わった」ではない

- `SpawnObject` などの結果は `GameProjectWorldResult`。クエリやシステムの途中では `Queued` が返ることがあり、これも成功。**`Accepted()` で確かめる**（`Succeeded()` だけ見ると取りこぼす）。新しいオブジェクトは区切りまで存在しないことがある。失敗は `world.GetCommandFailureCount()` / `ReadCommandFailure(...)` で読める。
- `GetSceneFlow().RequestScene(...)` の `true` は「受け付けた」だけ。読み込みはあとで終わり、失敗することもある。結果が要るなら `RequestSceneTracked(...)` と `ReadRequestResult(...)` を使う。
- プレハブの生成も非同期。`RequestInstantiate` のあと `ReadRequestResult` で結果を読む。
- イベント（`ReadEvent`）をフレームをまたいで読むときは、番号で重複を除く。
- Play 中の変更はエディタのシーンに書き戻されない。

<!-- id: eng-donts; must: true; order: 40 -->
## やってはいけないこと

- エンジンの非公開ヘッダ（`HIKARI/Scene`、`HIKARI/Render3D`、`HIKARI/Gfx`、エディタの内部）を include する。
- エンジンのソースを直す。
- `CreateGameProjectModule()` を 2 つ定義する。
- `DescribeProperties` の保存キー、`typeName`、`systemId` をあとから変える。
- コードと内蔵のキャラクターコントローラーで、同じキャラの Transform を同時に動かす（移動は `GetMotion()` に意図を渡す）。
- `SpawnObjectsWithComponents` に内蔵コンポーネントを入れようとする（作れるのは自作コンポーネントだけ）。
- シーンやアセットのファイルを手で書き換える。
- 速さ・時間・距離・色などの調整値をコードに直書きする。

<!-- id: eng-fluid-follow; must: false; order: 50 -->
## キャラクターに付いて行く流体の域（煙の場）

- 流体の域（Fluid 層）は既定で世界空間：再生を始めた位置に格子が固定され、あとで効果を動かしても域は動かない（動くのは中の源だけ）。`VfxView::Update` の位置も `SetVelocity` も、世界空間の域の位置は変えない。置いた場所で煙を受け止める使い方（剣気の尾迹を受ける場など）のための既定。
- 付いて行かせるなら、域の層で「ドメインをレイヤーに追従」（`basic.localSimulation`）をオンにし、「相対風」（`fluidDomain.relativeWind`）を `1` にする。域は層の変換（`Update` の位置、`SetVelocity`、付けた物体）に付いて行き、煙は世界に残る。相対風が 0 だと煙は域と一緒に動く。
- この設定なら、ほかの効果の流体注入層（親の無い FluidSource）は、動いた後の域にもそのまま入る。
- 効果のファイルをエディタの外で変えたら、取り込み直すまで実行には反映されない。`fluidDomain` に無い名前（`localSpace` など）は読まれない。
