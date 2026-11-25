"""HIKARI 制作ハブのビルド。

schema/schema.json（項目の宣言）、content/（既定のルール・エンジン知識・設定集のひな形・共通のワークフロー）、plugin/hub.json（接続先とスキルのリポジトリ）、
page/（サイトの元と、エンジン中枢と共用の翻訳 translate.js）から、次のものを作る。
作品の一覧はデータベースの作品目録（directory/<メール>/projects/<作品 id>）にあり、ビルドには入らない：

  新しい作品はオーナーがサイトの「新しい作品を作る」で作る（初期のルール・エンジン知識・設定集のひな形・共通のワークフローは、ページに埋め込んだものを入れる）。

  docs/index.html                       ハブのサイト（GitHub Pages が配る。全作品で 1 ページ、?p=<作品 id>）
  firebase/firestore.rules              データベースのアクセス規則（オーナーが Firebase コンソールに貼る。コミットしない）
                                        オーナーのメールは firebase/owner-email.local から入れる（これもコミットしない）
  plugin/owner/seed/<collection>/*.json 新しいプロジェクトに入れる初期データ
  plugin/lib/collections.json           hub コマンドが同期するコレクションの一覧（skip は必要なときだけ読むもの、prefix は新しい記録の id の頭）
  plugin/skills/work/references/data-model.md  エージェント向けのデータの書き方
  plugin/skills/work/references/engine.md      エンジン知識（ハブに届かないときの控え）
  dist/preview-owner.html, preview-member.html 手元で見るためのプレビュー（見本のデータ。コミットしない）
  dist/index.html                       公開前のサイトを手元で本物のデータにつないで見るための写し（コミットしない）

使い方： python -I -X utf8 tools/build.py
"""
from __future__ import annotations

import base64
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "schema" / "schema.json").read_text(encoding="utf-8"))
COLLECTIONS = {c["key"]: c for c in SCHEMA["collections"]}
OWNER_ONLY = ["settings"] + [c["key"] for c in SCHEMA["collections"] if c["writer"] == "owner"]
HUB = json.loads((ROOT / "plugin" / "hub.json").read_text(encoding="utf-8"))
# 招待された人が読むだけの作品（書けるのはオーナーだけ）：エンジンの中枢（D:/PJ/HIKARI-HQ/cloud が docs/engine/ に置くページ）。
READ_ONLY_PROJECTS = ["engine"]
HEAD = ('<!doctype html><html lang="ja"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="robots" content="noindex">')
RULES = """rules_version = '2';
// HIKARI 制作ハブのアクセス規則（自動生成：tools/build.py）。
// Firebase コンソールの Firestore Database →「ルール」に全部貼って「公開」する。
//
//   オーナー    ：下の isOwner() に書いたメールの Google アカウント。すべての作品を読み書きでき、招待の一覧を管理する。
//   メンバー    ：作品の invites/<Google アカウントのメール（小文字）> がある人。その作品を読み、記録を作る・直す。
//                 ただし __READ_ONLY_TEXT__ は招待された人も読むだけ（書けるのはオーナーだけ）。
//   オーナーだけ：__OWNER_ONLY_TEXT__ への書き込み、招待の一覧、作品目録への書き込み、記録の削除。
//   本人だけ    ：members/<自分の uid>。作品目録 directory/<自分のメール>/projects（入れる作品の一覧）は本人とオーナーが読める。
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function isOwner() {
      return signedIn()
        && request.auth.token.email_verified == true
        && request.auth.token.email.lower() == '__OWNER_EMAIL__';
    }
    function invited(pid) {
      return signedIn()
        && request.auth.token.email_verified == true
        && exists(/databases/$(database)/documents/projects/$(pid)/invites/$(request.auth.token.email.lower()));
    }
    function isMember(pid) { return isOwner() || invited(pid); }
    function canWrite(pid) { return isOwner() || (invited(pid) && !(pid in [__READ_ONLY__])); }

    // ページと hub コマンドが「自分はオーナーか」を確かめる場所（読めればオーナー。中身は無い）。
    match /hub/owner {
      allow read: if isOwner();
    }
    match /projects/{pid}/invites/{email} {
      allow read, write: if isOwner();
    }
    // 作品目録：この人が入れる作品。オーナーが招待するとき（と作品を作るとき）にページが書く。
    // ページの切り替えと hub コマンドが、これで「どのリポジトリがどの作品か」を知る。
    match /directory/{email}/projects/{pid} {
      allow read: if isOwner() || (signedIn() && request.auth.token.email_verified == true && request.auth.token.email.lower() == email);
      allow write: if isOwner();
    }
    match /projects/{pid}/members/{uid} {
      allow read: if isMember(pid);
      allow create, update: if isOwner() || (canWrite(pid) && request.auth.uid == uid);
      allow delete: if isOwner();
    }
    match /projects/{pid}/{coll}/{id} {
      allow read: if coll != 'invites' && isMember(pid);
      allow create, update: if (coll in [__OWNER_ONLY__] && isOwner())
        || (!(coll in [__OWNER_ONLY__, 'invites', 'members']) && canWrite(pid));
      allow delete: if isOwner();
    }
  }
}
"""


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def sections(folder: str, group_key: str, defaults: dict | None = None) -> list[dict]:
    """content/<folder>/*.md を「<!-- id: ...; key: value -->」の区切りごとの記録にする。
    まとまり（group_key）は、ファイルの先頭の「<!-- category: … -->」か「<!-- area: … -->」、または区切りごとの「section: …」。"""
    out: list[dict] = []
    for path in sorted((ROOT / "content" / folder).glob("*.md")):
        text = path.read_text(encoding="utf-8")
        group = re.search(r"<!--\s*(?:category|area):\s*(.+?)\s*-->", text)
        parts = re.split(r"^<!--\s*id:\s*(.+?)\s*-->\s*$", text, flags=re.M)
        for meta, body in zip(parts[1::2], parts[2::2]):
            fields = [kv.split(":", 1) for kv in meta.split(";")]
            doc_id = fields[0][0].strip()
            flags = {k.strip(): v.strip() for k, v in fields[1:]}
            value = flags.get(group_key) or (group and group.group(1))
            if not value:
                raise SystemExit(f"{path.name} {doc_id}: {group_key} がありません（ファイルの先頭の category・area か、区切りの section）")
            head, _, rest = body.strip().partition("\n")
            if not head.startswith("## "):
                raise SystemExit(f"{path.name} {doc_id}: 見出し（## ）がありません")
            doc: dict = {"title": head[3:].strip(), group_key: value, "body": rest.strip(),
                         "order": int(flags.get("order", "100"))} | (defaults or {})
            for key in ("core", "must"):
                if key in flags:
                    doc[key] = flags[key] == "true"
            out.append({"id": doc_id, "data": doc})
    ids = [d["id"] for d in out]
    if len(ids) != len(set(ids)):
        raise SystemExit(f"content/{folder}: id が重複しています")
    return out


