# Themes — product and implementation plan

> Status: proposed. No code written, and `THEMES.md` itself not yet written.
>
> Scope: user-selectable **appearance** (light / dark / follow-system) and **colour schemes**
> the user designs, across the whole app chrome. Sits under Phase 21.

## Context

The goal is user-selectable UI themes: light / dark / follow-system, plus selectable colour
schemes authored by hand.

The reason this needs a real plan rather than a checklist: **there is no design system to
extend.** `Enhance/Design/Colors.swift` is 18 lines and defines exactly one token,
`Color.enhanceMint`. Every other colour in the app — ~340 colour-bearing lines across ~22 files —
is a literal at its call site, and the entire dark appearance comes from a single
`.preferredColorScheme(.dark)` at `GalleryView.swift:59`.
There are zero uses of `@Environment(\.colorScheme)`, zero system-semantic colours, and
`AccentColor.colorset` is an empty stub with no `color` key at all.

So "add themes" is really three jobs in sequence: **build a semantic token layer → migrate 22
files onto it → add the two theme axes on top.** This document's main value is making that
sequencing, and the slot contract to design against, explicit before any code moves.

Settings already has the insertion point: `SettingsView.swift:53`
holds a `themesSection` with `@AppStorage("appTheme") = "PIXEL"` that is **never referenced from
`body`** — deliberate dead scaffolding.

## Decisions already taken (from the user)

| Question | Answer |
|---|---|
| Light mode scope | **Full light + dark + follow-system** |
| What a colour scheme changes | **Full palette per scheme** — every semantic slot authored per scheme |
| Fonts | **Colours only.** Font-token cleanup is separate, non-blocking work |
| Mesh gradient | **Varies per scheme** — each scheme authors its own stops |
| GIF matte | **Export matte stays black** (image-pipeline, not chrome). The on-screen canvas backdrop *is* a theme slot and may vary |
| Palette spec format | **Slot contract + fill-in worksheet** — constraints per value, no hues proposed |

---

## The migration in detail

### 1. Where the literals are

~60% of them sit in three files —
`GradientViews.swift` (34),
`EditorView.swift` (25),
`GalleryView.swift` (23) — so the effort is not
mis-estimated.

### 2. The two axes

`appearance` (light | dark | system) × `scheme` (N palettes). Effective palette =
`scheme.palette(for: resolvedColorScheme)`. Every scheme must author **both** a light and a dark
palette; there is no automatic derivation.

### 3. The slot contract

Derived from the de-facto slots already inlined in the code. Each row records the slot, today's
literal(s), and every call site pattern it replaces.

**Surfaces**
| Slot | Today | Note |
|---|---|---|
| `background` | `#171717` (Gallery:45, :417) **and** `#120E0A` (EditorView:26) | Two different blacks, neutral vs warm. **Reconcile to one before theming**, or promote the split to two named slots deliberately |
| `surface` | `#202020` ×8 (EditorView:725/763/779, GalleryView:71/265/445/458/471) | Most-repeated literal in the app — chips, pills, toasts |
| `surfaceRaised` | `#1C1815` (EffectDetailPanel:61), `#323232` (EffectCardView:92 active) | A third warm dark; reconcile with `surface` |
| `surfaceSubtle` | `.white.opacity(0.04)` (EffectCardView:92, SegmentedBar:54) | Must become an explicit colour, not a white alpha — white-on-white fails in light mode |
| `canvas` | `Color.black` (EditorView:878) | Photo backdrop. **Recommend every scheme default this to the same near-black in both appearances**, so it can be varied deliberately but never diverges from the export matte by accident. See §7 |

**Content**
| Slot | Today |
|---|---|
| `textPrimary` | `.white` ×~35 |
| `textSecondary` | `.white.opacity(0.5)` (SettingsView:44/68, EditorView:720), `Color(white: 0.82)` (EditorView:672) |
| `textDisabled` | `.white.opacity(0.3)` (EditorView:220/230/239) |
| `textOnAccent` | `#171717` ×5 (AppButton:29, EditorView:688/737, GalleryView:193/424), `#120E0A` (ParameterSliderRow:87) — text sitting **on** the accent or the mesh gradient |

**Accent**
| Slot | Today |
|---|---|
| `accent` | `Color.enhanceMint` / `UIColor.enhanceMint` — `Colors.swift:11,:17`, 13 call sites |
| `accentMuted` | Three near-identical dark greens that should collapse to one: AppButton:36, SegmentedBar:42, GifBadge:13 |

