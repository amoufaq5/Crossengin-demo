# Integration tests

End-to-end tests that exercise multiple substrate components together (e.g. a
moment entering perception, propagating through gates and synapses, and writing
an atom). These come online once the corresponding parts are implemented; the
substrate-liveness path is the first target.

**Governing ADR:** ADR-0049 (testing and benchmarks).

**Status:** Pending. Unit tests under [`../unit/`](../unit/) cover the substrate
kernel first; integration tests follow as parts land.
