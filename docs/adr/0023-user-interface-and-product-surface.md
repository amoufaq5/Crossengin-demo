# ADR-0023: User interface and product surface

## Status

Accepted (user-overridable)

## Context

The first twenty-two ADRs cover the brain architecture, the per-user memory substrate, the academic-knowledge pipeline, the soul layer, and the v0 deployment topology. None of them pin the user-facing surface. That surface cannot keep being deferred, because the three v0 success criteria from ADR-0022 are user-experience claims, not backend artifacts: medicine-domain factual QA with calibrated refusal is only a real claim if the user can see the citations behind an answer and watch the agent refuse on out-of-corpus questions; cross-session memory coherence is only demonstrable if the user can browse what the agent remembers about them across sessions; constitutional enforcement is only legible if refusals are visible rather than silent.

The brain modules also produce structured outputs that a generic chat box cannot carry without losing the project's differentiation. The academic knowledge module (ADR-0008) attaches citation references on factual claims; those need to render as inspectable chips rather than footnote text. The memory substrate (ADR-0006) stores composite `MemoryItem` records with frames, importance, and modality; those need a timeline view, not a chat scroll. The soul layer's three-tier values (ADR-0011), the constitutional gate verdicts logged per turn, and the narrative-thread state from the consciousness model (ADR-0013) all need a place to be exposed, or they remain implementation detail and the trust story stays invisible to users.

The constraint set is tight. The team is bootstrapped (ADR-0002, ADR-0017) and the v0 milestone plan (ADR-0022) budgets UI work across M2 through M6 alongside backend integration. The expected primary user — an individual managing a chronic or complex medical situation — uses the product mostly from a phone, but caregivers and clinicians evaluating the system will reach for it from a desktop browser. The licensing posture (ADR-0019) is strict permissive: every dependency the UI takes on has to be Apache 2.0, MIT, BSD, PostgreSQL, ISC, public-domain, or CC-BY for data.

This ADR pins the user-facing surface, the frontend stack, the accessibility and performance baselines, and the structural division of the product into panels. It does not pin design tokens, component specifications, copy, or branding — those belong in design documents under `docs/design/ui/` once this structure is accepted.

## Decision

The user-facing product is a **responsive Progressive Web App (PWA)** with three coordinated surfaces, installable on mobile and desktop, served from a single codebase. The three surfaces correspond to the three claims the product makes and the three success criteria it has to demonstrate.

**Panel 1 — Conversational surface** (the dominant surface, roughly 70% of session time). Mobile-first chat with token-by-token streaming responses. Rich content renders inline: markdown, tables, charts, and image attachments. Factual claims carry inline **citation chips** that expand to show the source passage from the academic knowledge graph (ADR-0008). A **thinking-trace toggle** reveals the reasoning chain on demand: academic retrieval → cognitive plan → visionary scenario rollout → response (ADR-0008, ADR-0009, ADR-0010). Voice input flows through the perception layer using Whisper (MIT) and voice output uses Piper (MIT); both ride the streaming perception path defined in ADR-0004. Image upload from camera or library uses the same perception pipeline. Quick-reply chips surface when the cognitive module asks a clarifying question. Conversation history is navigable; underneath, every conversation contributes to the single per-user memory substrate from ADR-0006.

**Panel 2 — Memory & self surface** (roughly 20% of session time; the trust differentiator). A **timeline view** of `MemoryItem` records grouped by date and topic. Each item is a card showing narrative summary, modality (text or image), source attribution, importance score, last-accessed timestamp, and pin/forget state. Search across memory uses the same three retrieval paths the cognitive module uses to query its own substrate: vector similarity, graph traversal, and full-text (ADR-0005, ADR-0006). A **frames view** ("what does it know about me") surfaces the major frames the system has built — medications, conditions, providers, lifestyle patterns — each editable so the user can correct mistakes. A pin/forget toolbar with confirmation flows lets the user shape salience. An **export** button downloads everything as JSON or markdown, on the deterministic versioned schema below. A **delete-everything** button implements GDPR right-to-be-forgotten as a first-class action with a sober confirmation flow, riding the export/delete primitives that ADR-0021 already requires the substrate to expose.

