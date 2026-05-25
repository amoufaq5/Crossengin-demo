# Benchmarks

Performance and capacity benchmarks for the substrate: node-pool claim/release
throughput, signal-propagation rate per tick, synapse plasticity update cost,
and the scaling targets from ADR-0003 (1M nodes/part, 1B signals/part). Several
benchmarks depend on the SIMD/sparse-adjacency NOVA enhancements (#2, #4, #12)
and are gated on those landing.

**Governing ADRs:** ADR-0003 (scaling), ADR-0049 (benchmarks).

**Status:** Pending. Microbenchmarks for the in-memory kernel come first;
at-scale benchmarks wait on NOVA enhancements #1, #2, #4, #12.
