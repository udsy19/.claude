// scripts/lib/landing-range.mjs — WHICH COMMITS IS A LANDING GATE GRADING?
//
// ONE OWNER for the question every landing-boundary gate has to answer before it can
// grade anything: given a tip, which commits did this landing bring in? Getting it wrong
// is not cosmetic — a gate that grades the wrong population reports a verdict about
// somebody else's work (`.claude/rules/no-bloat.md`: one derivation, one source).
//
// The rule, and the measurement behind each half:
//
//   TIP IS ON MAIN → "what did the last landing add?" A landing here is a merge, so the
//     range is `HEAD^1..HEAD`: the first-parent step is exactly the work the merge brought
//     in. A non-merge tip on main has no landing to grade and falls through to an EMPTY
//     range, which every caller must treat as a skip (exit 77) and never as a pass.
//
//   TIP IS AHEAD OF MAIN → "what is this branch carrying?" `merge-base..HEAD`. The main
//     ref is NOT used directly: a branch cut days ago is not a descendant of it, so an
//     ancestry guard against the ref itself would refuse every branch. The merge base is
//     the same intent, made ancestor-safe.
//
//   WHY IT IS NOT SIMPLY "HEAD is a merge → HEAD^1": on a branch that merged main, HEAD^1
//     is the branch's own previous tip, so the range became main's incoming landing and
//     the gate graded files the branch never touched. Whether the tip is ON MAIN is
//     therefore asked of git, not of the branch name.
//
// WHAT THIS FILE DOES NOT DO, deliberately: it never refuses and never exits. It RETURNS
// the facts (`base`/`tip` empty, `anc.status`), and the calling gate refuses in its own
// voice — so each gate's refusal wording, and the sabotage cuts anchored on it, stay in
// the gate.
//
// The main branch is `ORG_MAIN_BRANCH` (default `main`); `origin/<main>` is preferred
// when it resolves, because that is what a landing is measured against.

import { spawnSync } from 'node:child_process'
import { noGitEnv } from './git-env.mjs'

export const MAIN_BRANCH = process.env.ORG_MAIN_BRANCH || 'main'

/**
 * git, addressed explicitly with `-C <repo>` and with every GIT_* variable stripped
 * (see scripts/lib/git-env.mjs). Returns stdout, or null when the command failed and
 * `allowFail` is set.
 */
export function gitText(repo, args, { allowFail = false } = {}) {
  const r = spawnSync('git', ['-C', repo, ...args], {
    encoding: 'utf8', env: noGitEnv(), maxBuffer: 256 * 1024 * 1024,
  })
  if (r.status !== 0) {
    if (allowFail) return null
    throw new Error(`git ${args.slice(0, 3).join(' ')} failed (${r.status}): ${(r.stderr || '').trim()}`)
  }
  return r.stdout
}

/** Is `repo` a git repository at all? */
export function isRepo(repo) {
  return gitText(repo, ['rev-parse', '--git-dir'], { allowFail: true }) !== null
}

/**
 * THE DEFAULT BASE for a tip, by the rule at the top of this file.
 *
 * @param {object} o
 * @param {string} o.repo
 * @param {string} o.tipRev
 * @param {(msg:string)=>never} o.refuse  the CALLER's refusal (its name, its exit)
 * @returns {string} a revision expression for the base
 */
export function chooseBaseRev({ repo, tipRev, refuse }) {
  let onMain = null
  for (const ref of [`origin/${MAIN_BRANCH}`, MAIN_BRANCH]) {
    if (!gitText(repo, ['rev-parse', '--verify', `${ref}^{commit}`], { allowFail: true })) continue
    const anc = spawnSync('git', ['-C', repo, 'merge-base', '--is-ancestor', tipRev, ref], { env: noGitEnv() })
    onMain = { ref, yes: anc.status === 0 }
    break
  }
  if (!onMain) refuse(`no base was given and neither origin/${MAIN_BRANCH} nor ${MAIN_BRANCH} resolves in ${repo}, so the range cannot be chosen`)
  const parents = (gitText(repo, ['rev-list', '--parents', '-n', '1', tipRev], { allowFail: true }) ?? '').trim().split(/\s+/)
  const baseRev = onMain.yes && parents.length > 2
    ? `${tipRev}^1`
    : (gitText(repo, ['merge-base', onMain.ref, tipRev], { allowFail: true }) ?? '').trim()
  if (!baseRev) refuse(`no base was given and the merge base of ${onMain.ref} and ${tipRev} could not be computed`)
  return baseRev
}

/**
 * Resolve both ends and ask git whether base really is an ancestor of tip.
 *
 * Returns `{ base, tip, anc }`. `base`/`tip` are '' when the expression does not resolve
 * to a commit; `anc` is the raw `merge-base --is-ancestor` result, so the caller keeps its
 * own `if (anc.status !== 0)` guard and its own wording.
 */
export function resolveRevs({ repo, baseRev, tipRev }) {
  const base = (gitText(repo, ['rev-parse', '--verify', `${baseRev}^{commit}`], { allowFail: true }) ?? '').trim()
  const tip = (gitText(repo, ['rev-parse', '--verify', `${tipRev}^{commit}`], { allowFail: true }) ?? '').trim()
  const anc = base && tip
    ? spawnSync('git', ['-C', repo, 'merge-base', '--is-ancestor', base, tip], { env: noGitEnv() })
    : { status: 1 }
  return { base, tip, anc }
}

/** Every commit in `base..tip`, newest first — from `git rev-list`, never from a log. */
export function rangeCommits({ repo, base, tip }) {
  return (gitText(repo, ['rev-list', `${base}..${tip}`], { allowFail: true }) ?? '').split('\n').filter(Boolean)
}

/**
 * The RAW commit objects for a range, as `{sha, message}`.
 *
 * `git cat-file commit` — the object's own bytes, not a log formatted for a human. A
 * landing gate that grades what a commit SAYS must read the commit, not a report about
 * it (`.claude/rules/gate-independence.md`).
 */
export function rangeMessages({ repo, shas }) {
  return shas.map((sha) => ({
    sha: sha.slice(0, 9),
    message: gitText(repo, ['cat-file', 'commit', sha], { allowFail: true }) ?? '',
  }))
}
