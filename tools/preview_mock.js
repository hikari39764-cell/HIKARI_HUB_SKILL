// 手元のプレビュー用：window.claude の代わり（メモリ上の db・固定の利用者）。公開するページには入らない。
(() => {
const SEED = __SEED__, OWNER = __OWNER__;
const store = new Map(Object.entries(SEED));
const subs = new Set();
const clone = (v) => JSON.parse(JSON.stringify(v));
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
const merge = (a, b) => { const o = { ...a }; for (const [k, v] of Object.entries(b)) o[k] = isObj(v) && isObj(o[k]) ? merge(o[k], v) : v; return o; };
const meta = { fromCache: false, hasPendingWrites: false };
const snapDoc = (path) => { const d = store.get(path); return { id: path.split("/").pop(), exists: d !== undefined, data: () => (d === undefined ? undefined : clone(d)), metadata: meta }; };
// 公開ページのアクセス規則と同じ形：settings / rules / engine はオーナーだけ、members は自分のものだけ。
const guard = (path) => { if (!OWNER && (/^(settings|rules|engine)\//.test(path) || (path.startsWith("members/") && path !== "members/u_me"))) throw { code: "invalid_argument", message: "denied" }; };
const fire = () => { for (const fn of subs) fn(); };
const listen = (make, next) => { const fn = () => next(make()); subs.add(fn); setTimeout(fn, 0); return () => subs.delete(fn); };
function docRef(path) {
  return { id: path.split("/").pop(), path,
    get: async () => snapDoc(path),
    set: async (d) => { guard(path); store.set(path, clone(d)); fire(); },
    update: async (d) => { guard(path); if (!store.has(path)) throw { code: "invalid_argument", message: "missing" }; store.set(path, merge(store.get(path), clone(d))); fire(); },
    delete: async () => { guard(path); store.delete(path); fire(); },
    onSnapshot: (next) => listen(() => snapDoc(path), next),
    collection: (sub) => collRef(path + "/" + sub) };
}
function collRef(cpath) {
  const depth = cpath.split("/").length + 1;
  const snap = () => { const docs = [...store.keys()].filter((p) => p.startsWith(cpath + "/") && p.split("/").length === depth).sort().map(snapDoc); return { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: meta }; };
  const q = { path: cpath, where: () => q, orderBy: () => q, limit: () => q, get: async () => snap(), onSnapshot: (next) => listen(snap, next),
    doc: (id) => docRef(cpath + "/" + (id || Math.random().toString(16).slice(2, 10))) };
  return q;
}
const caps = {
  db: { doc: docRef, collection: collRef },
  user: { id: async () => "u_me", isOwner: async () => OWNER, canEdit: async () => true, can: async () => true },
  assets: { upload: async (blob) => ({ id: "preview", url: URL.createObjectURL(blob), sizeBytes: blob.size, contentType: blob.type }) },
};
window.claude = { use: async (name) => caps[name] || null };
window.__mock = { store };
})();