**Panel 3 — Governance & trust surface** (roughly 10% of session time; smallest but the one that earns the project's trust posture). Current soul state is rendered in human-readable form ("currently in supportive mode, attentive to your sleep concerns from yesterday"), pulling from the consciousness self-model in ADR-0013. The constitutional values are displayed read-only with version and signature, served from the same signed file the soul module reads — not duplicated in frontend code (ADR-0011). Developer-tunable values are shown with an audit log of every change (ADR-0011, ADR-0021). User-configurable preferences (tone, drive intensities, proactivity bounds) are editable within the bounds the developer layer authorizes. A **privacy dashboard** shows active perception modalities and what is stored encrypted versus plaintext (ADR-0021). A **per-user encryption key rotation flow**, **data export**, **delete**, and **account closure** flows are first-class actions. A **"why did you say that"** affordance is accessible from any prior response, opening an explanation panel that lists the specific `MemoryItem` records retrieved, the academic-graph nodes consulted, the visionary scenarios considered (ADR-0010), and the constitutional checks that passed (ADR-0011).

**Frontend stack** (every dependency on the ADR-0019 green list):

- **React 18 (MIT)** with TypeScript for the application.
- **Vite (MIT)** for build tooling.
- **Tailwind CSS (MIT)** for styling.
- **shadcn/ui (MIT)** for component primitives. Copied into the repo as source rather than pulled as a runtime dependency, so the project owns the code.
- **Zustand (MIT)** for client state.
- **Server-Sent Events** for streaming responses (simpler than WebSocket and matches the unidirectional response shape).
- **FastAPI (MIT)** at `crossengin/api/` as the backend gateway the UI calls. Consistent with the Python 3.11+ implementation stack pinned in ADR-0003.
- **Pydantic (MIT)** for request/response schemas shared between frontend types (via codegen) and backend models.
- **Lucia (MIT)** for authentication. Passkey-first using WebAuthn; email magic link as fallback for devices without WebAuthn. No passwords.
- **Whisper (MIT)** and **Piper (MIT)** integrated through the perception module (ADR-0004), not the frontend, so voice flows through the same pipeline as text and image.
- **Capacitor (MIT)** reserved for v1: wraps the same PWA codebase as native iOS and Android shells without a rewrite.
- **i18n** via FormatJS or i18next (both MIT). v0 ships English-only; all user-visible strings are extracted to a message catalog so v1+ adds languages without touching components.

**Accessibility baseline.** WCAG 2.2 Level AA conformance for the primary flows: chat send/receive, memory browse, governance view, data export and delete. Keyboard navigation for every interactive element. Screen-reader behaviour verified on NVDA and VoiceOver before v0 ships.

**Performance budgets.** Time-to-interactive under 3 seconds on a mid-range Android phone over 4G. First streamed token under 1 second after the user submits. Memory timeline scrolls at 60fps via virtual scrolling for any list over 100 items. Initial-route PWA bundle under 500KB gzipped; the memory and governance panels are lazy-loaded routes.

**Export schema.** A deterministic, semver-versioned JSON schema for the export-all action, so users who export and re-import (or move providers) get stable, round-trippable data. The schema lives alongside the Pydantic models so frontend and backend cannot drift.

## Consequences

- The three-panel structure makes memory ownership and governance transparency visible to the user. These are the things general-purpose AI products do not offer; making them surfaces of the product, not buried settings screens, is what makes the trust story tangible.
- One codebase serves mobile and desktop. The team does not need iOS or Android specialists for v0.
- iOS PWA limitations — background voice in particular, plus some hardware APIs — will be revisited when v1 adds Capacitor-wrapped native shells. v0 accepts the limitation in exchange for a single codebase.
- SSE streaming requires the cognitive module to yield tokens incrementally rather than batching its final response. FastAPI supports chunked transfer natively; the change is on the cognitive side, not the gateway.
- Citation chips require the cognitive module to attach `citation_refs` metadata to every factual claim it emits. This is a real backend change and should be tracked as a dependency of M5 in ADR-0022.
- The thinking-trace feature requires per-module structured logs to be queryable per-response, not just appended to an audit log. The ADR-0011 audit-log substrate can carry this if the per-response correlation ID is propagated through every module call.
- Memory timeline virtual scrolling requires the memory retriever to expose **cursor-paginated** APIs, not offset-paginated, so users with thousands of `MemoryItem` rows page cleanly without re-counting.
- The export-all schema is versioned and deterministic so import or migration is stable. Schema changes are semver-tracked.
- The constitutional-values read-only display is served from the same signed file the soul module loads. Duplicating the values in frontend code is forbidden — it would create the drift this ADR is designed to prevent.
- The 500KB initial-route budget is achievable but requires aggressive code splitting. Memory and governance panels load on navigation, not on cold start.
- Passkey-first auth gracefully degrades to email magic links on devices without WebAuthn. No device is excluded.
- WCAG 2.2 AA conformance costs roughly 15–20% of UI engineering time, including manual screen-reader testing. The cost is budgeted into M5 and M6 of ADR-0022, not deferred.

## Alternatives considered

**CLI only for v0, defer UI to v0.5 or v1.** Ships fastest and lets the backend stabilize before UI work begins. Rejected because the v0 success criteria are user-experience claims — the product is the experience, not a backend artifact. Deferring UI defers product validation.

**Native iOS and Android apps from day one** (SwiftUI plus Jetpack Compose). Best mobile experience and full platform feature access (background tasks, system-level voice). Rejected because it doubles the engineering surface immediately, requires platform-specific expertise the bootstrapped team does not have, and adds app-store review cycles to iteration speed.

**Desktop app via Electron or Tauri.** Strong local capabilities and a good match for a future local-first deployment story. Rejected because the primary user lives on the phone; a desktop-first surface inverts the actual usage pattern.

**Responsive Progressive Web App.** Chosen. One codebase serves mobile and desktop, installable on phone home screens, offline-capable, no app-store gatekeeping for v0 iteration. iOS PWA limitations are real but acceptable for v0, and Capacitor leaves a clean upgrade path for v1.

**Voice-only interface, no visual UI.** Novel and matches the companion framing. Rejected because it makes citations and memory browsing impossible to surface — the differentiators against general-purpose chat products become invisible. Voice-only fails the v0 success criteria.

**Embed in existing platforms** (Slack/Discord bot, browser extension). Lowest distribution friction. Rejected because it forces the product into someone else's UX model, kills the memory-ownership and governance UX, makes monetization harder, and gives the user no sense that their data is theirs.

## Open questions

These are deferred to design documents under `docs/design/ui/`, not answered in this ADR:

- Design tokens (color palette, typography scale, spacing system, motion design).
- Component-level specifications with states, variants, and interaction patterns.
- Onboarding flow design — first-time-user experience and consent collection for camera and microphone per ADR-0021.
- Visualization design for the academic knowledge graph when surfaced inside the "why did you say that" explanation panel.
- Empty-state designs for the memory timeline before the user has interacted enough to populate it.
- Error-state and offline-state designs.
- Per-component accessibility patterns (focus rings, ARIA labels, keyboard shortcuts).
- The audit-trail visualization for governance changes.
- Branding — logo, app name, tone of voice for system-authored copy.

## References

- ADR-0002 — project scope and v0 MVP; the three surfaces operationalize this scope.
- ADR-0003 — implementation language and stack; the Python 3.11+ + Rust backend is unchanged, frontend additions here.
- ADR-0004 — perception layer; voice and image input flow through it.
- ADR-0005 — knowledge representation paradigm; the substrate the memory and academic panels read from.
- ADR-0006 — memory architecture and storage; backs Panel 2's timeline, search, and export.
- ADR-0008 — academic knowledge module; backs Panel 1's citation chips and Panel 3's "why did you say that" sources.
- ADR-0009 — cognitive module; backs the thinking-trace plan stage and quick-reply chips.
- ADR-0010 — visionary layer; scenarios surfaced in the explanation panel.
- ADR-0011 — soul values governance; backs Panel 3's read-only constitutional display and developer-tunable bounds.
- ADR-0013 — soul consciousness model; backs the human-readable soul state in Panel 3.
- ADR-0019 — licensing posture; every dependency above is on the green list.
- ADR-0021 — privacy and data handling; backs Panel 2's export/delete and Panel 3's privacy dashboard, consent flows, and audit log.
- ADR-0022 — evaluation and milestone plan; UI work lands across M2–M6, and the three panels surface success criteria 1, 2, and 3 respectively.
- Progressive Web Apps reference — https://web.dev/progressive-web-apps/
- Web Content Accessibility Guidelines 2.2 — https://www.w3.org/TR/WCAG22/
- shadcn/ui documentation — https://ui.shadcn.com
