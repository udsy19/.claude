# Gate Independence

**A gate may not consume any value produced by the system under test. It must re-derive its ground
truth independently — from the artifact bytes, or from the source state.**

Trust requires positive evidence from an independent path. A gate that reads the producer's own
account of what it did is not measuring the producer; it is transcribing it.

**The unified form.** Every law below is that one statement projected onto a different surface:

> **A check is only as good as the independence of its inputs, and independence must be positively
> established, never assumed.**

Gates trusting their subject's metadata · baselines drawn from the population under test ·
presence-matching two contaminated lists · a board trusting its gates' exit codes · a falsification
harness endangering its own subject · an agent performing a trusted-human event · a guard set below
the band it defends · a detector written in the fix's own vocabulary · a sabotage that returns no
verdict at all — all the same violation, wearing the clothes of whatever surface it appeared on.

**There will be another instance, on a surface no law below describes.** Recognise it by the unified
form, not by matching an example: ask what the check's inputs are, who produced them, and what
positive evidence establishes that they did not come from the thing being checked — then ask the
same question inverted, *what positive evidence establishes that this check would fail if the thing
it checks were broken?* Then add the law — with its worked case and its falsification.

## The laws, in order

Every law below appears in [[Design/gate-independence-cases]] exactly once, with its heading quoted
**verbatim** — so a heading renamed without the index is one `grep -F` from being caught.
`node scripts/gates/rules-index.mjs` checks the join between the two files.

1. **Why this is a rule and not a preference** — every blocker it names was found against a board reporting all green.
2. **The required demonstration: byte-identical under sabotage** — corrupt, move and delete every producer hint; identical bytes prove it was never consulted.
3. **The positive complement: write the gate first, and watch it fail first** — a gate written after the fix can only confirm the fix, never audit it.
4. **Corollary: never calibrate against the population under test** — a baseline drawn from the artifact under test inherits its defects.
    4a. **The same error one level up: never calibrate the DETECTOR on the fix's own vocabulary** — a detector written in the fix's words finds the fix, not the class.
5. **A prescribed fix is a hypothesis — the gate falsifies the FIX as much as the defect** — whoever specified the fix — including whoever wrote the task — is not exempt.
6. **The board runner is itself a system under test** — a scoreboard may not trust a status code supplied by the thing it summarises.
7. **A gate whose failure mode is a HANG is not a red** — no verdict is a third outcome, and it must be reported as one, never as a slow machine.
8. **Completeness gates: derive the full expected set, never presence-match two artifact-derived lists** — two contaminated lists agree with each other about what is missing.
9. **An agent must never perform or simulate a trusted-human event** — where a store's value IS its provenance, producing its entries destroys the worth.
10. **Falsify against a disposable copy — never mutate the protected artifact** — a verification procedure must not endanger the thing it verifies.
11. **A one-sided threshold can be propped up by ink the check does not attribute** — a floor with no attribution and no upper bound can be cleared on borrowed signal.
12. **A guard must constrain the population the assertion compares — AND exceed the band it defends** — a guard below its own tolerance certifies arithmetic, not agreement.
13. **The tooling layer: a success message is not evidence that anything changed** — a script that cannot fail loudly will report success quietly.
    13a. **A string that looks right is not a string that is right — census the bytes, do not read them** — reading is what a homoglyph beats.
14. **A scalar is not geometry — settle shape disputes with tables** — one number, or a prose noun, is a hypothesis; a table of descriptors is a measurement.
    14a. **Corollary — one descriptor is fragile, and a predicate must be immune to inputs that carry no information** — a degenerate input can flip a classification a table would not.
15. **The falsification round is the closing move — and it must include the enabling step** — sabotage the assertion, the threshold AND every transform they depend on — and report the nulls.
16. **Evidence must prove it came from the build it claims** — reload unconditionally, read a token you just changed out of the served build, abort on mismatch.
17. **Reporting convention: scope every negative claim** — an unscoped negative aggregates into a global one.

Then the working end of the file, which states no new law: **In practice** (the checklist),
**Scope — where this rule stops**, and **Related**.

## The worked cases live next door

Each law ships with a case and the sabotage that proves it still bites:
**[[Design/gate-independence-cases]]** (`vault/Design/gate-independence-cases.md`). They are not here
because this file is loaded into every agent before it does any work. **Read them before you write
a gate, before you argue a law does not apply to your case, and before you add an eighteenth** — and
add this project's own case under a law the first time that law bites here.

## In practice

- **Derive from bytes or source state.** Parse the artifact; re-project from the model. Do not read
  "what I drew" summaries.
- **A missing input is a FAILURE, never a skip.** `if not x: continue` hands the producer a veto over
  its own test. If a field is absent, fail and say so.
- **Metadata the gate can _validate_ is acceptable; metadata it must _trust_ is not.** A
  producer-emitted mask is fine if the gate checks the mask against the output before using it.
- **Condition on the model, not on a producer flag.** A flag can be dropped; the model cannot.
- **Emission is not visibility.** Counting what a renderer emitted does not prove it can be seen.
  Where the deliverable is an image, assert against the delivered pixels.
- **The graded artifact must be the emitted artifact.** A runner that grades output a later step
  overwrites is the same failure in the time dimension. Assert completeness (the file decodes, the
  archive has its end record) and snapshot what was graded.
- **To prove what a BRANCH carries, diff it: `git diff --stat <base>...<tip>`, three dots.**
  `git status --porcelain` compares the working tree to HEAD, so it cannot see committed work by
  construction — it prints clean for any branch, however much that branch is holding.
- **A count is counted, not typed — and zero checks is a refusal, not a pass.** A verdict line that
  prints a literal, or reports green when no check ran, is measuring nothing.
- **Exit codes carry the verdict:** 0 green · 1 red · 2 refused (could not grade) · 77 a declared
  skip, named and never tallied as a pass.

## Scope — where this rule stops

The threat model is **regression and drift in our own code**, not a malicious producer forging
outputs. Perceptual gates that catch an output collapsing or going blank are doing their job; making
them forgery-proof is a security posture this rule does not call for. Tolerances that were measured
and deliberately left open are recorded, with their numbers, in the cases file — not silently.

The producer-metadata class is different, and is in scope, because it was never an edge case — the
gate was measuring nothing at all.

## Related

- `.claude/rules/no-bloat.md` — one derivation, one source; drift between two copies is the defect
  this rule catches from the other side.
- `.claude/rules/evidence-and-honesty.md` — the same law applied to what an agent REPORTS rather than
  what a gate checks.
- Worked examples in this repo: `scripts/gates/plan-integrity.mjs` (self-check on a disposable copy,
  differential control, a recursion guard), `scripts/gates/vault-reachability.mjs` (a parser
  calibrated on conventions its author did not write, a depth fixture as the positive control),
  `scripts/gates/sprawl.mjs` (a reason graded on what the gate could NOT have computed).
