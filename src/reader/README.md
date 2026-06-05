# Reader

Five-stage hybrid input processor: lexical anchor, context bias, spreading activation, coherence check, and fetch/route/learn. It is NOT a parser and NOT an LLM; it operates over the substrate and domain knowledge graphs.

**Governing ADRs:** ADR-0011, ADR-0012

**Status:** Pending. Depends on the multi-KG store (src/kg) and learned gates (src/gates); DEPENDS ON NOVA enhancement #8.

See [`docs/adr/`](../docs/adr/) for the decisions that bind this component, and the repository [README](../README.md) for the substrate overview.
