# Design System — audit and phased plan

> Status: **Phase 1 shipped 2026-08-12.** Phases 2-3 remain proposed. This document is the plan of
> record for turning Enhance's partial design layer into a real, enforceable design system.
>
> **Phase 1 found four errors in this plan**, every one of which would have been a silent visual
> change rather than a build failure. They are written up at each affected step below, and the
> pattern is worth carrying into Phase 2: *measure the literal before swapping it*. A token
> migration is only safe when the token provably equals what it replaces, and four of these did
> not.
>
> Companion docs: [FEATURE-THEMES.md](FEATURE-THEMES.md) (the light/dark + colour-scheme feature
> that sits *on top* of this work), [LEARNINGS.md](LEARNINGS.md) (rules discovered the hard way),
> [ROADMAP.md](ROADMAP.md) (where this is scheduled).

Scope: the app's UI chrome — tokens, primitives, and the screens that compose them. Effect and
shader colour math under `Services/Animators/**` is **out of scope**; those literals are image
processing, not design.

---

## 1. Where we are today (audit, 2026-08-10)

**Maturity: 1.5 / 5 — "emerging / partial."** A `Design/` token folder and a `Components/`
library exist and are used, but the token layer is shallow (essentially one colour token), most
values are literals at the call site, and there is no theming, accessibility, or validation
infrastructure. This matches the independent finding in FEATURE-THEMES.md: *"there is no design
system to extend."*

What is genuinely shared and works:

- **Typography** is tokenised — `Design/Typography.swift` defines nine `Font.silkscreen*` roles,
  used 33× against only 3 raw `.system`/`.custom(size:)` calls.
- **Accent colour** is centralised — `Color.enhanceMint` (`0x60FFA8`) in `Design/Colors.swift`,
  with a docstring recording that it replaced five duplicate definitions.
- **Spacing / animation constants** — `AppConstants.Spacing` / `.Animation` / `.Layout` in
  `Design/Constants.swift`, used ~42×, including thoughtful adaptive helpers
  (`effectCardSize(forControlsHeight:)`, `parameterRowHeight(forPanelHeight:rowCount:)`).
- **Press interaction** is one primitive — `enhanceButtonAnimation()` / `EnhancePressButtonStyle`
  in `Design/ButtonModifiers.swift`.
- **Haptics** are tokenised — `Services/HapticService.swift` (`light/medium/heavy/selection/
  success/error`).

What is missing or inconsistent:

| Category | Finding | Evidence |
|---|---|---|
| Colour tokens | Only `enhanceMint` exists. All neutrals/surfaces are literals | `0x171717/0x202020/0x1C1815/0x323232/0x120E0A/0xD9D9D9` across ~8 files |
| Radius tokens | `16` is the de-facto card/pill radius but is not a token; used in 21 places | `SegmentedBar`, `GifGridItem`, `ShowcaseCarousel`, `GalleryView`, `EditorView`, `SettingsView` |
| Typography leaks | Screens bypass the font tokens with raw `.custom("Silkscreen…", size:)` | `SettingsView` (4), `GalleryView` (10), `EditorView` (2), `BottomSheet` (2), `EffectDetailPanel` (1), `ParameterSliderRow` (1) |
| Secondary colours | Greens invented per call-site, none in `Colors.swift` | `AppButton` `0.20,0.411,0.298`; `SegmentedBar` `100/148/122`; `GifBadge` `0,0.51,0.298` |
| Motion | The spring `response 0.3, damping 0.6/0.8` is re-typed inline in ~11 places | `ButtonModifiers`, `AppButton`, `GalleryView`, `ShowcaseCarousel` |
| Surface duplication | The `0x202020` + radius-16 "pill" is hand-rolled 8 times in feature files | `EditorView.saveShareButtons` ×1, `EditorView.saveSheetContent` ×2, `GalleryView:71/265/445/458/471` |
| Component APIs | `AppButton` uses 4 style booleans; `CircleButton` hard-codes the glyph `"X"` and a 62×60 frame | `Components/AppButton.swift`, `Components/CircleButton.swift` |
| Light/dark | Dark-only via a single `.preferredColorScheme(.dark)`; `AccentColor.colorset` is an empty stub; dead theme scaffolding never rendered | `GalleryView.swift:59`, `SettingsView.swift:53` |
| Accessibility | **Zero** `accessibilityLabel`/traits; **zero** Dynamic Type / `@ScaledMetric`; fixed-pt bitmap font | whole app |
| Validation | No SwiftLint, no CI, no snapshot/visual-regression tests; 6 of 19 components have previews | repo root, `.github/` |

