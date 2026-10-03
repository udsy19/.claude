// scripts/lib/argv.mjs — ONE refusal, for every entry point that has a contract.
//
// An entry point that does not read its own command line answers every request
// with the same bytes and the same exit 0, so the operator's ask is discarded
// and the success message is evidence of nothing
// (`.claude/rules/gate-independence.md`, "a success message is not evidence that
// anything changed"). The shape is the one every script in this repo uses —
// name the offending token, say what IS accepted, exit 2 — so there is one
// refusal here and not a family of them.

/**
 * Refuse anything not in `accepts`. Exits 2 with a named token; returns
 * normally when every token is understood.
 *
 * @param {string[]} argv     process.argv.slice(2)
 * @param {object}   contract
 * @param {string}   contract.script   how the script names itself in messages
 * @param {string[]} contract.accepts  every flag the script implements ([] = takes nothing)
 * @param {string[]} contract.valued   the subset of `accepts` that consume the NEXT token
 * @param {string}   [contract.takes]  the POSITIONAL half of a contract that has one,
 *   in the words the caller wants printed ("a row id"). A contract that is "a flag OR a
 *   positional" must say both, or the refusal is a true list of flags and a false
 *   statement of what the script accepts. The caller keeps ownership of the positional.
 */
export function refuseUnknownArgv(argv, { script, accepts = [], valued = [], takes = null }) {
  const unknown = []
  const starved = []
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i]
    if (!accepts.includes(tok)) { unknown.push(tok); continue }
    if (valued.includes(tok)) {
      const value = argv[i + 1]
      // A flag standing where a value should be is a starved flag, not a value.
      if (value === undefined || accepts.includes(value)) starved.push(tok)
      else i += 1
    }
  }
  if (unknown.length === 0 && starved.length === 0) return

  const say = (m) => console.error(`${script}: ${m}`)
  if (unknown.length) {
    say(`unrecognised argument: ${unknown[0]}`)
    if (unknown.length > 1) say(`also unrecognised: ${unknown.slice(1).join(' ')}`)
  }
  for (const flag of starved) say(`${flag} expects a value after it`)
  if (accepts.length) say(`accepts: ${accepts.join(' ')}${takes ? `, or ${takes}` : ''}`)
  else say(takes ? `accepts: ${takes}` : 'takes no arguments')
  process.exit(2)
}