def workflows() -> list[dict]:
    """content/workflows/<id>.json：新しい作品に入る共通のワークフロー（範囲は「共通」）。"""
    fields = {f["key"] for f in COLLECTIONS["workflows"]["fields"]}
    out = []
    for path in sorted((ROOT / "content" / "workflows").glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        unknown = [k for k in doc if k not in fields]
        if unknown or doc.get("scope") != "共通" or not path.stem.startswith(COLLECTIONS["workflows"]["prefix"] + "-"):
            raise SystemExit(f"{path.name}: 知らない項目 {unknown}、範囲が「共通」でない、または id が wf- で始まらない")
        out.append({"id": path.stem, "data": doc})
    return out


def check_schema() -> None:
    unknown = [k for k in SCHEMA["sync_skip"] if k not in COLLECTIONS]
    if unknown:
        raise SystemExit(f"sync_skip に無いコレクション {unknown}")
    for c in SCHEMA["collections"]:
        keys = {f["key"] for f in c["fields"]}
        missing = [k for k in c["create"] if k not in keys]
        if missing:
            raise SystemExit(f"{c['key']}: create に無い項目 {missing}")
        if c.get("states") and "state" not in keys:
            raise SystemExit(f"{c['key']}: states があるのに state 項目がありません")
    prefixes = [c["prefix"] for c in SCHEMA["collections"] if c["prefix"]]
    if len(prefixes) != len(set(prefixes)):
        raise SystemExit("prefix が重複しています")


def firestore_rules() -> str:
    """オーナーのメールは公開しない：手元の firebase/owner-email.local（1 行）から入れる。無ければ貼る前に書き換える。"""
    local = ROOT / "firebase" / "owner-email.local"
    email = local.read_text(encoding="utf-8").strip().lower() if local.exists() else "OWNER_EMAIL_HERE"
    if not re.fullmatch(r"[^\s'@/]+@[^\s'@/]+", email) and email != "OWNER_EMAIL_HERE":
        raise SystemExit("firebase/owner-email.local がメールの形になっていません")
    quoted = ", ".join(f"'{k}'" for k in OWNER_ONLY)
    read_only = ", ".join(f"'{k}'" for k in READ_ONLY_PROJECTS)
    return RULES.replace("__READ_ONLY_TEXT__", "・".join(READ_ONLY_PROJECTS)).replace("__READ_ONLY__", read_only).replace("__OWNER_ONLY_TEXT__", "・".join(OWNER_ONLY)).replace("__OWNER_ONLY__", quoted).replace("__OWNER_EMAIL__", email)


def embed(value) -> str:
    """<script type="application/json"> の中に入れる JSON。"""
    return json.dumps(value, ensure_ascii=False).replace("</", "<\\/")


def page(config: dict, backend: str | None = None) -> str:
    """backend を渡すと、Firebase の窓口の代わりにそのスクリプト（プレビューの見本）を入れる。"""
    html = (ROOT / "page" / "hub.src.html").read_text(encoding="utf-8")
    logo = "data:image/png;base64," + base64.b64encode((ROOT / "page" / "logo.png").read_bytes()).decode("ascii")
    if backend is not None:
        head, _, rest = html.partition("<!--backend-->")
        html = head + f"<script>{backend}</script>" + rest.partition("<!--/backend-->")[2]
    # 翻訳・アイコン・共用スタイルはエンジン中枢のページも使う（page/ に 1 つだけ置く）。共用スタイルは自分のスタイルの後ろで上書きする。
    scripts = ((ROOT / "page" / "translate.js").read_text(encoding="utf-8") + "\n" + (ROOT / "page" / "shared.js").read_text(encoding="utf-8")).replace("</", "<\\/")
    return HEAD + (html.replace("__SCHEMA__", embed(SCHEMA)).replace("__CONFIG__", embed(config)).replace("__LOGO__", logo).replace("__SHARED_JS__", scripts)
                   .replace("__SHARED_CSS__", (ROOT / "page" / "shared.css").read_text(encoding="utf-8"))
                   .replace("__ICONS__", (ROOT / "page" / "icons.svg").read_text(encoding="utf-8")))


def data_model() -> str:
    lines = [
        "# ハブのデータ（自動生成：schema/schema.json から）",
        "",
        "ハブのデータベース（作品ごと）にある記録の一覧。`hub` コマンドで読み書きする。",
        "書き方の手順と例は `hub-io.md`。ここは「どのコレクションに、どんな項目があるか」。",
        "",
        "## すべての記録に付ける項目",
        "",
        "| 項目 | 意味 | 書き方 |",
        "|---|---|---|",
    ]
    lines += [f"| `{k}` | {v['ja']} | {v['help']} |" for k, v in SCHEMA["meta_fields"].items()]
    lines += [
        "",
        "- 新しく作るとき：`by`・`at`・`updated_at`・`updated_by`、エージェントなら `by_agent` も。",
        "- 直すとき：`updated_at`・`updated_by`。",
        "- id は `<接頭辞>-<16 進 6 文字>`（例 `c-3fa9c1`）。",
        "",
        "## 書ける人",
        "",
        "- **メンバー**：オーナーに招待された人と、その人の鍵を使うエージェント。記録を作る・直すことができる（消せるのはオーナーだけ）。",
        "- **オーナーだけ**：" + "、".join(f"`{k}`" for k in OWNER_ONLY) + "。ほかの人が書こうとすると拒否される（エージェントは書かない）。",
        "- **本人だけ**：`members/<自分の uid>`（呼び名と自分のブランチ。ページで本人が登録する。まだ無ければエージェントが登録する）。オーナーは全員の `branch` を決められる。",
        "- **エージェントが作るだけ**：`map`（`hub map` が git から作って送る。手で書かない）。",
        "",
        "## settings（オーナーだけが書く）",
        "",
        "### `settings/project`",
        "",
        "| 項目 | 意味 | 補足 |",
        "|---|---|---|",
    ]
    lines += [f"| `{f['key']}` | {f['ja']} | {f.get('help', '')} |" for f in SCHEMA["settings"]["project"]["fields"]]
    lines += ["", "### `settings/plan`", "", SCHEMA["settings"]["plan"]["help"], ""]
    writers = {"member": "メンバー", "owner": "オーナーだけ", "self": "本人だけ"}
    for c in SCHEMA["collections"]:
        lines += [f"## `{c['key']}` — {c['label']['ja']}", "", c["summary"]["ja"], "",
                  f"- 書ける人：{writers[c['writer']]}" + (f"　／　id：`{c['prefix']}-xxxxxx`" if c["prefix"] else "")]
        if c.get("states"):
            lines.append("- 状態（`state`）：" + " → ".join(f"`{s['name']}`" + ("" if s["open"] else "（終わり）") for s in c["states"])
                         + f"。新しく作るときは `{c['states'][0]['name']}`")
        if c.get("required_when_done"):
            lines.append("- 終了のとき必ず書く項目：" + "、".join(f"`{k}`" for k in c["required_when_done"]) + "（ないときは空の配列か「なし」）")
        lines.append("- 作るときに書く項目：" + "、".join(f"`{k}`" for k in c["create"]))
        lines += ["", "| 項目 | 型 | 意味 | 補足 |", "|---|---|---|---|"]
        for f in c["fields"]:
            kind = f["type"] + ("：" + "／".join(f["choices"]) if f.get("choices") else "") + ("（必須）" if f.get("required") else "")
            lines.append(f"| `{f['key']}` | {kind} | {f['ja']} | {f.get('help', '')} |")
        lines.append("")
    lines += [
        "## 型の意味",
        "",
        "- `text`・`longtext`：文字列（`longtext` は Markdown 可）　`number`：数値　`bool`：true / false",
        "- `list`：文字列の配列　`areas`：`settings/project` の `areas` にある名前の配列",
        "- `choice`：書いてある候補のどれか　`state`：そのコレクションの状態のどれか",
        "- `member`：メンバーの呼び名　`ref`：ほかの記録の id　`milestone`：`settings/plan` の milestones の id",
        "- `time`：ISO 8601 の日時　`log`：`[{at, note}]` の配列　`options`：`[{text, recommended}]` の配列",
        "- `answers`：`{回答 id: {by, by_agent, at, text, evidence}}` のマップ　`assets`：ページで上げた画像の id の配列（エージェントは書かない）",
        "- `object`・`objects`：形が決まったオブジェクトと、その配列（形は補足に書いてある）",
        "",
    ]
    return "\n".join(lines)


def sample_map() -> dict:
    """プレビューの地図。dist/preview-map/*.json（手元で hub map -NoPush の結果を置いたもの）があればそれを使う。"""
    local = sorted((ROOT / "dist" / "preview-map").glob("*.json"))
    if local:
        return {f"map/{p.stem}": json.loads(p.read_text(encoding="utf-8-sig")) for p in local}
    nodes = [{"id": i, "kind": k, "files": f, "bytes": f * 4000} for i, k, f in (
        ("Assets/Scenes/Stage1.scene.json", "scene", 1), ("Assets/Vfx", "asset", 6), ("Source/Runtime/Common", "code", 4),
        ("Source/Runtime/Enemy", "code", 8), ("Source/Runtime/Player", "code", 10), ("@sdk", "outside", 0))]
    edges = [{"from": a, "to": b, "kind": k, "n": n} for a, b, k, n in (
        ("Assets/Scenes/Stage1.scene.json", "Source/Runtime/Player", "component", 1), ("Assets/Scenes/Stage1.scene.json", "Source/Runtime/Enemy", "component", 3),
        ("Assets/Scenes/Stage1.scene.json", "Assets/Vfx", "asset", 2), ("Source/Runtime/Enemy", "Assets/Vfx", "asset", 2),
        ("Source/Runtime/Player", "Source/Runtime/Common", "include", 5), ("Source/Runtime/Enemy", "Source/Runtime/Common", "include", 3),
        ("Source/Runtime/Player", "@sdk", "engine", 9), ("Source/Runtime/Enemy", "@sdk", "engine", 6))]
    change = lambda path, node, status, add, rm: {"path": path, "node": node, "status": status, "add": add, "del": rm}
    def doc(branch, role, member, compare, ahead, behind, subject, changed):
        head = {"commit": "0" * 40, "subject": subject, "author": member or "hikari", "at": f"2026-11-10T1{len(changed)}:00:00+09:00"}
        return {"branch": branch, "role": role, "member": member, "compare": compare, "ahead": ahead, "behind": behind, "nodes": nodes, "edges": edges,
                "sdk": [{"header": "HIKARI/Project/WorldView.h", "n": 7}], "head": head, "changed": changed, "changed_total": len(changed),
                "last": head | {"changed": changed[:1], "changed_total": min(1, len(changed))} if changed else None,
                "mapped_at": "2026-11-10T11:30:00+09:00", "mapped_by": "hikari"}
    return {
        "map/develop": doc("develop", "base", "", "main", 4, 0, "敵のノックバックを取り込む", [change("Source/Runtime/Enemy/EnemyHit.cpp", "Source/Runtime/Enemy", "M", 40, 3)]),
        "map/main": doc("main", "release", "", "", 0, 0, "試遊会 第1回", []),
        "map/develop_kou": doc("develop_kou", "personal", "hikari", "develop", 3, 0, "被弾時の画面揺れを弱める",
                               [change("Source/Runtime/Player/PlayerHit.cpp", "Source/Runtime/Player", "M", 12, 4), change("Assets/Vfx/Hit.hvfx", "Assets/Vfx", "A", 80, 0)]),
        "map/develop_kato": doc("develop_kato", "personal", "kato", "develop", 2, 1, "空中で被弾したときの動き",
                                [change("Source/Runtime/Enemy/EnemyHit.cpp", "Source/Runtime/Enemy", "M", 22, 6), change("Source/Runtime/Player/PlayerHit.cpp", "Source/Runtime/Player", "M", 3, 1)]),
    }


def engine_reference(docs: list[dict]) -> str:
    lines = ["# HIKARI エンジンの必須知識（自動生成：content/engine から）", "",
             "ハブの `engine` コレクションが正。ここはハブに届かないときの控え。", ""]
    area = None
    for d in sorted(docs, key=lambda x: (COLLECTIONS["engine"]["areas"].index(x["data"]["area"]), x["data"]["order"])):
        if d["data"]["area"] != area:
            area = d["data"]["area"]
            lines += [f"# {area}", ""]
        lines += [f"## {d['data']['title']}" + ("　［必読］" if d["data"].get("must") else ""), "", d["data"]["body"], ""]
    return "\n".join(lines)


def preview_seed(initial: dict, owner: bool) -> dict:
    """プレビュー用の見本データ（公開ページには入らない）。initial は新しい作品に入る初期データ（{コレクション: {id: 記録}}）。"""
    me = "hikari" if owner else "kato"
    seed = {f"{folder}/{i}": d for folder, docs in initial.items() for i, d in docs.items()}
    seed["invites/kato@example.com"] = {"at": "2026-11-09T09:00:00+09:00"}
    stamp = lambda by, at, agent=None: {"by": by, "at": at, "updated_at": at, "updated_by": by} | ({"by_agent": agent} if agent else {})
    seed |= {
        "settings/project": {"name": "サンプル作品", "summary": "プレビュー用の見本です。", "repo": "example/sample-game", "base_branch": "develop", "release_branch": "main",
                             "areas": ["プレイヤー", "敵", "ステージ", "UI", "演出"], "budget_hours": 3, "max_sessions": 2,
                             "require_card": True, "protected_paths": ["ProjectSettings/", "CMakeLists.txt"], "skill_source": "example/hikari-hub"},
        "settings/plan": {"ready": ["c-000002", "c-000003"], "assign": {"c-000003": "kato"},
                          "milestones": [{"id": "ms-000001", "date": "2026-11-19", "title": "試遊会 第2回"}, {"id": "ms-000002", "date": "2026-12-03", "title": "中間提出"}]},
        "members/u_owner" if not owner else "members/u_me": {"handle": "hikari", "role": "ディレクター・プログラマー", "branch": "develop_kou"},
        "members/u_me" if not owner else "members/u_kato": {"handle": "kato", "role": "プログラマー", "branch": "develop_kato"},
        "members/u_ko": {"handle": "ko", "role": "デザイナー"},
        "cards/c-000001": {"title": "敵のノックバック", "kind": "機能", "summary": "被弾した敵を後ろへ押し出す。", "acceptance": ["距離と時間をエディタで調整できる", "壁を抜けない"],
                           "paths": ["Source/Runtime/Enemy/"], "areas": ["敵"], "state": "作業中", "assignee": "kato", "milestone": "ms-000001",
                           "branch": "feat/c-000001-enemy-knockback", **stamp("hikari", "2026-11-09T10:00:00+09:00")},
        "cards/c-000002": {"title": "タイトル画面の UI", "kind": "機能", "areas": ["UI"], "state": "あとで", "milestone": "ms-000001", **stamp("hikari", "2026-11-09T10:05:00+09:00")},
        "cards/c-000003": {"title": "壁際で被弾すると床に埋まるのを直す", "kind": "修正", "areas": ["プレイヤー"], "state": "あとで", "bug": "b-000001", **stamp("hikari", "2026-11-09T11:00:00+09:00")},
        "cards/c-000004": {"title": "被弾時の画面揺れを弱める", "kind": "調整", "areas": ["演出"], "state": "確認待ち", "waiting": "レビュー", "assignee": "kato", "pr": "11",
                           "milestone": "ms-000001", **stamp("hikari", "2026-11-08T15:00:00+09:00")},
        "cards/c-000005": {"title": "ボスの第2形態", "kind": "機能", "areas": ["敵"], "state": "あとで", **stamp("ko", "2026-11-10T09:00:00+09:00")},
        "cards/c-000006": {"title": "タイトル BGM の差し替え", "kind": "素材", "state": "完了", "assignee": "hikari", "milestone": "ms-000001", **stamp("hikari", "2026-11-07T15:00:00+09:00")},
        "reports/r-000001": {"kind": "作業", "card": "c-000001", "title": "敵のノックバック", "state": "作業中", "model": "claude-fable-5-2", "started_at": "2026-11-10T10:20:00+09:00",
                             "branch": "feat/c-000001-enemy-knockback",
                             "progress": [{"at": "2026-11-10T11:02:00+09:00", "note": "距離をフィールドにした。次は空中で当たったときの動き"},
                                          {"at": "2026-11-11T09:40:00+09:00", "note": "空中で当たったときは距離を半分にした。壁際の確認が残り"}],
                             **stamp("kato", "2026-11-10T10:20:00+09:00", "claude-code")},
        "reports/r-000004": {"kind": "日報", "title": "2026-11-11", "state": "終了", "today": "ボス第2形態の見た目案を 2 つ作った。", "next": "決めることの結果を待って作り込む。",
                             **stamp("ko", "2026-11-11T18:10:00+09:00")},
        "reports/r-000002": {"kind": "作業", "card": "c-000004", "title": "被弾時の画面揺れを弱める", "state": "終了", "conclusion": "揺れの強さと時間をカメラ効果アセットの値にした。",
                             "changes": ["Assets/Camera/HitShake.hcamfx"], "evidence": ["テスト用シーンで 10 回被弾して確認"], "unverified": ["ボス戦"], "remaining": [],
                             "tuning": ["g-000001"], "learned": ["k-000001"], "mistakes": [], "questions": [], "cost_hours": 0.8, "pr": "11", **stamp("kato", "2026-11-09T16:40:00+09:00", "claude-code")},
        "reports/r-000003": {"kind": "作業", "card": "c-000006", "title": "タイトル BGM の差し替え", "state": "終了", "conclusion": "差し替えた。",
                             "changes": ["Assets/Audio/title.ogg"], **stamp("ko", "2026-11-07T15:00:00+09:00", "claude-code")},
        "bugs/b-000001": {"title": "壁際で被弾すると床に埋まる", "where": "ステージ1 の右端", "steps": ["壁に背を向けて立つ", "敵の突進を受ける"], "expected": "壁の手前で止まる",
                          "actual": "床の下に落ちる", "frequency": "毎回", "severity": "止まる", "areas": ["プレイヤー"], "state": "対応中", "card": "c-000003",
                          **stamp("ko", "2026-11-09T10:50:00+09:00")},
        "questions/q-000001": {"title": "敵が空中で被弾したときも同じ距離だけ飛ばす？", "context": "いまは地上と同じ動き。", "to": "オーナー", "areas": ["敵"], "state": "未回答",
                               **stamp("kato", "2026-11-10T11:05:00+09:00", "claude-code")},
        "guides/g-000001": {"title": "被弾時の画面揺れ", "summary": "被弾したときにカメラを揺らす。強さと時間はカメラ効果アセットが持つ。",
                              "params": ["Assets/Camera/HitShake.hcamfx の Strength — 揺れの強さ（既定 0.4）", "Assets/Camera/HitShake.hcamfx の Duration — 揺れる時間（既定 0.15 秒）"],
                              "code": ["Source/Runtime/Player/PlayerHit.cpp:OnHit — どの被弾で揺らすかの条件"], "check": "テスト用シーンで被弾する。",
                              "areas": ["演出"], "card": "c-000004", "state": "有効", **stamp("kato", "2026-11-09T16:40:00+09:00", "claude-code")},
        "knowledge/k-000001": {"title": "カメラの揺れはカメラ効果アセットの値で調整する", "body": "コードに強さを書かず、`GetCamera()` に効果の再生だけを頼む。", "areas": ["演出"],
                               "source": "r-000002", "state": "要確認", **stamp("kato", "2026-11-09T16:40:00+09:00", "claude-code")},
        "mistakes/m-000001": {"title": "ノックバックの距離をコードに直書きした", "what": "1.5 m を定数で書いた。", "root_cause": "コードの約束を読まずに書き始めた。", "caught_by": "レビュー",
                              "fix": "コンポーネントのフィールドにした。", "prevention": "調整値は最初から DescribeProperties に出す。", "areas": ["敵"], "state": "記録",
                              **stamp("kato", "2026-11-10T11:30:00+09:00", "claude-code")},
        "decisions/d-000001": {"title": "ボス第2形態に入る HP は何％？", "context": "50％だと 1 回の戦闘で必ず見られる。30％だと短い。",
                               "options": [{"text": "50％", "recommended": True}, {"text": "30％", "recommended": False}], "decider": "オーナー", "state": "未決定",
                               **stamp("ko", "2026-11-10T09:30:00+09:00")},
        "locks/l-000001": {"target": "Assets/Scenes/Stage2.scene", "until": "18:00", "state": "編集中", **stamp("ko", "2026-11-10T09:05:00+09:00")},
        "proposals/p-000001": {"title": "PR にはプレイ動画を付ける", "category": "Git 規約", "body": "見た目や手触りが変わる PR には 10 秒ほどの動画を付ける。",
                               "reason": "スクリーンショットでは揺れの強さが伝わらなかった。", "state": "提案", **stamp("ko", "2026-11-10T09:40:00+09:00")},
        "design/ds-concept": {"title": "このゲームのひとこと", "section": "コンセプト", "must": True, "order": 10, "state": "確定",
                              "body": "押し寄せる敵の群れを、**ため攻撃 1 発で吹き飛ばす**爽快感のアクション。数で押されて、技で押し返す。", **stamp("hikari", "2026-11-09T09:20:00+09:00")},
        "workflows/wf-000001": {"title": "敵を 1 体足す", "summary": "敵の定義アセットを 1 つ足し、出現表に入れて遊べるようにする。共通の敵コンポーネント（EnemyCore）にまとめ終わっているので、コードは書かない。",
                                "params": ["名前：敵の名前（英語、例 SlimeRed）", "HP=30：体力", "速さ=2.5：歩く速さ（m/秒）", "見た目：使うモデルのアセット"],
                                "steps": ["`Assets/Enemies/_Template.henemy` を `Assets/Enemies/{名前}.henemy` に複製する", "HP を {HP}、MoveSpeed を {速さ}、Model を {見た目} にする",
                                          "`Assets/Stages/SpawnTable.hdata` に {名前} を 1 行足す", "ビルドして、テスト用シーンで出現・被弾・撃破を確かめる", "調整ガイド「敵の定義アセット」に {名前} の行を足す"],
                                "checks": ["テスト用シーンで出て、当たって、倒せる", "ビルドが警告ゼロ"], "stops": ["共通の敵コンポーネントにない動きが要る"],
                                "refactor": ["敵の共通部分を EnemyCore にまとめる（済み：r-000002）"], "model": "ふつうのモデルでよい", "areas": ["敵"], "scope": "この作品", "state": "検証済み",
                                "runs": 3, "last_run": "2026-11-11T15:00:00+09:00", "fixes": [{"at": "2026-11-11T15:00:00+09:00", "note": "kato：出現表の列の順番が手順に書いていない"}],
                                "history": [{"at": "2026-11-10T12:00:00+09:00", "note": "kato・claude-code：r-000002 の提案から作った"}, {"at": "2026-11-10T18:00:00+09:00", "note": "hikari・サイト：試して検証済みにした"}],
                                "source": "r-000002", **stamp("kato", "2026-11-10T12:00:00+09:00", "claude-code")},
        "reports/r-000005": {"kind": "作業", "title": "弾のはね返り", "state": "終了", "conclusion": "壁ではね返る弾を足した。",
                             "repeat": "弾の種類を足すのは 3 回目。毎回、当たり判定と寿命のコードを写している。先に共通の弾コンポーネントにまとめてから、「弾を 1 種類足す」をワークフローにしたい。",
                             "changes": ["Source/Runtime/Bullet/BounceBullet.cpp"], "evidence": ["テスト用シーンで壁に 5 回撃って確認"], "unverified": [], "remaining": [], "tuning": [],
                             "learned": [], "mistakes": [], "questions": [], "cost_hours": 0.6, **stamp("kato", "2026-11-11T17:30:00+09:00", "claude-code")},
        "reports/r-000006": {"kind": "作業", "title": "敵を 1 体足す：SlimeRed", "state": "終了", "workflow": "wf-000001", "params": ["名前=SlimeRed", "HP=30", "速さ=2.5", "見た目=Assets/Models/Slime.hmesh"],
                             "conclusion": "ワークフローどおりに足した。出現表の列の順番で迷った（改善案に書いた）。", "changes": ["Assets/Enemies/SlimeRed.henemy", "Assets/Stages/SpawnTable.hdata"],
                             "evidence": ["テスト用シーンで出現・被弾・撃破を確認"], "unverified": [], "remaining": [], "tuning": ["g-000001"], "learned": [], "mistakes": [], "questions": [], "cost_hours": 0.3,
                             **stamp("kato", "2026-11-11T15:00:00+09:00", "claude-code")},
        "engine_requests/e-000001": {"title": "名前でオブジェクトを探したい", "kind": "機能不足", "detail": "出現地点を名前で探す API がない。", "workaround": "SceneObject フィールドで参照を持つ。", "state": "未送付", **stamp("kato", "2026-11-10T11:40:00+09:00", "claude-code")},
    } | sample_map()
    me_mail = "owner@example.com" if owner else "member@example.com"
    return {f"projects/sample/{k}": v for k, v in seed.items()} | {f"directory/{me_mail}/projects/sample": {"at": "2026-11-09T09:00:00+09:00"}}


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    check_schema()
    rules, engine = sections("rules", "category"), sections("engine", "area")
    bad = [d["id"] for d in rules if d["data"]["category"] not in COLLECTIONS["rules"]["categories"]]
    bad += [d["id"] for d in engine if d["data"]["area"] not in COLLECTIONS["engine"]["areas"]]
    if bad:
        raise SystemExit(f"分類が schema にありません：{bad}")

    owner = ROOT / "plugin" / "owner"
    # 新しい作品に入れる初期データ（サイトの「新しい作品を作る」が使う）。設定の既定値は schema の settings.*.defaults。
    design = sections("design", "section", {"state": COLLECTIONS["design"]["states"][0]["name"]})
    bad += [d["id"] for d in design if d["data"]["section"] not in next(f for f in COLLECTIONS["design"]["fields"] if f["key"] == "section")["choices"]]
    if bad:
        raise SystemExit(f"設定集の章が schema にありません：{bad}")
    seed = {folder: {d["id"]: d["data"] for d in docs} for folder, docs in (("rules", rules), ("engine", engine), ("design", design), ("workflows", workflows()))}
    config = {"firebase": HUB["firebase"], "skill": HUB["skill"], "seed": seed}
    site = page(config)
    write(ROOT / "docs" / "index.html", site)
    write(ROOT / "docs" / ".nojekyll", "")
    write(ROOT / "dist" / "index.html", site)
    write(ROOT / "firebase" / "firestore.rules", firestore_rules())
    shutil.rmtree(owner / "seed", ignore_errors=True)
    for folder, docs in seed.items():
        for doc_id, data in docs.items():
            write(owner / "seed" / folder / f"{doc_id}.json", json.dumps(data, ensure_ascii=False, indent=2) + "\n")

    # prefix：メンバーが作る記録の id の頭（hub push が、新しい記録の id が <頭>-16 進 6 文字かを確かめる）。
    listing = {"all": ["settings"] + list(COLLECTIONS), "skip": SCHEMA["sync_skip"],
               "prefix": {k: c["prefix"] for k, c in COLLECTIONS.items() if c.get("prefix") and c["writer"] != "owner"}}
    write(ROOT / "plugin" / "lib" / "collections.json", json.dumps(listing, ensure_ascii=False, indent=2) + "\n")

    refs = ROOT / "plugin" / "skills" / "work" / "references"
    write(refs / "data-model.md", data_model())
    write(refs / "engine.md", engine_reference(engine))

    mock = (ROOT / "tools" / "preview_mock.js").read_text(encoding="utf-8")
    sample = config | {"firebase": {}}
    for name, is_owner in (("owner", True), ("member", False)):
        script = mock.replace("__SEED__", embed(preview_seed(seed, is_owner))).replace("__OWNER__", "true" if is_owner else "false")
        write(ROOT / "dist" / f"preview-{name}.html", page(sample, script))
    print(f"ルール {len(rules)} 件、エンジン知識 {len(engine)} 件、設定集 {len(seed['design'])} 件、ワークフロー {len(seed['workflows'])} 件、サイト {len(site.encode('utf-8')) // 1024} KB")


if __name__ == "__main__":
    main()
