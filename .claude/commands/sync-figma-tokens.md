---
description: Diff the Swift design tokens against Figma, refresh the snapshot, and read the FEEDBACK frames
---

Sync the design tokens between `Design/*.swift` and the Figma spec sheet, and surface any
feedback the user has left in the file.

**Figma file:** `Enhance — Design Tokens`, fileKey `3JAlyYiwLvAf60QmGK33py`
(https://www.figma.com/design/3JAlyYiwLvAf60QmGK33py)

Swift is the source of truth. Figma is derived. An edit made in Figma is a *proposal* — it only
becomes real once it lands in `Design/Colors.swift` (or `Constants`/`Typography`/`Motion`).

## Steps

**1. Check the local export still parses.**

```bash
swift Tools/export-tokens.swift --check
```

A failure here means a token was written in a shape the regex no longer matches — the export is
silently missing something. Fix the pattern in `Tools/export-tokens.swift` before going further;
everything downstream trusts this output.

**2. Diff Swift against the committed snapshot.**

```bash
swift Tools/export-tokens.swift --diff
```

This is what CI runs. If it reports drift, that means Swift has moved away from the last agreed
Figma values — decide with the user which side is right before changing anything.

**3. Read the live Figma file.** Load the `figma-use` skill first (mandatory before `use_figma`),
then read all local variables and text styles and compare them to `swift Tools/export-tokens.swift`.
This catches the case step 2 cannot: the user changing a value in Figma since the snapshot was
captured.

Report differences as `name: Swift <value> vs Figma <value>`. Do **not** silently pick a winner —
a Figma edit is usually a deliberate request, and a Swift edit is usually the shipped truth.
Ask which way to sync when they disagree.

**4. Read the FEEDBACK frames.** Each page has (or may have) a frame named `FEEDBACK` containing a
text layer named `notes`. Read those text layers and surface anything the user has written.

**This is the only way their written feedback reaches you** — an agent can read Figma text layers
but **not** Figma comments, so comments left on the file are invisible. If the notes layer still
holds only its placeholder (`— `), say there is nothing new rather than inventing findings.

**5. Apply what was agreed, then re-sync.**

- Swift changes: edit the token in `Design/`, then re-run `--diff`.
- Figma changes: use `use_figma` to set the variable value.
- Then regenerate `Tools/figma-tokens.json` from the live Figma values and update its
  `capturedAt` date, so CI is checking against something current. A stale snapshot diffs clean
  against a file that has since moved, which is the one failure mode this tooling has.

**6. Run the tests and commit** if anything changed. Token renames are safe while unreferenced;
once Phase 2 migrates the screens, a rename touches call sites too.

## Notes

- Motion is exported but never diffed — Figma has no native motion variable, so comparing it
  would report permanent false drift.
- `Tools/export-tokens.swift` must stay in `Tools/`, not under `Enhance/`. That folder is a
  synchronized group, so any `.swift` file inside it is compiled into the app target and a script
  with top-level statements breaks the build. See LEARNINGS 2026-08-12.
- The Figma Variables REST API is Enterprise-gated and this file is on a Professional plan, which
  is why the CI check diffs a committed snapshot instead of calling Figma live.
