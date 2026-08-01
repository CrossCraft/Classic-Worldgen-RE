# ACCEPTANCE.md — A Guide for Human 2

Hi! You're the human supervising the Role-2 agent loop (the reverse engineer &
spec formalizer). The agent studies the original generator privately and
publishes only mathematics; it is never allowed to touch git itself. That means
**you** are the quality gate: you review its work, and you run the commits.

This guide tells you what to check after each session and what belongs in a
commit. It should take you a few minutes per review.

## The one-paragraph mental model

The agent works in `dirty/` (git-ignored scratch space, never committed) and
publishes into `spec/` (the only clean deliverable). It may also instrument the
harness (`src/main/java/**`, `run_harness.py`, `Dockerfile`, `justfile`) to
capture intermediate values — but those edits are investigative scaffolding,
not deliverables, and they never get committed. Everything else is off-limits.
Its job ends with changes **unstaged**; your job is to verify, then stage and
commit the clean parts only.

## Checklist per agent session

Run through these in order. Most are one command each.

### 1. The stage is done, not just started

- Read the agent's final report. It should say what was found, what was added
  to `spec/`, and what it validated.
- Open `dirty/NOTES.md`. It should be updated: current stage, new pipeline
  findings with evidence, and remaining open questions. If the notes are stale
  or empty, send the agent back — notes are its memory, and tomorrow's session
  depends on them.

### 2. The spec still builds

```sh
just spec-build
```

- Must be green. `sorry` warnings are fine while a stage is in progress
  (that's declared unfinished business), but hard errors are not.
- The stage's completion criteria in `GOALS.md` say more: e.g. Stage 2 needs
  dumps validation recorded in the notes, Stage 3 needs consistency with
  `just composition` on three seeds. Check the block for the active stage.

### 3. The harness still works

If the agent touched the harness (instrumentation for dumps), run:

```sh
just smoke
```

It must pass. Instrumentation is allowed, breaking the black-box loop is not.
But note: these harness edits stay uncommitted (see below) — they're checked
here only so the next session starts from a working harness.

### 4. The spec is actually clean

Skim the new `.lean` files. The rules (`spec/README.MD`) are short and strict:

- Allowed: `axiom`, `opaque`, `structure`/`inductive` (types only),
  `theorem`/`lemma`.
- Forbidden: `def`, `abbrev`, `instance`, `#eval` or any evaluation directive,
  and **comments of any kind** — no `--`, no `/- -/`.

This is the clean-room boundary. The spec must state mathematics, never
decompiled code. If you see anything that looks like translated Java — variable
names copied wholesale, code-shaped definitions — that's a stop, not a commit.

A fast mechanical pass:

```sh
grep -rn -e '--' -e '/-' -e '#eval' -e 'def ' -e 'abbrev ' -e 'instance ' spec/Spec/ spec/Spec.lean
```

Any hit needs a human look. (Word-boundary false positives are fine to
dismiss; the point is that you looked.)

### 5. Only the right files changed

```sh
git status
```

- Expected: modified/new files under `spec/`, possibly docs the agent was
  asked to write, possibly harness files (modified but never to be staged —
  see "What never gets committed").
- `dirty/`, `out/`, `classic.jar`, `spec/.lake/` should never appear —
  they're git-ignored. If `git status` shows them, something's wrong with
  `.gitignore`, not with your eyes.
- Nothing should be staged. The agent's hard rule is "leave everything
  unstaged." If the index isn't empty, the agent broke a rule — investigate
  before doing anything else.

## What to commit

In practice there is exactly one clean deliverable:

- **`spec/`** — new or extended stage files (`Spec/Random.lean`,
  `Spec/Noise.lean`, …) and the updated root `Spec.lean` import. This is the
  whole point of the project.

- **Docs, with care** — updates to `README.md`, `GOALS.md`, `spec/README.MD`,
  etc. Review these line by line before committing: they define the process
  and the clean-room rules, so a sloppy or overreaching doc edit quietly
  changes the contract for both roles. Commit them separately from spec work,
  and only when you agree with every word.

## What never gets committed

- **Harness changes** — instrumentation edits to `src/main/java/**`,
  `run_harness.py`, `Dockerfile`, `justfile`. In a two-person setup there is
  no reliable way to guarantee these edits carry no tainted knowledge from
  the agent's private analysis, so they stay unstaged scaffolding. Leave them
  in the working tree for as long as they're useful; discard them when the
  stage is done.
- `dirty/` — dumps, decompile notes, scratch scripts. Git-ignored on purpose.
- `out/` — extracted block arrays.
- `classic.jar` — the original binary; never copied, modified, or committed.
- `spec/.lake/` — build artifacts.
- Anything containing decompiled Mojang source, in any file, ever.

## Commit style

One commit per coherent unit (typically: one stage's spec file plus its root
import update, or one doc change), with a message that says what was
formalized and which stage it belongs to. Keep doc commits separate from spec
commits.

## When to push back instead of committing

- `just spec-build` or `just smoke` is red.
- `dirty/NOTES.md` wasn't updated.
- The spec contains comments, definitions, or anything code-shaped.
- The diff touches files outside the stage's scope with no explanation.
- You're being asked to commit harness edits — decline; they're scaffolding.
- A doc change rewrites rules or scope rather than clarifying them.
- The agent staged something itself.

In all these cases, leave the tree as-is and re-task the agent with the
specific failure. The loop works because the human gate is boring and strict —
keep it that way.
