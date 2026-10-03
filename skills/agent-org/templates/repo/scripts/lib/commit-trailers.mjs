// scripts/lib/commit-trailers.mjs — WHAT A COMMIT MESSAGE CLAIMS, AS A PARAGRAPH.
//
// ONE OWNER for a rule every landing gate that grades a commit-message trailer needs
// (today: `scripts/gates/sprawl.mjs`, trailer `EVIDENCE-GROWTH:`), and a rule that was
// got wrong once by measurement rather than by review.
//
// A JUSTIFICATION IS A PARAGRAPH, NOT A LINE. The first version of the sprawl gate
// matched line by line, and graded a real lander's honest six-line `EVIDENCE-GROWTH:`
// paragraph as VACUOUS because every path it named sat on a CONTINUATION line. That is
// `.claude/rules/gate-independence.md` law 4a exactly: a detector written in one
// author's own spelling of the trailer finds that author and misfiles everybody else.
// The paragraph runs from the trailer line to the next blank line or the next trailer,
// which is what a commit message already means by a paragraph.
//
// A STATED CEILING: this has no quote/blockquote/fence awareness. A commit body that
// QUOTES a stale trailer (a revert notice, a `> ` blockquote) is read as a live
// paragraph. Grep-strength, not semantic-strength. Declared, not fixed.

/**
 * Every `<trailer>` PARAGRAPH in a commit message.
 *
 * @param {string} message  the commit object's body
 * @param {string} trailer  e.g. 'EVIDENCE-GROWTH:'
 * @returns {string[]} one entry per paragraph, newlines preserved
 */
export function trailerParagraphs(message, trailer) {
  const body = String(message ?? '').split('\n')
  const out = []
  for (let i = 0; i < body.length; i++) {
    if (!body[i].includes(trailer)) continue
    const para = [body[i]]
    while (i + para.length < body.length) {
      const next = body[i + para.length]
      if (next.trim() === '' || next.includes(trailer)) break
      para.push(next)
    }
    out.push(para.join('\n'))
    i += para.length - 1
  }
  return out
}

/**
 * Whitespace-split, stripped of the punctuation prose wraps a token in.
 *
 * Shared because a gate that grades the RESIDUE of a reason — what is left after the
 * tokens the gate could have written itself are removed — is only as trustworthy as the
 * tokeniser that produced it.
 */
export function tokens(text) {
  return String(text ?? '')
    .split(/\s+/)
    .map((t) => t.replace(/^[`'"([{<]+/, '').replace(/[`'"),.;:\]}>]+$/, ''))
    .filter(Boolean)
}
