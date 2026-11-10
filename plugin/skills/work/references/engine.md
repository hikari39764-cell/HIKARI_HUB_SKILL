# HIKARI エンジンの必須知識（自動生成：content/engine から）

ハブの `engine` コレクションが正。ここはハブに届かないときの控え。

# はじめに

## この知識の使い方（最初に読む）　［必読］

エンジン知識には 2 種類ある。

- **考え方**（版の印がないもの）：役割分担、ライフサイクルの落とし穴、確かめ方など。SDK の版が変わっても使える。
- **版ごとの控え**（「SDK 4.17 の時点」のように版の印があるもの）：API の名前・一覧・コード例。その版のヘッダから書き写したもので、SDK が更新されると古くなる。**道しるべとして読み、正確な内容は必ずヘッダで確かめる。**

守ること：

- **正しいのは常に、いま入っている SDK のヘッダ**（`<HIKARI>/Sdk/include/HIKARI/Project/*.h`）。使う API は、呼ぶ前にそのヘッダのコメントを読む。コメントに寿命・スレッド・失敗時の扱いが書いてある。
- **版を確かめる**：プロジェクトの `CMakeLists.txt` の `find_package(HIKARI <版> CONFIG REQUIRED)`、入っている SDK の `HIKARI/Project/GameProjectSdk.h`（`HIKARI::SDK::kVersionMajor / kVersionMinor / kVersionPatch`）、ハブのプロジェクト設定の「HIKARI SDK のバージョン」。食い違っていたら人に伝える。控えの版がプロジェクトの版と違うときは、その控えを当てにしない。
- **食い違いを見つけたら直す仕組みに乗せる**：ハブの知識がヘッダと違っていたら、ヘッダに従って作業し、ハブの「エンジンへの要望」に種類「知識の訂正」で出す（どの項目が、ヘッダのどこと、どう違うか）。
- SDK の `docs/` にある古い手引きは内容が古いことがある。食い違ったらヘッダに従う。
- 公開ヘッダにない機能は「まだない」。非公開ヘッダで回避せず、ハブの「エンジンへの要望」に出す。

## 全体像：誰が何を持つか　［必読］

- ゲームは独立した C++ プロジェクト。`HIKARI_GameProject.dll` にビルドされ、エンジン（エディタ／実行時）が読み込む。
- **エンジンが持つ**：ウィンドウ、描画、入力の取得、物理の進行、メインループ、アセットの読み込み、オブジェクトの寿命。
- **ゲームのコードが持つ**：ルール（条件、判断、状態遷移、進行）。
- **エディタで作る**：シーン、プレハブ、見た目、調整する数値。
- コードは「いつ・どんな規則で」を決め、「どう見えるか・どれくらいか」はコンポーネントのフィールドかアセットに出してエディタで調整する。
- エンジンのソースは直さない。`WinMain` も書かない。include するのは `HIKARI/Project/*` と `HIKARI/Runtime/ComponentTypeId.h` だけ。

## プロジェクトの構成　［必読］

```text
MyGame/
  Assets/            エディタで作るシーン・モデル・VFX・UI・フォントなど
  ProjectSettings/   機能の有効化、入力、物理、起動シーンなど
  Source/Runtime/    ゲームのコード（ゲームと一緒に配布される）
  Source/Editor/     （任意）エディタ拡張。CMake で別に宣言する
  Data/              （任意）作品のテキストデータ。実行時は読み取り専用
  Library/           ビルド・インポートの結果。コミットしない
  Project.hikari     ランチャーが開くプロジェクトの記述
  CMakeLists.txt     find_package(HIKARI ...) と hikari_add_game_project(...)
```

- `Source/Runtime` に足した `.h` / `.cpp` は CMake が自動で集める。
- `CMakeUserPresets.json` はエディタが PC ごとに書く。コミットしない。
- テンプレートの `.gitattributes` は `Assets/` の `.bin` `.dds` `.png` を Git LFS にしている。

## 新規プロジェクトのコードの形（4 つの部品）　［必読］

`Source/Runtime/*GameProjectModule.cpp` に次の 4 つが入っている。普段さわるのは上の 2 つ。