**The core opportunity:** almost every gap is a literal that *should* be a token, and the app's
own dominant pattern teaches a coding agent to keep writing literals. Closing this makes the app
both consistent and safe for agents to extend.

### How big is it, exactly *(re-measured 2026-08-12)*

FEATURE-THEMES claims "~340 colour literals across ~22 files". **Both numbers are wrong, and the
file count — the one that sets migration scope — is understated.** Method, so this can be
re-run rather than argued about:

```bash
cd Enhance
PAT='0x[0-9A-Fa-f]{6}|Color\(red:|\.white|\.black'
grep -rEno "$PAT" --include="*.swift" . | grep -v 'Services/Animators/' | wc -l   # occurrences
grep -rEl "$PAT" --include="*.swift" . | grep -v 'Services/Animators/' | wc -l    # files
```

| Scope | Occurrences | Files |
|---|---|---|
| UI chrome (excludes `Services/Animators/**`, which is image processing) | **178** | **27** |
| Everything | 236 | 43 |

Concentration matters more than the total: `EditorView` (37), `GradientViews` (32) and
`GalleryView` (25) hold **more than half** of the UI-chrome literals between them, so Phase 2's
value is front-loaded into three files.

Narrower counts, for the specific Phase 1 swaps:

| What | Count | Files |
|---|---|---|
| Hex literals `0xNNNNNN` | 20 | 8 |
| Inline `.custom("Silkscreen…")` | 28 | 7 |
| Numeric `cornerRadius:` | 32 | 10 |
| `cornerRadius: 16` specifically | 21 | 6 |
| Inline spring `response:` | 16 | 5 |

> **A note on the exclusion.** `Services/Animators/**` is 58 occurrences across 16 files and is
> deliberately out of scope — those are effect colour maths, not design. A lint rule added in
> Phase 3 must carry the same exclusion or it will fail on RISO's paper colour and LAZER EYES'
> glow.

---

## 1b. Keeping Figma in sync *(added 2026-08-12)*

There is a Figma spec sheet — **Enhance — Design Tokens** — carrying the colour variables, the
Silkscreen text styles, the radius scale, the shipped components and the open questions.

**Swift is the source of truth; Figma is derived.** That direction is deliberate: a derived file
cannot drift, whereas two authored copies always will. Edits made in Figma are *proposals* — change
the value there, then change `Design/Colors.swift` to match, then re-run the sync.

```bash
swift Tools/export-tokens.swift            # tokens as JSON
swift Tools/export-tokens.swift --check    # exit 1 if a token pattern stopped matching
```

`Tools/export-tokens.swift` parses `Design/*.swift` and emits every token as JSON. It parses rather
than imports because it runs as a plain script with no app target — the trade is that a token
written in an unexpected form would be silently *missed*, which is why the script carries expected
counts per kind and fails when one drops.

**It must live in `Tools/`, not under `Enhance/`** — that folder is a synchronized group, so any
`.swift` file inside it is compiled into the app. See LEARNINGS 2026-08-12.

Feeding the JSON into Figma and diffing is currently a manual step (an agent with the Figma MCP
server can do it). **Last run: 2026-08-12 — 28 checkable tokens, zero drift, nothing extra on
either side.** Motion is exported but not verifiable; Figma has no native motion variable.

> **Code Connect was considered and rejected.** It maps *components* to code snippets for Dev Mode
> handoff — it does not sync token values, is one-directional, and reports no drift. It also
> requires an Organization or Enterprise plan (this file lives on a Professional team) and
> components published to a team library.

---

## 2. Principles for the migration

1. **Phases 1–2 are pure refactors with zero intended visual change.** Every new token equals the
   exact literal it replaces (`surfaceRaised == 0x202020`, `radius.card == 16`). The acceptance
   test is strict: the app renders pixel-identical before and after.
2. **Theming (light mode) is out of scope here.** It is Phase 21 / FEATURE-THEMES.md. This work
   builds the substrate it needs, without shipping it. Tokens stay semantic so a theme can later
   supply per-scheme values.
