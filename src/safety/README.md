# Safety and audit gate

Permission tiers (auto/notify/approve), reversibility classifier (default irreversible), override mechanisms (belief edit, goal veto, hard stop, kill switch), and constitutional rules expressed as hard inhibitory signals.

**Governing ADRs:** ADR-0041, ADR-0042, ADR-0043, ADR-0044, ADR-0045

**Status:** Implemented (Phase 8). `reversibility_classifier`, `permission_tiers`,
`override_mechanism`, and `constitutional_filter` live here; the append-only,
hash-chained decision log is in [`src/audit/`](../audit/) (ADR-0043). Each module
compiles and has a passing `tests/unit/` suite. The fsync-durable store
(ADR-0043) and process-exit/snapshot syscalls (ADR-0044) are runtime seams (NOVA
enhancements #9/#10); all decision logic is implemented and tested.

See [`docs/adr/`](../docs/adr/) for the decisions that bind this component, and the repository [README](../README.md) for the substrate overview.