| 部品 | 基底 | 役割 |
|---|---|---|
| `GameSession` | `HIKARI::IGameProjectSession` | 1 回の Play のあいだ、シーンをまたいで残す状態 |
| `Game` | `HIKARI::IGameSystem` | 毎フレーム呼ばれるゲームの処理 |
| `GameplayFeature` | `HIKARI::IRuntimeFeature` | コンポーネントとシステムの登録（`Register`）と既定のシステム一覧 |
| `GameProjectModule` | `HIKARI::RUNTIME::IGameProjectModule` | Feature の登録（`RegisterRuntimeFeatures`）とセッションの生成（`CreateGameSession`） |

- 最後に `HIKARI::RUNTIME::CreateGameProjectModule()` が 1 つだけ定義されている。**2 つ目を書かない。**
- テンプレートの `Game::Update` は `world.GetGameSession()` を `dynamic_cast<GameSession*>` で取り、`nullptr`（＝Play 中でない）なら何もしない。この形を崩さない。

# コード

## どこに何を書くか　［必読］

| やりたいこと | 書く場所 |
|---|---|
| ゲーム全体の進行（ラウンド、勝敗、スコア） | `IGameSystem`（テンプレートの `Game`）＋普通の C++ クラス |
| オブジェクトごとの値をエディタで調整したい | `IGameComponent` に値を持たせ、`DescribeProperties` で宣言 |
| 同じ種類のオブジェクトをまとめて動かす | コンポーネントはデータだけ、`IGameSystem` が `ForEachComponent` で処理 |
| 1 個のオブジェクトだけの小さな動き | `IGameComponent::Update(GameComponentContext&, float)` |
| シーンをまたいで残す状態（所持品、進行度） | `IGameProjectSession`（テンプレートの `GameSession`） |
| 次の起動でも残すデータ | 自分で決めた形式を `SaveGameView`（`GameFlowViews.h`）で読み書き |

- 中のクラスが全部エンジンの型を継承する必要はない。`RoundRules` や `Inventory` は普通のクラスでよい。
- 同じ状態を複数の場所で持たない。持ち主を 1 つに決める。

## システム（IGameSystem）　［必読］

`HIKARI/Project/GameSystem.h`。必要なものだけ override する。

- 呼ばれる順：`PreUpdate` → （固定刻みの回数だけ `PreFixedUpdate` → `FixedUpdate` → `PostFixedUpdate`）→ `Update` → `LateUpdate` → `PreRender` → `Render` → `PostRender`
- `OnWorldAttached` / `OnWorldDetached`：World に付いた・外れたとき。**ゲーム開始の合図ではない**（編集中にも呼ばれる）。
- `DescribeSettings(PropertyFields&)`：シーンに保存するシステムの設定を宣言する。
- 引数の `FrameContext`（`FrameContext.h`）：
  - `gameDt`：ゲームの時間（時間倍率込み）。普通はこれを使う
  - `fixedDt`：固定刻み（既定 1/60 秒）。`FixedUpdate` で使う
  - `unscaledDt`：時間倍率をかける前。ポーズ中の UI など
  - `paused`、`frameIndex`、`fixedStepsThisFrame`、`fixedInterpolationAlpha` など
- 物理に関わる動き（押し出し、力、移動の意図）は `FixedUpdate` に書く。

```cpp
class Game final : public HIKARI::IGameSystem {
public:
    void Update(HIKARI::WorldView& world, const HIKARI::FrameContext& frame) override {
        auto* session = dynamic_cast<GameSession*>(world.GetGameSession());
        if (session == nullptr || frame.paused) {
            return; // Play 中でない、またはポーズ中
        }
        session->gameplaySeconds += frame.gameDt;
    }
};
```

## コンポーネントと、エディタで調整できる値　［必読］

`HIKARI/Project/GameComponent.h`、`PropertyFields.h`。値は `DescribeProperties` に **1 項目 1 行で 1 回だけ** 書く。同じ宣言が、シーンからの読み込み・保存・インスペクタ表示の 3 つに使われる。

