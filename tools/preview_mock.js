// 手元のプレビュー用：window.hubBackend の代わり（メモリ上のデータ・固定の利用者）。公開するサイトには入らない。
// 「?out=1」を付けるとログイン前の画面から始まる。
(() => {
const SEED = __SEED__, OWNER = __OWNER__;
const ME = { uid: "u_me", email: OWNER ? "owner@example.com" : "member@example.com", name: OWNER ? "見本のオーナー" : "見本のメンバー" };
const store = new Map(Object.entries(SEED));
const subs = new Set();
const clone = (v) => JSON.parse(JSON.stringify(v));
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
const merge = (a, b) => { const o = { ...a }; for (const [k, v] of Object.entries(b)) o[k] = isObj(v) && isObj(o[k]) ? merge(o[k], v) : v; return o; };
const meta = { fromCache: false, hasPendingWrites: false };
const snapDoc = (path) => { const d = store.get(path); return { id: path.split("/").pop(), exists: d !== undefined, data: () => (d === undefined ? undefined : clone(d)), metadata: meta }; };
// firestore.rules と同じ形：settings / rules / engine / invites はオーナーだけ、members は自分のものだけ、消せるのはオーナーだけ。
// hub/owner はオーナーにしか読めない（ページはこれでオーナーかどうかを確かめる）。
function guard(path, remove) {
  if (OWNER) return;
  const m = path.match(/^projects\/[^/]+\/([^/]+)\/(.+)$/);
  if (!m || remove || /^(settings|rules|engine|invites)$/.test(m[1]) || (m[1] === "members" && m[2] !== ME.uid)) throw { code: "permission-denied", message: "denied" };
}
const fire = () => { for (const fn of subs) fn(); };
const listen = (make, next) => { const fn = () => next(make()); subs.add(fn); setTimeout(fn, 0); return () => subs.delete(fn); };
function docRef(path) {
  return {
    get: async () => { if (path === "hub/owner") guard(path); return snapDoc(path); },
    set: async (d) => { guard(path); store.set(path, clone(d)); fire(); },
    update: async (d) => { guard(path); store.set(path, merge(store.get(path) || {}, clone(d))); fire(); },
    delete: async () => { guard(path, true); store.delete(path); fire(); },
    onSnapshot: (next) => listen(() => snapDoc(path), next) };
}
function collRef(cpath) {
  const depth = cpath.split("/").length + 1;
  const snap = () => ({ docs: [...store.keys()].filter((p) => p.startsWith(cpath + "/") && p.split("/").length === depth).sort().map(snapDoc), metadata: meta });
  const q = { orderBy: () => q, limit: () => q, onSnapshot: (next) => listen(snap, next) };
  return q;
}
let signed = !new URLSearchParams(location.search).has("out"), onAuth = () => {};
window.hubBackend = {
  db: { doc: docRef, collection: collRef },
  onAuth: (cb) => { onAuth = cb; setTimeout(() => cb(signed ? ME : null), 0); },
  signIn: async () => { signed = true; onAuth(ME); },
  signOut: async () => { signed = false; onAuth(null); },
  key: () => "hhk1.preview",
};
window.__mock = { store };
})();
