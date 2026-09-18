"use strict";

const CACHE_NAME = "remote-chat-assets-v4";
const APP_ASSETS = ["./", "./index.html", "./app.css", "./app.js", "./manifest.webmanifest"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
});

self.addEventListener("fetch", (event) => {
  const requestUrl = new URL(event.request.url);
  if (requestUrl.origin !== self.location.origin || requestUrl.pathname.includes("/api/")) return;
  if (!APP_ASSETS.some((asset) => requestUrl.pathname.endsWith(asset.replace("./", "/")) || (asset === "./" && requestUrl.pathname.endsWith("/")))) return;
  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