```cpp
class KnockbackComponent final : public HIKARI::IGameComponent {
public:
    void DescribeProperties(HIKARI::PropertyFields& fields) override {
        if (!fields.Section("Knockback", true)) {
            return;
        }
        fields.Float("distance", "Distance (m)", distance, 0.0f, 10.0f, 0.05f);
        fields.Float("seconds", "Seconds", seconds, 0.0f, 2.0f, 0.01f);
    }

    float distance = 1.5f;
    float seconds = 0.2f;
};
```

- 1 つ目の引数は**保存キー**。あとから変えると保存済みの値が読めなくなる。変えない。
- 保存値がない項目は、メンバーの初期値のまま。範囲付きの数値は読み込み時にも範囲に収まる。
- `Section` は読み込み・保存のときは必ず `true` を返す（インスペクタで閉じていても中の項目は処理される）。
- 使える項目：`Bool`、`Int`、`Float`、`Float3`、`Color3`、`Text`、`Choice`（名前で保存する選択肢。enum 版もある）、`SceneObject`（シーン内オブジェクトの参照）、`Asset` / `AssetId`（種類を選んで GUID で参照。Cook が依存を集める）、`Texture`、`Vfx`、`InputAction`、`Variable`、`Event`。`Note` と `Button` はインスペクタ専用。
- コールバックに渡る `GameComponentContext` から `GetObject()`、`GetWorld()`、変数の読み書き、`EmitEvent` が使える。コールバックの外に持ち出さない。
- コンポーネントに `World*` やエンジン内部のポインタを持たせない。フレームをまたいでオブジェクトを指すなら `GameProjectObjectHandle`（`ObjectView::GetHandle()`）を持つ。

## 登録（Feature の Register）　［必読］

`HIKARI/Project/RuntimeRegistration.h`。作ったコンポーネントとシステムは、Feature の `Register` で登録しないと存在しない。

```cpp
constexpr std::string_view kKnockbackType = "MyGame.Knockback";
constexpr std::string_view kKnockbackSystem = "MyGame.KnockbackSystem";

bool Register(HIKARI::RuntimeFeatureContext& context) override {
    return context.RegisterSystem<Game>({.systemId = "MyGame.Game", .displayName = "Game"}) &&
           context.RegisterComponent<KnockbackComponent>({.typeName = kKnockbackType, .displayName = "Knockback"}) &&
           context.RegisterSystem<KnockbackSystem>({.systemId = kKnockbackSystem, .displayName = "Knockback"}) &&
           context.BindComponentSystem({.componentType = kKnockbackType, .systemId = kKnockbackSystem});
}
```

- `typeName` と `systemId` は**変えない識別子**（大文字小文字を区別）。シーンに保存される。`<作品名>.<名前>` の形にする。
- `BindComponentSystem`：そのコンポーネントがシーンにあれば、結び付けたシステムが自動で動く。コンポーネントに付くルールはこれを使う。
- `GetDefaultSystems()`：いつも動かす全体のシステムの一覧（テンプレートでは `Game`）。
- `Register` には登録以外の処理を書かない（エンジンが一覧を作るために試しに呼ぶ）。
- 上の例は形を示すもの。include とコンパイルは自分で確かめる。

## オブジェクトを探す・まとめて処理する　［必読］

`HIKARI/Project/WorldView.h`、`HIKARI/Runtime/ComponentTypeId.h`。

```cpp
world.ForEachComponent<KnockbackComponent>(
    HIKARI::MakeComponentTypeId(kKnockbackType),
    [&](HIKARI::ObjectView object, KnockbackComponent& knockback) {
        HIKARI::GameProjectTransform transform{};
        if (object.GetWorldTransform(transform)) {
            // ...
        }
    });
```

- エディタで選んだオブジェクトを指す：コンポーネントに `fields.SceneObject("target", "Target", targetId_)` を置き、`world.FindSceneObject(targetId_)` で解決して `IsValid()` を確かめる。
- ハンドルから：`world.FindObject(handle)`。
- **名前や Tag で探す公開 API はない。** 「同じ名前なら自動でつながる」仕組みもない。参照はフィールドで持つ。
- `ObjectView`：`GetName`、`GetSceneObjectId`、`GetLocalTransform` / `GetWorldTransform`、`SetLocalTransform` / `SetWorldTransform`、`GetParent`。内蔵コンポーネントの操作は `GetLight`、`GetDecal`、`GetModel`、`GetWorldSprite`、`GetWorldText`、`GetSpriteAnimation`、`GetSpriteMaterial`、`GetMaterialFx`（対象がなければ各操作が Unsupported を返す）。

