# Benchmarks

Performance and capacity benchmarks for the substrate: node-pool claim/release
throughput, signal-propagation rate per tick, synapse plasticity update cost,
and the scaling targets from ADR-0003 (1M nodes/part, 1B signals/part). Several
benchmarks depend on the SIMD/sparse-adjacency NOVA enhancements (#2, #4, #12)
and are gated on those landing.

**Index speedup benchmarks** (head-to-head scan vs. indexed, with a parity check):
- `bench_ann_query` — LSH nearest-neighbour vs. linear cosine scan (P3.4).
- `bench_operator_lookup` — edge-index `rk_operators_from` vs. full atom scan
  (P1.5, ADR-0070): ~1132× at N=2000 atoms, both paths returning identical hits.

**Governing ADRs:** ADR-0003 (scaling), ADR-0049 (benchmarks), ADR-0070 (edge index).

**Status:** Pending. Microbenchmarks for the in-memory kernel come first;
at-scale benchmarks wait on NOVA enhancements #1, #2, #4, #12.
