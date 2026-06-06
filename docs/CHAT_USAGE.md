# CrossEngin chat usage guide -- features, commands, and how chat works after R39

This is the document to read after `docs/GETTING_STARTED.md`. Getting Started
tells you how to install CrossEngin. This document tells you what to do with it
once it is installed.

CrossEngin is a non-LLM cognitive substrate. The chat is the most ergonomic
operator interface to that substrate -- you talk to a fabric of computational
units, not a chatbot. Many of the most interesting features are admin commands
(lines starting with `/`) rather than free-form conversation. This guide walks
through every feature, what changed in R39, and what is still planned.

> **Round-39 note.** R39 lands four code rounds in sequence: R39A (chat intent
> dispatcher with self-ID routing), R39B (HTTP transport for the internet-fetch
> path), R39C (chat-state save/load API), R39D (autonomous-learning idle-loop
> drain), and R39F (text preprocessing pipeline). Where a feature only works
> after a specific R39 piece lands, this guide says so explicitly. For the
> deeper architectural decisions see `docs/adr/r39-*.md` (three ADRs).

Contents:

1. [What the chat is, and what it isn't](#1-what-the-chat-is-and-what-it-isnt)
2. [Quick start](#2-quick-start)
3. [Web vs terminal modes](#3-web-vs-terminal-modes)
4. [Admin commands -- the full table](#4-admin-commands----the-full-table)
5. [What works out of the box](#5-what-works-out-of-the-box)
6. [Teaching the agent](#6-teaching-the-agent)
7. [Self-directed learning](#7-self-directed-learning)
8. [Self-identification (post-R39A)](#8-self-identification-post-r39a)
9. [Inspecting cognitive state](#9-inspecting-cognitive-state)
10. [Persistence](#10-persistence)
11. [Troubleshooting](#11-troubleshooting)
12. [Deeper dive -- pointers to the ADRs](#12-deeper-dive----pointers-to-the-adrs)

---

## 1. What the chat is, and what it isn't

CrossEngin is a **substrate**, not a chatbot. The chat surface is one
modality the substrate uses to communicate with you; the substrate also has
voice, vision, and (in v2) federation modalities. What you should expect from
the chat:

- **The "agent's brain" is an explicit knowledge graph (KG) of typed atoms.**
  When you type a word, the substrate looks up the matching atom, activates
  it, lets activation spread through related atoms, and decodes a response
  from the resulting concept activation. There is no neural network in the
  reply path. There is no LLM (ADR-0014).
- **Admin commands are the primary inspection interface.** `/status`,
  `/why`, `/history`, `/reflect`, `/meta` -- these expose the substrate's
  internal state in a way no LLM-backed chatbot can. If you find yourself
  asking "what is it thinking?" the answer is in `/status` and `/why`,
  not in the reply itself.
- **The agent will sometimes say "okay" and not much else.** Pre-R39 the
  default response to most words was a terse acknowledgement; the KG was
  small (~13 seeded atoms) and the language renderer was conservative.
  Post-R39 it can additionally answer self-identification questions and
  trigger autonomous research on unknown words.
- **The agent is honest about what it does not know.** Confidence is
  Bayesian (alpha/beta counts per ADR-0023). An answer with low confidence
  is hedged in the language ("I think...", "I've only seen this twice").

What the chat is NOT:

- It is not an LLM wrapper. You can verify this by running `/why` after any
  reply -- the trace shows substrate node IDs, never a prompt.
- It is not a search engine. It can fetch a fixed whitelist of reference
  pages (ADR-0028) but does not crawl the web.
- It is not stateful across processes by default in terminal mode. Each
  `scripts/chat.sh` invocation boots a fresh agent. Use the web mode
  (`scripts/web.py`) for per-cookie persistence across requests, and
  `/save` + `/load` for explicit snapshots. Full per-session persistence
  across `/quit` is planned R40 (see section 10).

---

## 2. Quick start

You need a built `bin/crossengin-chat`. From a freshly cloned repo:

```sh
make install
```

This compiles every module and installs the runnable binaries into `./bin/`.

### Terminal mode

```sh
bash scripts/chat.sh
```

You get a prompt. Type something; the agent replies. Quit with `/quit`,
`/exit`, or `q`.

### Web mode

```sh
python3 scripts/web.py
```

Then open <http://localhost:8765/> in a browser. Each browser tab gets its own
session cookie; the cookie is bound to a long-lived chat child process so
state carries across requests in that tab. The full admin command set works
in the web UI exactly as it does in the terminal (the web UI is just a
different stdin/stdout).

Knobs (env vars) the web mode respects:

| Variable                | Default     | Effect                                          |
|-------------------------|-------------|-------------------------------------------------|
| `CE_PORT`               | `8765`      | Listen port.                                    |
| `CE_BIN`                | `./bin/crossengin-chat` | Binary to spawn per cookie.         |
| `CE_BIND`               | `127.0.0.1` | Bind address. `0.0.0.0` exposes admin to LAN -- not recommended. |
| `CE_WEB_MAX_SESSIONS`   | `8`         | LRU cap on concurrent cookie children.          |
| `CE_METRICS_CACHE_S`    | `10`        | Prometheus /metrics cache TTL.                  |
| `CE_ATOMS_CACHE_S`      | `30`        | Atom-search /api/atoms cache TTL.               |

Diagnostic endpoints:

- `GET /metrics` -- Prometheus text format, scrape-friendly.
- `GET /api/sessions` -- JSON list of live cookies + last-active timestamps.
- `GET /atoms` -- HTML atom-search UI; pairs with `GET /api/atoms?q=&kg=`.
- `GET /api/banner` -- the chat's boot banner.

---

## 3. Web vs terminal modes -- persistence comparison

| Property                           | Terminal (`chat.sh`) | Web (`web.py`)                       |
|------------------------------------|----------------------|--------------------------------------|
| State persists across messages     | **No** (fresh boot per message in current shell) | **Yes** (one child per cookie) |
| State persists across browser tabs / sessions in the same machine | n/a | Per-cookie -- each tab is its own child |
| State persists across `/quit`      | No (planned R40)     | No (planned R40)                     |
| Multiple users at once             | One per terminal     | Up to `CE_WEB_MAX_SESSIONS` cookies  |
| Admin commands                     | Full set             | Full set                             |
| `/save` / `/load` works            | Yes                  | Yes                                  |
| Prometheus metrics                 | No                   | Yes (`/metrics`)                     |
| Atom search UI                     | No                   | Yes (`/atoms`)                       |

**Concrete recommendation:** for exploring features start with the web mode.
The per-cookie persistence makes the feedback loop tight. Switch to terminal
mode for scripted operator workflows.

---

## 4. Admin commands -- the full table

Every command starts with `/`. Most have short forms. Type `/help` in any chat
session for the live listing -- the table below is the post-R39 canonical set.

### Inspection

| Command                | Effect                                                       |
|------------------------|--------------------------------------------------------------|
| `/help`                | Print the live admin help.                                    |
| `/status`              | Soul name + purpose, mood (valence/arousal), KG atom counts, scheduler tick rate, decision-log size, active goal (if any), halted flag. |
| `/history [N]`         | Last N decision-log entries (default 5).                      |
| `/why`                 | Explain the most recent decision -- shows the action type, perm tier, outcome, and the substrate node IDs in the trace. |
| `/why-deep [N]`        | Recursive decision tree N levels deep (default 3, cap 8): the operator chain that fired plus the activating message plus the upstream evidence atoms. |
| `/reflect [DEPTH]`     | Forward-simulate from current conclusions; record tentative inferences into the reflection KG (`refl_kg`). No action -- this is a sandbox. |
| `/meta`                | Per-source promotion / atrophy rates.                         |
| `/find QUERY`          | Top-5 atoms by TF-IDF cosine similarity to QUERY (R10C).      |
| `/communities`         | Label-propagation community detection over KG cross-refs.     |
| `/louvain`             | Louvain modularity-optimising community detection.            |
| `/pagerank`            | Top-5 atoms by PageRank centrality.                           |
| `/predict ID [K] [M]`  | Link prediction; M in {cn, jaccard, aa}; top-K candidate edges from atom ID. |
| `/explain ATOM_ID`     | Recursive provenance walk for ATOM_ID via the R20B rule engine; prints an indented proof tree. |
| `/prove P C [DEPTH]`   | Operator-chain proof from atom labelled P to atom labelled C (bounded BFS). |
| `/recall member|window|top|recent` | Episodic-memory lookups (cluster member, time window, top-believed, most-recent). |

### Teaching and learning

| Command                              | Effect                                                       |
|--------------------------------------|--------------------------------------------------------------|
| `/teach <word>`                      | Ingest a single word as a new vocabulary atom + concept binding. |
| `/teach <subj> <rel> <obj>`          | Ingest a 3-atom relational triple (preferred form for facts). |
| `/learn <topic|url|file|@batch|rss:URL|dir:PATH>` | Ingest from a cached external corpus produced by `scripts/learn.sh <ARG>` (six source kinds). |
| `/pin <word> <conf-milli>`           | Pin word W's belief to confidence C in 0..1000 milli.        |
| `/seed [PACK]`                       | List domain seed packs (no arg) or install PACK.             |

### Safety / state mutation

| Command                              | Effect                                                       |
|--------------------------------------|--------------------------------------------------------------|
| `/halt`                              | Stop the effector (input still flows in). Honours ADR-0044's hard-stop bit. |
| `/resume`                            | Un-halt.                                                     |
| `/save [PATH]`                       | Write a substrate snapshot. Default path: `$CE_SNAP_PATH` or `/tmp/crossengin.snap`. |
| `/load [PATH]`                       | Read a snapshot from disk; rehydrate live soul + KGs (atoms merge by label). |
| `/compact [--dry-run]`               | Compact the in-memory snapshot: drop dead atoms, archived episodes, sub-threshold synapses. Next `/save` writes the compacted form. |
| `/snap_verify [PATH]`                | Recompute Merkle root and compare to the file's claim (R15E tamper detection). |
| `/snap_sign_status [PATH]`           | Ed25519 attestation status (R16A).                           |
| `/meta-feedback`                     | Dry-run: which source-authority tier changes WOULD apply.    |
| `/meta-apply`                        | Commit those tier changes.                                   |
| `/switch [ID]`                       | List sessions (no arg) or activate/create ID.                |

### Voice / vision / video / advanced

These are scoped to specific feature rounds; they are listed in `/help` and
detailed in their per-round audit docs (`AUDIO_AUDIT.md`, `IMAGE_AUDIT.md`,
`VIDEO_AUDIT.md`, `STT_AUDIT.md`):

`/speak`, `/say`, `/converse`, `/listen`, `/pitch`, `/pitch_shift`, `/clone`,
`/reverb`, `/gate`, `/denoise`, `/spec`, `/mfcc`, `/melody`, `/wake_train` /
`/wake`, `/spk_enroll` / `/spk_recognize`, `/see`, `/play`, `/match_images`,
`/orb_match`, `/pano`, `/hog`, `/detect`, `/faces`, `/track`, `/smooth`,
`/lbp`, `/ocr`, `/face_enroll` / `/face_recognize`, `/depth`, `/flow`,
`/segment`, `/slic`, `/lipsync`.

### Federation / DP

`/dp_status`, `/dp_query`, `/dp <subcommand>` (status / log / warn / reset),
`/fed_join`, `/fed_stats`, `/fed_leave`, `/leader`, `/attest_log`, `/nat`,
`/snap_replicas`, `/relay`, `/relay_secure`, `/webrtc`. See
`FEDERATED_AUDIT.md` and `DP_AUDIT.md` for the per-round detail.

### Diagnostics

| Command            | Effect                                                       |
|--------------------|--------------------------------------------------------------|
| `/__metrics__`     | Internal: machine-readable `key=value` block for `web.py`'s `/metrics` scraper. You can call it interactively for raw counters. |
| `/__atoms__`       | Internal: machine-readable `ATOM ...` block for `web.py`'s `/api/atoms` search. |
| `/ann_query LABEL` | Debug: top-5 nearest atoms by LSH-bucketed cosine.            |

### Exit

| Command              | Effect                                          |
|----------------------|--------------------------------------------------|
| `/quit` / `/exit`    | Exit the chat. In R40 this will also trigger chat-state save. |

---

## 5. What works out of the box

Right after `make install`, with no teaching, the agent has:

- **A seeded vocabulary of ~13 atoms.** The seed pack includes: `self`,
  `user`, `hello`, `help`, `ok`, `yes`, `fever`, `infection`, `treat`, plus
  the language scaffolding atoms (the binding between word labels and concept
  IDs). You can confirm this with `/status` -- "knowledge: 13 atoms in
  shared KG".
- **A configured soul.** `/status` shows `soul: <name> (purpose: <purpose>)`.
  The default name and purpose live in `src/seed/first_atoms.nova` and the
  soul wrapper (ADR-0034).
- **A live constitution.** The default rule blocks any message containing
  the literal token `"exfiltrate"`; that token is part of the v1 safety
  smoke test for ADR-0045.
- **Greetings work.** `hello` activates the seeded greeting atom and the
  reply is a greeting. `help` activates the help atom.
- **`/status` and `/why` work.** Even on a brand-new boot these print
  meaningful output (zeros and seed counts, respectively).

If you type a word that isn't in the seed pack the response is typically
"okay" or similar terse acknowledgement. Pre-R39 that was the end of the
story. Post-R39, an unknown word **also** queues an autonomous learning
episode (section 7) and self-targeted questions are answered from the soul
(section 8).

---

## 6. Teaching the agent

The single most important interactive action is `/teach`. Two forms:

```text
/teach <word>
```

Ingests `<word>` as a new vocabulary atom plus a concept binding. The atom
gets `provenance=user-taught` (Tier A per ADR-0029); a fetched claim later
will never silently overwrite it. Example:

```text
> /status
knowledge: 13 atoms in shared KG, 0 in reflection KG
> /teach widget
(ingested 'widget' -- 14 atoms now)
> widget
agent> (responds with the widget concept activated; default reply renders depending on context)
```

For facts, the preferred form is a 3-atom triple:

```text
/teach <subject> <relation> <object>
```

Example:

```text
> /teach aspirin treats fever
(ingested 'aspirin' -- 15 atoms now; 'treats' relation; 'fever' atom updated)
> aspirin
agent> (responds with the aspirin atom activated and the treats-fever edge near-firing)
> /why
most recent: #N MENTION  tier: auto/notify  outcome: ok  trace: M node(s)
```

Triples are how the KG accumulates structure. The `/teach <word>` form is
fine for bare vocabulary; for anything you want the system to be able to
reason over, teach the relation explicitly.

---

## 7. Self-directed learning

Two ways the agent acquires knowledge from outside this conversation:

### A. Explicit -- `scripts/learn.sh` + `/learn`

This was the pre-R39 path and it still works post-R39. Six source kinds:

```sh
# Topic (wikipedia by default):
scripts/learn.sh fever

# Direct URL:
scripts/learn.sh https://en.wikipedia.org/wiki/Aspirin

# Local file:
scripts/learn.sh /tmp/my_notes.txt

# Batch (one URL per line):
scripts/learn.sh @/tmp/urls.txt

# RSS feed (first 5 article links):
scripts/learn.sh rss:https://feeds.example.com/atom.xml

# Directory of .txt + .md files:
scripts/learn.sh dir:/tmp/corpus/
```

Each call writes `/tmp/crossengin_learn_<tag>.txt` plus a
`...<tag>_triples.txt`. Then in the chat:

```text
> /learn fever
(learned about 'fever' [topic]: 30 word(s), 7 operator(s) ingested, KG=600)
> /learn /tmp/my_notes.txt
(learned about '/tmp/my_notes.txt' [file]: 4 word(s), 1 operator(s) ingested, KG=604)
```

Why this path still matters post-R39: it does its own HTTPS via system curl,
so it works for any URL today. The autonomous path (next) is HTTP-only in
R39B until R39B.2 lifts HTTPS.

### B. Autonomous -- post-R39A + R39B + R39D

When a user utterance contains a word the agent does not know, the
R39A intent dispatcher queues an `SLT_UNKNOWN_QUERY` learning episode
(per ADR-0026). The R39D idle-loop drain dequeues episodes when the
chat is otherwise quiet; for each one R39B fetches the configured URL
for the topic via HTTP; R39F preprocesses (strip HTML, lowercase,
stopword-filter, slide a 5-word window for triples); the result is
ingested as new atoms with `provenance=fetched` and the appropriate
source-authority tier (ADR-0029).

**What this looks like:**

```text
> tell me about quasars
agent> okay
                              # at this point an SLT_UNKNOWN_QUERY for "quasars" is queued
> /history
  #N FETCH_PERMIT       tier: auto/notify      outcome: ok
  #N+1 FETCH_TRANSPORT   tier: auto/notify      outcome: ok
  #N+2 INGEST            tier: auto/notify      outcome: ok
> quasars                    # 5-10 seconds later, on a fresh message
agent> (responds with the now-populated quasars concept atom activated)
```

**What you should see in `/why`:**

The decision log walks the autonomous-fetch chain: the trigger, the
whitelist permit check, the transport call, and the ingest. If any step
failed -- the host was off-whitelist, the rate limit had been hit, the
body was too large, the URL was HTTPS (deferred per R39B), the parse
failed -- the corresponding `act_*` entry shows `outcome:` with the
failure tag.

**Honest caveats on the autonomous path:**

- HTTPS is deferred to R39B.2. An autonomous episode that resolves to a
  `https://` URL is logged with outcome `deferred` and tells you to use
  `scripts/learn.sh <url>` instead. For Wikipedia content today the
  manual path is the only path that works.
- The whitelist seed ships small (~15-30 domains). Topics outside the
  whitelist are not researched autonomously; the episode is denied with
  `FETCH_DENIED_HOST`.
- Rate limit is genuinely tight: 30 fetches per hour, 2s spacing per
  domain, 1 in-flight at a time. A long unknown-word-rich utterance can
  produce a queue that takes minutes to drain.
- Multi-language preprocessing is English-only in R39F. Non-English
  content will produce noisier atoms until R39F.2.

For the full architecture see `docs/adr/r39-autonomous-learning-architecture.md`.

---

## 8. Self-identification (post-R39A)

R39A wires the chat dispatcher to the existing self-model query API
(ADR-0038). The agent can now answer questions about itself from the
live soul block (ADR-0034). Examples that work after R39A:

```text
> who are you?
agent> I am <soul_name>. My purpose is <soul_purpose>.

> what are you?
agent> (same as "who are you"; renders identity)

> what do you know?
agent> (renders a competence summary -- top-N atoms by belief, capability tags)

> what can you do?
agent> (same as "what do you know"; renders capabilities)

> what are your goals?
agent> (renders the active goal tree from core/goal.nova)

> what are you working on?
agent> (same; renders goals)

> how are you?
agent> (renders mood state -- valence/arousal, qualitative when ADR-0035 is mature)

> how do you feel?
agent> (same as "how are you")

> what are you doing right now?
agent> (renders live loop state from agent/agent.nova)
```

The dispatcher uses an anchored regex map (see
`docs/adr/r39-self-identification-wiring.md` for the full map). The patterns
are intentionally literal so that "did you eat lunch?" does NOT match
self-ID just because it contains "you". Phrasings outside the literal
patterns -- "could you tell me who you are?", "are you Claude?" -- fall
through to the standard KG-match path.

**Honest gaps:**

- Niche phrasings are missed by the regex map. Future rounds may add a
  learned intent classifier.
- The mood narrative is terse pending richer ADR-0035 emotion-rendering.
- There is no theory-of-mind tailoring (ADR-0039) -- the same answer for
  every user.

---

## 9. Inspecting cognitive state

This is where the substrate is unlike an LLM. Every reply has a complete,
auditable trace.

### `/status`

```text
> /status
soul     : Athena (purpose: companion)
mood     : valence=500 arousal=400
knowledge: 412 atoms in shared KG, 7 in reflection KG
audit    : 22 decision-log entries
moments  : 4 moment(s), 0 archived
synapses : 1284 live edge(s) (reasoning part)
selfmodel: 6 competence record(s)
scheduler: tick=215 rate=10Hz
dp_status: budget OK
goal     : #1 hold-context-with-user
```

Read this top to bottom. Each line maps to a substrate module: soul ->
`core/soul.nova`, mood -> ADR-0035 valence/arousal, knowledge -> ADR-0016
atoms + ADR-0023 beliefs, audit -> ADR-0043, moments -> ADR-0022 episodic,
synapses -> ADR-0007, selfmodel -> ADR-0020, scheduler -> ADR-0037,
dp_status -> ADR-0050 differential privacy.

### `/why`

```text
> /why
most recent: #22 MENTION  tier: auto/notify  outcome: ok
  tier    : auto/notify
  outcome : ok
  trace   : 14 node(s)
```

The trace is the count of substrate nodes that fired during this
decision -- node IDs are in the full log (use `/why-deep`). Tier is the
ADR-0041 permission tier; outcome is whether the action completed.

### `/why-deep [N]`

```text
> /why-deep 4
#22 MENTION  tier: auto/notify  outcome: ok
  upstream activating message: "aspirin"
  upstream evidence atoms: aspirin(412) treats(403) fever(7)
  operator chain: lookup(aspirin) -> route(treats) -> render(fever)
  one level up: #21 PERCEIVE  tier: notify  outcome: ok
    ... (recurses N levels)
```

This is the trust-calibration surface. If a reply looks wrong, `/why-deep`
shows the exact substrate path -- which atoms activated, in what order,
through which operators.

### `/reflect [DEPTH]`

Sandbox-mode forward simulation. Runs a reflection cycle from current
conclusions; new tentative inferences land in the reflection KG (`refl_kg`
in `/status`) rather than the live KG. No action is taken. Useful for "what
would the agent conclude if I gave it five more steps to think?".

### `/history [N]`

```text
> /history 10
  #13 PERCEIVE   tier: notify       outcome: ok
  #14 MENTION    tier: auto/notify  outcome: ok
  #15 FETCH_PERMIT tier: auto/notify outcome: rate-limited
  #16 PERCEIVE   tier: notify       outcome: ok
  ...
```

Decision log entries since boot (post-R40 this will be persistent).

### `/meta`

```text
> /meta
SOURCE                 PROMOTION   ATROPHY
user_taught            0.92        0.04
fetched_wikipedia      0.71        0.12
fetched_arxiv          0.55        0.18
```

Per-source promotion and atrophy rates from the meta-observer (ADR-0050).
Paired with `/meta-feedback` (dry-run of proposed tier changes) and
`/meta-apply` (commit them).

---

## 10. Persistence

This is the area with the most planned R40 work. Today (post-R39C, pre-R40):

### What persists today

- **Substrate snapshots via `/save` and `/load`.** This is the ADR-0048
  binary tagged format. `/save [PATH]` writes the snapshot; `/load [PATH]`
  reads it back, rehydrating soul (first), KGs (second), episodic (third).
  Default path is `$CE_SNAP_PATH` or `/tmp/crossengin.snap`. Snapshots
  carry a Merkle root for tamper detection (`/snap_verify`) and an
  Ed25519 attestation (`/snap_sign_status`).
- **Per-cookie state in `scripts/web.py` for the lifetime of the cookie.**
  Each browser tab gets a long-lived chat child; state stays alive while
  that child stays alive. Close the tab and clear cookies -> the next
  request to that URL spawns a fresh child.
- **The decision log within a session.** `/history` and `/why` see
  everything since boot.

### What does NOT persist today (planned R40)

- **Automatic save on `/quit`.** Today `/quit` exits without saving.
  R40 wires `chat_state_save` (from R39C) into the `/quit` handler so
  the in-process state lands in `$HOME/.crossengin/chat_state.dat`.
- **Automatic load on boot.** Today a fresh chat starts empty unless you
  explicitly `/load`. R40 boots from
  `$HOME/.crossengin/chat_state.dat` if present.
- **Idle-tick checkpoint.** R40 will save in the background every N
  seconds when the chat has changed.
- **Per-cookie state files in `scripts/web.py`.** Currently the cookie
  state is in the child process only -- if the child gets evicted by the
  LRU cap it's gone. R40 will bind each cookie to its own state file.

R39C ships the API (`chat_state_save` / `chat_state_load`) and the format
(text v1 line records at `$HOME/.crossengin/chat_state.dat`). It is not
yet wired to chat-lifecycle events. See
`docs/adr/r39-persistence-and-rehydration.md` for the format details and
the R40 plan.

### Honest gaps in R39C

- No atomic write yet -- a hard kill mid-save leaves a torn file the
  loader refuses to read. The substrate snapshot's atomic-rename pattern
  will land for chat state in R40.
- No compaction before save -- a long session's file is whole. The
  substrate has `snap_compact`; chat state does not, in R39C.
- No multi-process safety -- two chat instances sharing the same
  `$HOME` will race. Run one chat per home directory until R40.

---

## 11. Troubleshooting

### "The agent always says okay"

This is the classic pre-R39 frustration. The agent only had a seeded
~13-atom vocabulary and the language renderer was conservative. Post-R39:

1. **Self-identification questions are answered.** Try `who are you?`
   (post-R39A).
2. **Unknown words trigger autonomous learning.** Try `tell me about
   <topic>`, wait 5-10 seconds, then send a follow-up message about
   the same topic -- the second turn should reflect the freshly-fetched
   atoms (post-R39A + R39B + R39D, for HTTP topics).
3. **Teach the agent.** `/teach aspirin treats fever` and similar
   triples build the KG up fast. `/teach` is the highest-yield action
   in the chat by a wide margin.
4. **Use `/learn` for bulk vocabulary.** `scripts/learn.sh fever` then
   `/learn fever` ingests ~30 words + ~7 triples per call.

### Rate-limit warnings

If you see `outcome: rate-limited` in `/history` the substrate is
honouring ADR-0028's 30/hr global cap, 2s/domain spacing, and 1 in-flight
cap. The episode is requeued, not dropped -- it will run when the limiter
opens. You can also see this with `/meta` and the live `/__metrics__`
counters.

### Fetch failures

`/history` shows them as `FETCH_*` entries with non-`ok` outcome. The
named failure modes:

- `outcome: denied-host` -- URL is not on the whitelist.
- `outcome: rate-limited` -- one of the three rate gates fired.
- `outcome: invalid` -- response failed validation (content-type, size,
  or structural check).
- `outcome: deferred` -- URL was HTTPS; R39B is HTTP-only. Use
  `scripts/learn.sh <url>` instead.
- `outcome: error <HTTP_ERR_*>` -- the HTTP client surfaced a low-level
  error (DNS, connect, recv, etc.).

Every entry has the URL and the byte count in the decision log; `/why`
walks one entry in detail.

### Constitution blocked my message

The seeded constitution refuses any message containing literal
`"exfiltrate"`. This is the v1 smoke test for ADR-0045. The reply is
typically silent (the effector drops) and `/history` shows
`outcome: constitution-block`.

### `/quit` doesn't save

Correct -- this is the R39C / R40 gap. Today you must explicitly `/save`
before quitting if you want state to survive.

### Web mode: my session disappeared

Cookies are bound to your browser tab. Clearing cookies -> a new session.
The LRU cap (`CE_WEB_MAX_SESSIONS=8` by default) also evicts the
least-recently-used child; if you have 9 tabs the oldest gets evicted.
Raise the cap or use `/save` + `/load` between sessions until R40's
per-cookie state files land.

### `make install` fails

See `docs/GETTING_STARTED.md` Section 6 -- the doctor script
(`scripts/crossengin-doctor.sh`) walks the environment and prints
specific remedies. The most common cause is a missing or wrong
`NOVA_ROOT`.

---

## 12. Deeper dive -- pointers to the ADRs

If you want the architectural reasoning behind any of this:

- **R39 wiring (this round).**
  - `docs/adr/r39-autonomous-learning-architecture.md` -- trigger ->
    research -> preprocess -> ingest end-to-end. Performance, failure
    modes, security posture, honest gaps.
  - `docs/adr/r39-self-identification-wiring.md` -- the chat-side
    intent dispatcher and the regex pattern map.
  - `docs/adr/r39-persistence-and-rehydration.md` -- R39C save/load
    API and the R40 plan.
- **Foundational substrate ADRs (cited above).**
  - ADR-0001 -- substrate architecture (start here for the macro shape).
  - ADR-0014 -- no LLM in cognition.
  - ADR-0016 / ADR-0023 -- atoms + Bayesian beliefs.
  - ADR-0026 -- self-learning triggers.
  - ADR-0028 -- internet fetching gates.
  - ADR-0029 -- source authority weighting and conflict resolution.
  - ADR-0034 -- soul wrapper with timescales.
  - ADR-0038 -- self-model query API.
  - ADR-0041 -- permission tiers.
  - ADR-0042 -- reversibility classifier.
  - ADR-0043 -- decision log.
  - ADR-0045 -- constitutional rules.
  - ADR-0046 -- desktop deployment v1.
  - ADR-0048 -- persistence (snapshot + rehydration order).
  - ADR-0049 -- testing and capability benchmarks.
  - ADR-0050 -- build sequence + milestones.
- **R36F-prefixed series** -- rounds-up rationale for the macro
  decisions (language choice, federation stack, substrate vs pipeline,
  self-hosting invariant, canonical crypto primitives).

---

If you find a command in `/help` that is not in this guide, that is a
documentation gap -- please open an issue. If you find a behaviour that
contradicts this guide, that is a regression or a sibling-round drift --
also please open an issue.