## やりたいこと → 使うもの　［必読］

サービスは `WorldView` から取る。`WorldView.h` は型を前方宣言しているだけなので、**使うサービスのヘッダを include する**。

| やりたいこと | 取り方 | ヘッダ |
|---|---|---|
| 入力（アクション、ポインタ、振動） | `world.GetInput()` | `ActionViews.h` |
| キャラの移動、物理クエリ | `world.GetMotion()`、`world.GetPhysicsQueries()` | `ActionViews.h` |
| モデルのアニメーション | `world.GetAnimation()` | `ActionViews.h` |
| ゲームカメラ、揺れ、時間の遅さ | `world.GetCamera()`、`world.GetTimeDilation()` | `ActionViews.h` |
| エフェクトを出す・動かす・止める | `world.GetVfx()` | `VfxView.h` |
| 音 | `world.GetAudio()` | `AudioView.h` |
| HUD（画像・文字・背景ぼかし） | `world.GetUi()` | `UiView.h` |
| カメラ演出（シーケンス） | `world.GetSequence()` | `SequenceView.h` |
| プレハブを出す | `world.GetPrefabs()` | `PrefabView.h` |
| シーン切替、会話、セーブ、Play 中か | `world.GetSceneFlow()`、`GetDialogue()`、`GetSaveGame()`、`GetRuntimeSession()` | `GameFlowViews.h` |
| 経路探索 | `world.GetNavigation()` | `NavigationView.h` |
| 地形、地面への光線 | `world.GetTerrain()`、`world.RaycastGround(...)` | `TerrainView.h`、`GroundSource.h` |
| 時刻・天気、局所の霧、流体の煙 | `GetEnvironment()`、`GetLocalFog()`、`GetFluid()` | `EnvironmentView.h`、`LocalFogView.h`、`FluidView.h` |
| 作品のテキストデータを読む | `world.GetProjectData().ReadText(...)` | `ProjectDataView.h` |
| 画質・ウィンドウ設定 | `world.GetDisplaySettings()` | `DisplaySettingsView.h` |
| 共有の変数・イベント | `world.ReadVariable` / `WriteVariable` / `EmitEvent` / `ReadEvent` | `WorldView.h` |
| オブジェクトを作る・消す・親子にする | `world.SpawnObject` / `DestroyObject` / `SetParent` | `WorldView.h`、`WorldTypes.h` |

- 戻り値を必ず確かめる。View の `IsValid()` は「使える状態か」であって、個々の操作の成功ではない。
- 入力の例：

```cpp
HIKARI::GameProjectInputActionState interact{};
if (world.GetInput().GetAction("Gameplay.Interact", interact) && interact.pressed) {
    // 押された瞬間
}
```

- HUD は `SubmitSprite` / `SubmitText` / `SubmitBackdrop` を**毎フレーム**呼んで描く。シーンに物を足すわけではない。
- 実行中に出すものはエディタでプレハブにしておき、`GetPrefabs().RequestInstantiate(...)` → `ReadRequestResult(...)` で結果を読み、終わったら `ReleaseRequest(...)`。
- 内蔵の Model・Camera・Collider などをコードで一から組み立てる前提にしない。プレハブで用意する。

# ビルド

## ビルドして確かめる　［必読］

エンジンを入れた場所の `Sdk` にあるスクリプトで、**ゲームだけ**をビルドする（エンジンはビルドしない）。

```powershell
$sdk = '<HIKARI のインストール先>\Sdk'
& "$sdk\Tools\Build-HikariProject.ps1" -Project '<ゲームのフォルダ>\Project.hikari' -SdkRoot $sdk -Preset editor-release
```

