// HIKARI 两个网站共用的小工具（制作ハブ page/hub.src.html とエンジン中枢 D:/PJ/HIKARI-HQ/cloud/page.src.html の両方がビルドで埋め込む）。
"use strict";
// 换页时让内容依次浮现一次：key（页面的位置）变了才动，数据更新引起的重画不动。动效本身在 shared.css。
window.hikariEnter = (() => {
  let last = null, timer = 0;
  return (el, key) => {
    if (key === last) return;
    last = key;
    el.classList.remove("enter");
    void el.offsetWidth;
    el.classList.add("enter");
    clearTimeout(timer);
    timer = setTimeout(() => el.classList.remove("enter"), 600);
  };
})();

// 工作流（两个网站同一种写法）。参数一行一个：“名字：说明”，有默认值写成“名字=默认值：说明”；def 是 undefined 时运行要填。
// mark：已经转义好的 HTML 里，把步骤中的 {参数} 标出来（${…} 不是参数）。
window.hikariFlow = (() => {
  const LINE = /^\s*([^=：:]+?)\s*(?:=\s*([^：:]*?)\s*)?(?:[：:]\s*(.*))?$/;
  return {
    params: (w) => (w.params || []).map((line) => { const m = String(line).match(LINE) || []; return { name: m[1] || String(line).trim(), def: m[2], desc: m[3] || "" }; }),
    mark: (html) => html.replace(/(?<!\$)\{([^{}\s"':=,]+)\}/g, '<code class="param">{$1}</code>'),
  };
})();

// 复制到剪贴板：先用 Clipboard API；没有权限或不是安全来源时，换成选中文本再复制的老办法。
// 打开着的对话框外面是 inert 的，所以临时的文本框放进对话框里。
window.hikariCopy = async (text) => {
  try { await navigator.clipboard.writeText(text); return true; } catch { /* 下面换老办法 */ }
  const el = Object.assign(document.createElement("textarea"), { value: text, readOnly: true });
  el.style.cssText = "position:fixed;top:0;left:0;opacity:0";
  (document.querySelector("dialog[open]") || document.body).appendChild(el);
  el.select();
  let ok = false;
  try { ok = document.execCommand("copy"); } catch { ok = false; }
  el.remove();
  return ok;
};