3. **Reuse before building.** Prefer routing existing components through tokens over inventing new
   ones. Only one new primitive (`Surface`) is introduced, and only because it removes the single
   biggest duplication.
4. **Effect/shader colour math is exempt.** `Services/Animators/**` literals are pipeline values,
   not chrome, and must not be tokenised.

---

## 3. Phased plan

```
Phase 1 (tokens, additive)  ──►  Phase 2 (migrate onto tokens / Surface)  ──►  Phase 3 (enforce + validate)
   self-contained                 needs P1 tokens                              needs P2 to be literal-free
```

Ship each phase as its own PR; within a phase, one commit per file group so reverts stay surgical.

### Phase 1 — Token & component standardization (low-risk, additive)

**Objective:** complete the token layer and route existing components through it via 1:1
literal→token swaps. No new primitives, no feature-file restructuring.

**1a — extend the token layer**

| File | Change |
|---|---|
| `Design/Colors.swift` | Add surface/neutral tokens equal to today's literals: `background`=`0x171717`, `surfaceRaised`=`0x202020`, `surfacePanel`=`0x1C1815`, `surfaceActive`=`0x323232`, `onAccent`=`0x120E0A`, `hairline`=`white.opacity(0.04)`, `toggleTrack`=`0xD9D9D9`, `segmentSelected`=`rgb(100,148,122)`. Keep `enhanceMint`. |
| `Design/Constants.swift` | Add `CornerRadius.card = 16` (the radius used in 21 places). Keep `standard 8 / large 12 / circle 100` and `Layout.panelCornerRadius 20`. |
| `Design/Typography.swift` | Add the two missing roles call sites use: `silkscreenSectionTitle` = Bold 16, `silkscreenLabel` = Regular 16. |
| `Design/Motion.swift` *(new)* | Named springs: `press` (response 0.3, damping 0.6), `panel` (0.3, 0.8), `carousel` (0.35, 0.85). |

**1b — route shared components through the tokens (1:1, no visual delta)**

- `Components/ParameterSliderRow.swift:87` `0x120E0A` → `.onAccent`; `:86` inline font →
  **`.silkscreenControlEmphasis`**, *not* `.silkscreenControl`. The "verify Bold vs Regular" note
  was right to exist: the knob is **Bold** 13 and `silkscreenControl` is Regular 13, so the swap
  as written would have de-emphasised the one number the user reads while dragging. ✓ done
- `Components/EffectCardView.swift:92` `0x323232` → `.surfaceActive`, `white.opacity(0.04)` → `.hairline`.
- `Components/EffectDetailPanel.swift:61` `0x1C1815` → `.surfacePanel`; `:84` inline font → `.silkscreenTitle`.
- `Components/SegmentedBar.swift:41/45/53` radius → `.card`; selected green → `.segmentSelected`.
- `Components/BottomSheet.swift:41/46` inline fonts → `.silkscreenSectionTitle` / `.silkscreenTitle`.
- `Components/GifGridItem.swift:52/54/59`, `Components/ShowcaseCarousel.swift:103` radius → `.card`; `ShowcaseCarousel.swift:155` spring → `Motion.carousel`.
- `Design/ButtonModifiers.swift:11/33`, `Components/AppButton.swift:43` springs → `Motion.press`. ✓ done
- `Components/AppButton.swift:36` → `.buttonSecondary`, `Components/GifBadge.swift:13` →
  `.badgeGreen`. ✓ done — the two per-call-site greens the audit flagged.
- **`Components/AppButton.swift:29` was left alone.** The plan maps its `Color(red: 0.09, …)`
  foreground to `.onAccent`, but 0.09 grey is ≈ `0x171717` and `onAccent` is `0x120E0A` — a
  neutral dark grey against a warm near-black. The app has *two* different "dark content on a
  light fill" colours; converging them is a design decision, not a Phase 1 swap.

**Dependencies:** none — self-contained, mergeable alone.

**Acceptance criteria:**
1. Builds clean in Xcode, no new warnings.
2. **Visual diff = zero** on Gallery, Editor, detail panel, Settings (before/after screenshots).
3. `EnhanceTests` pass (all logic, unaffected).
4. `grep` confirms migrated literals gone from the touched component files.

**Rollback:** each sub-step is its own commit; tokens equal old literals, so any revert restores
byte-identical rendering. Worst case, `git revert` the Phase-1 range — nothing depends on it yet.

