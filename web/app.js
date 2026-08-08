// CrossEngin web UI (R51). Vanilla JS, no framework.
//
// Talks to the shim (scripts/rpc_web_shim.py) via POST /rpc/<verb>.
// The shim forwards to the TCP daemon (crossengin-rpc-daemon) and
// returns its {ok, result, error} envelope verbatim.

"use strict";

const $ = (id) => document.getElementById(id);
const empty = (el) => { while (el.firstChild) el.removeChild(el.firstChild); };

async function rpc(verb, args = {}) {
  const resp = await fetch(`/rpc/${encodeURIComponent(verb)}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  // The shim returns the daemon's line as-is with content-type
  // application/json. If it errored on its own, still valid JSON.
  const text = await resp.text();
  try {
    return { httpStatus: resp.status, envelope: JSON.parse(text), raw: text };
  } catch (e) {
    return {
      httpStatus: resp.status,
      envelope: { ok: false, result: null, error: `bad shim response: ${e}` },
      raw: text,
    };
  }
}

// ---- daemon health ping --------------------------------------------------

async function pingDaemon() {
  const dot = document.querySelector("#daemon-status .dot");
  const txt = document.querySelector("#daemon-status .daemon-text");
  try {
    const { envelope } = await rpc("kg.list");
    if (envelope.ok) {
      dot.className = "dot dot-ok";
      txt.textContent = "daemon up";
    } else {
      dot.className = "dot dot-bad";
      txt.textContent = `daemon: ${envelope.error || "?"}`;
    }
  } catch (e) {
    dot.className = "dot dot-bad";
    txt.textContent = `shim unreachable`;
  }
}

// ---- side panels ---------------------------------------------------------

async function refreshSkills() {
  const list = $("skills-list");
  empty(list);
  try {
    const { envelope } = await rpc("skill.list");
    if (!envelope.ok || !Array.isArray(envelope.result)) {
      list.innerHTML = `<li class="loading">no skills</li>`;
      return;
    }
    if (envelope.result.length === 0) {
      list.innerHTML = `<li class="loading">none registered</li>`;
      return;
    }
    for (const sk of envelope.result) {
      const li = document.createElement("li");
      const mark = sk.installed ? "" : " (uninstalled)";
      li.textContent = `${sk.name || "?"}${mark}`;
      if (sk.description) {
        li.title = sk.description;
      }
      list.appendChild(li);
    }
  } catch (e) {
    list.innerHTML = `<li class="loading">error: ${e}</li>`;
  }
}

async function refreshKGs() {
  const list = $("kgs-list");
  empty(list);
  try {
    const { envelope } = await rpc("kg.list");
    if (!envelope.ok || !Array.isArray(envelope.result)) {
      list.innerHTML = `<li class="loading">no KGs</li>`;
      return;
    }
    if (envelope.result.length === 0) {
      list.innerHTML = `<li class="loading">none</li>`;
      return;
    }
    for (const kg of envelope.result) {
      const li = document.createElement("li");
      li.textContent = kg;
      list.appendChild(li);
    }
  } catch (e) {
    list.innerHTML = `<li class="loading">error: ${e}</li>`;
  }
}

// ---- render an ExecutionResult ------------------------------------------

function renderExecution(env) {
  const result = env.result || {};

  $("result").hidden = false;

  // ---- NL-layer refusal or admin action ---------------------------------
  const refusal = result.refusal_reason;
  const adminAction = result.admin_action;
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

  // ---- Sources + disagreements ------------------------------------------
  const proposal = result.proposal || null;
  const atoms = proposal && Array.isArray(proposal.atoms) ? proposal.atoms : [];
  if (atoms.length > 0) {
    $("sources-block").hidden = false;
    const ul = $("sources-list");
    empty(ul);
    // Also build a "same label, multiple KGs, big spread" map for the
    // disagreement panel. Deliberately client-side and cheap: the
    // templater already computed authoritative disagreements; here we
    // just surface them prominently for the reader.
    const byLabel = new Map(); // label -> [{kg, belief}]
    for (const a of atoms) {
      const li = document.createElement("li");
      li.className = "source";
      li.innerHTML = `
        <span class="kg"></span><span class="label"></span>
        <span class="belief"></span>`;
      li.querySelector(".kg").textContent = a.kg || "?";
      li.querySelector(".label").textContent = a.label || "?";
      li.querySelector(".belief").textContent =
        `belief ${a.belief ?? "?"}/1000`;
      ul.appendChild(li);
      const bucket = byLabel.get(a.label) || [];
      bucket.push({ kg: a.kg, belief: a.belief });
      byLabel.set(a.label, bucket);
    }
    // Disagreement: same label, >= 2 distinct KGs, belief spread >= 300.
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
          `'${d.label}' — spread ${d.spread} milli — ` + parts.join(" · ");
        dl.appendChild(li);
      }
    } else {
      $("disagree-block").hidden = true;
    }
  } else {
    $("sources-block").hidden = true;
    $("disagree-block").hidden = true;
  }

  // ---- Persona projection ------------------------------------------------
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

  // ---- Effector calls (described, not executed) --------------------------
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

  // ---- Parse debug -------------------------------------------------------
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

// ---- render a StructuredQuery only (parse debug button) -----------------

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

// ---- submit + button handlers -------------------------------------------

function withBusy(btn, fn) {
  return async (...args) => {
    const original = btn.textContent;
    btn.disabled = true;
    try {
      return await fn(...args);
    } finally {
      btn.textContent = original;
      btn.disabled = false;
    }
  };
}

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

// ---- boot ----------------------------------------------------------------

document.addEventListener("DOMContentLoaded", () => {
  $("ask-form").addEventListener("submit", onAsk);
  $("parse-btn").addEventListener("click", onParseOnly);
  pingDaemon();
  refreshSkills();
  refreshKGs();
});
