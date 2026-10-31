// CrossEngin web UI (R108, ADR-0209 Mode 4). Vanilla JS, no framework.
//
// Talks to the shim (scripts/rpc_web_shim.py) via POST /rpc/<verb>.
// The shim forwards to the TCP daemon and returns its {ok, result,
// error} envelope, mapping wire errors to HTTP status codes we use
// here for the banner UX (429 rate-limit, 401 unknown token, 403
// insufficient cap, 405 unknown verb, 400 other).
//
// R108 additions on top of the R51 SPA:
//   * cap-token login modal + localStorage persistence
//   * per-panel pagination state + Load-more button (R107 next_after)
//   * error banners (rate-limit / auth / cap / network)
//   * sidebar tabs for panels: ask / capsules / skills / kgs / patterns
//     / confidence / gaps / metrics / prefs
//   * mobile hamburger toggle

"use strict";

const $ = (id) => document.getElementById(id);
const empty = (el) => { while (el.firstChild) el.removeChild(el.firstChild); };

// ---- token storage -------------------------------------------------------

const TOKEN_KEY = "crossengin_token";

function loadToken() {
  try { return localStorage.getItem(TOKEN_KEY) || ""; }
  catch (e) { return ""; }
}
function saveToken(t) {
  try { localStorage.setItem(TOKEN_KEY, t); } catch (e) { /* private-mode etc */ }
}
function clearToken() {
  try { localStorage.removeItem(TOKEN_KEY); } catch (e) { /* ditto */ }
}

// ---- rpc() ---------------------------------------------------------------