**Lines, overlays, depth**
| Slot | Today |
|---|---|
| `separator` | `#D9D9D9` (SettingsView:141) vs `.white.opacity(0.25)` (ParameterSliderRow:68) — inconsistent, reconcile |
| `outline` | `.white.opacity(0.3)` (ZoomFrameOverlay:42), `.white` (:78) |
| `scrim` | `.black.opacity(0.2–0.6)` ×6 (EditorView:823, GalleryView:486, EffectCardView:104, GifGridItem:51, ZoomFrameOverlay:58, GIFPreviewView:15). Model as one base colour + the existing opacities |
| `shadow` | `Color(white: 0.12, opacity: 0.15)` — three identical copies (EditorView:373, SettingsView:113, GifGridItem:58) |

**Gradient (per scheme, per appearance)**
`meshPrimary: [Color]` (9), `meshSecondary: [Color]` (9), `borderPrimary` (2), `borderSecondary` (2)
— from `GradientViews.swift:8–17, :56–64`. Note that
`EditorView.swift:345–358` **duplicates 11 of these
stops inline** as an `AngularGradient`; that duplication must be removed during migration or it will
silently ignore the theme.

**Non-colour slot**
`pressBrightness: Double` — `ButtonModifiers.swift:9,:32` uses
`+0.15`, tuned for dark. Light mode needs a negative value or the press state washes out. This is why
the slot belongs in the palette rather than staying a constant.

### 4. Architecture

State the recommendation and, briefly, why the obvious alternative loses:

- **Rejected: asset-catalog colorsets with light/dark appearances.** They solve the appearance axis
  for free but not the scheme axis — N schemes means N colorsets per slot and name-mangled lookup,
  with no runtime switching.
- **Chosen:** a plain `struct ThemePalette` with one stored property per slot (**no default values** —
  omitting a slot must be a compile error), a `ColorScheme`-keyed lookup per scheme, and injection via
  a custom `EnvironmentKey` at `\.theme`.

Document the one real gotcha: **when appearance is `system`, `preferredColorScheme(nil)` means the
palette can only be resolved from inside the hierarchy**, where `@Environment(\.colorScheme)` reads
the live system value. So a small `ThemeProvider` wrapper view reads the ambient `colorScheme` and
injects `\.theme`; the manager alone cannot compute it.

Also record:
- `UIViewRepresentable` reads the palette from `context.environment[\.theme]` — that covers
  `ImageCanvasView.swift` (which needs `UIColor` twins on
  the palette) and `AnimatedGifView.swift`. Do **not** duplicate
  a parallel UIKit theme path.
- Storage: two new `@AppStorage` keys, `appearanceMode` and `colorSchemeID`, both raw-value strings
  with unknown-value fallback to the default. The existing `"appTheme"` key may hold `"PIXEL"`,
  `"THEME 2"`, or `"THEME 3"` on installed devices — **abandon it, don't migrate it**; those values
  never meant anything.

### 5. Staged migration

Each stage ends green and shippable.

- **Stage 0 — reconcile duplicates while still dark-only.** Pick canonical values for: the two
  backgrounds, the three surface darks, the three greens, the two separators, the three copies of the
  same shadow. Refactor-only; no visible change. Doing this after tokenising means baking the
  inconsistency into every scheme.
- **Stage 1 — token layer, zero visual change.** Define `ThemePalette`, the environment key, and one
  `dark` palette that reproduces today's look exactly.
- **Stage 2 — migrate call sites.** Order: `Design/` → shared `Components/` (AppButton, CircleButton,
  BottomSheet, SegmentedBar, EffectCardView, EffectDetailPanel, ParameterSliderRow, GifGridItem,
  GifBadge, ZoomFrameOverlay, GIFPreviewView, PermissionViews, ImageCanvasView) → `Features/`
  (GalleryView, EditorView) → `Views/` (SettingsView, AnimatedGifView). Delete the four private
  `mintGreen` aliases and the inline gradient duplication. Screenshot-compare against `main` after
  each group — the whole stage must be visually identical.
- **Stage 3 — appearance axis.** `ThemeProvider`, the two storage keys, replace
  `.preferredColorScheme(.dark)` at GalleryView:59, author the default scheme's **light** palette, fix
  `pressBrightness`.
