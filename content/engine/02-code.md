<!-- area: コード -->
<!-- id: eng-where-to-write; must: true; order: 10 -->
## どこに何を書くか

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

<!-- id: eng-system; must: true; order: 20 -->
## システム（IGameSystem）

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

<!-- id: eng-component; must: true; order: 30 -->
## コンポーネントと、エディタで調整できる値

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

<!-- id: eng-register; must: true; order: 40 -->
## 登録（Feature の Register）

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

<!-- id: eng-query; must: true; order: 50 -->
## オブジェクトを探す・まとめて処理する

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

<!-- id: eng-services; must: true; order: 60 -->
## エンジンの機能の使い方（探し方）

- 入力・音・エフェクト・カメラ・UI・シーン切替・セーブなどのエンジンの機能は、コールバックで渡される `WorldView` から「サービス」を取って使う（例 `world.GetInput()`）。
- **何があるかは `WorldView.h` を読む。** サービスごとに `〜View.h`（操作）と `〜Types.h`（構造体と enum）がある。`WorldView.h` は型を前方宣言しているだけなので、使うサービスのヘッダを include する。
- 戻り値を必ず確かめる。View の `IsValid()` は「使える状態か」であって、個々の操作の成功ではない。
- HUD の描画のように「毎フレーム頼む」ものと、エフェクトや音のように「1 回頼んでハンドルを持つ」ものがある。どちらかはヘッダのコメントで確かめる。
- 実行中に出すものはエディタでプレハブにしておき、コードからは生成を頼む（非同期。結果を読んでから使う）。内蔵のモデルやカメラをコードで一から組み立てる前提にしない。
- 探しても見つからない機能は「まだない」。ハブの「エンジンへの要望」に出す。
