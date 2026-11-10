<!-- area: ビルド -->
<!-- id: eng-build; must: true; order: 10; sdk: 4.17 -->
## ビルドして確かめる

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

<!-- id: eng-reload; must: true; order: 20; sdk: 4.17 -->
## 変更が反映される条件

- 実行中の DLL はソースを変えても変わらない。**Play を止めてから**ビルドし、プロジェクトを開き直す。状態を保ったままのホットリロードはない。
- エンジンをコマンドラインで動かしても、ゲームのモジュールは再ビルドされない。ソースを変えたら先にビルドする。
- 新しいシステムが動かないとき：
  1. Feature の `Register` で登録したか
  2. コンポーネントに付くルールなら `BindComponentSystem` で結び付けたか
  3. 全体のシステムなら `GetDefaultSystems()` に入っているか。既存のシーンは自分のシステム一覧を保存しているので、シーンの「システム」設定も見る
  4. エンジンのログの `[SceneSystem] active schedule` に名前が出ているか
- 入力が効かないとき：DLL が新しいか、Play 中か、ゲーム画面をクリックしたか、入力設定にそのアクションがあるか、UI の入力コンテキストが Gameplay を止めていないか。

<!-- id: eng-verify; must: true; order: 30; sdk: 4.17 -->
## エージェントが確かめられること・人に頼むこと

- 確かめられる：ビルドが警告ゼロで通ること、ロジックの単体の確認（計算、状態遷移）。
- 人に頼む：見た目、手触り、音、実機でのプレイ。エージェントはエディタやゲームを勝手に起動しない。
- 見た目や手触りを確かめていないカードは「確認待ち（検収）」にして、報告の「未確認」に何を見てほしいかを書く。
- エンジンは知らないコマンドライン引数を無視して普通にエディタを開く。資料にない引数を推測で使わない。

<!-- id: eng-ide; must: false; order: 40; sdk: 4.17 -->
## IDE で書く

- エディタがプロジェクトを開く・ビルドするたびに、`CMakeLists.txt` の横に `CMakeUserPresets.json`（その PC 用）を書く。VS Code（CMake Tools）や Visual Studio で `hikari-ide` プリセットを選ぶと SDK のヘッダが補完される。
- IDE のビルドは確認用。エディタが読むモジュールは `Build-HikariProject.ps1`（またはエディタ）のビルド。
- CMake Tools が「No cache object found」と言ったら `Library/Build/CMake/ide` を消して設定し直す。
