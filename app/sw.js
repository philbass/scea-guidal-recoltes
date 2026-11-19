/* =====================================================================
   SCEA Guidal · fonctionnement hors connexion (service worker)
   Garde sur le téléphone les fichiers de l'application et les
   bibliothèques, pour que l'app s'ouvre même sans réseau aux champs.
   - Fichiers de l'app (index.html, config.js…) : réseau d'abord
     (les mises à jour arrivent tout de suite), copie gardée sinon.
   - Bibliothèques et polices (CDN) : copie gardée d'abord (versions figées).
   - Les échanges avec Supabase (données) ne passent jamais par ici :
     les saisies faites sans réseau sont gardées par l'application
     elle-même et envoyées au retour du réseau.
   Changer VERSION à chaque modification de ce fichier.
   ===================================================================== */
const VERSION = "guidal-v7-1";
const APP = ["./", "index.html", "config.js", "demo.js", "manifest.webmanifest", "icon.svg", "icon-180.png", "icon-192.png", "icon-512.png"];
const CDN = /^https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)\//;

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSION).then(c => Promise.all(APP.map(u => c.add(u).catch(() => null)))).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = req.url;
  /* bibliothèques et polices : copie gardée d'abord */
  if (CDN.test(url)) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res && (res.ok || res.type === "opaque")) { const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
      return res;
    })));
    return;
  }
  /* fichiers de l'application (même adresse) : réseau d'abord, copie gardée sinon */
  if (new URL(url).origin === self.location.origin) {
    e.respondWith(fetch(req).then(res => {
      if (res && res.ok) { const copy = res.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req, { ignoreSearch: true }).then(hit => hit || caches.match("index.html"))));
  }
  /* tout le reste (Supabase…) : comportement normal du navigateur */
});