- `-Preset`：`editor-release`（普段）／`debug`／`game-shipping`（書き出し用）。`-ForceBuild` で必ず作り直す。
- ログ：`Library/Build/HIKARI_ProjectBuild.log`。失敗したらまずこれを読む。
- 結果：`Library/Build/editor-release/bin/HIKARI_GameProject.dll`
- C++ のコンパイルには x64 の MSVC と Windows SDK が要る（CMake は SDK に入っている）。
- **警告ゼロでビルドが通ること**が、コードを変えたカードの最低条件。通していないなら報告の「未確認」に書く。
- `<HIKARI のインストール先>` が分からないときは人に聞く（PC ごとに違う。リポジトリに書かない）。

## 変更が反映される条件　［必読］

- 実行中の DLL はソースを変えても変わらない。**Play を止めてから**ビルドし、プロジェクトを開き直す。状態を保ったままのホットリロードはない。
- エンジンをコマンドラインで動かしても、ゲームのモジュールは再ビルドされない。ソースを変えたら先にビルドする。
- 新しいシステムが動かないとき：
  1. Feature の `Register` で登録したか
  2. コンポーネントに付くルールなら `BindComponentSystem` で結び付けたか
  3. 全体のシステムなら `GetDefaultSystems()` に入っているか。既存のシーンは自分のシステム一覧を保存しているので、シーンの「システム」設定も見る
  4. エンジンのログの `[SceneSystem] active schedule` に名前が出ているか
- 入力が効かないとき：DLL が新しいか、Play 中か、ゲーム画面をクリックしたか、入力設定にそのアクションがあるか、UI の入力コンテキストが Gameplay を止めていないか。

## エージェントが確かめられること・人に頼むこと　［必読］

- 確かめられる：ビルドが警告ゼロで通ること、ロジックの単体の確認（計算、状態遷移）。
- 人に頼む：見た目、手触り、音、実機でのプレイ。エージェントはエディタやゲームを勝手に起動しない。
- 見た目や手触りを確かめていないカードは「確認待ち（検収）」にして、報告の「未確認」に何を見てほしいかを書く。
- エンジンは知らないコマンドライン引数を無視して普通にエディタを開く。資料にない引数を推測で使わない。

## IDE で書く

- エディタがプロジェクトを開く・ビルドするたびに、`CMakeLists.txt` の横に `CMakeUserPresets.json`（その PC 用）を書く。VS Code（CMake Tools）や Visual Studio で `hikari-ide` プリセットを選ぶと SDK のヘッダが補完される。
- IDE のビルドは確認用。エディタが読むモジュールは `Build-HikariProject.ps1`（またはエディタ）のビルド。
- CMake Tools が「No cache object found」と言ったら `Library/Build/CMake/ide` を消して設定し直す。

# 落とし穴

## ライフサイクル：Attach はゲーム開始ではない　［必読］

- `OnWorldAttached` / コンポーネントの `OnAttach` は、エディタでの読み込み、オブジェクトの追加、World の作り直しでも呼ばれる。ここにゲームの副作用（スコアの初期化、敵の出現）を書かない。
- システムとコンポーネントの `Update` は**編集中にも**呼ばれることがある。ゲームのルールは Play 中だけ動かす：
  - `world.GetGameSession()` が `nullptr` でない（Play の外では `nullptr`）
  - または `world.GetRuntimeSession().IsPlayActive()`
- ゲーム開始・シーンの出入りの処理は `IGameProjectSession` に書く。順番は：`OnGameStarted` → 最初のシーンの `OnSceneEntered` → （切替のたびに `OnSceneExiting` → World の入れ替え → `OnSceneEntered`）→ `OnGameStopped`（引数なし。最後の World が外れたあと）。
- システムとコンポーネントのメンバーは、その World と一緒に消える。シーンをまたぐ状態をそこに置かない。

## 持ち出してはいけないもの　［必読］

- `WorldView` から取ったサービスの View、クエリ中のコンポーネントへの参照、借りた文字列（`std::string_view`）は、**そのコールバックの中だけ**で使う。シーンが変わったら取り直す。
- オブジェクトを覚えておくなら `GameProjectObjectHandle`。使う前に `world.FindObject(handle).IsValid()` を確かめる。
- ハンドルは保存できない。セーブにはシーンの GUID とシーンオブジェクト id（`ObjectView::GetSceneObjectId()`）を書き、読み込んだあとで解決し直す。
- `world.GetGameSession()` のポインタは、その Play のあいだだけ有効。

