<!-- category: コード規約 -->
<!-- id: rule-style-format; core: true; order: 10 -->
## 整形と文字

- エンジンと同じ `.clang-format`（リポジトリ直下）を使う。120 桁・4 スペース・改行 CRLF・include は並べ替えない。
- 変えた行だけ整形し、関係ない行は触らない（ファイル全体の整形をコミットに混ぜない）。
- 文字コードは UTF-8（BOM なし）。ファイル名・フォルダ名は半角英数字とアンダースコア。

<!-- id: rule-style-naming; core: false; order: 20 -->
## 命名とファイル

- HIKARI SDK に合わせる：型・関数は `PascalCase`、変数・引数・構造体のフィールドは `camelCase`、private メンバーは末尾に `_`（例 `speed_`）、enum の値は `PascalCase`。
- 名前空間はプロジェクトのテンプレートが作ったものをそのまま使う。
- 主なクラス 1 つにつき `.h` と `.cpp` を 1 組。ファイル名はクラス名と同じ。機能ごとにフォルダを分ける（例 `Source/Runtime/Enemy/`）。
- include の順：自分のヘッダ → 標準ライブラリ → HIKARI SDK（`HIKARI/Project/...`）→ 作品内の他のヘッダ。

<!-- id: rule-style-comments; core: false; order: 30 -->
## コメント

- 日本語で書く。何をしているかではなく、なぜそうしているかを書く。
- 消したコードをコメントで残さない。TODO には理由とカード id を書く（例 `// TODO(c-k3j9a): 空中被弾は別カード`）。