### Phase 2 — Migrate the most-duplicated UI patterns

**Objective:** eliminate the raised "pill/card" surface duplication and the inline Silkscreen
fonts in screens. Introduce one primitive.

**2a — `Components/Surface.swift` (new):** a `ViewModifier` + `.surface(_ style:)` extension.
Params: fill (`.raised`=`surfaceRaised`, `.panel`, `.active`), `opacity`, `cornerRadius`
(default `.card`). Wraps `RoundedRectangle(cornerRadius:.card, style:.continuous).fill(...)`.

**2b — migrate inline pills/panels onto `Surface`**

- `Features/Editor/EditorView.swift` — three `0x202020.opacity(0.8)` + radius-16 pills →
  `.surface(.raised, opacity: 0.8)`. **Anchored by symbol, not line**: one in
  `saveShareButtons`, two in `saveSheetContent`. *(These were `:726/765/781` when the plan was
  written and are `:1124/1162/1178` today — text overlays rewrote the file in between. Re-find
  them with `grep -n '0x202020' Features/Editor/EditorView.swift` rather than trusting either
  number.)*
- `Features/Gallery/GalleryView.swift:71 / 265 / 445 / 458 / 471` — `0x202020` pills (`:71` at `.opacity(0.95)`) → `.surface(.raised)`.
- `Features/Gallery/GalleryView.swift:45 / 417` — `0x171717` full-bleed → `.background`.
- Remaining radius-16 clip-shapes in `GalleryView` (`:198/252/264/429/444/457/470`) and `EditorView` (`:694/743`) → `CornerRadius.card`.

**2c — migrate remaining inline typography in screens**

- `Views/SettingsView.swift:43/56/67/82` fonts → tokens; `:141` `0xD9D9D9` → `.toggleTrack`.
- `Features/Gallery/GalleryView.swift` (10 sites: `:136/164/170/192/231/246/259/291/302/423`) → tokens.
- `Features/Editor/EditorView.swift:219/252` → `.silkscreenSectionTitle` / `.silkscreenTitle`.

**2d — tighten two component APIs (recommended; can defer to keep 2 swaps-only)**

- `Components/AppButton.swift`: collapse the 4 style booleans into an `AppButton.Style` enum, keeping the current initializer as a `@available(*, deprecated)` shim so no call site breaks. Foreground `0.09…` → `.onAccent`.
- `Components/CircleButton.swift`: parameterize the hard-coded `"X"` glyph (default keeps `"X"`), so the Editor close and the panel `"<"` can converge later.

**Dependencies:** requires Phase 1 tokens. Do not start until Phase 1 merges.

**Acceptance criteria:**
1. Builds clean; tests pass.
2. **Visual diff = zero** across all migrated screens (core guardrail — refactor, not redesign).
3. `grep -rn "0x202020\|cornerRadius: 16\|.custom(\"Silkscreen" Features Views` returns only intentional exceptions (ideally none).
4. `AppButton` legacy call sites still compile via the shim.

**Rollback:** `Surface` is additive; migration commits are per-file and revert-safe (feature
reverts don't touch the primitive). If `Surface` regresses, revert 2b–2c first (restores inline
literals, still correct), leaving 2a dormant.

**Risk note:** the three `EditorView` pills use `.opacity(0.8)` where Gallery's use `0.95`/`1.0`.
The `Surface` API must expose `opacity` so these stay distinct — do not collapse them.

### Phase 3 — Documentation, previews, linting, visual & a11y checks

**Objective:** lock the gains in with enforcement and validation so drift (and agents) cannot
reintroduce literals.

**3a — enforcement**

- `.swiftlint.yml` *(new)*: `custom_rules` making **errors** of `Color(red:` / `Color(hex:` / `.custom("Silkscreen` **outside `Enhance/Design/`**, excluding `Services/Animators/**` (legitimate effect colour math).
- `.github/workflows/ci.yml` *(new)*: macOS runner running `swiftlint --strict` + `xcodebuild test`. None exists today — this is the first automated gate.

**3b — component catalog & previews**

- `DesignSystem/Catalog/ComponentGallery.swift` *(new)*: one `#Preview` exercising every primitive's variants/states.
- Add `#Preview`s to the 13 of 19 components that lack them.

**3c — visual-regression & accessibility checks**

