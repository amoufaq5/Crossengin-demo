# CrossEngin domain packs

Real content in the `.cerec` (CrossEngin native records) format, ready
to feed into the ingestion pipeline (`src/ingest/`).

## Available packs

- **`solar_system.cerec`** — 33 atoms + 49 implications + 4 observations
  covering the eight planets, the Sun, major moons, and compositional
  facts. Ontological is-a edges are `FORMAL`; graded associations are
  `EMPIRICAL`. Source-tagged `src:pack:solar_system:v1` with citations
  to three external references (IAU 2006 planet definition, NASA fact
  sheet, JPL Horizons).

- **`folk_astronomy.cerec`** — 5 atoms deliberately holding low-belief
  historical / folk beliefs (Pluto still a planet, geocentric universe)
  under `src:pack:folk_astronomy:v1`. Designed to demonstrate cross-KG
  conflict detection when ingested alongside `solar_system`.

## Ingest via the chat REPL

```
> /ingest cerec data/packs/solar_system.cerec astronomy src:pack:solar_system:v1
ingest[...]: 1 ingested, 0 queued for review, 0 dropped,
             33 atoms added, 0 parse errors

> /ingest cerec data/packs/folk_astronomy.cerec folk_astronomy \
                                                 src:pack:folk_astronomy:v1
ingest[...]: 1 ingested, 0 queued for review, 0 dropped,
             5 atoms added, 0 parse errors
```

Both packs' source-tag prefixes start with `src:pack:`, which
`ingestion_agent` treats as trusted by default — records ingest
directly into the KG instead of entering the review queue.

## Cross-KG conflict demo

After ingesting both, the multi-KG empirical consistency scan surfaces
the deliberate disagreements between the scientific and folk KGs:

```
> /kg_consistency 200
(empirical belief conflicts across KGs, spread >= 200 milli:)
  'planet':   astronomy believes 950  vs folk_astronomy believes 400
  'sun':      astronomy believes 1000 vs folk_astronomy believes 200
  'earth':    astronomy believes 1000 vs folk_astronomy believes 600
```

Each conflict names both KGs, both belief means, and the atom label.
Nothing was silently fused; the disagreement is a first-class event.

## File format

`.cerec` is a line-based text format. Directive per line, whitespace-
separated tokens:

```
KG      <kg_name>                    open a new record for KG
SRC     <src:tag>                    the source attribution tag
ATOM    <label> <kind> <belief>      kind=1..6 (see kg/atom_store),
                                     belief 0..1000 milli
IMP     <ante> <conseq> <STRENGTH>   STRENGTH = FORMAL | EMPIRICAL
OBS     <label> <sign> <weight>      sign = +1 | -1, weight in milli
CITE    <src:from> <src:to> <rel>    rel = supports | contradicts | extends
```

- Comment lines start with `#` and are discarded.
- Blank lines are whitespace within a record (do not close it).
- A record is closed by a new `KG` directive or by end-of-file.
- Bad lines are logged and skipped -- one malformed directive does
  not abort the file.

## Authoring a new pack

1. Copy `solar_system.cerec` as a template.
2. Pick a `src:pack:<name>:v<n>` tag; keep the pack under 200 atoms
   for the initial version to keep ingest fast on the current
   linear-search KG lookup path (a hash-index for `mkgc_scan_conflicts`
   is on the roadmap).
3. Reserve `FORMAL` implications for ontological is-a relationships
   the kernel is expected to enforce; use `EMPIRICAL` for anything
   graded or subject to future evidence.
4. Cite external sources with `CITE` so a later audit can trace
   which reference contributed which atom.
5. Add a test in `tests/unit/test_pack_<name>.nova` following
   `test_pack_solar_system.nova` as a template.
