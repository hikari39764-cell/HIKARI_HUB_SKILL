<!-- area: 資料 -->
<!-- id: eng-headers; must: true; order: 10 -->
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

<!-- id: eng-request; must: true; order: 20 -->
## エンジンに足りないものを見つけたら

1. 公開ヘッダを探して、本当にないことを確かめる。
2. ハブの「エンジンへの要望」に書く：何をしたくて、どの API・画面で、何が足りないか。SDK の版。いまの回避策。
3. ゲーム側は回避策で進める（回避策がなければ「決めること」に出す）。非公開ヘッダは使わない。
4. 直った版が書かれたら、回避策を消すカードを作る。

<!-- id: eng-data; must: false; order: 30 -->
## 作品のテキストデータ（Data/）

- レベル設定や表のような作品のテキストは、プロジェクト直下の `Data/` に UTF-8 で置ける。
- 読むのは `world.GetProjectData().ReadText(relativePath, sink)`（`ProjectDataView.h`）。同期・読み取り専用で、プロジェクトのファイルやセーブデータは書かない。
- 形式と検証は自分のコードで決める。セーブには使わない（`SaveGameView`）。

<!-- id: eng-scene-files; must: false; order: 40 -->
## シーン・描画の様式・後処理のファイルの形

普段はエディタで作る（ファイルを手で書き換えないのは「やってはいけないこと」の通り）。ここは、ファイルを読んで中身を確かめるときと、確認用のシーンなどをファイルで用意するしかないときのための控え。用意するなら、同じ版のエディタで保存したファイルを手本にして次の形に合わせる。エンジンは今の形式の版だけを読み、合わないファイルは読まずに理由をログへ書く。

**シーン（`.hscene`）**

- 一番上：`version`（今は `10`。違うとログに `[SceneAsset] unsupported scene version` が出て読まれない）、`sceneName`、`environment`、`camera`（`defaultCameraObjectId`）、`cinematics`、`lightingBake`、`systems`、`objects`。
- `environment`：`profile`（環境。内蔵 ID `engine.environment.*` か `.henvironment` の GUID）、`weather`（`engine.weather.*` か `.hweather` の GUID。空ならプロファイルの既定）、`renderStyle`（描画の様式。`engine.style.*` か `.hrenderstyle` の GUID）、`time`（`year`・`month`・`day`・`localHours`）、`timeScale`（0 で時刻を止める）、`location`（`latitudeDegrees`・`longitudeDegrees`・`utcOffsetHours`・`northYawDegrees`）。書かない項目は既定値。
- `objects` の 1 つ：`id`（シーンの中で重ならない整数）、`name`、`parent`（親の `id` か `null`）、`enabled`、`transform`（`position`・`rotationEulerDeg`・`scale`）、`components`（`id`・`type`・`properties` の並び）。`properties` の名前は、組み込みのコンポーネントならエディタで保存したシーンにある名前、自作のコンポーネントなら `DescribeProperties` で宣言した名前。

**描画の様式（`.hrenderstyle`）**：後処理はここで重ねる

- `formatVersion`（`1`）、`name`、`shading`、`post`。`post` は上から順に重なる `{"profile": "…", "enabled": true}` の並び。`profile` は内蔵 ID（`engine.post.profile.pixel` など）か `.hpostprofile` の GUID。

**後処理のプロファイル（`.hpostprofile`）**：効果の値を上書きするだけ

- `formatVersion`（`1`）、`name`、`effect`（`engine.post.effect.pixel` などか `.hposteffect` の GUID）、`values`。
- `values` は `{"キー": [数を 1〜4 個]}`。キー・既定値・範囲は効果のファイル（`.hposteffect`）の `params`（`key`・`defaultValues`・`minValues`・`maxValues`）にある。内蔵の効果は `<HIKARI>/EngineContent/Post/Effects/*.hposteffect`。書かないキーは効果の既定値になる（内蔵のプロファイルの `values` が空なのはそのため）。
- 例：`{"formatVersion": 1, "name": "Pixel", "effect": "engine.post.effect.pixel", "values": {"strength": [1.0], "pixelSize": [4.0]}}`

**新しいファイルを足したら**

- 資産として使うには取り込みが要る（エディタで開く、または無頭で `--import-assets Assets`）。GUID は取り込みで `ProjectSettings/AssetMeta/` に作られる。
- 読めたかどうかは無頭実行のログで確かめる。値を毎フレーム変えたいときは、ファイルではなくコード（`SubmitPostProfileParameter` など、ヘッダで確かめる）で上書きする。
