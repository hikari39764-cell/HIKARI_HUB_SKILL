"""HIKARI 制作ハブのビルド。

schema/schema.json（項目の宣言）と content/（既定のルール・エンジン知識）から、次のものを作る：

  plugin/owner/hub.html                 公開するプロジェクトページ（作品名は /hub:new が差し込む）
  plugin/owner/capabilities.json        公開時に渡す権限の宣言（db のアクセス規則）
  plugin/owner/seed/<collection>/*.json 新しいプロジェクトに入れる初期データ
  plugin/skills/work/references/data-model.md  エージェント向けのデータの書き方
  plugin/skills/work/references/engine.md      エンジン知識（ハブに届かないときの控え）
  dist/preview-owner.html, preview-member.html 手元で見るためのプレビュー（コミットしない）

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


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def sections(folder: str, group_key: str) -> list[dict]:
    """content/<folder>/*.md を「<!-- id: ...; key: value -->」の区切りごとの記録にする。"""
    out: list[dict] = []
    for path in sorted((ROOT / "content" / folder).glob("*.md")):
        text = path.read_text(encoding="utf-8")
        group = re.search(r"<!--\s*(?:category|area):\s*(.+?)\s*-->", text)
        if not group:
            raise SystemExit(f"{path.name}: 先頭に category か area がありません")
        parts = re.split(r"^<!--\s*id:\s*(.+?)\s*-->\s*$", text, flags=re.M)
        for meta, body in zip(parts[1::2], parts[2::2]):
            fields = [kv.split(":", 1) for kv in meta.split(";")]
            doc_id = fields[0][0].strip()
            flags = {k.strip(): v.strip() for k, v in fields[1:]}
            head, _, rest = body.strip().partition("\n")
            if not head.startswith("## "):
                raise SystemExit(f"{path.name} {doc_id}: 見出し（## ）がありません")
            doc: dict = {"title": head[3:].strip(), group_key: group.group(1), "body": rest.strip(),
                         "order": int(flags.get("order", "100"))}
            for key in ("core", "must"):
                if key in flags:
                    doc[key] = flags[key] == "true"
            if "sdk" in flags:
                doc["sdk"] = flags["sdk"]
            out.append({"id": doc_id, "data": doc})
    ids = [d["id"] for d in out]
    if len(ids) != len(set(ids)):
        raise SystemExit(f"content/{folder}: id が重複しています")
    return out


def check_schema() -> None:
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


def capabilities() -> dict:
    """読むのは招待された全員、書くのは編集者以上。オーナー領域はオーナーだけ、members は本人だけ。"""
    rules = [{"path": "", "read": "view", "write": "admin"}]
    rules += [{"path": key, "write": "owner"} for key in OWNER_ONLY]
    rules += [{"path": "members", "read": "view", "write": "owner"}, {"path": "members/{self}", "write": "admin"}]
    return {"db": {"rules": rules}, "user": {}, "assets": {}}


def page(project_name: str | None = None) -> str:
    html = (ROOT / "page" / "hub.src.html").read_text(encoding="utf-8")
    logo = "data:image/png;base64," + base64.b64encode((ROOT / "page" / "logo.png").read_bytes()).decode("ascii")
    html = html.replace("__SCHEMA__", json.dumps(SCHEMA, ensure_ascii=False).replace("</", "<\\/")).replace("__LOGO__", logo)
    return html.replace("__PROJECT_NAME__", project_name) if project_name else html


def data_model() -> str:
    lines = [
        "# ハブのデータ（自動生成：schema/schema.json から）",
        "",
        "プロジェクトページの共有データベースにある記録の一覧。`ArtifactData` ツールで読み書きする。",
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
        "- **メンバー**：編集者として招待された人と、そのエージェント。",
        "- **オーナーだけ**：" + "、".join(f"`{k}`" for k in OWNER_ONLY) + "。ほかの人が書こうとすると拒否される（エージェントは書かない）。",
        "- **本人だけ**：`members`（ページで本人が登録する。エージェントは読むだけ）。",
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
        "",
    ]
    return "\n".join(lines)


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


def preview_seed(rules: list[dict], engine: list[dict], owner: bool) -> dict:
    """プレビュー用の見本データ（公開ページには入らない）。"""
    me = "hikari" if owner else "kato"
    seed = {f"rules/{d['id']}": d["data"] for d in rules} | {f"engine/{d['id']}": d["data"] for d in engine}
    stamp = lambda by, at, agent=None: {"by": by, "at": at, "updated_at": at, "updated_by": by} | ({"by_agent": agent} if agent else {})
    seed |= {
        "settings/project": {"name": "サンプル作品", "summary": "プレビュー用の見本です。", "repo": "example/sample-game", "base_branch": "main",
                             "sdk": "4.18.0", "areas": ["プレイヤー", "敵", "ステージ", "UI", "演出"], "budget_hours": 3, "max_sessions": 2,
                             "require_card": True, "protected_paths": ["ProjectSettings/", "CMakeLists.txt"], "hub_url": "https://claude.ai/artifact/EXAMPLE", "skill_source": "example/hikari-hub"},
        "settings/plan": {"ready": ["c-000002", "c-000003"], "assign": {"c-000003": "kato"},
                          "milestones": [{"id": "ms-000001", "date": "2026-11-19", "title": "試遊会 第2回"}, {"id": "ms-000002", "date": "2026-12-03", "title": "中間提出"}]},
        "members/u_owner" if not owner else "members/u_me": {"handle": "hikari", "role": "ディレクター・プログラマー"},
        "members/u_me" if not owner else "members/u_kato": {"handle": "kato", "role": "プログラマー"},
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
                             "progress": [{"at": "2026-11-10T11:02:00+09:00", "note": "距離をフィールドにした。次は空中で当たったときの動き"}],
                             **stamp("kato", "2026-11-10T10:20:00+09:00", "claude-code")},
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
        "engine_requests/e-000001": {"title": "名前でオブジェクトを探したい", "kind": "機能不足", "detail": "出現地点を名前で探す API がない。", "sdk": "4.17.0",
                                     "workaround": "SceneObject フィールドで参照を持つ。", "state": "未送付", **stamp("kato", "2026-11-10T11:40:00+09:00", "claude-code")},
    }
    return seed


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    check_schema()
    rules, engine = sections("rules", "category"), sections("engine", "area")
    bad = [d["id"] for d in rules if d["data"]["category"] not in COLLECTIONS["rules"]["categories"]]
    bad += [d["id"] for d in engine if d["data"]["area"] not in COLLECTIONS["engine"]["areas"]]
    if bad:
        raise SystemExit(f"分類が schema にありません：{bad}")

    owner = ROOT / "plugin" / "owner"
    write(owner / "hub.html", page())
    write(owner / "capabilities.json", json.dumps(capabilities(), ensure_ascii=False, indent=2) + "\n")
    shutil.rmtree(owner / "seed", ignore_errors=True)
    for folder, docs in (("rules", rules), ("engine", engine)):
        for d in docs:
            write(owner / "seed" / folder / f"{d['id']}.json", json.dumps(d["data"], ensure_ascii=False, indent=2) + "\n")

    refs = ROOT / "plugin" / "skills" / "work" / "references"
    write(refs / "data-model.md", data_model())
    write(refs / "engine.md", engine_reference(engine))

    mock = (ROOT / "tools" / "preview_mock.js").read_text(encoding="utf-8")
    for name, is_owner in (("owner", True), ("member", False)):
        seed = json.dumps(preview_seed(rules, engine, is_owner), ensure_ascii=False).replace("</", "<\\/")
        head = "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1,viewport-fit=cover'>"
        script = mock.replace("__SEED__", seed).replace("__OWNER__", "true" if is_owner else "false")
        write(ROOT / "dist" / f"preview-{name}.html", f"{head}<script>{script}</script>" + page("サンプル作品"))
    print(f"ルール {len(rules)} 件、エンジン知識 {len(engine)} 件、ページ {len(page().encode('utf-8')) // 1024} KB")


if __name__ == "__main__":
    main()
