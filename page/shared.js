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
