---
type: design
status: current
date: {{DATE}}
updated: {{DATE}}
---

# Gate independence — the worked cases

The seventeen laws of `.claude/rules/gate-independence.md`, each with the failure that produced it
and the falsification that holds it. **The rule is the rules file; this is its evidence.** Every
`##` heading below is a law's heading, verbatim (`node scripts/gates/rules-index.mjs` checks it).

Each law carries the general case it was distilled from (from the project this kit was built on),
and a slot for **this project's own case** — add it the first time the law bites here, with the
commit, the gate and the evidence path. A law with no case behind it is the kind people route around.

## Why this is a rule and not a preference

Three blockers in one mission were each one instance of a gate consuming a value its subject
produced — and each was found against a board reporting every row green. A green board built on
producer-supplied inputs is not evidence; it is the producer's opinion of itself, tallied.

**This project's case:** —

## The required demonstration: byte-identical under sabotage

Any gate that touches producer-adjacent data ships with this proof: corrupt every producer-supplied
hint the gate could plausibly read, move it somewhere impossible, delete it — and show the gate's
output is **byte-identical**. "Still passes" proves nothing; identical bytes prove the value was
never consulted.

**This project's case:** —

## The positive complement: write the gate first, and watch it fail first

A gate written before the fix is calibrated against ground truth; one written after is calibrated
against the fix. Case: a defect report named four broken items; the gate, written first and watched
red on the unfixed tree, named **eight**. The report had undercounted its own defect by half.

**This project's case:** —

## Corollary: never calibrate against the population under test

A baseline drawn from the artifact under test inherits its defects. Case: a metric that normalised
each item against its same-size siblings was blind to two items that were each other's only peer —
and both were defective. Calibrate against an external anchor, or a property that holds by
construction.

**This project's case:** —

### The same error one level up: never calibrate the DETECTOR on the fix's own vocabulary

Case: a census of scripts that "refuse unknown arguments" matched one author's own wording of the
refusal, and filed a script that had refused by name for months under "absorbs". A detector written
in the fix's words finds the fix, not the class. Calibrate it on instances its author did not write.

## A prescribed fix is a hypothesis — the gate falsifies the FIX as much as the defect

Write the gate against the **property that must hold**, never against the fix someone specified.
Case: a brief diagnosed the cause and prescribed a four-step remedy; the property gate showed the
cause was one step further back, and the remedy would not have fixed it. Whoever wrote the task is
not exempt; return FALSIFIED-THE-TASK when the property says so.

**This project's case:** —

## The board runner is itself a system under test

A runner once incremented FAILED on a gate's exit code alone, so a gate that exited 0 while printing
FAIL was tallied as passing — the board printed `12/12 passing` above `G12 FAIL`. A scoreboard may
not trust a status code supplied by the thing it summarises; and a GREEN SUBSET must never exit 0.

**This project's case:** —

## A gate whose failure mode is a HANG is not a red

Case: a sabotage made a shared refusal helper print and not exit; the expected red never came — the
gate's self-entry recursed, spawned grandchildren, and the round hung for 900 s with no verdict. A
hang is a third outcome. Bound every child, guard every recursion, and report NO VERDICT by name.

**This project's case:** —

## Completeness gates: derive the full expected set, never presence-match two artifact-derived lists

If both sides of a completeness check descend from the artifact, they agree with each other about
the missing element. Case: a schedule-completeness gate anchored one half to the source state and
compared the other half between two lists from one upstream — dropping an element from that upstream
left the gate green. Derive the expected set from the source.

**This project's case:** —

## An agent must never perform or simulate a trusted-human event

Where a store's value IS its provenance — a human calibration log, an owner's acceptance, an owner's
verdict on a result — an agent may not produce its entries, not when mechanically possible and not
when instructed. Decline, and say why. A mission's `accepted-by: owner` is such an event.

**This project's case:** —

## Falsify against a disposable copy — never mutate the protected artifact

Case: falsifying "the rules file exists" by moving it aside, running a slow gate, and moving it back;
the command timed out inside the window and the project's laws were left deleted from the tree.
Negative cases run in a scratch worktree or a temp copy, always.

**This project's case:** —

## A one-sided threshold can be propped up by signal the check does not attribute

Case: a visibility floor (`signal / outline >= 0.70`) counted every mark inside a footprint as that
item's, so an item painted over by something else still cleared the floor on borrowed signal.
Attribute what you count, and bound it from both sides.

**This project's case:** —

## A guard must constrain the population the assertion compares — AND exceed the band it defends

A non-vacuity guard answers "is there anything to measure?" before the assertion. It must pin the
SAME population the assertion compares, and its floor must exceed the tolerance it defends — a guard
of `> 0` in front of a ±1 tolerance certifies arithmetic, not agreement.

**This project's case:** —

## The tooling layer: a success message is not evidence that anything changed

Case: an edit script printed "applied" while its anchor (wrong indentation) matched nothing —
`str.replace` returns the original string and the print runs regardless. Assert the anchor exists
before, re-read the bytes after. Applies to every script that reports its own result.

**This project's case:** —

### A string that looks right is not a string that is right — census the bytes, do not read them

Case: an index quoted law headings verbatim so a rename would be one `grep -F` away — and the author
typed a Cyrillic look-alike letter. It rendered and reviewed perfectly, and defeated the grep it was
written for. Census suspicious text by code point, never by eye.

## A scalar is not a shape — settle shape disputes with tables

Three classification arguments in one cycle were each decided from one summary number, and each was
wrong; each was corrected the moment someone printed a table of descriptors. One number, or a prose
noun, is a hypothesis; a table is a measurement.

**This project's case:** —

### Corollary — one descriptor is fragile, and a predicate must be immune to inputs that carry no information

Case: a shape predicate keyed on vertex count read a perfect rectangle as "not a box" because of a
20 mm zero-area spike — a vertex that carried no shape. Strip or ignore degenerate input before a
predicate sees it, and test the predicate on exactly that input.

## The falsification round is the closing move — and it must include the enabling step

A falsification pair around a feature can leave the step that makes the feature meaningful untested.
Sabotage the assertion, the threshold, AND every transform they depend on, one at a time, on a
disposable copy — and report the NULL results (the cuts that did not go red) as loudly as the fires.

**This project's case:** —

## Evidence must prove it came from the build it claims

Case: an "after" screenshot was captured by navigating to the same URL — not a reload — so the page
ran the previous build and the diff was 0.22% of noise, reported as "the feature is not rendering".
Reload unconditionally, read a token you just changed out of the served build, abort on mismatch;
measure by differencing two artifacts that differ only in the thing under test.

**This project's case:** —

## Reporting convention: scope every negative claim

An agent truthfully reported a file "untouched" — true of its own change. Another agent had
legitimately changed it in the same mission; aggregated without its scope, the true claim became a
false one. Say "untouched **by this change**", never bare "untouched".

**This project's case:** —
