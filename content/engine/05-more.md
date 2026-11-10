<!-- area: 資料 -->
<!-- id: eng-headers; must: true; order: 10; sdk: 4.17 -->
## ヘッダの読み方（困ったらここから）

`<HIKARI>/Sdk/include/HIKARI/Project/` にある。名前の付け方：

- `〜View.h` / `〜Views.h`：`WorldView` から取るサービス（操作の窓口）
- `〜Types.h`：その機能で使う構造体と enum
- `GameSystem.h`、`GameComponent.h`、`PropertyFields.h`、`FrameContext.h`、`GameProjectSession.h`：ゲームコードの土台
- `RuntimeFeature.h`、`RuntimeRegistration.h`、`GameProjectModule.h`：登録
- `WorldView.h`、`WorldTypes.h`、`WorldQuery.h`、`ComponentViews.h`：オブジェクトと World
- `Editor〜.h`、`GameProjectEditorModule〜.h`：エディタ拡張（`Source/Editor` 用）
- `Render〜.h`、`MassSystem.h`、`World〜Types.h`：描画の拡張、大量オブジェクト（上級。必要になるまで触らない）

探し方：やりたいことの言葉で `grep` する（例 `grep -rn "Vibration" <HIKARI>/Sdk/include/HIKARI/Project`）。見つからなければ「まだない」と考えて、ハブの「エンジンへの要望」に出す。

<!-- id: eng-request; must: true; order: 20; sdk: 4.17 -->
## エンジンに足りないものを見つけたら

1. 公開ヘッダを探して、本当にないことを確かめる。
2. ハブの「エンジンへの要望」に書く：何をしたくて、どの API・画面で、何が足りないか。SDK の版。いまの回避策。
3. ゲーム側は回避策で進める（回避策がなければ「決めること」に出す）。非公開ヘッダは使わない。
4. 直った版が書かれたら、回避策を消すカードを作る。

<!-- id: eng-data; must: false; order: 30; sdk: 4.17 -->
## 作品のテキストデータ（Data/）

- レベル設定や表のような作品のテキストは、プロジェクト直下の `Data/` に UTF-8 で置ける。
- 読むのは `world.GetProjectData().ReadText(relativePath, sink)`（`ProjectDataView.h`）。同期・読み取り専用で、プロジェクトのファイルやセーブデータは書かない。
- 形式と検証は自分のコードで決める。セーブには使わない（`SaveGameView`）。