- Add **swift-snapshot-testing** (SwiftPM), baseline the catalog + 4 core screens, wire into CI. This makes the "zero visual diff" guardrail machine-checkable going forward.
- **Accessibility baseline** (first pass; currently zero): `accessibilityLabel` on icon-only controls (`CircleButton`, close buttons, carousel items); snapshot tests at `AX5`/`XXL` Dynamic Type to surface the fixed-pt-font clipping. Full Dynamic Type support is a larger follow-up.

**3d — author the guidance docs**

- Promote this file into the token reference once Phases 1–2 land (fill in real token names/values).
- `AGENTS.md` at repo root — the AI contribution rules in §5, now enforceable because 3a exists.

**Dependencies:** 3a's lint rules assume Phases 1–2 removed the literals. Snapshot baselines
should be captured after Phase 2 so they encode the migrated (but visually identical) state.

**Acceptance criteria:**
1. `swiftlint --strict` passes, and **fails** on a deliberately-added `Color(hex:)` in a feature file.
2. CI green on a PR; red when a snapshot changes.
3. Catalog renders every primitive; baselines committed.
4. VoiceOver reads a real label (not "button") on the Editor close control.

**Rollback:** entirely additive tooling. Disable a rule in `.swiftlint.yml`, remove the workflow,
or delete baselines to reset. No runtime code depends on Phase 3.

---

## 4. Target structure & taxonomy (proposal)

```
Enhance/
  DesignSystem/
    Tokens/      → Colors, Typography, Spacing, Radius, Motion, Elevation (new), IconSize (new)
    Primitives/  → AppButton (style enum), CircleButton, IconButton, Surface, Pill,
                   SegmentedBar, GifBadge, BottomSheet, ProgressOverlay — theme-driven, zero literals
    Patterns/    → EffectDetailPanel, ParameterSliderRow, ParameterPickerRow, PermissionViews
    Theme/       → Theme.swift, Environment+Theme.swift (light/dark axis — Phase 21)
    Catalog/     → ComponentGallery.swift (#Preview storybook)
  Features/{Gallery,Editor,Settings}/  → compose Primitives + Patterns only; never restyle
  Services/  Models/  Extensions/  Assets/  Shaders/
```

**Taxonomy:** *Tokens* (values) → *Primitives* (single-responsibility, theme-driven, zero
literals) → *Patterns* (composed, reusable) → *Features* (screens compose only). Literals live
**only** in `Tokens/`. This can be reached incrementally — the current `Design/` and `Components/`
folders are compatible waypoints; a physical move is optional and lowest priority.

---

## 5. AI contribution rules (destined for `AGENTS.md`)

1. **Never** write a raw colour in UI code — no `Color(red:…)`, `Color(hex:…)`, `.white/.black/.gray`. Use a semantic token from `Design/Colors`. (Effect/shader colour math under `Services/Animators` is the only exception.)
2. **Never** write a raw font — use `Font.silkscreen*`, never `.custom("Silkscreen…", size:)` or `.system(...)` at a call site.
3. Use tokens for spacing (`AppConstants.Spacing`), radius (`CornerRadius.*`), and motion (`Motion.*`). No magic numbers; `cornerRadius: 16` is `CornerRadius.card`.
4. **Reuse before building.** Panels/pills = the `Surface` primitive; buttons = `AppButton`/`CircleButton`. Missing primitives go in `Components/` (not a feature file), with a `#Preview`.
5. Features **compose, they don't restyle.** No bespoke backgrounds, radii, or fonts inside `Features/`.
6. Every interactive/icon-only control needs an `accessibilityLabel`; honour Dynamic Type; keep a 44×44 minimum touch target.
7. New/changed primitives require a variant+state `#Preview` and must pass SwiftLint (raw-colour / raw-font rules are errors).
8. Dark + light + follow-system must all render; read colours via the token layer, never assume dark.
9. When unsure which token applies, **stop and ask** — do not invent a value.

---

## 6. Explicitly out of scope (today)

- Light/dark theming and colour schemes — Phase 21, [FEATURE-THEMES.md](FEATURE-THEMES.md).
- Full Dynamic Type reflow — Phase 3 establishes the test and labels only.
- Effect/shader colour math in `Services/Animators/**` — pipeline values, never chrome.
- A physical folder move to `DesignSystem/` — optional, lowest priority; the plan works in place.
