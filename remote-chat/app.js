(() => {
  "use strict";

  const API_PATH = "/api/remote-chat/v1";
  const BASE_KEY = "remote-chat-api-base";
  const TOKEN_KEY = "remote-chat-token";
  const pollEvery = { visible: 3000, hidden: 30000 };
  const state = { base: "", token: "", cursor: "", connected: false, pollTimer: 0, messages: new Map(), pending: new Map(), agents: [], selectedAgentId: "", selectedAgentName: "", rosterAvailable: true, avatarUrls: new Map(), requests: [], requestRevision: "", requestDrafts: new Map(), requestErrors: new Map(), requestSending: new Set(), requestFetchError: "", requestNotice: "" };

  const elements = {
    apiBase: document.querySelector("#api-base"), token: document.querySelector("#token"), panel: document.querySelector("#connection-panel"),
    status: document.querySelector("#status"), delivery: document.querySelector("#delivery-status"), messages: document.querySelector("#messages"),
    content: document.querySelector("#message-content"), send: document.querySelector("#send-button"), filter: document.querySelector("#agent-filter"), roster: document.querySelector("#agent-roster"),
    attention: document.querySelector("#attention-area"), attentionCount: document.querySelector("#attention-count"), attentionStatus: document.querySelector("#attention-status"), requestList: document.querySelector("#request-list")
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
  function setComposerEnabled(enabled) { elements.content.disabled = !enabled; elements.send.disabled = !enabled; elements.filter.disabled = !enabled; }

  async function request(path, options = {}) {
    const headers = new Headers(options.headers);
    headers.set("Authorization", `Bearer ${state.token}`);
    headers.set("Accept", "application/json");
    const response = await fetch(apiUrl(path), { ...options, headers, cache: "no-store" });
    if (!response.ok) {
      const error = new Error(response.status === 401 ? "Authentication failed." : `Request failed (${response.status}).`);
      error.status = response.status;
      throw error;
    }
    return response.json();
  }

  function messageTime(timestamp) {
    const date = new Date(timestamp);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }

  function messageAgentId(message) {
    if (!message.is_agent) return "";
    return String(message.agent_id || message.sender_agent_id || message.sender_id || "");
  }

  function isSystemMessage(message) { return Boolean(message.is_system || message.type === "system" || message.sender === "System"); }

  function matchesSelectedAgent(message) {
    if (!state.selectedAgentId || !message.is_agent || isSystemMessage(message)) return true;
    const agentId = messageAgentId(message);
    const agent = state.agents.find((item) => item.id === state.selectedAgentId);
    return agentId === state.selectedAgentId || (!agentId && agent && message.sender === agent.name);
  }

  function renderMessage(message) {
    const item = document.createElement("li");
    item.className = `message${isSystemMessage(message) ? " system" : message.is_agent ? " agent" : " mine"}${message.pending ? " pending" : ""}`;
    item.dataset.messageId = message.id;
    const header = document.createElement("div");
    header.className = "message-head";
    const sender = document.createElement("strong"); sender.textContent = message.sender || "User";
    const time = document.createElement("time"); time.textContent = messageTime(message.timestamp);
    const content = document.createElement("p"); content.className = "message-content"; content.textContent = message.content || "";
    header.append(sender, time); item.append(header, content);
    if (message.is_agent && !isSystemMessage(message)) {
      const reply = document.createElement("button"); reply.className = "reply"; reply.type = "button"; reply.textContent = "Reply";
      reply.addEventListener("click", () => { selectAgent(messageAgentId(message), message.sender); }); item.append(reply);
    }
    elements.messages.append(item); elements.messages.scrollTop = elements.messages.scrollHeight;
  }

  function renderMessages() {
    elements.messages.replaceChildren();
    for (const message of state.messages.values()) if (matchesSelectedAgent(message)) renderMessage(message);
  }

  function addMessage(message) {
    if (!message || !message.id || state.messages.has(message.id)) return;
    state.messages.set(message.id, message); renderMessages();
  }

  function removePending(id) {
    const item = elements.messages.querySelector(`[data-message-id="${id}"]`);
    if (item) item.remove();
    state.messages.delete(id);
    renderMessages();
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
    for (const message of data.messages || []) addMessage(message);
    if (data.next_cursor) state.cursor = data.next_cursor;
  }

  function renderRoster() {
    const selected = state.selectedAgentId;
    elements.filter.replaceChildren(new Option("All agents", ""));
    for (const agent of state.agents) elements.filter.add(new Option(agent.name, agent.id, false, agent.id === selected));
    if (selected && !state.agents.some((agent) => agent.id === selected)) elements.filter.add(new Option(state.selectedAgentName || "Selected agent", selected, true, true));
    if (!state.rosterAvailable) {
      elements.roster.replaceChildren(Object.assign(document.createElement("p"), { className: "roster-empty", textContent: "Agent roster is unavailable. Messages are still available." }));
      return;
    }
    if (!state.agents.length) {
      elements.roster.replaceChildren(Object.assign(document.createElement("p"), { className: "roster-empty", textContent: "No working agents reported." }));
      return;
    }
    const list = document.createElement("ul"); list.className = "agent-list";
    for (const agent of state.agents) {
      const item = document.createElement("li"); item.className = "agent-card";
      if (agent.avatarSrc) { const avatar = document.createElement("img"); avatar.className = "agent-avatar"; avatar.src = agent.avatarSrc; avatar.alt = ""; item.append(avatar); }
      const text = document.createElement("span"); text.textContent = `${agent.name || "Agent"} is ${agent.state || "working"}...`;
      item.append(text); list.append(item);
    }
    elements.roster.replaceChildren(list);
  }

  async function loadRoster() {
    try {
      const data = await request("/agents");
      const agents = Array.isArray(data.agents) ? data.agents.filter((agent) => agent && agent.id != null).map((agent) => ({ ...agent, id: String(agent.id) })) : [];
      await Promise.all(agents.map(loadAvatar));
      state.agents = agents;
      state.rosterAvailable = true;
    } catch (_) { state.rosterAvailable = false; }
    renderRoster(); renderMessages();
  }

  function requestKey(item) { return `${item.kind || "request"}:${item.agent_id || ""}:${item.request_id || ""}`; }

  function textElement(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    element.textContent = text;
    return element;
  }

  function saveRequestDrafts() {
    for (const card of elements.requestList.querySelectorAll("[data-request-key]")) {
      const questions = [];
      for (const fieldset of card.querySelectorAll(".request-question")) {
        const selected = [...fieldset.querySelectorAll(".answer-choice:checked")].map((input) => ({ type: input.dataset.answerType, value: input.value }));
        const custom = fieldset.querySelector(".custom-text");
        questions.push({ selected, custom: custom ? custom.value : "" });
      }
      if (questions.length) state.requestDrafts.set(card.dataset.requestKey, questions);
    }
  }

  function restoreQuestionDraft(fieldset, draft) {
    if (!draft) return;
    for (const input of fieldset.querySelectorAll(".answer-choice")) input.checked = draft.selected.some((choice) => choice.type === input.dataset.answerType && choice.value === input.value);
    const custom = fieldset.querySelector(".custom-text");
    if (custom) custom.value = draft.custom || "";
  }

  function appendPermissionDetails(card, item) {
    const details = [
      ["Patterns", Array.isArray(item.patterns) ? item.patterns.map(String).join("\n") : ""],
      ["Command", item.command || ""],
      ["Path", item.path || ""]
    ];
    for (const [label, value] of details) {
      if (!value) continue;
      const detail = document.createElement("div"); detail.className = "request-detail";
      detail.append(textElement("span", "", label), textElement("code", "", value)); card.append(detail);
    }
  }

  function appendQuestion(fieldset, question, index, draft) {
    fieldset.className = "request-question";
    if (question.header) fieldset.append(textElement("legend", "question-header", question.header));
    fieldset.append(textElement("p", "question-text", question.question || `Question ${index + 1}`));
    const inputType = question.multiple ? "checkbox" : "radio";
    for (const option of Array.isArray(question.options) ? question.options : []) {
      const label = document.createElement("label"); label.className = "answer-option";
      const input = document.createElement("input"); input.type = inputType; input.name = `question-${index}`; input.value = option.label || ""; input.className = "answer-choice"; input.dataset.answerType = "option";
      label.append(input, textElement("span", "", option.label || "Option"));
      if (option.description) label.append(textElement("small", "", option.description));
      fieldset.append(label);
    }
    if (question.custom) {
      const custom = document.createElement("label"); custom.className = "custom-answer";
      const choice = document.createElement("input"); choice.type = inputType; choice.name = `question-${index}`; choice.value = "custom"; choice.className = "answer-choice"; choice.dataset.answerType = "custom"; choice.setAttribute("aria-label", "Use custom answer");
      const input = document.createElement("input"); input.type = "text"; input.maxLength = 1000; input.placeholder = "Your own answer..."; input.className = "custom-text"; input.setAttribute("aria-label", "Custom answer");
      input.addEventListener("input", () => { if (input.value) choice.checked = true; });
      custom.append(choice, input); fieldset.append(custom);
    }
    restoreQuestionDraft(fieldset, draft);
  }

  function setRequestControls(card, disabled) {
    for (const control of card.querySelectorAll("button, input")) control.disabled = disabled;
  }

  function cardFeedback(card, text) {
    const feedback = card.querySelector(".request-feedback");
    if (feedback) feedback.textContent = text;
  }

  function collectAnswers(card) {
    const answers = [];
    for (const fieldset of card.querySelectorAll(".request-question")) {
      const values = [...fieldset.querySelectorAll('.answer-choice[data-answer-type="option"]:checked')].map((input) => input.value);
      const customChoice = fieldset.querySelector('.answer-choice[data-answer-type="custom"]');
      const customText = fieldset.querySelector(".custom-text");
      if (customChoice && customChoice.checked) {
        const value = customText.value.trim();
        if (!value) { customText.focus(); throw new Error("Enter the selected custom answer."); }
        values.push(value);
      }
      if (!values.length) { fieldset.querySelector("input")?.focus(); throw new Error("Answer every question before submitting."); }
      answers.push(values);
    }
    return answers;
  }

  async function respondToRequest(item, decision, card) {
    const key = requestKey(item);
    if (state.requestSending.has(key)) return;
    let answers;
    if (decision === "answer") {
      try { answers = collectAnswers(card); }
      catch (error) { cardFeedback(card, error.message); return; }
    }
    state.requestSending.add(key); state.requestErrors.delete(key); state.requestNotice = ""; cardFeedback(card, "Sending response..."); setRequestControls(card, true); updateAttentionState();
    const body = { kind: item.kind, agent_id: item.agent_id, request_id: item.request_id, decision };
    if (answers) body.answers = answers;
    try {
      await request("/requests/respond", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      state.requestDrafts.delete(key); state.requestErrors.delete(key);
      const refreshed = await loadRequests();
      if (!refreshed) {
        state.requests = state.requests.filter((requestItem) => requestKey(requestItem) !== key);
        state.requestRevision = JSON.stringify(state.requests); renderRequests();
      }
    } catch (error) {
      const message = error.status === 409 ? "This request is stale and can no longer be answered." : `Could not send response: ${error.message}`;
      state.requestErrors.set(key, message);
      await loadRequests();
      if (error.status === 409 || !state.requests.some((requestItem) => requestKey(requestItem) === key)) state.requestNotice = message;
    } finally {
      state.requestSending.delete(key);
      const currentCard = [...elements.requestList.querySelectorAll("[data-request-key]")].find((itemCard) => itemCard.dataset.requestKey === key);
      if (currentCard) { setRequestControls(currentCard, false); cardFeedback(currentCard, state.requestErrors.get(key) || ""); }
      updateAttentionState();
    }
  }

  function renderPermission(card, item) {
    card.append(textElement("p", "request-title", `${item.permission || "Action"} permission requested`));
    appendPermissionDetails(card, item);
    const actions = document.createElement("div"); actions.className = "request-actions";
    const once = textElement("button", "", "Allow once"); once.type = "button"; once.addEventListener("click", () => respondToRequest(item, "once", card)); actions.append(once);
    if (item.can_always) { const always = textElement("button", "secondary", "Always allow"); always.type = "button"; always.addEventListener("click", () => respondToRequest(item, "always", card)); actions.append(always); }
    const reject = textElement("button", "reject", "Reject"); reject.type = "button"; reject.addEventListener("click", () => respondToRequest(item, "reject", card)); actions.append(reject);
    card.append(actions);
  }

  function renderQuestion(card, item, draft) {
    const form = document.createElement("form");
    for (const [index, question] of (Array.isArray(item.questions) ? item.questions : []).entries()) {
      const fieldset = document.createElement("fieldset"); appendQuestion(fieldset, question || {}, index, draft?.[index]); form.append(fieldset);
    }
    const actions = document.createElement("div"); actions.className = "request-actions";
    const submit = textElement("button", "", "Send answers"); submit.type = "submit";
    const reject = textElement("button", "reject", "Reject"); reject.type = "button"; reject.addEventListener("click", () => respondToRequest(item, "reject", card));
    actions.append(submit, reject); form.append(actions);
    form.addEventListener("submit", (event) => { event.preventDefault(); respondToRequest(item, "answer", card); }); card.append(form);
  }

  function updateAttentionState() {
    const status = [state.requestNotice, state.requestFetchError].filter(Boolean).join(" ");
    elements.attention.hidden = state.requests.length === 0 && !status;
    elements.attentionCount.textContent = state.requests.length ? String(state.requests.length) : "";
    elements.attentionCount.hidden = state.requests.length === 0;
    elements.attentionStatus.textContent = status;
  }

  function renderRequests() {
    saveRequestDrafts(); elements.requestList.replaceChildren();
    const liveKeys = new Set(state.requests.map(requestKey));
    for (const key of state.requestDrafts.keys()) if (!liveKeys.has(key)) state.requestDrafts.delete(key);
    for (const item of state.requests) {
      const key = requestKey(item);
      const card = document.createElement("article"); card.className = "request-card"; card.dataset.requestKey = key;
      const head = document.createElement("div"); head.className = "request-card-head";
      head.append(textElement("strong", "", item.agent_name || item.agent_id || "Agent"), textElement("span", "request-kind", item.kind === "question" ? "Question" : "Permission")); card.append(head);
      if (item.kind === "question") renderQuestion(card, item, state.requestDrafts.get(key)); else renderPermission(card, item);
      card.append(textElement("p", "request-feedback", state.requestErrors.get(key) || ""));
      if (state.requestSending.has(key)) setRequestControls(card, true);
      elements.requestList.append(card);
    }
    updateAttentionState();
  }

  async function loadRequests() {
    try {
      const data = await request("/requests");
      const requests = Array.isArray(data.requests) ? data.requests.filter((item) => item && item.request_id != null && (item.kind === "permission" || item.kind === "question")) : [];
      const revision = JSON.stringify(requests);
      state.requestFetchError = "";
      if (revision !== state.requestRevision) { state.requests = requests; state.requestRevision = revision; renderRequests(); }
      else updateAttentionState();
      return true;
    } catch (error) {
      state.requestFetchError = `Could not refresh requests: ${error.message}`;
      updateAttentionState();
      return false;
    }
  }

  async function loadAvatar(agent) {
    if (!agent.avatar_url) return;
    if (state.avatarUrls.has(agent.id)) { agent.avatarSrc = state.avatarUrls.get(agent.id); return; }
    try {
      const response = await fetch(new URL(agent.avatar_url, `${state.base}/`), { headers: { Authorization: `Bearer ${state.token}` }, cache: "no-store" });
      if (!response.ok) return;
      const url = URL.createObjectURL(await response.blob());
      state.avatarUrls.set(agent.id, url); agent.avatarSrc = url;
    } catch (_) {}
  }

  function selectAgent(id, name) {
    const agent = state.agents.find((item) => item.id === id);
    state.selectedAgentId = agent ? agent.id : id;
    state.selectedAgentName = agent ? agent.name : name || "";
    if (!agent && name) {
      const matchingAgent = state.agents.find((item) => item.name === name);
      state.selectedAgentId = matchingAgent ? matchingAgent.id : state.selectedAgentId;
      state.selectedAgentName = matchingAgent ? matchingAgent.name : state.selectedAgentName;
    }
    renderRoster(); renderMessages(); elements.content.focus();
  }

  function schedulePoll() {
    window.clearTimeout(state.pollTimer);
    if (!state.base || !state.token) return;
    state.pollTimer = window.setTimeout(async () => {
      try { await loadMessages(); await loadRoster(); await loadRequests(); state.connected = true; setComposerEnabled(true); setStatus("Connected", "online"); }
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
      for (const url of state.avatarUrls.values()) URL.revokeObjectURL(url);
      state.avatarUrls.clear(); state.connected = true; state.cursor = ""; state.messages.clear(); state.requests = []; state.requestRevision = ""; state.requestDrafts.clear(); state.requestErrors.clear(); state.requestFetchError = ""; state.requestNotice = ""; elements.messages.replaceChildren(); renderRequests();
      await loadMessages(true);
      await loadRoster();
      await loadRequests();
      elements.panel.hidden = true; setComposerEnabled(true); setStatus("Connected", "online"); setDelivery(); schedulePoll();
    } catch (error) { markDisconnected(error.message); schedulePoll(); }
  }

  async function sendPending(pending) {
    try {
      const body = { content: pending.content, client_message_id: pending.clientMessageId };
      if (pending.targetAgentId) body.target_agent_id = pending.targetAgentId;
      const data = await request("/messages", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      removePending(pending.id);
      if (data.message) addMessage(data.message);
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
    const pending = { id: `pending-${uuid()}`, content, clientMessageId: uuid(), targetAgentId: state.selectedAgentId };
    addMessage({ id: pending.id, sender: "You", content, timestamp: Date.now(), is_agent: false, pending: true });
    elements.content.value = ""; sendPending(pending);
  });
  elements.filter.addEventListener("change", () => {
    state.selectedAgentId = elements.filter.value;
    state.selectedAgentName = state.agents.find((agent) => agent.id === state.selectedAgentId)?.name || "";
    renderMessages();
  });
  window.addEventListener("online", connect);
  window.addEventListener("offline", () => markDisconnected("Network unavailable."));
  window.addEventListener("focus", () => { if (state.base && state.token) { loadMessages().catch((error) => markDisconnected(error.message)); loadRoster(); loadRequests(); schedulePoll(); } });
  document.addEventListener("visibilitychange", () => { if (state.base && state.token && !document.hidden) { loadMessages().catch((error) => markDisconnected(error.message)); loadRoster(); loadRequests(); } schedulePoll(); });

  const query = new URLSearchParams(location.search);
  const fragment = new URLSearchParams(location.hash.replace(/^#/, ""));
  const qrToken = fragment.get("remote_chat_token") || query.get("remote_chat_token") || "";
  const qrBase = query.get("remote_chat_base") || location.origin;
  elements.apiBase.value = localStorage.getItem(BASE_KEY) || qrBase;
  elements.token.value = qrToken || sessionStorage.getItem(TOKEN_KEY) || "";
  if (qrToken) window.history.replaceState({}, document.title, location.pathname);
  if (elements.token.value && elements.apiBase.value) connect();
  if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("service-worker.js"));
})();