- **Stage 4 — scheme axis.** The scheme enum and N × 2 authored palettes, filled from §6.
- **Stage 5 — Settings UI.** Replace the dead `themesSection` with two groups: `APPEARANCE`
  (LIGHT / DARK / SYSTEM, reusing the existing `checkmark(isSelected:)` row idiom at
  `SettingsView.swift:118`) and `COLOUR SCHEME` (a swatch row
  modelled on the existing app-icon row). Both use `HapticService.selection()` like every other
  settings control.
- **Stage 6 — tests and device verification.**

### 6. The authoring worksheet

A per-scheme fill-in table, one row per slot × {light, dark}, with the constraint stated for each
value rather than a suggested hue: what it sits on, its contrast target, and its failure mode.
Baseline rules to state once: `textPrimary` on `background` ≥ 4.5:1; `textSecondary` ≥ 3:1;
`accent` on `background` ≥ 3:1; **`textOnAccent` must clear 4.5:1 against both the accent and the
darkest and lightest mesh stops**, since it sits on the animated gradient. Include the 22-value
gradient block per scheme per appearance with a note that the two mesh sets must read as a pleasant
cross-fade, not just as individually valid colours.

### 7. Boundaries — what does *not* follow the theme

Important enough to be its own section, because it is where a naive migration does damage:

- **Everything under `Services/Animators/`** — `CIColor`/`UIColor` constants are image-pipeline
  values baked into the user's output.
- **`Models/LaserColor.swift` and
  `Models/GradientStops.swift`** — dual-purpose. The swatches are
  UI but must show the *true* effect colour, so they stay literal.
- **`GIFGenerator.swift:207`** — `UIColor.black` frame matte.
  **Stays black.** Per the user's decision, the on-screen `canvas` slot may vary by theme while this
  does not; record the resulting divergence as a known, accepted behaviour, and recommend keeping
  `canvas` near-black in every scheme so it stays theoretical.

### 8. Known hazards

- `.presentationBackground(.black)` and `Color.black` header at
  `BottomSheet.swift:27,:35` — sheets are a separate
  presentation; confirm the root `preferredColorScheme` and the injected `\.theme` both reach sheet
  content rather than assuming they do.
- The `icon-check` asset has the mint `#60FFA8` **baked into its SVG fill**
  (`Colors.swift:8` records this) so it will not follow a scheme's
  accent. Fix by converting it to a template image and tinting — `LEARNINGS.md:710` documents the
  exact `template-rendering-intent` technique, and `:846` the full-opacity trap that follows.
- **Scrims over photos are about the photo, not the theme.** A dark scrim under white text over a
  user's image is probably still right in light mode. Decide per site rather than flipping all six.
- `AccentColor.colorset` is an empty stub — either give it the default scheme's accent or leave it
  alone knowingly; today the system tint is Apple's default blue.
- `EnhanceApp.swift:11–13` sets `UILabel/UITextField/UITextView.appearance()` fonts globally. Nothing
  colour-related, but it is the precedent for global appearance in this app — do **not** add colours
  there, since `appearance()` proxies cannot follow a live theme change.

### 9. Verification

- **Tests** (extend `EnhanceTests/`, which is logic-only — there is no snapshot infrastructure and
  this plan does not add one):
  - appearance resolution: light/dark/system → expected `ColorScheme`, including the system case;
  - unknown/corrupt `AppStorage` values fall back to the default instead of crashing;
  - **contrast assertions** — a small WCAG ratio helper run over every scheme × appearance against
    the §6 targets. This is the one test that can actually catch a badly authored palette.
  - a `ThemePalette` with no default values makes "every scheme defines every slot" a compile-time
    guarantee — say so, rather than writing a test for it.
- **Device/simulator**: build and drive the iOS simulator; capture Gallery, Editor (both tabs),
  Settings sheet, and the permission-denied screen across every scheme × {light, dark}. Then flip the
  system appearance with the app in `system` mode and confirm it follows live without a relaunch.
- **Stage 2 gate**: a screenshot diff against `main` proving the token migration changed nothing.

### 10. Roadmap pointers — done

`ROADMAP.md` Phase 21 now points here and carries the "migration, not a feature" headline, and
Phase 18 records that the dead `themesSection` scaffolding is claimed by Stage 5 so it does not get
repurposed for the rate/share rows.

---

## Status and next step

Nothing here is built. The immediate next step is **Stage 0** — reconciling the duplicate values
while the app is still dark-only, because tokenising first would bake today's inconsistencies
into every scheme.

The one open authoring dependency is §6: the palettes cannot be written by anyone but the user,
since the decision recorded above was "slot contract + fill-in worksheet — constraints per value,
no hues proposed."
