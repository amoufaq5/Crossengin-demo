# ADR-0209: Deployment Form Factors (Five Modes)

## Status

Proposed. Enumerates the five consumption modes named by ADR-0200 as
first-class deliverables and describes the form factor, protocol,
authentication, update path, current status, and next work for each.
This ADR is the operator-facing map of "what can I actually deploy
today, and what is coming next."

**Round status:** R107 shipped uniform cursor pagination across 10
list verbs (`kg.list`, `capsule.list`, `skill.list`, `pattern.list`,
`ownership.list`, `session.list`, `capability.list`,
`ingest.policy.list`, `nl.metrics`, `self.gaps`) — mobile-friendly
wire pre-work for Mode 4 (client-app) scaling and Phase I part 2
(R108: web SPA polish that consumes the new `next_after` field).
See `docs/SHIP_AS_APP.md` §7.56.

## Date

2026-08-22

## Context

ADR-0200 introduces the frame that CrossEngin is a factory with five
consumption modes. Individual ADRs cover the shape of each mode
(ADR-0203 bake, ADR-0204 slim runtime, ADR-0205 per-user selective
load, ADR-0104 NL surface for user-facing modes, ADR-0201 sidecar
LLM). What is not documented in one place is the deployment map: a
customer asks "what am I actually installing where," and the answer
today is scattered across ten ADRs.

This ADR is the map.

## Decision

### Mode 1: Mother-daemon-direct (server)

**Form factor:** the mother daemon runs on an enterprise server;
multiple users authenticate over the wire and interact through the
same process.

**Protocol:** JSON-RPC over TLS (per R86..R94). Wire verbs from
ADR-0104 (`nl.ask`, `nl.parse_only`, `kg.list`, `capsule.*`,
`skill.*`, `persona.*`, `ingest.*`) plus admin verbs.

**Auth model:** capability tokens (ADR-0105) per caller, backed by
the ownership overlay (R55.x). Each caller has a holder id; every
verb consults the caller's grants.

**Update path:** the operator ingests new records into the mother;
they become live after review-queue approval. No versioning event;
the daemon is always at head.

**Current status:** shipped. R94 landed the TLS wire; R55.x landed
overlay + tokens; R47..R48 landed skills + NL. The `chat REPL`
example (`examples/crossengin_chat.nova`) and the minimal SPA in
`examples/spa/` both drive this mode.

**Next work:** admin-bulk operations on capsules and skills;
per-session hooks on the wire; ownership-audit-log surfacing;
hardware-key admin bootstrap.

### Mode 2: Per-user selective load

**Form factor:** the SAME mother daemon as mode 1, but each user
project onto a subset of capsules / skills / patterns / personas via
their preference overlay.

**Protocol:** same JSON-RPC over TLS. Adds the `user.preference.*`
verb family (ADR-0205).

**Auth model:** same capability tokens plus the ownership overlay,
distinguishing `operator_hard` from `user_soft` sources.

**Update path:** the mother's ingest lifecycle plus a user's own
preference calls. Preferences are effective immediately; no restart.

**Current status:** overlay primitive shipped (R55.x); the
`user.preference` verb family is Phase B work. Client-side
preference UX is a mode-4 concern.

**Next work:** verb family and its serialization; a
preference-management panel in the SPA client.

### Mode 3: Baked-child (appliance)

**Form factor:** a signed child bundle (ADR-0203) deployed to a
customer host, running on the same NOVA binary launched with
`--child-mode` (ADR-0204). Immutable KG; no ingest; no bake;
posture verifiable at boot.

**Protocol:** JSON-RPC over TLS. The child's allowlist limits which
verbs the child responds to. `daemon.status` reports the current
posture.

**Auth model:** capability tokens with the child's allowed grants;
overlay carries only the allowlisted holders. Same wire discipline
as mode 1 but narrower.

**Update path:** the mother produces signed KG-deltas (ADR-0203);
the child pulls, verifies, applies. Failure to verify refuses and
alerts the operator.

**Current status:** design lock (this ADR + ADR-0203 + ADR-0204);
implementation is roadmap R95..R98.

**Next work:** the bake pipeline, the bundle format, the update-
channel poller, the delta-rollback path.

### Mode 4: Client app (desktop / web / mobile)

**Form factor:** a native application that talks to a remote mother
(mode 1 or mode 3) over the wire.

