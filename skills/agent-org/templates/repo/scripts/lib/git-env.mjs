// The environment to hand `git` when the repo you mean is the one you NAMED.
//
// `git -C <dir>` changes the working directory. It does NOT override GIT_DIR,
// GIT_INDEX_FILE or GIT_WORK_TREE, and git exports all of those into every hook
// it runs. So a test that builds a scratch repo with `git -C <mkdtemp> init &&
// git -C <mkdtemp> add .` does exactly what it says when you run it by hand, and
// something entirely different from inside a pre-commit hook: `init` re-initialises
// the COMMITTING repo, and `add .` stages the scratch directory into the
// committing repo's index. Measured once as ~3,400 tracked files showing as
// staged-deleted, mid-commit.
//
// Note that `{ ...process.env, GIT_DIR: undefined }` does NOT work: Node
// stringifies the value, so the child sees the literal `GIT_DIR=undefined`. The
// variables must be DELETED from a copy, which is what this does.
//
// The policy is a PREFIX, not a list of names: GIT_QUARANTINE_PATH,
// GIT_OBJECT_DIRECTORY, GIT_ALTERNATE_OBJECT_DIRECTORIES and GIT_CEILING_DIRECTORIES
// all redirect a child too, and a denylist would let tomorrow's variable through.
export function noGitEnv(base = process.env) {
  const env = { ...base }
  for (const k of Object.keys(env)) if (k.startsWith('GIT_')) delete env[k]
  return env
}
