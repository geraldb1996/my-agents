(() => {
  "use strict";

  const API_PATH = "/api/remote-chat/v1";
  const BASE_KEY = "remote-chat-api-base";
  const TOKEN_KEY = "remote-chat-token";
  const pollEvery = { visible: 3000, hidden: 30000 };
  const state = { base: "", token: "", cursor: "", connected: false, pollTimer: 0, messages: new Set(), pending: new Map() };

  const elements = {
    apiBase: document.querySelector("#api-base"), token: document.querySelector("#token"), panel: document.querySelector("#connection-panel"),
    status: document.querySelector("#status"), delivery: document.querySelector("#delivery-status"), messages: document.querySelector("#messages"),
    content: document.querySelector("#message-content"), send: document.querySelector("#send-button")
  };

  function apiUrl(path) { return `${state.base}${API_PATH}${path}`; }
  function normalizeBase(value) { return value.trim().replace(/\/+$/, ""); }
  function uuid() {
    if (crypto.randomUUID) return crypto.randomUUID();
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return [...bytes].map((byte, index) => `${byte.toString(16).padStart(2, "0")}${[3, 5, 7, 9].includes(index) ? "-" : ""}`).join("");
  }
  function setStatus(text, kind = "") { elements.status.textContent = text; elements.status.className = `status ${kind}`; }
  function setDelivery(text = "", isError = false) { elements.delivery.textContent = text; elements.delivery.className = isError ? "delivery-status error" : "delivery-status"; }
  function setComposerEnabled(enabled) { elements.content.disabled = !enabled; elements.send.disabled = !enabled; }

  async function request(path, options = {}) {
    const headers = new Headers(options.headers);
    headers.set("Authorization", `Bearer ${state.token}`);
    headers.set("Accept", "application/json");
    const response = await fetch(apiUrl(path), { ...options, headers, cache: "no-store" });
    if (!response.ok) throw new Error(response.status === 401 ? "Authentication failed." : `Request failed (${response.status}).`);
    return response.json();
  }

  function messageTime(timestamp) {
    const date = new Date(timestamp);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }

  function renderMessage(message, pending = false) {
    if (state.messages.has(message.id)) return;
    state.messages.add(message.id);
    const item = document.createElement("li");
    item.className = `message${message.is_agent ? "" : " mine"}${pending ? " pending" : ""}`;
    item.dataset.messageId = message.id;
    const header = document.createElement("div");
    header.className = "message-head";
    const sender = document.createElement("strong"); sender.textContent = message.sender || "User";
    const time = document.createElement("time"); time.textContent = messageTime(message.timestamp);
    const content = document.createElement("p"); content.className = "message-content"; content.textContent = message.content || "";
    header.append(sender, time); item.append(header, content);
    elements.messages.append(item); elements.messages.scrollTop = elements.messages.scrollHeight;
  }

  function removePending(id) {
    const item = elements.messages.querySelector(`[data-message-id="${id}"]`);
    if (item) item.remove();
    state.messages.delete(id);
  }

  function deliveryText(data) {
    const results = data.delivery || data.target_results || data.results;
    if (!Array.isArray(results)) return "";
    return results.map((result) => result.message || result.status || "").filter(Boolean).join(" ");
  }

  async function loadMessages(initial = false) {
    if (!state.base || !state.token) return;
    const query = initial || !state.cursor ? "?limit=100" : `?after=${encodeURIComponent(state.cursor)}&limit=100`;
    const data = await request(`/messages${query}`);
    for (const message of data.messages || []) renderMessage(message);
    if (data.next_cursor) state.cursor = data.next_cursor;
  }

  function schedulePoll() {
    window.clearTimeout(state.pollTimer);
    if (!state.base || !state.token) return;
    state.pollTimer = window.setTimeout(async () => {
      try { await loadMessages(); state.connected = true; setComposerEnabled(true); setStatus("Connected", "online"); }
      catch (error) { markDisconnected(error.message); }
      schedulePoll();
    }, document.hidden ? pollEvery.hidden : pollEvery.visible);
  }

  function markDisconnected(message) {
    state.connected = false;
    setComposerEnabled(false);
    setStatus(navigator.onLine ? `Desktop offline: ${message}` : "Offline: waiting for network.", "offline");
  }

  async function connect() {
    state.base = normalizeBase(elements.apiBase.value);
    state.token = elements.token.value.trim();
    if (!state.base || !state.token) return;
    localStorage.setItem(BASE_KEY, state.base);
    sessionStorage.setItem(TOKEN_KEY, state.token);
    setStatus("Checking desktop...");
    try {
      await request("/health");
      state.connected = true; state.cursor = ""; state.messages.clear(); elements.messages.replaceChildren();
      await loadMessages(true);
      elements.panel.hidden = true; setComposerEnabled(true); setStatus("Connected", "online"); setDelivery(); schedulePoll();
    } catch (error) { markDisconnected(error.message); schedulePoll(); }
  }

  async function sendPending(pending) {
    try {
      const data = await request("/messages", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ content: pending.content, client_message_id: pending.clientMessageId }) });
      removePending(pending.id);
      if (data.message) renderMessage(data.message);
      if (data.next_cursor) state.cursor = data.next_cursor;
      setDelivery(deliveryText(data));
      await loadMessages();
    } catch (error) {
      const item = elements.messages.querySelector(`[data-message-id="${pending.id}"]`);
      if (item && !item.querySelector(".retry")) {
        const retry = document.createElement("button"); retry.className = "retry"; retry.type = "button"; retry.textContent = "Delivery failed. Retry";
        retry.addEventListener("click", () => { retry.remove(); sendPending(pending); }); item.append(retry);
      }
      setDelivery(`Delivery failed: ${error.message}`, true); markDisconnected(error.message);
    }
  }

  document.querySelector("#connection-form").addEventListener("submit", (event) => { event.preventDefault(); connect(); });
  document.querySelector("#settings-toggle").addEventListener("click", () => { elements.panel.hidden = !elements.panel.hidden; });
  document.querySelector("#close-settings").addEventListener("click", () => { elements.panel.hidden = true; });
  document.querySelector("#message-form").addEventListener("submit", (event) => {
    event.preventDefault(); const content = elements.content.value.trim(); if (!content || !state.connected) return;
    const pending = { id: `pending-${uuid()}`, content, clientMessageId: uuid() };
    renderMessage({ id: pending.id, sender: "You", content, timestamp: Date.now(), is_agent: false }, true);
    elements.content.value = ""; sendPending(pending);
  });
  window.addEventListener("online", connect);
  window.addEventListener("offline", () => markDisconnected("Network unavailable."));
  window.addEventListener("focus", () => { if (state.base && state.token) { loadMessages().catch((error) => markDisconnected(error.message)); schedulePoll(); } });
  document.addEventListener("visibilitychange", () => { if (state.base && state.token && !document.hidden) loadMessages().catch((error) => markDisconnected(error.message)); schedulePoll(); });

  elements.apiBase.value = localStorage.getItem(BASE_KEY) || location.origin;
  elements.token.value = sessionStorage.getItem(TOKEN_KEY) || "";
  if (elements.token.value && elements.apiBase.value) connect();
  if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("service-worker.js"));
})();