**Sub-forms:**

- **Desktop CLI.** Ships as `crossengin` binary; interactive REPL
  (`examples/crossengin_chat.nova`) and one-shot commands. Status:
  shipped.
- **Web SPA.** Ships as a minimal single-page app under
  `examples/spa/`. Status: shipped for basic ask / list. Next:
  preference-management panel, session-history view.
- **Mobile (iOS / Android).** Talks to a remote mother over the
  TLS wire. Status: NEW EPIC. Requires TLS pinning against the
  operator's mother cert; requires a mobile-friendly session
  model (background reconnect, offline preference cache); requires
  push-mode notifications for high-priority daemon events (a
  future wire capability).

**Protocol:** JSON-RPC over TLS in all three sub-forms.

**Auth model:** capability tokens issued to the caller. The client
stores the token in an OS-appropriate secret store (Keychain on
macOS/iOS, Credential Manager on Windows, KeyStore on Android,
libsecret on Linux desktops).

**Update path:** the client updates on its own release cadence;
daemon updates are independent.

**Next work:** mobile epic (spec + first iOS build + first Android
build); preference-panel in the SPA; session-history in the SPA.

### Mode 5: Embedded (robot / OS / IoT)

**Form factor:** long-horizon. Runs inside a resource-constrained
device: a robot controller, an operating-system-level assistant, an
IoT hub.

**Protocol / auth / update path:** deferred. Requires a resource-
constrained NOVA runtime story that today does not exist; requires a
new bundle format optimized for footprint; requires a wire posture
that can survive intermittent connectivity.

**Current status:** design frame only. This mode is named as a
deliverable in ADR-0200 but the concrete design is a separate ADR
series that lands once the resource-constrained runtime work is
scoped.

**Next work:** open the ADR series (ADR-02XX robot embedding, ADR-
02XX OS-level assistant, ADR-02XX IoT hub) once ADR-0203 lands and
the bake pipeline is proven on modes 1-4.

## Consequences

### Positive

- Operator-facing map. One document answers "what can I deploy."
- Coverage of all five vision modes. No gaps between what ADR-0200
  promises and what this ADR describes.
- Each mode is independently shippable. Modes 1, 3, 4 are on
  independent roadmaps; a shipping delay in one does not block the
  others.
- Auth and protocol are consistent across modes 1-4. Same wire,
  same tokens, same overlay. Mode 5 will diverge but by design.

### Negative

- Long list of "next work" items. Mode 3 is design-locked but not
  implemented; mode 4 mobile is a new epic; mode 5 is deferred.
  The map is more optimistic than the current shipping surface.
- Mobile epic is genuinely large. TLS pinning, offline-capable
  wire client, background reconnect, notification wire capability
  — each is a real design.
- Mode 5 pushes work off. Deferring embedded until modes 1-4 are
  proven is the right call but customers asking about IoT today
  will not get a shipping answer.

### Neutral

- The five-mode enumeration matches the ADR-0200 vision verbatim.
  Consistency of naming.

## Alternatives Considered

1. **Ship modes 1, 2, 3 only (rejected).** Mode 4 (client apps) is
   how end users touch the system; without it the substrate is
   operator-facing only.

2. **Collapse mode 2 into mode 1 (rejected).** Per-user selective
   load is a distinct consumption story with a distinct verb
   surface (`user.preference.*`); the client and operator both
   need to know the mode exists.

3. **Skip mode 5 from this ADR (rejected).** Naming it as
   "deferred, separate ADR series" is more honest than pretending
   it does not exist.

4. **Bundle mobile with the mode-3 appliance story (rejected).**
   Mobile is a client, not an appliance. The auth and update
   models differ.

## See Also

- ADR-0200 — Mother/Child factory; the five-mode source.
- ADR-0203 — Bake pipeline (mode 3).
- ADR-0204 — Slim runtime (mode 3).
- ADR-0205 — Per-user selective load (mode 2).
- ADR-0104 — NL surface (all user-facing modes).
- ADR-0206 — Beliefs and self-awareness (`self.*` verbs, all modes).
- R54 — Capability tokens.
- R55.x — Ownership overlay.
- R86..R94 — TLS on the wire.
- `examples/crossengin_chat.nova` — mode-1 REPL.
- `examples/spa/` — mode-4 web SPA.