## 「受け付けた」は「終わった」ではない　［必読］

- `SpawnObject` などの結果は `GameProjectWorldResult`。クエリやシステムの途中では `Queued` が返ることがあり、これも成功。**`Accepted()` で確かめる**（`Succeeded()` だけ見ると取りこぼす）。新しいオブジェクトは区切りまで存在しないことがある。失敗は `world.GetCommandFailureCount()` / `ReadCommandFailure(...)` で読める。
- `GetSceneFlow().RequestScene(...)` の `true` は「受け付けた」だけ。読み込みはあとで終わり、失敗することもある。結果が要るなら `RequestSceneTracked(...)` と `ReadRequestResult(...)` を使う。
- プレハブの生成も非同期。`RequestInstantiate` のあと `ReadRequestResult` で結果を読む。
- イベント（`ReadEvent`）をフレームをまたいで読むときは、番号で重複を除く。
- Play 中の変更はエディタのシーンに書き戻されない。

## やってはいけないこと　［必読］

- エンジンの非公開ヘッダ（`HIKARI/Scene`、`HIKARI/Render3D`、`HIKARI/Gfx`、エディタの内部）を include する。
- エンジンのソースを直す。
- `CreateGameProjectModule()` を 2 つ定義する。
- `DescribeProperties` の保存キー、`typeName`、`systemId` をあとから変える。
- コードと内蔵のキャラクターコントローラーで、同じキャラの Transform を同時に動かす（移動は `GetMotion()` に意図を渡す）。
- `SpawnObjectsWithComponents` に内蔵コンポーネントを入れようとする（作れるのは自作コンポーネントだけ）。
- シーンやアセットのファイルを手で書き換える。
- 速さ・時間・距離・色などの調整値をコードに直書きする。

# 資料

## ヘッダの読み方（困ったらここから）　［必読］

`<HIKARI>/Sdk/include/HIKARI/Project/` にある。名前の付け方：

- `〜View.h` / `〜Views.h`：`WorldView` から取るサービス（操作の窓口）
- `〜Types.h`：その機能で使う構造体と enum
- `GameSystem.h`、`GameComponent.h`、`PropertyFields.h`、`FrameContext.h`、`GameProjectSession.h`：ゲームコードの土台
- `RuntimeFeature.h`、`RuntimeRegistration.h`、`GameProjectModule.h`：登録
- `WorldView.h`、`WorldTypes.h`、`WorldQuery.h`、`ComponentViews.h`：オブジェクトと World
- `Editor〜.h`、`GameProjectEditorModule〜.h`：エディタ拡張（`Source/Editor` 用）
- `Render〜.h`、`MassSystem.h`、`World〜Types.h`：描画の拡張、大量オブジェクト（上級。必要になるまで触らない）

探し方：やりたいことの言葉で `grep` する（例 `grep -rn "Vibration" <HIKARI>/Sdk/include/HIKARI/Project`）。見つからなければ「まだない」と考えて、ハブの「エンジンへの要望」に出す。

## エンジンに足りないものを見つけたら　［必読］

1. 公開ヘッダを探して、本当にないことを確かめる。
2. ハブの「エンジンへの要望」に書く：何をしたくて、どの API・画面で、何が足りないか。SDK の版。いまの回避策。
3. ゲーム側は回避策で進める（回避策がなければ「決めること」に出す）。非公開ヘッダは使わない。
4. 直った版が書かれたら、回避策を消すカードを作る。

## 作品のテキストデータ（Data/）

- レベル設定や表のような作品のテキストは、プロジェクト直下の `Data/` に UTF-8 で置ける。
- 読むのは `world.GetProjectData().ReadText(relativePath, sink)`（`ProjectDataView.h`）。同期・読み取り専用で、プロジェクトのファイルやセーブデータは書かない。
- 形式と検証は自分のコードで決める。セーブには使わない（`SaveGameView`）。
