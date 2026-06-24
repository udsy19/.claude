#!/bin/bash
# skill-router.sh — UserPromptSubmit hook.
#
# Matches the user's prompt against the agent-skills discovery flowchart and
# injects routing hints, so the right skills are applied reflexively on every
# turn — without the user invoking a slash command. This is what turns the
# skill library from a passive reference into a thinking process: the routing
# decision happens at the moment of every request, not once at session start.
#
# Tuned to be aggressive but smart: broad synonym coverage so real intent is
# rarely missed, but disambiguated so incidental nouns ("login button",
# "this endpoint is slow") don't drag in the wrong skill. Generic build verbs
# only fire when paired with a code-shaped object. Emits nothing on a weak/no
# match, skips deliberate slash-command prompts, and never blocks the prompt
# (always exits 0). On UserPromptSubmit, stdout on exit 0 is added to context.
#
# Intentionally NOT using `set -e`: every match line is a conditional, and a
# non-match must never abort the script and drop the routing pass.
#
# Dependencies: jq (degrades to a silent no-op if absent).

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

if [ -t 0 ]; then INPUT="{}"; else INPUT=$(cat); fi
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0

# Deliberate slash-command invocations are already explicit — don't second-guess them.
case "$PROMPT" in /*) exit 0 ;; esac

# Lowercase for matching.
P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

HITS=""
add() { HITS="${HITS}$1"$'\n'; }
m()   { printf '%s' "$P" | grep -Eq "$1"; }

# ── Define ──────────────────────────────────────────────────────────────────
m '\b(not sure what|figure out what|don.?t know what|help me (decide|figure)|what (do|should) (i|we) (want|build|need)|where (do|should) (i|we) (start|begin)|kick.?off)\b' \
  && add 'interview-me — surface what you actually want before building'
m '\b(brainstorm|ideate|ideation|ideas?|options|alternatives|approaches|explore (options|ideas|approaches)|pros and cons|trade.?offs?|weigh (the )?options)\b' \
  && add 'idea-refine — diverge then converge on the approach'
m '\b(spec|specification|requirements?|acceptance criteria|user stor(y|ies)|scope (this|the|out)|define (what|the)|new (project|feature|service|app|product)|from scratch|greenfield)\b' \
  && add 'spec-driven-development — requirements + acceptance criteria before code'

# ── Plan ────────────────────────────────────────────────────────────────────
m '\b(break ?down|plan|roadmap|milestones?|task list|decompose|step.?by.?step|sequence the|order of work|how (do|should) (i|we) approach)\b' \
  && add 'planning-and-task-breakdown — decompose into small verifiable tasks'

# ── Build ───────────────────────────────────────────────────────────────────
# Anti-bloat: introducing a new symbol → search for existing code first.
m '\b(add|create|make|build|implement|write|introduce|extract|new)\b[^.!?]{0,30}\b(helper|util|utility|function|method|class|component|type|interface|schema|endpoint|route|prompt|module|fixture|hook|service|file)\b' \
  && add 'pre-edit-scan — search for existing code before writing (no duplicates, no dead code)'
{ m '\b(extract (this|it) (in)?to|wrap (this|it) in a function|pull (this|it) (out )?into)\b'; } \
  && add 'pre-edit-scan — search for existing code before writing (no duplicates, no dead code)'
# Generic build intent: a build verb paired with a code-shaped object (smart gate).
m '\b(implement|develop|code up|wire up|hook up|build out|stand up)\b' \
  && add 'incremental-implementation — thin vertical slices, verify each'
m '\b(add|create|make|build|write|set up|integrate)\b[^.!?]{0,25}\b(feature|functionality|function|method|class|module|component|endpoint|service|integration|screen|page|flow|handler|route|model|migration|script)\b' \
  && add 'incremental-implementation — thin vertical slices, verify each'
m '\b(ui|ux|frontend|front.end|css|tailwind|stylesheet|styling|component|layout|accessibilit|a11y|responsive|design system|dark mode|animation)\b' \
  && add 'frontend-ui-engineering — production UI with accessibility'
m '\b(landing page|marketing (page|site)|hero section|portfolio site|redesign|look and feel|make it (look|feel) (good|better|nicer|beautiful|polished|stunning|premium|distinctive|modern)|aesthetic|visual (design|identity)|design direction|colou?r (palette|scheme)|theme the|style the (page|site|ui|app)|brutalis|glassmorph|neumorph|typograph|font pairing|visually (distinctive|appealing|striking))\b' \
  && { add 'frontend-design — distinctive, production-grade visual design (anti AI-slop)'
       add 'ui-ux-pro-max — searchable design DB: 50+ styles, palettes, fonts, UX rules'; }
m '\b(user experience|\bux\b|interaction design|onboarding|progressive disclosure|user flow|usability|micro.?interaction|empty state|forgiveness pattern|error (recovery|handling) (flow|ux))\b' \
  && add 'innovative-ux-designer — deep UX fundamentals (also controlled-ux-designer)'
m '\b(re.?render(s|ing)?|usememo|usecallback|react\.?memo|bundle size|barrel (file|import)|fetch(ing)? waterfall|next\.?js (perf|performance|optimi)|server components?|\brsc\b|hydrat)\b' \
  && add 'react-best-practices — React/Next perf: waterfalls, bundle, re-renders'
{ m '\breact\b[^.!?]{0,25}\b(slow|sluggish|janky|performance|optimi)' || m '\b(slow|sluggish|janky|performance|optimi)[a-z ]{0,25}\breact\b'; } \
  && add 'react-best-practices — React/Next perf: waterfalls, bundle, re-renders'
m '\b(boolean props|compound component|component (api|architecture|library)|prop drilling|render props|forwardref|headless component|polymorphic|variant (prop|component)|too many props)\b' \
  && add 'composition-patterns — component architecture, compound components'
m '\b(react native|react.native|\bexpo\b|flatlist|flashlist|reanimated|nativewind|mobile (app|ui|screen|performance)|ios and android|gesture handler|safe area)\b' \
  && add 'react-native-skills — mobile UI performance + patterns'
m '\b(api design|design (an?|the) (api|interface|endpoint|schema)|rest api|graphql|openapi|public api|api contract|interface (design|contract)|versioning the api)\b' \
  && add 'api-and-interface-design — stable contracts, clear versioning'
m '\b(official docs?|api reference|library version|verify against|latest (version|api)|check the docs|read the docs|per the documentation)\b' \
  && add 'source-driven-development — verify against official docs before coding'
m '\b(best way|best practice|recommended (way|approach|library|tool|pattern)|which (library|framework|tool|approach|one)|should i use|x or y|is it true|does .+ support|what.?s the (right|best|recommended)|current (best|approach|standard)|standard (way|approach)|state of the art)\b' \
  && add 'anti-hallucination — research the best approach + verify before deciding'
m '\b(are you sure|is (this|that) (correct|right|accurate|true)|verify (this|that|the)|fact.?check|double.?check (this|that|the claim)|did you (verify|check)|cite (your )?source|where.?s the source)\b' \
  && add 'anti-hallucination — verify claims against sources, mark uncertainty'
m '\b(high.stakes|unfamiliar code|risky change|legacy|production.critical|not sure (if|whether) (this|it).?s (right|correct)|double.check (the|my) (approach|design)|am i (doing|approaching) this right)\b' \
  && add 'doubt-driven-development — cross-examine non-trivial decisions in-flight'
m '\b(understand the (codebase|code|repo|project)|where (is|are|does)|how does (this|the) .* work|load context|too much context|which files|map (out )?the code|get up to speed|trace through)\b' \
  && add 'context-engineering — load the right context at the right time'
m '\b(token (efficien|budget|cost|usage|spend)|reduce (context|tokens)|too many tokens|context (bloat|window)|expensive context|save tokens|context efficien)\b' \
  && add 'context-engineering — token & tool-use efficiency (read narrow, delegate, lean output)'

# ── Verify ──────────────────────────────────────────────────────────────────
m '\b(bug|broken|error|throws?|throwing|exception|crash(es|ed|ing)?|stack ?trace|traceback|regression|not working|doesn.?t work|isn.?t working|won.?t (work|run|build|start)|fail(s|ed|ing)?|unexpected|wrong (output|result|value|behaviou?r)|why (is|does|won|isn|doesn).*( |.?t)|debug|reproduce)\b' \
  && { add 'debugging-and-error-recovery — reproduce → localize → fix → guard'
       add 'test-driven-development — write a failing test that locks the fix'; }
m '\b(test|tests|tdd|coverage|unit test|integration test|write tests?|add tests?|test case)\b' \
  && add 'test-driven-development — failing test first, then make it pass'
m '\b(browser|e2e|end.to.end|devtools|playwright|puppeteer|cypress|chrome|headless|in the browser|click (the|through))\b' \
  && add 'browser-testing-with-devtools — verify runtime behavior in a real browser'

# ── Review ──────────────────────────────────────────────────────────────────
m '\b(code review|review (this|the|my|these|it)|pull request|before (we |i )?merge|ready to merge|is (this|it) (good|ok|clean|solid)|feedback on (my|the) code|look over (my|the) code)\b' \
  && add 'code-review-and-quality — five-axis review before merge'
m '\b(simplify|refactor|too complex|over.?(complicated|engineered)|convoluted|cleaner|clean (this |it |the code )?up|reduce complexity|tidy|messy|hard to read|spaghetti)\b' \
  && add 'code-simplification — reduce complexity, preserve behavior'
m '\b(security|secure|vulnerab|xss|sql injection|csrf|ssrf|injection|authentication|authorization|secrets?|owasp|harden|sanitiz|escap(e|ing) input|rate limit|exploit|attack surface|threat)\b' \
  && add 'security-and-hardening — input validation, least privilege, OWASP'
m '\b(slow|performance|perf|optimi[sz]e|latency|n\+1|memory leak|bottleneck|too slow|speed (it|this) up|faster|profil(e|ing)|throughput|sluggish)\b' \
  && add 'performance-optimization — measure first, optimize what matters'
m '\b(accessibilit|a11y|wcag|screen reader|aria|contrast ratio|colou?r contrast|keyboard nav|focus (state|ring|visible|management)|alt text|axe.?core|section 508|ada complian)\b' \
  && { add 'accesslint-audit — find/fix WCAG 2.2 issues (needs accesslint MCP + Chrome)'
       add 'web-design-guidelines — 100+ web interface rules incl. accessibility'; }
m '\b(review (my|the|this) (ui|interface|frontend|component|page|design)|audit (my|the|this)? ?(ui|page|interface|frontend|design)|ui (review|audit|qa)|interface guidelines|design (review|qa))\b' \
  && add 'web-design-guidelines — audit UI against 100+ interface rules'

# ── Ship ────────────────────────────────────────────────────────────────────
m '\b(commit|worktree|work.?tree|branch|pull request|\bpr\b|parallel (feature|work)|multiple features|in parallel|isolate (this|the) (work|feature|change)|save (this|it|the work) to git)\b' \
  && add 'autonomous-git-workflow — commit continuously, parallelize via worktrees'
m '\b(rebase|merge conflict|version bump|changelog|semver|tag (a |the )?release|squash|cherry.?pick|clean (up )?(the )?history)\b' \
  && add 'git-workflow-and-versioning — atomic commits, clean history'
m '\b(\bci\b|\bcd\b|pipeline|github actions|gitlab ci|circleci|jenkins|build pipeline|automate (the )?(build|deploy|test|release))\b' \
  && add 'ci-cd-and-automation — automated quality gates on every change'
m '\b(deprecat|migrat|sunset|retire|backward.compat|breaking change|phase out|upgrade path|move users|cut over)\b' \
  && add 'deprecation-and-migration — retire + migrate users safely'
m '\b(document|\bdocs\b|readme|adr|decision record|write.?up|explain (the )?(design|decision|architecture))\b' \
  && add 'documentation-and-adrs — capture the why, not just the what'
m '\b(log(ging|s)?|metrics?|tracing|trace|observability|telemetry|alert(s|ing)?|monitor(ing)?|instrument|sentry|datadog|prometheus|grafana)\b' \
  && add 'observability-and-instrumentation — structured logs, RED metrics, traces'
m '\b(deploy|launch|release|rollout|roll.?back|go.live|ship (it|this)|production (deploy|release)|cut a release)\b' \
  && add 'shipping-and-launch — pre-launch checklist, monitoring, rollback'
m '\b(ship (fast|small|often|early|incrementally)|move fast|small batch(es)?|in small|all at once|reduce wip|cycle time|lead time|\bmvp\b|bias to ship|get it out|iterate in prod|continuous delivery|deploy (often|frequently)|big.bang)\b' \
  && add 'ship-fast — small batches, low WIP, deploy often behind flags'
m '\b(remember (this|that|to)|note (this|that) for|for (next time|the future|future reference|later)|keep track of|don.?t forget|save this (for|to memory)|make a note|persist (this|that)|add (this )?to (claude\.?md|memory))\b' \
  && add 'memory-discipline — persist durable learnings to native memory (right home, stay concise)'

[ -z "$HITS" ] && exit 0

# Dedupe by skill name (first whitespace token), preserving lifecycle order.
DEDUPED=$(printf '%s' "$HITS" | awk 'NF && !seen[$1]++')
[ -z "$DEDUPED" ] && exit 0

TOTAL=$(printf '%s\n' "$DEDUPED" | grep -c .)
printf '[skill-router] This request maps to the agent-skills below. Apply them as workflows (not suggestions); when several apply, run them in lifecycle order. Confirm against the full discovery flowchart before acting:\n'
printf '%s\n' "$DEDUPED" | head -6 | sed 's/^/  • /'
if [ "$TOTAL" -gt 6 ]; then
  printf '  • (+%s more — consult the full flowchart)\n' "$((TOTAL - 6))"
fi
exit 0
