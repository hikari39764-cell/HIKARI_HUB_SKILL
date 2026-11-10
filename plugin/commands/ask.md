---
description: わからないことを、まずハブで探し、なければ質問板に出す
argument-hint: "<質問>"
---

`hub:work` スキルを読み込む（準備がまだなら「0. 準備」から）。

質問：$ARGUMENTS

1. `.hikari-hub/cache` の `knowledge`・`questions`・`engine`・`rules`・`decisions` を Grep で探す。見つかったら、出典（記録の名前）を付けて答える。
2. 見つからなければ `questions` に出す。背景と、もう調べたことを書く。仕様・見た目・方針は `オーナー` あて、それ以外は `エージェント` あて。
3. 待つ間に進められる前提があれば、それを人に伝える。
