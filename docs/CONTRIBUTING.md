# Contributing to CrossEngin

This guide documents the round-based development model used by
CrossEngin (and its sister repo NOVA). It exists so a new contributor
can understand "why is the commit history so structured" within five
minutes of arriving.

## The round-based development model

CrossEngin evolves through numbered **rounds** (R0, R1, ..., R35,
R36 at time of writing). Each round is a coordinated sprint where
multiple agents work on the codebase concurrently without stepping on
each other.

A round has the shape:

  - **A round letter group**: rounds are subdivided into "tracks"
    (R35A, R35B, R35C, R35D, R35E, R35F). Each letter is one agent.
  - **File ownership is exclusive.** Each agent has a strict list of
    files they may modify or create. Two agents in the same round
    NEVER touch the same file.
  - **Each agent ends with one commit + one push.** Round letters
    map 1:1 to commits.
  - **Consumer / producer pattern.** Some rounds produce a primitive
    (e.g. R34B ships TURN codec); later rounds consume it (e.g. R35D
    is "R34B consumer + R30C consumer"). The commit message records
    the dependency explicitly.

### Why this model

  - **Concurrency without merge conflicts.** With strict file
    ownership, two agents working in parallel cannot generate a merge
    conflict. The cost is upfront file-ownership planning.
  - **Traceable provenance.** Every line of code is attributable to a
    specific round + agent. Bug bisection has a strong signal:
    "regression appeared at R34C -> look at the R34C commit."
  - **Documentation discipline.** Each round writes a `NEXT_SESSION.md`
    section describing what shipped, deferred work, and honest
    caveats. Over 35 rounds this aggregates into a high-fidelity
    project history.

## File ownership protocol

Before touching any file, an agent verifies it is on their owned-files
list. Anything not on the list is **off-limits**:

  - Files owned by another agent in the same round.
  - Files owned by no one in this round (= no one should be modifying
    them; if they're modified, treat as a pristine baseline).
  - Sibling agents' untracked files (see "stash protocol" below).

### What "modifying" means
  - Editing existing content -> requires ownership.
  - Creating a new file -> requires the parent directory or path to
    be on the owned-files list.
  - Reading a file -> always allowed.

### What if I think I need to modify a file outside my list
You probably don't. Common shapes:

  - You found a bug in someone else's module. Don't fix it; file a
    follow-up note in `NEXT_SESSION.md` and let the next round own it.
  - You need a small utility from another module. Import it; don't
    duplicate it; don't refactor it.
  - You're convinced the file ownership is wrong. Stop and ask in
    `NEXT_SESSION.md` instead of editing.

## The stash protocol

When an agent starts a round, the working tree may already contain
modifications from sibling agents that haven't yet been pushed. The
agent must **stash only their own owned-paths**, never sibling-agent
files.

### Allowed stash invocation

```bash
git stash push -m "R<round letter>-preflight" -- <owned-path-1> <owned-path-2> ...
```

  - The `-m` message names the round letter so the stash can be
    identified later if needed.
  - Every path after `--` is explicit. Glob carefully: `docs/adr/*.md`
    is safe ONLY if your ownership covers all matching files.

### Forbidden stash invocations

```bash
# NEVER use -u (includes untracked files, which may be sibling
# agents' work in progress):
git stash push -u

# NEVER omit the path list (stashes everything modified):
git stash push -m "..."

# NEVER use git stash (no subcommand, no paths -- same problem):
git stash
```

### Why this matters

Sibling agent R36X may have just created an untracked file
`docs/MY_NEW_GUIDE.md` and not yet committed it. If R36F runs
`git stash -u`, R36X's file ends up in R36F's stash. R36F then drops
the stash later, and R36X's work is silently lost. The `-u` flag is
banned to prevent exactly this.

## Commit message conventions

A commit message has the shape:

```
<scope>: <short imperative subject> (R<round letter>[ / R<dep> consumer])

<body explaining what + why, with cross-references to rounds>

<footer>
```

Examples from the recent history:

```
federation: DTLS-SRTP keying material extraction (RFC 5764) -- wire R31B PRF to R34C srtp (R35A / R34C.2)
docs: R35B section in README + FEDERATED_AUDIT
federation: ICE-TURN integration -- escalate to relay candidate on ICE failure (R35D / R30C + R34B consumer)
```

The footer is the session-tracking URL. Add it via heredoc:

```bash
git commit -m "$(cat <<'EOF'
scope: subject (R36X)

Body paragraph.

https://claude.ai/code/session_<id>
EOF
)"
```

### Do NOT include a model identifier
Commits, code comments, ADRs, and any file in the repo must NOT
include a model identifier (e.g. claude-opus-4-7 etc.). The footer
URL is sufficient provenance.

## Branches

Round work happens on a shared branch (e.g. `claude/festive-franklin-PP7mW`).
All agents in a round pull from + push to the same branch. Pushes are
non-fast-forward-friendly because each agent's commit is on the same
branch tip; conflicts are resolved by file-ownership discipline, not
by rebase.

If you must rebase: prefer creating new commits over `git rebase -i`
or `git rebase --no-edit` (forbidden). If multiple sibling commits
need consolidation, that's a follow-up round's job, not yours.

## Documentation: NEXT_SESSION.md

`NEXT_SESSION.md` is the running log. At the close of your round,
prepend a section:

```markdown
## R<round letter> -- <one-line subject>

**Status: complete** -- <one paragraph summary>

### What R<round letter> delivers
<bullet list of concrete changes>

### Verification
<how you confirmed it works>

### Deferred to future rounds
<honest list of out-of-scope work>

### Honest design caveats
<honest list of known limitations>
```

Keep it crisp -- this is the file the next round's agents will read.

## Documentation: README.md

Each round's PR updates the `README.md` STATUS callout block with a
short summary of what shipped. Heavy edits to the README body are
reserved for documentation rounds (like R36F).

## Documentation: ADRs

Architecture Decision Records live under `docs/adr/`. The numbered
series `0001-...` to `0050-...` covers the original architectural
arc. Round-specific ADRs use the `r<round letter>-NNNN-...` prefix
to avoid collision with the original series. Use the template:

```markdown
# ADR <number>: <title>

## Status
Accepted (R<round>) -- <one-sentence context>.

## Context
<the problem>

## Decision
<what was chosen>

## Consequences
<positive / negative / follow-up>

## Alternatives considered
<rejected approaches and why>
```

## Code style

Follow the conventions visible in the existing source:
  - NOVA modules use snake_case for functions, ALL_CAPS for constants,
    PascalCase reserved for enums / struct tags where present.
  - Module headers carry a brief comment describing scope + RFC
    references where relevant.
  - Tests live under `tests/unit/test_<module>.nova` and follow the
    `_test_setup_*` / `_test_assert_*` / `main()` shape.

## Testing

Every behaviour change ships with a test. Run:

```bash
bash scripts/test.sh
```

Add new test files to `tests/unit/` and they are picked up
automatically by the runner.

## When in doubt

  - Read `NEXT_SESSION.md` for what shipped recently.
  - Read the round's docstring in the file you're touching.
  - Read the ADR if one exists.
  - Don't touch files outside your ownership.
  - Don't fix off-list bugs in your round; file them for the next.
