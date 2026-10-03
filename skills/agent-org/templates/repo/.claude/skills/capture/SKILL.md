---
name: capture
description: File a link, video, screenshot or pasted text the user sends into the vault as a capture note under vault/Research/captures/, extracted with defuddle (web pages) or the watch skill (YouTube/video), summarised into "what it shows / what we take from it", and linked from the relevant design doc. Use when the user pastes a URL or media as a reference, or says "/capture", "save this", "look at this".
---

# /capture <url | path>

1. Fetch: web page → the `defuddle` skill (fallback `WebFetch`); YouTube / video → the `watch` skill;
   image → the Read tool (vision). Never summarise from the URL text alone.
2. Write `vault/Research/captures/YYYY-MM-DD-<slug>.md` from `vault/Templates/capture.md` with
   `source:` set, the owner's reason in their words if they gave one, and timestamps for video.
3. "What we take from it" must name the module it lands in (a source path) or the design doc
   (`[[Design/...]]`), and produce 1–5 backlog lines. A capture with no landing place says so.
4. Add a `[[Research/captures/...]]` link to the design doc it informs (append under a "References"
   heading; do not rewrite the doc). Run `node scripts/vault-hubs.mjs` so the capture is hub-linked,
   and report the note path and the backlog lines to the user.
