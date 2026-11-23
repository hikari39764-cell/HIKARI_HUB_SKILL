// ページに出ている文字を、ブラウザ内蔵の翻訳（Translator API、Chrome 138 以降のパソコン版）で訳す。
// 制作ハブ（page/hub.src.html）とエンジン中枢（D:/PJ/HIKARI-HQ/cloud/page.src.html）の両方がビルドで埋め込む。
// 訳はこの端末の中で作られ、どこにも送られない。コード・パス・id・入力欄は訳さない。
//
//   const tr = HikariTranslate({ onChange: 再描画, onFail: 内蔵の翻訳が使えないときの案内, key: "保存に使う名前" });
//   描画のたびに tr.apply()。ボタンのクリックの中で tr.toggle(言語) か tr.setTarget(言語)
//   （翻訳のモデルを初めて落とすときは、クリックの中で作る必要がある）。
//   tr.supported が false、または内蔵の翻訳が動かなかったときは onFail を呼んで止まる：ブラウザ自身の「翻訳」を使ってもらう。
"use strict";
window.HikariTranslate = function ({ onChange, onFail, key = "hikari-tr" }) {
  const supported = "Translator" in self;
  // 訳さないところ。ブラウザ自身の翻訳にも translate="no" で伝える。
  const KEEP = "code, pre, .mono";
  const SKIP = KEEP + ', script, style, textarea, input, select, option, svg, [translate="no"]';
  // モデルの用意や 1 文の翻訳がこれだけ黙っていたら、この端末では動かないとみなす（落としている間は進むたびに待ち直す）。
  const QUIET_MS = 20000;
  const cache = new Map(), wait = new Map(), makers = new Map(), unsupported = new Set();
  let on = false, target = "ja", busy = false, needClick = false, progress = -1;
  try { const saved = JSON.parse(localStorage.getItem(key) || "null"); if (saved) { on = !!saved.on && supported; target = saved.target || target; } } catch { /* 保存できなくても動く */ }

  // 見分けは文字の種類で足りる：かながあれば日本語、漢字だけなら中国語、ラテン文字が 3 語以上なら英語。
  // それ以外（数字、記号、1 語の英字 = 名前や id のことが多い）は訳さない。
  function langOf(text) {
    if (/[\u3040-\u30ff]/.test(text)) return "ja";
    if (/[\u4e00-\u9fff]/.test(text)) return "zh";
    if ((text.match(/[A-Za-z]{2,}/g) || []).length >= 3 && /\s/.test(text)) return "en";
    return "";
  }
  const memKey = () => key + ":" + target;
  function load() {
    cache.clear();
    try { for (const [k, v] of Object.entries(JSON.parse(localStorage.getItem(memKey()) || "{}"))) cache.set(k, v); } catch { /* 無くてもよい */ }
  }
  // 訳した文は端末に残す（次に開いたときすぐ出る）。古いものから捨てて 3000 件まで。
  function save() {
    try { localStorage.setItem(memKey(), JSON.stringify(Object.fromEntries([...cache].slice(-3000)))); } catch { /* 入りきらなくても動く */ }
  }
  const remember = () => { try { localStorage.setItem(key, JSON.stringify({ on, target })); } catch { /* 同上 */ } };
  load();

  // promise が QUIET_MS 黙っていたら TimeoutError で失敗させる。返す kick() を呼ぶと待ち直す（ダウンロードが進んだとき）。
  function watchdog(promise) {
    let timer, kick;
    const guarded = new Promise((resolve, reject) => {
      kick = () => { clearTimeout(timer); timer = setTimeout(() => reject(Object.assign(new Error("quiet"), { name: "TimeoutError" })), QUIET_MS); };
      kick();
      promise.then((v) => { clearTimeout(timer); resolve(v); }, (e) => { clearTimeout(timer); reject(e); });
    });
    return { guarded, kick };
  }
  function maker(src) {
    if (!makers.has(src)) {
      let kick = () => {};
      const created = self.Translator.create({ sourceLanguage: src, targetLanguage: target, monitor: (m) => m.addEventListener("downloadprogress", (e) => { progress = Math.round(e.loaded * 100); kick(); onChange(); }) });
      const w = watchdog(created);
      kick = w.kick;
      makers.set(src, w.guarded.then((t) => { progress = -1; return t; }, (e) => {
        makers.delete(src);
        progress = -1;
        if (e && e.name === "NotAllowedError") needClick = true;   // モデルを落とすにはクリックが要る
        else unsupported.add(src);                                // この組み合わせは訳せない、または動かない
        throw e;
      }));
    }
    return makers.get(src);
  }

  // 画面の文字を見て回る。visit(テキストノード, 文, 元の言語)。
  function walk(root, visit) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.nodeValue.trim();
      if (text.length < 2 || !node.parentElement || node.parentElement.closest(SKIP)) continue;
      const src = langOf(text);
      if (src && src !== target && !unsupported.has(src)) visit(node, text, src);
    }
  }
  // 訳し終わったものはすぐ差し替え、まだのものは順番待ちに入れる。
  function apply(root = document.body) {
    for (const el of root.querySelectorAll(KEEP)) el.translate = false;
    if (!on) return;
    walk(root, (node, text, src) => {
      const done = cache.get(text);
      if (done === undefined) wait.set(text, src);
      else if (done !== text) node.nodeValue = node.nodeValue.replace(text, () => done);
    });
    if (wait.size && !busy && !needClick) run();
  }
  // 内蔵の翻訳が動かない：止めて、ページにブラウザ自身の翻訳を案内してもらう。
  function giveUp() {
    on = false;
    wait.clear();
    remember();
    if (onFail) onFail();
  }
  async function run() {
    busy = true;
    onChange();
    let shown = performance.now(), ok = 0;
    try {
      while (wait.size && on && !needClick) {
        const [text, src] = wait.entries().next().value;
        wait.delete(text);
        if (unsupported.has(src)) continue;
        try {
          const translator = await maker(src);
          cache.set(text, await watchdog(translator.translate(text)).guarded);
          ok += 1;
        } catch (e) {
          if (e && e.name === "TimeoutError") unsupported.add(src);
          else if (!needClick && !unsupported.has(src)) cache.set(text, text);   // この文だけ訳せなかった：原文のまま
        }
        if (performance.now() - shown > 400) { shown = performance.now(); onChange(); }
      }
    } finally {
      busy = false;
      save();
      // 画面にある言語がどれも訳せなかった：内蔵の翻訳はこの端末では使えない。
      const left = new Set();
      if (on) walk(document.body, (node, text, src) => left.add(src));
      if (on && !needClick && !ok && unsupported.size && !left.size) giveUp();
      onChange();
    }
  }
  // クリックの中で、いま画面にある言語の翻訳を用意する（初めてならモデルを落とし始める）。
  function prepare() {
    needClick = false;
    const sources = new Set();
    walk(document.body, (node, text, src) => sources.add(src));
    for (const src of sources) maker(src).catch(() => {});
  }
  function setTarget(lang) {
    if (!lang || lang === target) return;
    target = lang;
    makers.clear();
    unsupported.clear();
    wait.clear();
    load();
    remember();
    if (on) prepare();
  }
  return {
    supported,
    get on() { return on; },
    get target() { return target; },
    // ボタンに出す様子："" / "busy"（訳している）/ "click"（モデルを落とすにはもう一度押す）。download はモデルを落としている % か -1。
    get status() { return needClick ? "click" : busy ? "busy" : ""; },
    get download() { return progress; },
    apply,
    setTarget,
    toggle(lang) {
      if (!supported) { if (onFail) onFail(); return; }
      if (lang && lang !== target) { setTarget(lang); on = true; } else on = !on || needClick;
      if (on) unsupported.clear();   // 押し直したら、前に動かなかった組み合わせももう一度試す
      remember();
      if (on) prepare();
      onChange();
    },
  };
};
