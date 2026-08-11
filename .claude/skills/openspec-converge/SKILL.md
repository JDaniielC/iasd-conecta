---
name: openspec-converge
description: Assess the codebase against a change's artifacts and append the remaining work as tasks. Use after apply, before archive, to find what the implementation still does not satisfy. Never edits code.
allowed-tools: Bash(openspec:*)
license: MIT
compatibility: Requires openspec CLI.
metadata:
  author: iasd-conecta
  version: "1.0"
  portedFrom: speckit-converge
---

Assess the code against a change's own artifacts and append what is still missing
to that change's `tasks.md`.

**Why this exists, in this repository.** It is not part of OpenSpec, and it was
not part of Spec Kit either — it was written here. On feature 013 it ran seven
times and produced **20 defects that nothing else caught**: `flutter analyze`
was clean, 273 unit/widget tests were green, 210 integration tests were green,
and a code review had already passed. Among the 20: the app destroying a photo
the person had while telling them nothing had changed; a file left public with
no row anywhere, invisible to the only health query the project had; and two
concurrent drains corrupting the very column that was supposed to distinguish a
transient failure from a permanent one.

The common shape, and what to hunt for: **the failure path of a multi-step
write.** Everything works when every step succeeds. Ask what state survives when
step *k* fails, who sees that state, and who cleans it up.

---

## Boundary

This workflow **assesses and appends. It never edits.**

- It MUST NOT modify `proposal.md`, `design.md`, or any delta spec.
- It MUST NOT modify, create, or delete project code — completing the appended
  tasks is the apply workflow's job.
- Its only write is appending a `## Convergence N` section at the **end** of the
  change's `tasks.md`. It never rewrites, renumbers, reorders, or deletes an
  existing task, including tasks from an earlier convergence pass.
- When the code already satisfies everything, it leaves `tasks.md`
  **byte-for-byte unchanged** — no empty header — and reports a clean result.

The project constitution (`.specify/memory/constitution.md`, if present) is
non-negotiable. Code that violates a MUST principle is the highest-severity
finding.

## Steps

1. **Locate the change.**

   ```bash
   openspec status --change "<name>" --json
   ```

   Use `changeRoot` and `artifactPaths` from the JSON; do not assume paths. If
   no change is named and it cannot be inferred from the conversation, list them
   with `openspec list --json` and ask.

2. **Read the intent, and only the intent.** The change's `proposal.md`,
   `design.md`, and its delta specs (`specs/<capability-path>/spec.md`) are the
   sole source of what the code owes. Build an inventory keyed by requirement
   and by scenario — a delta spec's `WHEN/THEN` scenarios are the acceptance
   criteria, one key each.

   Read `tasks.md` only to find the highest existing convergence number.

3. **Bound the scope.** Derive the files in scope from the paths the artifacts
   name plus a keyword search for the concepts each requirement describes. Do
   not assess beyond what the artifacts define.

4. **Assess, and prefer measurement over reading.** For each item in the
   inventory, look at the code. Produce a finding only where there is a gap.

   **A finding you have not observed is a hypothesis.** This repository's
   history is unambiguous on the point: the most expensive defects here all
   looked correct on the page. Where a claim can be tested cheaply — a query, a
   `curl`, two concurrent calls, a row inserted and rolled back — test it, and
   put the observed number in the finding. Where it cannot, say so.

   Two traps this repository has fallen into more than once, worth checking by
   name:

   - **Proving the wrong role.** A test that runs as `postgres` or `anon` proves
     nothing about an app whose every user is `authenticated`. Exercise the role
     the app actually has.
   - **Proving the happy path only.** If nothing in the suite makes step 2 of a
     3-step write fail, the failure path is unspecified *and* untested, and that
     is where the user-visible damage lives.

5. **Classify every finding** by gap type — `missing` (absent entirely),
   `partial` (exists, does not fully satisfy), `contradicts` (conflicts with
   stated intent or a MUST principle), `unrequested` (present but not called
   for; surfaced for awareness, never deleted here) — and by severity:

   - **CRITICAL** — violates a constitution MUST, or blocks the baseline
     behaviour the proposal promises.
   - **HIGH** — `missing`/`partial` on a core requirement or scenario.
   - **MEDIUM** — `partial` on a secondary requirement, or an `unrequested`
     addition without justification.
   - **LOW** — polish, or low-risk `unrequested` additions.

6. **Report before writing.** Output a table — id, gap type, severity, the
   requirement or scenario it traces to, the evidence observed, the remaining
   work — ordered by severity. Then the counts: requirements and scenarios
   checked, findings by gap type, findings by severity.

   Also report, in one line each, the hypotheses you checked and **disproved**.
   They cost the same to find and they stop the next pass from re-raising them.

7. **Append, or report converged.**

   With findings, append to the end of `tasks.md`:

   ```markdown
   ## Convergence <N>

   - [ ] <imperative description> — per <requirement or scenario>, (<gap-type>)
   ```

   `<N>` is the next convergence number. Constitution violations come first and
   are described as `CRITICAL`. Each task carries the evidence: the measured
   number, the file and line, the reason it matters. A task that only names the
   defect will be implemented as a guess.

   With no findings, do not touch the file. Report:
   **"Converged — the implementation satisfies this change's artifacts."**

8. **Validate and hand off.**

   ```bash
   openspec validate "<name>" --strict
   ```

   On append: say how many tasks were added and recommend `/opsx:apply` to
   complete them, noting that a following convergence pass should find fewer.
   On converged: recommend `/opsx:archive`.

## When it keeps finding the same class of thing

If successive passes keep landing in one area, stop treating them as separate
defects. It happened here: ten of the twenty findings were in one removal
pipeline, and each fix opened the next, because the behaviour required on
partial failure had never been written down. The fix was not a better
convergence pass — it was a decision recorded in the spec, after which the
findings stopped.

When you see that pattern, say so, and propose the missing decision instead of
the eleventh patch.
