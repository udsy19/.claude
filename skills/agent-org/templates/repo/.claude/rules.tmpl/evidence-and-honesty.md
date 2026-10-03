# Evidence and honesty

How an agent REPORTS. (How a gate CHECKS is `gate-independence.md`; this is the same law applied to
the words an agent hands upward.)

- **A claim is not evidence; an artifact is.** Evidence is a command + its exit code + an artifact
  path. When a report and a screenshot disagree, the screenshot wins.
- **Report faithfully.** Failures come with their output; skips are named as skips; "done and
  verified" is said only when it is. A partial result is reported as PARTIAL, with what is missing.
- **Report the nulls.** What you sabotaged that did NOT go red is the most valuable line in a report.
- **Numbers carry provenance:** the script, gate or session that produced them, and the commit they
  were measured on. A number carried forward from an earlier pass is re-derived, not copied.
- **Never print, commit or paste a secret.** Owners type secrets into their own terminals.
