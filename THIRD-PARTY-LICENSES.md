# Third-Party Licenses & Attributions

This project bundles work from several open-source projects. Their licenses and
copyright notices are reproduced below as required. Each component remains under
its **own** license; this project's own `LICENSE` covers only the original
contributions listed at the end.

---

## Foundation — Addy Osmani / `agent-skills` (MIT)

The core skill library, agent personas, slash commands, base hooks
(`session-start`, `sdd-cache-*`, `simplify-ignore`), and the `references/`
checklists are derived from **[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)**.

---

## Anthropic — `frontend-design` (Apache-2.0)

The `frontend-design` skill is from **[anthropics/skills](https://github.com/anthropics/skills)**,
licensed under the Apache License, Version 2.0. The full license text ships
alongside the skill at [`skills/frontend-design/LICENSE.txt`](skills/frontend-design/LICENSE.txt).

**Modifications (per Apache-2.0 §4b):** the skill's `SKILL.md` frontmatter and
heading were adjusted for integration into this collection; the instructional
content is otherwise unchanged.

---

## Next Level Builder — `ui-ux-pro-max` (MIT)

From **[nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)**.
Full text ships at [`skills/ui-ux-pro-max/LICENSE`](skills/ui-ux-pro-max/LICENSE).

```
Copyright (c) 2024 Next Level Builder
```

(MIT terms — see the shared MIT text at the bottom of this file.)

---

## Vercel — React/UI skills (MIT)

`web-design-guidelines`, `react-best-practices`, `composition-patterns`, and
`react-native-skills` are from **[vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills)**.
The upstream repository declares the MIT License (in its README and each skill's
frontmatter) but does not ship a standalone `LICENSE` file; the MIT terms are
reproduced below.

```
Copyright (c) Vercel, Inc.
```

---

## AccessLint — `accesslint-scan` / `accesslint-audit` / `accesslint-diff` (MIT)

From **[accesslint/claude-marketplace](https://github.com/accesslint/claude-marketplace)**.
The upstream repository declares the MIT License (in its README) but does not
ship a standalone `LICENSE` file; the MIT terms are reproduced below.

```
Copyright (c) AccessLint
```

---

## ⚠️ bencium — `controlled-ux-designer` / `innovative-ux-designer` (NO LICENSE)

These two skills are from **[bencium/bencium-claude-code-design-skill](https://github.com/bencium/bencium-claude-code-design-skill)**,
which **does not declare any license**. Under default copyright law that means
**all rights reserved**: the original author retains all rights and has not
granted redistribution permission.

They are included in this repository **without a license**. If you reuse,
fork, or redistribute them, obtain permission from the original author first.
Credit and copyright remain entirely with bencium.

---

## MIT License (applies to the MIT-licensed components above)

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The Apache-2.0 component (`frontend-design`) is governed by its own bundled
license at [`skills/frontend-design/LICENSE.txt`](skills/frontend-design/LICENSE.txt).