async function rpc(verb, args = {}) {
  const token = loadToken();
  const payload = Object.assign({}, args);
  // Cap-token rides at TOP level of the wire message (the shim lifts
  // it out of the body). Include only when the user has one.
  if (token) payload.token = token;
  let resp;
  try {
    resp = await fetch(`/rpc/${encodeURIComponent(verb)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    showBanner("net", "Daemon unreachable. Check that the shim is running.");
    return { httpStatus: 0, envelope: { ok: false, error: `network: ${e}` }, raw: "" };
  }
  const text = await resp.text();
  let envelope;
  try { envelope = JSON.parse(text); }
  catch (e) {
    envelope = { ok: false, result: null, error: `bad shim response: ${e}` };
  }
  // Classify by HTTP status first (the shim's authoritative signal),
  // then fall back to error-string sniffing.
  if (!envelope.ok) {
    const err = (envelope.error || "").toLowerCase();
    if (resp.status === 429 || err.includes("rate limit")) {
      showBanner("warn", "Rate limit exceeded. Retry in ~1s.");
    } else if (resp.status === 401 ||
               err.includes("unknown token") ||
               err.includes("token revoked") ||
               err.includes("token expired") ||
               err.includes("missing 'token'")) {
      showBanner("bad", "Sign-in required. Paste your cap token.");
      openLogin();
    } else if (resp.status === 403 || err.includes("capability required")) {
      showBanner("bad", "Your token lacks permission for this action.");
    }
  } else {
    dismissAllBanners();
  }
  return { httpStatus: resp.status, envelope, raw: text };
}

// ---- banner rail ---------------------------------------------------------

const BANNER_TIMEOUT_MS = 5000;
let bannerSeq = 0;
const bannerTimers = new Map();

function showBanner(kind, text) {
  const rail = $("banner-rail");
  const id = "banner-" + (++bannerSeq);
  const div = document.createElement("div");
  div.className = "banner banner-" + kind;
  div.id = id;
  const span = document.createElement("span");
  span.textContent = text;
  const close = document.createElement("button");
  close.type = "button";
  close.textContent = "x";
  close.className = "banner-close";
  close.setAttribute("aria-label", "dismiss");
  close.addEventListener("click", () => dismissBanner(id));
  div.appendChild(span);
  div.appendChild(close);
  rail.appendChild(div);
  const t = setTimeout(() => dismissBanner(id), BANNER_TIMEOUT_MS);
  bannerTimers.set(id, t);
}
function dismissBanner(id) {
  const el = document.getElementById(id);
  if (el) el.remove();
  const t = bannerTimers.get(id);
  if (t) { clearTimeout(t); bannerTimers.delete(id); }
}
function dismissAllBanners() {
  const rail = $("banner-rail");
  if (!rail) return;
  Array.from(rail.children).forEach((el) => dismissBanner(el.id));
}

// ---- login modal ---------------------------------------------------------

function openLogin() {
  const m = $("login-modal");
  m.hidden = false;
  const inp = $("login-token");
  inp.value = loadToken();
  inp.focus();
}
function closeLogin() { $("login-modal").hidden = true; }

function onLoginSubmit(ev) {
  ev.preventDefault();
  const val = $("login-token").value.trim();
  if (!val) return;
  saveToken(val);
  closeLogin();
  updateAuthChrome();
  pingDaemon();
  reloadActivePanel();
}
function onLoginAnon() {
  clearToken();
  closeLogin();
  updateAuthChrome();
  pingDaemon();
  reloadActivePanel();
}
function onLogout() {
  clearToken();
  updateAuthChrome();
  openLogin();
}

function updateAuthChrome() {
  const has = !!loadToken();
  $("logout-btn").hidden = !has;
}

// ---- daemon health ping --------------------------------------------------

async function pingDaemon() {
  const dot = document.querySelector("#daemon-status .dot");
  const txt = document.querySelector("#daemon-status .daemon-text");
  const { envelope, httpStatus } = await rpc("kg.list", { limit: 1 });
  if (envelope.ok) {
    dot.className = "dot dot-ok";
    txt.textContent = "daemon up";
  } else if (httpStatus === 0) {
    dot.className = "dot dot-bad";
    txt.textContent = "shim unreachable";
  } else {
    dot.className = "dot dot-bad";
    txt.textContent = `daemon: ${envelope.error || httpStatus}`;
  }
}

// ---- pagination state ----------------------------------------------------

const panelState = {
  capsules: { items: [], next_after: "" },
  skills:   { items: [], next_after: "" },
  kgs:      { items: [], next_after: "" },
  patterns: { items: [], next_after: "" },
  gaps:     { items: [], next_after: "" },
  metrics:  { items: [], next_after: "" },
};

function resetPanelState(name) {
  panelState[name] = { items: [], next_after: "" };
}

async function fetchPage(verb, panelName, extraArgs) {
  const st = panelState[panelName];
  const args = Object.assign({ limit: 50 }, extraArgs || {});
  if (st.next_after) args.after = st.next_after;
  const { envelope } = await rpc(verb, args);
  return envelope;
}

function attachLoadMore(panelName, refreshFn) {
  const btn = document.querySelector(`.load-more[data-panel="${panelName}"]`);
  if (!btn) return;
  btn.onclick = async () => {
    btn.disabled = true;
    await refreshFn(false);
    btn.disabled = false;
  };
}

function setLoadMoreVisible(panelName, visible) {
  const btn = document.querySelector(`.load-more[data-panel="${panelName}"]`);
  if (btn) btn.hidden = !visible;
}

// ---- Capsules panel ------------------------------------------------------

async function refreshCapsules(reset) {
  if (reset) resetPanelState("capsules");
  const env = await fetchPage("capsule.list", "capsules");
  const list = $("capsules-list");
  if (reset) empty(list);
  if (!env.ok) {
    list.innerHTML = `<li class="loading">${env.error || "error"}</li>`;
    return;
  }
  const items = (env.result && env.result.capsules) || [];
  for (const c of items) {
    const li = document.createElement("li");
    const mark = c.installed ? "" : " (uninstalled)";
    li.innerHTML = `<code></code> <span class="ver"></span>`;
    li.querySelector("code").textContent = c.name || "?";
    li.querySelector(".ver").textContent =
      `v${c.version || "?"}${mark}`;
    list.appendChild(li);
  }
  panelState.capsules.items = panelState.capsules.items.concat(items);
  const na = (env.result && env.result.next_after) || "";
  panelState.capsules.next_after = na;
  setLoadMoreVisible("capsules", na !== "");
  if (panelState.capsules.items.length === 0) {
    list.innerHTML = `<li class="loading">no capsules</li>`;
  }
}

// ---- Skills panel --------------------------------------------------------

async function refreshSkills(reset) {
  if (reset) resetPanelState("skills");
  const env = await fetchPage("skill.list", "skills");
  const list = $("skills-list");
  if (reset) empty(list);
  if (!env.ok) {
    list.innerHTML = `<li class="loading">${env.error || "error"}</li>`;
    return;
  }
  const items = (env.result && env.result.skills) || [];
  for (const sk of items) {
    const li = document.createElement("li");
    const mark = sk.installed ? "" : " (uninstalled)";
    li.innerHTML = `<code></code> <span class="ver"></span>`;
    li.querySelector("code").textContent = (sk.name || "?") + mark;
    if (sk.version) li.querySelector(".ver").textContent = "v" + sk.version;
    if (sk.description) li.title = sk.description;
    list.appendChild(li);
  }
  panelState.skills.items = panelState.skills.items.concat(items);
  const na = (env.result && env.result.next_after) || "";
  panelState.skills.next_after = na;
  setLoadMoreVisible("skills", na !== "");
  if (panelState.skills.items.length === 0) {
    list.innerHTML = `<li class="loading">no skills</li>`;
  }
}

// ---- KGs panel -----------------------------------------------------------

async function refreshKGs(reset) {
  if (reset) resetPanelState("kgs");
  const env = await fetchPage("kg.list", "kgs");
  const list = $("kgs-list");
  if (reset) empty(list);
  if (!env.ok) {
    list.innerHTML = `<li class="loading">${env.error || "error"}</li>`;
    return;
  }
  const items = (env.result && env.result.labels) || [];
  for (const lab of items) {
    const li = document.createElement("li");
    li.textContent = lab;
    list.appendChild(li);
  }
  panelState.kgs.items = panelState.kgs.items.concat(items);
  const na = (env.result && env.result.next_after) || "";
  panelState.kgs.next_after = na;
  setLoadMoreVisible("kgs", na !== "");
  if (panelState.kgs.items.length === 0) {
    list.innerHTML = `<li class="loading">no KGs</li>`;
  }
}

// ---- Patterns panel ------------------------------------------------------

async function refreshPatterns(reset) {
  if (reset) resetPanelState("patterns");
  const env = await fetchPage("pattern.list", "patterns");
  const list = $("patterns-list");
  if (reset) empty(list);
  if (!env.ok) {
    list.innerHTML = `<li class="loading">${env.error || "error"}</li>`;
    return;
  }
  const items = (env.result && env.result.patterns) || [];
  for (const p of items) {
    const li = document.createElement("li");
    li.innerHTML = `<code></code> <span class="ver"></span>
                    <span class="meta"></span>`;
    li.querySelector("code").textContent = p.name || "?";
    li.querySelector(".ver").textContent = "v" + (p.version || "?");
    li.querySelector(".meta").textContent =
      `${p.pattern_count || 0} patterns · ${p.source_tag || ""}`;
    list.appendChild(li);
  }
  panelState.patterns.items = panelState.patterns.items.concat(items);
  const na = (env.result && env.result.next_after) || "";
  panelState.patterns.next_after = na;
  setLoadMoreVisible("patterns", na !== "");
  if (panelState.patterns.items.length === 0) {
    list.innerHTML = `<li class="loading">no pattern capsules</li>`;
  }
}

// ---- Gaps panel ----------------------------------------------------------

async function refreshGaps(reset) {
  if (reset) resetPanelState("gaps");
  const env = await fetchPage("self.gaps", "gaps");
  const list = $("gaps-list");
  if (reset) empty(list);
  if (!env.ok) {
    list.innerHTML = `<li class="loading">${env.error || "error"}</li>`;
    return;
  }
  const items = (env.result && env.result.entries) || [];
  for (const g of items) {
    const li = document.createElement("li");
    li.className = "gap-row";
    li.innerHTML = `<span class="reason"></span>
                    <span class="topic"></span>
                    <span class="detail"></span>
                    <span class="ts"></span>`;
    li.querySelector(".reason").textContent = g.reason || "?";
    li.querySelector(".topic").textContent = g.topic || "";
    li.querySelector(".detail").textContent = g.detail || "";
    if (g.timestamp) {
      // Timestamps are nanotime; render seconds since epoch when
      // sensible, otherwise the raw counter.
      const secs = Math.floor(Number(g.timestamp) / 1e9);
      if (secs > 1e9) {
        li.querySelector(".ts").textContent =
          new Date(secs * 1000).toISOString().replace("T", " ").slice(0, 19);
      } else {
        li.querySelector(".ts").textContent = String(g.timestamp);
      }
    }
    list.appendChild(li);
  }
  panelState.gaps.items = panelState.gaps.items.concat(items);
  const na = (env.result && env.result.next_after) || "";
  panelState.gaps.next_after = na;
  setLoadMoreVisible("gaps", na !== "");
  if (panelState.gaps.items.length === 0) {
    list.innerHTML = `<li class="loading">no gap events recorded</li>`;
  }
}

// ---- Metrics dashboard ---------------------------------------------------

async function refreshMetrics(reset) {
  if (reset) resetPanelState("metrics");
  const env = await fetchPage("nl.metrics", "metrics");
  const tbody = document.querySelector("#metrics-table tbody");
  if (reset) empty(tbody);
  if (!env.ok) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td colspan="7"></td>`;
    tr.querySelector("td").textContent = env.error || "error";
    tbody.appendChild(tr);
    return;
  }
  // nl.metrics returns { holders: {<h>: <row>, ...}, next_after: ... }.
  // The holders object preserves insertion order per R107 (aggregate
  // row `_total_all_holders` is appended per page).
  const holders = (env.result && env.result.holders) || {};
  const na = (env.result && env.result.next_after) || "";
  for (const [holder, row] of Object.entries(holders)) {
    const tr = document.createElement("tr");
    if (holder === "_total_all_holders") tr.className = "agg-row";
    const total     = row.total ?? 0;
    const unparsed  = row.unparsed ?? 0;
    const attempts  = row.llm_fallback_attempts ?? row.attempts ?? 0;
    const successes = row.llm_fallback_successes ?? row.successes ?? 0;
    const failures  = row.llm_fallback_failures ?? row.failures ?? 0;
    const rate = total > 0 ? ((attempts * 100) / total).toFixed(1) : "0.0";
    const cells = [holder, total, unparsed, attempts, successes, failures, rate + "%"];
    for (const c of cells) {
      const td = document.createElement("td");
      td.textContent = c;
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  panelState.metrics.next_after = na;
  setLoadMoreVisible("metrics", na !== "");
  if (Object.keys(holders).length === 0) {
    const tr = document.createElement("tr");
    tr.innerHTML = `<td colspan="7">no traffic yet</td>`;
    tbody.appendChild(tr);
  }
}

// ---- self.confidence -----------------------------------------------------

async function onConfidenceSubmit(ev) {
  ev.preventDefault();
  const topic = $("conf-topic").value.trim();
  if (!topic) return;
  const out = $("confidence-out");
  out.hidden = false;
  out.textContent = "querying…";
  const { envelope } = await rpc("self.confidence", { topic });
  if (!envelope.ok) { out.textContent = envelope.error || "error"; return; }
  const r = envelope.result || {};
  const conf = ((r.aggregate_confidence_milli || 0) / 10).toFixed(1);
  const matches = (r.matches || []).map((m) =>
    `  · ${m.kg || "?"}:${m.label || "?"} — belief ${m.belief ?? "?"}/1000 (w ${m.weight_milli ?? "?"})`
  ).join("\n") || "  (no matches)";
  out.textContent =
    `topic: ${r.topic}\n` +
    `mode: ${r.mode}\n` +
    `matched atoms: ${r.matched_atom_count}\n` +
    `aggregate confidence: ${conf}%\n` +
    `epistemic status: ${r.epistemic_status}\n` +
    `top matches:\n${matches}`;
}

// ---- Preferences editor --------------------------------------------------

async function refreshPrefs() {
  const list = $("prefs-list");
  empty(list);
  const { envelope } = await rpc("user.preference.list", {});
  if (!envelope.ok) {
    list.innerHTML = `<li class="loading">${envelope.error || "error"}</li>`;
    return;
  }
  const prefs = (envelope.result && envelope.result.preferences) || [];
  if (prefs.length === 0) {
    list.innerHTML = `<li class="loading">no preferences set for this holder</li>`;
    return;
  }
  for (const p of prefs) {
    const li = document.createElement("li");
    const flag = p.enabled ? "on" : "off";
    li.innerHTML = `<code></code> <span class="pill"></span>`;
    li.querySelector("code").textContent = `${p.kind}:${p.name}`;
    li.querySelector(".pill").textContent = flag;
    list.appendChild(li);
  }
}

async function onPrefSet(ev) {
  ev.preventDefault();
  const kind = $("pref-kind").value;
  const name = $("pref-name").value.trim();
  if (!name) return;
  const enabled = $("pref-enabled").checked ? "1" : "0";
  const { envelope } = await rpc("user.preference.set", { kind, name, enabled });
  if (!envelope.ok) {
    showBanner("bad", envelope.error || "set failed");
  }
  refreshPrefs();
}
async function onPrefClear() {
  const kind = $("pref-kind").value;
  const name = $("pref-name").value.trim();
  const args = name ? { kind, name } : { all: "1" };
  const { envelope } = await rpc("user.preference.clear", args);
  if (!envelope.ok) {
    showBanner("bad", envelope.error || "clear failed");
  }
  refreshPrefs();
}

// ---- render an ExecutionResult (Ask panel) -------------------------------

function renderExecution(env) {
  const result = env.result || {};
  $("result").hidden = false;

  const refusal = result.refusal_reason;
  const templated = result.templated_answer;

  if (!result.ok || (refusal && refusal.length > 0)) {
    $("answer-block").hidden = true;
    $("refusal-block").hidden = false;
    $("refusal-text").textContent = refusal || env.error || "unknown refusal";
  } else {
    $("refusal-block").hidden = true;
    $("answer-block").hidden = false;
    $("answer-text").textContent = templated || "(no answer text)";
  }

  const proposal = result.proposal || null;
  const atoms = proposal && Array.isArray(proposal.atoms) ? proposal.atoms : [];
  if (atoms.length > 0) {
    $("sources-block").hidden = false;
    const ul = $("sources-list");
    empty(ul);
    const byLabel = new Map();
    for (const a of atoms) {
      const li = document.createElement("li");
      li.className = "source";
      li.innerHTML = `<span class="kg"></span><span class="label"></span>
                      <span class="belief"></span>`;
      li.querySelector(".kg").textContent = a.kg || "?";
      li.querySelector(".label").textContent = a.label || "?";
      li.querySelector(".belief").textContent = `belief ${a.belief ?? "?"}/1000`;
      ul.appendChild(li);
      const bucket = byLabel.get(a.label) || [];
      bucket.push({ kg: a.kg, belief: a.belief });
      byLabel.set(a.label, bucket);
    }
    const disagreements = [];
    for (const [label, items] of byLabel.entries()) {
      const kgs = new Map();
      for (const it of items) if (!kgs.has(it.kg)) kgs.set(it.kg, it.belief);
      if (kgs.size < 2) continue;
      const beliefs = [...kgs.values()];
      const spread = Math.max(...beliefs) - Math.min(...beliefs);
      if (spread >= 300) {
        disagreements.push({ label, spread, entries: [...kgs.entries()] });
      }
    }
    if (disagreements.length > 0) {
      $("disagree-block").hidden = false;
      const dl = $("disagree-list");
      empty(dl);
      for (const d of disagreements) {
        const li = document.createElement("li");
        const parts = d.entries.map(([kg, b]) => `${kg} believes ${b}`);
        li.textContent =
          `'${d.label}' -- spread ${d.spread} milli -- ` + parts.join(" · ");
        dl.appendChild(li);
      }
    } else {
      $("disagree-block").hidden = true;
    }
  } else {
    $("sources-block").hidden = true;
    $("disagree-block").hidden = true;
  }

  const proj = proposal && proposal.projection ? proposal.projection : null;
  if (proj && (proj.valence_shift || proj.arousal_shift || proj.risk_score
               || proj.similar_count || proj.pref_matches)) {
    $("projection-block").hidden = false;
    const dl = $("projection-dl");
    empty(dl);
    const rows = [
      ["valence shift", (proj.valence_shift >= 0 ? "+" : "") + proj.valence_shift],
      ["arousal shift", proj.arousal_shift],
      ["risk score", `${proj.risk_score}/1000`],
      ["similar past decisions", proj.similar_count],
      ["matching preferences", proj.pref_matches],
    ];
    for (const [k, v] of rows) {
      const dt = document.createElement("dt");
      dt.textContent = k;
      const dd = document.createElement("dd");
      dd.textContent = v;
      dl.appendChild(dt);
      dl.appendChild(dd);
    }
  } else {
    $("projection-block").hidden = true;
  }

  const ecs = proposal && Array.isArray(proposal.effector_calls)
    ? proposal.effector_calls : [];
  if (ecs.length > 0) {
    $("effectors-block").hidden = false;
    const ul = $("effectors-list");
    empty(ul);
    for (const ec of ecs) {
      const li = document.createElement("li");
      const args = Array.isArray(ec.args) ? ec.args.join(", ") : "";
      li.innerHTML = `<code></code>`;
      li.querySelector("code").textContent = `${ec.name}(${args})`;
      ul.appendChild(li);
    }
  } else {
    $("effectors-block").hidden = true;
  }

  const q = result.query || null;
  if (q) {
    $("debug-block").hidden = false;
    const dl = $("debug-dl");
    empty(dl);
    const rows = [
      ["kind", q.kind],
      ["parser used", q.parser_used],
      ["raw text", q.raw_text],
      ["args", Array.isArray(q.args) ? q.args.join(" · ") : "-"],
    ];
    for (const [k, v] of rows) {
      const dt = document.createElement("dt");
      dt.textContent = k;
      const dd = document.createElement("dd");
      dd.textContent = v ?? "-";
      dl.appendChild(dt);
      dl.appendChild(dd);
    }
  } else {
    $("debug-block").hidden = true;
  }
}

function renderParseOnly(env) {
  $("result").hidden = false;
  $("answer-block").hidden = true;
  $("refusal-block").hidden = true;
  $("sources-block").hidden = true;
  $("disagree-block").hidden = true;
  $("projection-block").hidden = true;
  $("effectors-block").hidden = true;
  $("debug-block").hidden = false;
  const q = env.result || {};
  const dl = $("debug-dl");
  empty(dl);
  const rows = [
    ["kind", q.kind],
    ["parser used", q.parser_used],
    ["raw text", q.raw_text],
    ["args", Array.isArray(q.args) ? q.args.join(" · ") : "-"],
  ];
  for (const [k, v] of rows) {
    const dt = document.createElement("dt");
    dt.textContent = k;
    const dd = document.createElement("dd");
    dd.textContent = v ?? "-";
    dl.appendChild(dt);
    dl.appendChild(dd);
  }
}

// ---- Ask handlers --------------------------------------------------------

async function onAsk(ev) {
  ev.preventDefault();
  const text = $("q").value.trim();
  if (!text) return;
  const uid = $("uid").value.trim() || "owner";
  const askBtn = $("ask-btn");
  const parseBtn = $("parse-btn");
  askBtn.disabled = parseBtn.disabled = true;
  const originalAsk = askBtn.textContent;
  askBtn.textContent = "thinking…";
  try {
    const { envelope, raw } = await rpc("nl.ask", { text, user_id: uid });
    $("raw-pre").textContent = raw;
    if (envelope.ok) renderExecution(envelope);
    else {
      $("result").hidden = false;
      $("answer-block").hidden = true;
      $("refusal-block").hidden = false;
      $("refusal-text").textContent = envelope.error || "unknown error";
      $("sources-block").hidden = true;
      $("disagree-block").hidden = true;
      $("projection-block").hidden = true;
      $("effectors-block").hidden = true;
      $("debug-block").hidden = true;
    }
  } finally {
    askBtn.textContent = originalAsk;
    askBtn.disabled = parseBtn.disabled = false;
  }
}

async function onParseOnly() {
  const text = $("q").value.trim();
  if (!text) return;
  const btn = $("parse-btn");
  const ask = $("ask-btn");
  btn.disabled = ask.disabled = true;
  const original = btn.textContent;
  btn.textContent = "parsing…";
  try {
    const { envelope, raw } = await rpc("nl.parse_only", { text });
    $("raw-pre").textContent = raw;
    if (envelope.ok) renderParseOnly(envelope);
    else {
      $("result").hidden = false;
      $("answer-block").hidden = true;
      $("refusal-block").hidden = false;
      $("refusal-text").textContent = envelope.error || "unknown error";
    }
  } finally {
    btn.textContent = original;
    btn.disabled = ask.disabled = false;
  }
}

// ---- Tab / sidebar switching --------------------------------------------

let currentTab = "ask";

function switchTab(name) {
  currentTab = name;
  document.querySelectorAll(".tab").forEach((el) => {
    el.classList.toggle("active", el.dataset.tab === name);
  });
  document.querySelectorAll(".panel-view").forEach((el) => {
    el.classList.toggle("active", el.dataset.view === name);
  });
  // On narrow screens, collapse the sidebar after a pick.
  if (window.innerWidth <= 640) $("sidebar").classList.remove("open");
  loadTab(name);
}

function reloadActivePanel() {
  loadTab(currentTab);
}

function loadTab(name) {
  switch (name) {
    case "capsules":   refreshCapsules(true);   break;
    case "skills":     refreshSkills(true);     break;
    case "kgs":        refreshKGs(true);        break;
    case "patterns":   refreshPatterns(true);   break;
    case "gaps":       refreshGaps(true);       break;
    case "metrics":    refreshMetrics(true);    break;
    case "prefs":      refreshPrefs();          break;
    case "confidence": /* no-op; user drives */ break;
    case "ask":        /* form already live */  break;
  }
}

// ---- boot ----------------------------------------------------------------

document.addEventListener("DOMContentLoaded", () => {
  // Login modal
  $("login-form").addEventListener("submit", onLoginSubmit);
  $("login-anon").addEventListener("click", onLoginAnon);
  $("logout-btn").addEventListener("click", onLogout);

  // Ask form
  $("ask-form").addEventListener("submit", onAsk);
  $("parse-btn").addEventListener("click", onParseOnly);

  // Confidence + prefs
  $("confidence-form").addEventListener("submit", onConfidenceSubmit);
  $("pref-form").addEventListener("submit", onPrefSet);
  $("pref-clear").addEventListener("click", onPrefClear);

  // Tabs
  document.querySelectorAll(".tab").forEach((el) => {
    el.addEventListener("click", () => switchTab(el.dataset.tab));
  });

  // Mobile hamburger
  $("nav-toggle").addEventListener("click", () => {
    $("sidebar").classList.toggle("open");
  });

  // Load-more buttons
  attachLoadMore("capsules", refreshCapsules);
  attachLoadMore("skills",   refreshSkills);
  attachLoadMore("kgs",      refreshKGs);
  attachLoadMore("patterns", refreshPatterns);
  attachLoadMore("gaps",     refreshGaps);
  attachLoadMore("metrics",  refreshMetrics);

  // First-load: if no token, invite login; otherwise proceed.
  updateAuthChrome();
  if (!loadToken()) openLogin();
  pingDaemon();
});
