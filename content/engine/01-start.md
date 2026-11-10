<!-- area: はじめに -->
<!-- id: eng-how-to-read; must: true; order: 5; sdk: 4.17 -->
## この知識の使い方（最初に読む）

- ここに書いてあるのは、HIKARI SDK 4.17 の公開ヘッダと新規プロジェクトのテンプレートから確かめた内容。
- **正しいのは常に SDK のヘッダ**（`<HIKARI>/Sdk/include/HIKARI/Project/*.h`）。使う API は、呼ぶ前にそのヘッダのコメントを読む。コメントに寿命・スレッド・失敗時の扱いが書いてある。
- SDK の `docs/` にある古い手引きは内容が古いことがある。食い違ったらヘッダに従う。
- いまの版は `HIKARI/Project/GameProjectSdk.h` の `HIKARI::SDK::kVersionMajor / kVersionMinor / kVersionPatch`。プロジェクトの `CMakeLists.txt` の `find_package(HIKARI <版> CONFIG REQUIRED)` と合っているか見る。
- 公開ヘッダにない機能は「まだない」。非公開ヘッダで回避せず、ハブの「エンジンへの要望」に出す。

<!-- id: eng-overview; must: true; order: 10; sdk: 4.17 -->
## 全体像：誰が何を持つか

- ゲームは独立した C++ プロジェクト。`HIKARI_GameProject.dll` にビルドされ、エンジン（エディタ／実行時）が読み込む。
- **エンジンが持つ**：ウィンドウ、描画、入力の取得、物理の進行、メインループ、アセットの読み込み、オブジェクトの寿命。
- **ゲームのコードが持つ**：ルール（条件、判断、状態遷移、進行）。
- **エディタで作る**：シーン、プレハブ、見た目、調整する数値。
- コードは「いつ・どんな規則で」を決め、「どう見えるか・どれくらいか」はコンポーネントのフィールドかアセットに出してエディタで調整する。
- エンジンのソースは直さない。`WinMain` も書かない。include するのは `HIKARI/Project/*` と `HIKARI/Runtime/ComponentTypeId.h` だけ。

<!-- id: eng-layout; must: true; order: 20; sdk: 4.17 -->
## プロジェクトの構成

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

<!-- id: eng-template; must: true; order: 30; sdk: 4.17 -->
## 新規プロジェクトのコードの形（4 つの部品）

`Source/Runtime/*GameProjectModule.cpp` に次の 4 つが入っている。普段さわるのは上の 2 つ。

| 部品 | 基底 | 役割 |
|---|---|---|
| `GameSession` | `HIKARI::IGameProjectSession` | 1 回の Play のあいだ、シーンをまたいで残す状態 |
| `Game` | `HIKARI::IGameSystem` | 毎フレーム呼ばれるゲームの処理 |
| `GameplayFeature` | `HIKARI::IRuntimeFeature` | コンポーネントとシステムの登録（`Register`）と既定のシステム一覧 |
| `GameProjectModule` | `HIKARI::RUNTIME::IGameProjectModule` | Feature の登録（`RegisterRuntimeFeatures`）とセッションの生成（`CreateGameSession`） |

- 最後に `HIKARI::RUNTIME::CreateGameProjectModule()` が 1 つだけ定義されている。**2 つ目を書かない。**
- テンプレートの `Game::Update` は `world.GetGameSession()` を `dynamic_cast<GameSession*>` で取り、`nullptr`（＝Play 中でない）なら何もしない。この形を崩さない。
