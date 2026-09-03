# Enhance (ZoomGif) — Roadmap

> Last updated: 2026-08-18 (subject-segmentation spike + service; new effects/features intake)

## Vision

Enhance is built around a simple creative flow:
**choose a photo → define a focal point → generate motion → refine → save or share.**

Each step should feel fast, tactile, and visually satisfying.

---

## How to read this file

Four sections, ordered by what unblocks what — **not** by phase number. The old numbering survives
only in [HISTORY.md](HISTORY.md), because it had stopped describing any real order (17e sat in
front of 17h and 17i; 19b and 19c predate 20).

1. **[Foundations](#1--foundations)** — work that unblocks other work. Every item names the
   dependent it unblocks. An item that cannot name one belongs in §3.
2. **[Effects](#2--effects)** — classified by *what blocks them*, since kernel-vs-not stopped
   predicting anything (see the note in §2).
3. **[Product bets](#3--product-bets)** — judged on upside. Nothing is waiting on them.
4. **[Defects](#4--defects)** — judged on accruing cost. Kept apart from §3 deliberately: a
   feature always looks more appealing than a bug, so they must not compete in one list.

**Device verification is tracked per item**, not in a separate list. In this project an effect is
not done when it compiles — THIRD EYE took several device passes and each one changed constants.
Items marked 🔍 are landed and green but never confirmed on hardware.

> **Docs:** [EFFECTS.md](EFFECTS.md) — how to build an effect, and what is worth building.
> [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) — the design-system audit and phased plan.
> [LEARNINGS.md](LEARNINGS.md) — rules discovered the hard way.
> [HISTORY.md](HISTORY.md) — everything already shipped, and why.
> **[BIGHEAD-HANDOFF](BIGHEAD-HANDOFF.md)** — everything tried on BIG HEAD, measured facts, and
> the questions we want fresh eyes on. **Read it before touching `BigHeadEffect`.**
> Feature plans: [TEXT-EFFECTS](FEATURE-TEXT-EFFECTS.md) · [THEMES](FEATURE-THEMES.md) ·
> [LENS](FEATURE-LENS-DISTORTION.md) · [SCRAMBLER](FEATURE-SCRAMBLER.md) *(historical)* ·
> [VIEW-TRANSITIONS](FEATURE-VIEW-TRANSITIONS.md) ·
> [MOTION-EFFECTS](FEATURE-MOTION-EFFECTS.md) *(plan: FRAME ECHO and motion-reading effects on bursts)*

---

## Pick up here

**State:** `main` has LENS, THIRD EYE, SLICE SHIFT, text-overlay Stages A–F, the design-system
plan, and — as of 2026-08-18 — `SubjectSegmentationService` and the §1g spike behind it. The
pattern is to commit on a branch and fast-forward `main` at each green stage, so Xcode always sees
a working build.

**Check for in-flight work before starting; do not trust a dated claim here.** This paragraph used
to assert every side branch was at or behind `main`, which was true on 2026-08-12 and quietly
stopped being true. On 2026-08-18 there were six worktrees, one of them ahead. `git worktree list`
and `git log --oneline main..<branch>` take a second and are the only honest answer.

**Next up, in order:**

1. 🔍 **One device pass over the effect panel** — it now answers three open questions at once, and
   one of them may be blocking. RISO is **seven** rows since BACKGROUND ONLY landed (§2b), the
   long-standing six-row check was never done, and on a three-row effect the toggle card sits on
   the panel's bottom edge where **nothing I tried would scroll it** (§2e). If that scroll really
   is stuck rather than my synthetic touches failing, the toggle is unreachable on some effects
   and this jumps to the top of everything.
2. **The rest of §2f**, all unblocked now that the mask, the compositor and the toggle exist:
   SUBJECT REPEATED INTO A PATTERN and ANIMATED BACKGROUND are ordinary work — the second is an
   upgrade to `AnimeBackgroundEffect`'s elliptical mask rather than a new card. **TEXT BEHIND
   SUBJECT is owned by another session (§3a) — coordinate before touching the rasteriser.**
   Carry the finding from FACE CUTOUT: pointwise effects cut cleanly, neighbourhood samplers
   bleed the subject outward.
3. **Whether BACKGROUND ONLY stays on the neighbourhood-sampling effects** (§2f) — a taste call
   with renders already shown to the user on 2026-08-18. MOTION BLUR haloes; SWIRL smears. The
   only real fix is inpainting, which is what PARALLAX is blocked on, so the options are accept
   or withhold.
4. **Pattern Refraction** (§2c) is the last of the *old* effect list, with the displacement spike
   (§2b) worth running first for that one. BIG HEAD (§2a) and BITMAP (§2b) are the ready-and-cheap
   new arrivals if an effect is wanted before the displacement spike lands.
   **Ask before starting another effect outright**: three have been declined on the user's call
   (HATCHING, BOKEH, Water Caustic), so the constraint is taste, not capability — the kernel path
   is now proved three times over. Show a render early rather than polishing alone. FACE SWAP
   (§2g) sits under exactly this gate — its mechanism exists but its look is unproven.

**CI shipped on 2026-08-12** (§1b) and guards `EnhanceTests` on every push to `main` and every PR.
**The kernel gate passed the same day** (§1c) — and note it shipped with a real bug that only RISO
exposed, recorded in LEARNINGS: a passthrough proves the pipeline runs, not that it is isolated.

*(§1e, §2d control audit, and SLICE SHIFT are also done. HATCHING skipped and BOKEH declined, both
on the user's call — §2a is empty, so nothing further is buildable from stock filters alone.)*

> **A note on trusting this file.** A 2026-08-11 sweep checked every load-bearing claim against the
> code and found six wrong — one of which actively instructed a future session to revert a repaired
> bug. Claims here now carry a file and line where one exists. **If you find one that disagrees
> with the code, the code wins and the doc is the defect** — fix it in the same commit.

---

## 1 — Foundations

Work that unblocks other work. **Entry bar: each item names what it blocks.** This bar exists
because the project has already been burned once — the old Phase 17e sat in front of every
interesting effect for months on the assumption that Figma shader effects need custom kernels,
which LENS then disproved by reconstructing one from about eight stock Core Image nodes.

**Bugs that get worse with new infrastructure belong here, not in §4.** Precedent: the face-effect
render cost was filed as a P2 nit, then continuous speed shipped and
`frameCount = max(12, Int(1/speed/0.04))` turned ~25 frames into 100 at 0.25× — the same bug, four
times worse, and by then gating two features.

### 1a. The panel row budget — a constraint, not a task ✓ closed

This section records the ceiling everything else must respect; the decision itself is at the end.

Computed from `PanelMetrics.swift:35-41` (grid 16, small 8, floor 34pt, cap 44pt), the panel height
needed before rows floor and the content overflows:

| rows | minimum panel height | on an SE 3 (~190pt) |
|---|---|---|
| 3 | 192pt | **fits — verified on device 2026-08-11** |
| 4 | 234pt | scrolls (survivable — see below) |
| 5 | 276pt | scrolls |

- **3 rows fits without scrolling.** Confirmed on an SE 3 (2026-08-11): rows compress toward the
  floor rather than clipping, which is `PanelMetrics` working as designed. An earlier prediction
  that THIRD EYE's three rows overflowed was wrong — it computed a correct 192pt threshold against
  the guard test's "~190–200pt" note, which was an estimate rather than a measurement.
- **4+ rows overflow into a scroll, and that is survivable.** The table's "does not fit" means "does
  not fit *without scrolling*", not "cannot render".

**Correction (2026-08-11): a slider drag does *not* lose to the scroll.** This section previously
said `DragGesture(minimumDistance: 0)` (`ParameterSliderRow.swift:95`) loses to the `ScrollView`
(`EffectDetailPanel.swift:53`), so a slider drag would scroll the panel instead of moving the knob.
Text overlays' SLIDE preset ships **four rows** — FILL, swatches, FROM, DISTANCE — which is the
first configuration in the app to enable that scroll, and it was tested on an SE 3: **the DISTANCE
slider works normally.** The `minimumDistance: 0` gesture claims the touch first, exactly as
`EffectDetailPanel.swift:45-52` describes. The panel's own comment was right and this file was
wrong; they had contradicted each other since the restructure.

That does not make the scroll *desirable* — a panel the user must scroll to reach a control is still
worse than one that fits — but it is not a correctness problem.

**No panel changes are wanted.** *(User's call, 2026-08-11.)* Raising the panel's height, lowering
the 34pt floor, and capping effects at three rows were all considered and **all declined**. Three
rows is the comfortable ceiling and effects should aim for it; a fourth row is a UX judgement, not
a blocker.

**That judgement has now been exercised: the scroll is acceptable.** *(User's call, 2026-08-12,
made for Riso Print but stated generally — "the row count is fine because the panel can scroll".)*
So **row count is no longer a design constraint on new effects**, and an effect should not contort
its parameters to fit three rows. The evidence backing this is in the correction above: four rows
ship today in text overlays' SLIDE preset and the slider drag still beats the `ScrollView` on an
SE 3. Aim for three because it is nicer, not because four is forbidden.

One thing to respect rather than fix: **row count is not fixed per effect.** TEXT's
`editingRowCount` varies with the selected preset, so a category can change row count at runtime
without the user changing effect — which is how it reached four rows in the first place.


### 1b. CI running the test suite → protects every parallel session

[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) §3a sequences CI *after* its Phases 1–2, because the **lint**
rules assume the colour literals are gone. Running `xcodebuild test` carries no such dependency,
which is what made the test half splittable and shippable first.

**A concrete instance of what this catches** *(2026-08-11)*: two sessions running simulators at once
starved the machine enough that
`EditorViewModelTests/generateZoomPreviewImage_afterAnEarlyNoOp_stillBuildsWhenTheSourceArrives`
took **154s and 258s wall-clock against a 2-second poll budget**. It passes in isolation and in a
quiet full run — a genuine flake, not a regression. Poll since widened to 10s (assertion unchanged;
it still exits the moment the image appears, so the happy path costs nothing). **Four sessions
sharing one machine is exactly the environment where a timing assumption rots**, and nobody found
this by reading the test — they found it by tripping over it. A runner with a known load profile is
where that belongs.

**And a second instance the same day**: a run reported 165 failures *at exactly 0.000 seconds each*,
which was the test host dying rather than any code change — five simulator deaths in one day. Both
failure modes are invisible to a local run that someone decides to trust. See LEARNINGS 2026-08-11
for the timing tell.

- [x] ~~**Split test-only CI out and do it now**~~ — **shipped 2026-08-12**,
      [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml). A `macos-15` runner on
      `xcodebuild test`, on pushes to `main`, all PRs, and manual dispatch. Lint still follows
      later, with the token migration. Three things in it are load-bearing and should not be
      "simplified" away:
      - **The simulator is resolved at run time**, not hardcoded. The workflow picks the newest
        available iPhone with iOS ≥ 18.2 (the deployment target) and fails loudly, printing every
        runtime, when there is none. **The first run proved this was not over-engineering**: the
        runner has **Xcode 16.4** — two majors behind the 26.3 on the dev machine — and its
        runtimes are 18.5, 18.6, 26.0, 26.1, 26.2. **There is no iOS 18.2 runtime on the runner at
        all**, so the conventional `-destination 'name=iPhone 16,OS=18.2'` would have failed on
        the very first run. It selected an iPhone 17 Pro on iOS 26.2.
        *Worth knowing:* the suite passes under both Xcode 16.4 and 26.3, but that two-major gap is
        a standing source of "green locally, red in CI" and the reverse. Check the toolchain line
        in the run log before assuming a CI-only failure is a real regression.
      - **`-scheme Enhance` is mandatory.** The project also shipped an `Enhance 1` scheme —
        byte-identical except that it declared *no testables*, so a run under it would have
        reported success having executed **zero tests**. It was unreferenced and present since the
        first push; **deleted in the same commit**, but pin the scheme regardless.
      - **A dead-host diagnostic.** On failure the workflow checks whether *every* failure took
        0.000s and, if so, says so — that is the second incident above, and read as a code failure
        it sends someone hunting a regression that does not exist.
- [ ] **Promote `EnhanceUITests` into the gate.** Deliberately excluded for now: it contains a
      launch-*performance* measurement and a screenshot capture, both timing- and
      rendering-sensitive on a shared runner — the exact class of assumption this section says rots
      under load. It needs a known-good baseline first, or it just teaches everyone to ignore red.
- [ ] Sweep the suite for other wall-clock assumptions now that CI exists — the 154s/258s one was
      found by accident, so it is unlikely to be the only one.

*Local baseline, for comparison against CI:* `EnhanceTests` is **~44s** on an iPhone 17 Pro
simulator (tests run parallelised, so the per-test times in the log are clones' wall-clock, not
CPU — they cannot be used to attribute a slowdown to a specific test).

- [ ] **Watch the CI wall-clock; it is not yet stable.** Three runs so far: **348s, 298s, 727s**.
      The jump is inside the *testing* phase (652s of the third run), not the build — the
      `*.ci.metal` rule costs about 2.5s, and the four tests it added cost about 1s locally, where
      total time did not move at all (391 → 396 tests, ~44s either way). So it reads as runner
      variance rather than a regression, **but one data point cannot separate those**, and this is
      the section that exists because timing assumptions rot under load. If it stays above ~10
      minutes, profile before adding anything else to the suite;
      `GIFGeneratorTests/generateGIF_withVisualEffect_returnsData` is the first place to look.

### 1c. CIKernel de-risking gate ✓ passed 2026-08-12 → Riso Print, Water Caustic, Hatching styles unblocked

Split out of the old Phase 17e. The risk in that phase was never the effect math — it is that a
target-scoped `-fcikernel` reaches `Shaders/Pixellate.metal` and **breaks the animated canvas border
at runtime**. Decoupled, the gate took about an hour, exactly as estimated, and the rest is now
ordinary work.

- [x] ~~**Build rule scoped to `*.ci.metal`.**~~ A `PBXBuildRule` on the app target only. Custom
      rules take precedence over Xcode's built-in Metal rule *for matching files*, so
      `Pixellate.metal` still goes through the stock path. **Measured, not assumed:** after the
      change `default.metallib` is ~61KB and still contains `pixellate`, while
      `Passthrough.ci.metallib` is a separate ~3KB file carrying the `air.ci_builtin` marker.
- [x] ~~**Passthrough kernel, then confirm the border still renders in both `EditorView` and
      `GradientViews`.**~~ `Shaders/CI/Passthrough.ci.metal`, kept as a canary.
      **Confirmed by looking**, on an SE 3 simulator: the canvas border and the ENHANCE button both
      render pixellated and animate between frames. Four tests in `CIKernelGateTests` cover the
      rest, including one asserting `default.metallib` is *not* a Core Image library — so a future
      widening of the rule fails a test instead of silently blanking the border on device.

**One thing the plan did not anticipate**, now fixed in EFFECTS.md and LEARNINGS: this project sets
`ENABLE_USER_SCRIPT_SANDBOXING = YES`, under which a rule's `outputFiles` is a *write-permission
list*. Declaring only the `.metallib` makes the intermediate `.air` fail with
`Sandbox: deny(1) file-write-create`. It also hid at first — an explicit `-derivedDataPath` to a
scratch directory built green, and only the default DerivedData path failed, which is what CI uses.

> **Note for whoever writes the first real kernel:** the gate deliberately proves the *pipeline*,
> not the math. Colour space (kernels run in linear sRGB) and the ROI callback are still ahead of
> you — both are in EFFECTS.md, and both make a correct port look wrong.

### 1d. Design system, Phases 1–2 → blocks themes (§3b)

Tokens, then migration onto them. Pure refactors with **zero intended visual change** — each token
equals the literal it replaces, so the app should render pixel-identical. Full plan in
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md); the audit scores the current system 1.5 / 5.

- [ ] **Phase 1 — tokens.** Extend `Design/Colors`, `Constants`, `Typography`; add
      `Design/Motion.swift`; route existing components through them via 1:1 swaps. Self-contained.
- [ ] **Phase 2 — migrate the duplicated patterns.** A `Surface` primitive; move the inline
      `0x202020` pills and the inline Silkscreen fonts onto tokens.
- [x] ~~**Re-derive the plan's `EditorView` line references first.**~~ Done 2026-08-12, and the
      prediction was exactly right: the three `0x202020` pills moved from `:726/765/781` to
      `:1124/1162/1178`, while **every** `GalleryView`, `SettingsView` and `Components` reference
      still held. They are now anchored by symbol (`saveShareButtons`, `saveSheetContent`) with the
      grep that re-finds them, so the next refactor cannot rot them again.
- [x] ~~**Re-measure the literal count, with a stated method.**~~ Done 2026-08-12 — the method and
      the table are in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) §1 so they can be re-run. **178
      occurrences across 27 files** of UI chrome, or 236 across 43 including
      `Services/Animators/**`. FEATURE-THEMES' "~340 across ~22 files" was wrong in both
      directions, and the file count was indeed understated. The useful finding is the
      concentration: `EditorView` (37), `GradientViews` (32) and `GalleryView` (25) hold more than
      half of it, so Phase 2 is front-loaded into three files.

### 1e. Return the new asset id from the save callback ✓ shipped 2026-08-11

*Promoted from §4, delivered by the text-overlay session in `36539df`, refined in `8345075`.* One
structural gap served two features — while it sat under P1 Correctness it was competing with polish
bugs it will always out-rank, which is why the promotion was the right call.

`saveGifToMyGifsAlbum`'s completion is now `(Bool, String?, Error?)`
(`PhotoManager.swift:77`), so the new `PHAsset` identifier reaches the caller and both persistence
paths key off it:

- [x] ~~**Thread the created asset identifier back through the save callback.**~~ `saveGIFToLibrary`
      calls `persistZoomParams` *and* `persistTextOverlay` against `newIdentifier`
      (`EditorViewModel.swift:1265-1268`), and `updateOriginalGIF` re-files both against the
      *replacement* asset (`:1316-1319`) — that path is a delete-then-create, so the identifier
      changes and anything written against the old one is orphaned. Both sites carry a comment
      saying why.

This closed the reported bug where editing a gallery GIF that already had text made **the text
silently disappear**: "SAVE NEW COPY" could not store the overlay without an asset id, so the
reopened editor had `textOverlay == nil` while the words were baked into the pixels, and the first
regeneration rebuilt from the deliberately textless frame 0. It also closed the P1 zoom-param gap —
new saves no longer fall back to a hardcoded `scale = 2.0, rect = (0.15, 0.15, 0.7, 0.7)`.

### 1f. Effect-carousel thumbnail cost → worsens with every effect added

**Now at 15 thumbnails** — 8 → 11 → 15, the last jump on 2026-08-12 from RISO and STRETCH. Each new
effect in §2 makes it worse, which is what puts it here rather than in §4, and the prediction has
now come true twice without anyone measuring the cost.

**Two of the fifteen are kernel effects, and RISO is the most expensive effect in the app** —
three input samples plus three halftone screens per pixel, on every card. The carousel renders a
card per `selectable` effect, so this is no longer a uniform-cost list.

- [ ] 🔍 Whether entering the IMAGE tab stutters while thumbnails render, and the scroll feel of a
      15-item carousel. **Measure before optimising**: the cost is asserted here, never timed, and
      `previewProgress` means each card renders one frame rather than an animation.

### 1g. Subject segmentation → unblocks the six effects in §2f

*Filed 2026-08-18 from a ten-idea intake.* Six of the new effect ideas are one missing capability
wearing six hats, which is what puts this here rather than in §2: **face cutout with background
effects, subject-repeated-into-a-pattern, text behind the subject, text partially obscured by the
subject, animated background with a stationary subject, and the parallax/bounce family** all need
the same thing — a mask that separates subject from background. None of them is buildable without
it and all of them are ordinary work after it.

**The app has no subject segmentation today.** Verified by grep, not assumed: no
`VNGenerateForegroundInstanceMaskRequest`, no `VNGeneratePersonSegmentationRequest`, anywhere in
`Enhance/`. The nearest thing is `FaceRegionMaskBuilder.ellipticalMask`
(`FaceRegions/FaceRegionMaskBuilder.swift:19`), which inscribes an **ellipse** in a face's bounds —
right for copying a feature, useless for a cutout that must read as a person, because it has no
notion of a silhouette.

- [x] **The spike — run 2026-08-18. The mask is good enough; the worry was aimed at the wrong
      thing.** Ran `VNGenerateForegroundInstanceMaskRequest` over all eight `showcase-*` assets
      (they are already 600×600, i.e. exactly the output size) and pushed naive cutouts through the
      real export path — `CGImageDestination`, GIF, `HasGlobalColorMap: true`, matching
      `GIFGenerator.swift:128-141` — then looked at frames read back out of the written GIF.
      Four findings, each of which changes something downstream:
      - **Hair and whiskers were the wrong thing to fear.** The mask is a *smooth silhouette* — it
        resolves neither hair wisps nor whiskers, and the feathered edge is only 1.2–1.9% of the
        frame (≈4.3k–6.7k px), i.e. 1–2px of antialiasing, not a soft matte. It does not matter:
        fine strands are light against a treated background and still read, because the background
        effect is applied to the *whole* frame and the mask only chooses between two versions of
        the same pixel. Nothing is cut off; the strands just get the background's treatment.
      - **The real palettisation damage is banding in the background, not fringing at the edge.**
        Verified by comparing the pre-GIF PNG against a frame read back from the GIF: the edge is
        identical, while a smooth desaturated background breaks into visible contour bands under
        the 256-colour global map. **So the constraint lands on §2f's background effects, not on
        the mask** — an effect that flattens the background into few colours (MONOTONE, DUOTONE,
        RISO, DITHER) costs nothing, while one leaving a smooth gradient (blur, desaturate) bands.
        Prefer the former when picking the first shipped pairing.
      - **1 in 8 photos has no subject at all.** `showcase-1` (a cat under bedding, low contrast,
        heavily occluded) returns *no observation* — reproducibly, not intermittently. So the
        family needs a defined no-subject behaviour, and it is the same design question §2g raises
        for FACE SWAP's one-face case. Decide it once, for both.
      - **Cost is not the problem the item assumed, but the *first* call is.** Warm, the request is
        12–17 ms plus 2–68 ms for `generateScaledMaskForImage` on a 600×600 input. **Cold it is
        ~215 ms** — a one-time model load, paid by whichever photo is segmented first. So the cache
        is worth having but is not the interesting part; the interesting part is that the first
        subject effect a user taps will stall about a fifth of a second unless the model is warmed
        earlier (photo pick is the obvious moment). Measured on macOS — see the caveat below.
      **Caveat, and it is the reason this stays open until a device pass:** the spike ran Vision on
      **macOS 26**, not iOS 18.2. The API and the pipeline are identical, but the segmentation model
      may not be, so the *hit rate* and silhouette fidelity above are indicative, not measured for
      our target. Re-run the same corpus on device before treating the 7/8 number as real.
      Harness: `Tools/segmentation-spike.swift` (see §1g note below).
- [x] **The service — landed 2026-08-18** as `Services/SubjectSegmentationService.swift`, with 14
      tests green and the full suite at 565. Mirrors `FaceDetectionService`'s cache-per-image shape
      (`FaceDetectionService.swift:14-22`), and adds three things the build forced:
      - **No subject is an ordinary answer, and it is cached.** `subjectMask(for:)` returns `nil`;
        `hasSubject(in:)` tells the editor whether to say so. **Decision, on the user's call
        (2026-08-18): follow the face precedent — show a toast and leave the cards live.**
        `detectFacesIfNeeded` (`EditorViewModel.swift:689-703`) already does exactly this with
        "NO FACES DETECTED", and answering the same situation two different ways was the thing to
        avoid. **This puts a requirement on the §2f effects rather than on the service: an effect
        handed a `nil` mask must return the frame unchanged**, the way face effects degrade when no
        face is selected — a card that stays tappable must not render a broken frame. Write that
        into the first one and it is free for the rest.

        **Seen on device 2026-08-18, and the requirement above does not cover it: live cards on a
        photo with nothing detected render as *blank grey rectangles*.** `generateFaceFilterThumbnails`
        bails on `guard let face = detectedFaces.first` (`EditorViewModel.swift:926`), so the FACE
        carousel on a landscape photo is a row of empty cards with labels — verified in the
        Simulator on a waterfall shot. The subject carousel will inherit exactly this unless the
        first §2f effect renders its thumbnails from the *unmasked* photo when the mask is `nil`.
        A frame that stays correct and a thumbnail that goes blank are two different problems, and
        only the first was written down. Filed against the face tab in §4 as well, since it is a
        live defect there today rather than a new one.
      - **Failure is kept distinct from absence.** `subjectMaskOrThrow(for:)` throws where the
        convenience wrapper returns `nil`. This is not fastidiousness — see the LEARNINGS entry
        below; conflating them made a green test that proved nothing.
      - **`prewarm()`**, to pay the ~215 ms cold model load at photo-pick instead of on the tap
        that enables the effect. **Not yet wired to a caller** — do that when the first subject
        effect lands and there is something to warm *for*.
- [x] **Device pass — run 2026-08-18 on an iPhone (iOS 26.6). §1g is closed; §2f is unblocked.**
      Vision does **not** throw on iOS, and the numbers are a near-exact match for the macOS
      spike — differences of a few pixels in ~360,000, i.e. the same model behaving the same way:

      | image | subject % (macOS → iOS) | edge px (macOS → iOS) |
      |---|---|---|
      | showcase-2 | 32.5 → 32.6 | 6336 → 6337 |
      | showcase-3 | 30.8 → 30.9 | 6517 → 6487 |
      | showcase-4 | 16.8 → 16.8 | 4626 → 4633 |
      | showcase-5 | 24.8 → 24.7 | 6060 → 6068 |
      | showcase-6 | 55.7 → 55.7 | 5866 → 5863 |
      | showcase-7 | 32.5 → 32.5 | 4333 → 4327 |
      | showcase-8 | 49.2 → 49.2 | 6668 → 6667 |

      **The two findings that were only indicative are now measured.** `showcase-1` returns no
      subject on device as well, so **7/8 is real** and the no-subject path is a genuine product
      case rather than a macOS artifact. And the cold model load reproduced almost exactly —
      **214 ms** for the first request against 15–30 ms warm — so `prewarm()` is worth wiring when
      the first effect lands, at photo-pick.
      Re-run any time with the command below; it is cheap and takes about a second on device.
- [x] ~~🔍 **Run it on a device — the one thing still unverified.**~~ *Done, above.* **`VNGenerateForegroundInstanceMaskRequest`
      throws on the iOS Simulator** (no model), so the real path cannot be exercised there at all;
      the tests inject a stub deliberately. Combined with the spike having run on macOS, the
      capability has been seen working on macOS, seen throwing in the Simulator, and **never once
      run on iOS**. `EnhanceTests/SubjectSegmentationDeviceTests.swift` exists to settle it: it
      runs the real path over all eight `showcase-*` assets and attaches a CSV of
      subject/background/edge coverage plus one cutout GIF per hit, so the numbers can be diffed
      against the macOS run recorded above. **It reports rather than asserts** — the only
      assertion is that Vision does not throw, because a coverage threshold invented in advance
      would be a guess. The file is `#if !targetEnvironment(simulator)`, so CI stays green and the
      test simply does not exist on the Simulator. Full write-up: LEARNINGS, 2026-08-18.

      ```
      xcrun xctrace list devices          # find the device name
      xcodebuild test -project Enhance.xcodeproj -scheme Enhance \
        -destination 'platform=iOS,name=<DEVICE>' \
        -only-testing:EnhanceTests/SubjectSegmentationDeviceTests
      ```

**Two things to carry into every effect built on this**, both already learned elsewhere:

- **This family composites rather than filters.** §2a records what that cost the first time: SLICE
  SHIFT, the app's first compositing effect, surfaced a class of interaction that eleven
  filter-style effects never had — a `wantsLiveCanvas` regression it merely exposed, and laser eyes
  rendering black because the preview does not rasterise between passes the way the GIF does.
  Budget a device pass per effect, and expect the interactions with face effects rather than being
  surprised by them.
- **§1f gets worse.** The carousel is at 15 thumbnails and this family could add five or more, on
  top of a segmentation pass. That is the point at which a fifth `EffectCategory`
  (`Models/EffectCategory.swift` — a `SUBJECT` tab beside ZOOM/FACE/VISUAL/TEXT) is probably the
  honest answer rather than a longer VISUAL carousel. **Flagged, not decided** — decide it when the
  second subject effect lands, not now.

---

## 2 — Effects

> **Why the classification changed.** The old axis was "does this need a custom kernel," and it
> stopped predicting anything. LENS was assumed to need one and needed eight stock nodes. Water
> Caustic was filed as an easy catalog fill and is the one candidate that genuinely cannot be built
> stock. Pattern Refraction and Pixel Stretch were filed as kernel work without anyone checking
> whether `CIDisplacementDistortion` covers them. The axis is now *what actually blocks this*.

Build mechanics, per-effect specifications, and the candidates deliberately rejected live in
**[EFFECTS.md](EFFECTS.md)**. This section tracks status only.

### 2a. Ready to build — stock filters, no new infrastructure

- ~~**BOKEH (face-aware)**~~ — **not wanted, 2026-08-11.** Cut on the user's call before any code
      was written; nothing was built and nothing is owed. The analysis below is kept because it is
      the reason the *approach* is cheap, not the reason the effect is wanted — if it is ever
      revived, none of it needs re-deriving. **Do not re-propose it as "the obvious next build"
      without asking**; it has been declined once. `CIMaskedVariableBlur` grades blur by
      mask value, so blur falls off with distance from the face and reads as depth rather than as a
      cutout; feed it `FaceRegionMaskBuilder`, which THIRD EYE already left behind. This is the only
      candidate that adds a *capability* — subject-aware depth of field — rather than another
      surface treatment, and the source shader cannot do it because it has no notion of a subject.
      Only the highlight weighting is kernel-only, and that approximates stock (threshold
      highlights → blur separately → add back). **Open design call:** it is face-dependent so it
      belongs in the face carousel, but unlike THIRD EYE it should *degrade* rather than vanish on
      estimated landmarks — a blur does not need precise geometry.
- [x] ~~**SLICE SHIFT**~~ — **shipped 2026-08-11.** Horizontal bands displaced sideways, strip
      compositing, no kernel. Three rows: AMOUNT, SIZE, JITTER — the last blends a regular
      alternating comb into per-band randomness, and the two read as genuinely different looks
      (interlacing vs broken signal), which is why they are separate controls.
      **Built as a grid effect**: band height scales with `FrameGeometry.scale` and band position
      is phase-aligned to `contentOrigin`, so the preview and the export agree under zoom and the
      bands stay pinned to the subject as the animation pans.
      Soft band edges were deliberately skipped — a gradient mask per band roughly triples the
      node count, and the hard cut suits the look.
      **Confirmed on an iPhone SE 3, 2026-08-11** — approved as-is, no tuning pass needed, and the
      three-row panel fits without scrolling.
      **Composing it with face effects is also device-confirmed**, after two reports it caused:
      the face tab showing a raw photo after ENHANCE (a pre-existing `wantsLiveCanvas` regression
      it merely exposed), and laser eyes rendering black then dim (the preview not rasterising
      between the face and visual passes the way the GIF does — LEARNINGS 2026-08-11).
      **It is the first effect that composites rather than filters**, which is why it surfaced a
      class of interaction eleven filter-style effects never had; worth remembering before adding
      another compositing effect.
- [ ] ⚠️ **BIG HEAD: the person-mask rebuild is PARKED on the user's call (2026-08-20) after
      failing visual review twice.** The shipped effect is the simple version: ellipse ∩ the
      shared subject mask, sequential per-face, keeping only three corrections from the rebuild
      (halved ellipse extents, 3× growth, the `settingAlphaOne` mask flattening —
      LEARNINGS 2026-08-20). **Read this before ever re-opening the ambitious path:**
      - **What was proven and survives**: `VNGeneratePersonInstanceMaskRequest` separates ≤4
        people cleanly (spike CSVs + tinted composites in the 2026-08-20 xcresults);
        `SubjectSegmentationService.personMasks` is cached, stubbable, orientation-correct, with
        a face-spanning label vote; the `FaceEffect` batch seam exists (protocol requirement,
        sequential default — dispatch pinned by test); `HeadRegionBuilder` stays compiled,
        unreferenced, per the retired-effects convention.
      - **What failed review**: past the 4-instance cap, shared masks grown once per face
        duplicated heads and torsos; the traced contour is Vision's *face oval*, so a cut on it
        clips ears and draws a visible line (dropping the cut below the trace helped, but the
        user's verdict on the full set was "not correct at all"); each fix re-grew the
        complexity the 2026-08-19 reset existed to remove. Five renders and two failed reviews
        in one day — the constraint is the look, not the mechanism.
      - **The review lesson is a memory now**: judge animated output by early/mid/final frames
        of *every* file, never the last frame of a sample — the last frame is the most occluded
        and least diagnostic. Two of this rebuild's "successes" were artifacts of final-frame
        review.
- [x] ~~⚠️ **BIG HEAD reset to `ea96ce3` (2026-08-19)**~~ *(superseded by the rebuild above; the
      reset's warning — do not re-patch wall geometry — held: the rebuild has no walls.)* A day of fixes took it from 122 to 468 lines — a flare, a crowded/solo split,
      neighbour-gap walls, a per-face raster cache, coordinate rescaling, a render-once guard —
      and every one of them was geometry standing in for a person boundary that segmentation will
      not supply. Each fix traded one artifact for another, so the file was reset rather than
      patched further.
      **What the reset gives back, and it is not nothing:** the two worst bugs of that day were
      introduced by the additions, not present here. There are no stored face lists, so the
      coordinate mismatch that made the effect draw nothing in the app cannot occur — the caller
      owns the space, and it already scales the face. And the head region is a `CIRadialGradient`
      ellipse rather than a rasterised path, so there is no full-frame bitmap per face and no
      24MP crash.
      **What it gives up:** the traced-jaw boundary, so the region is an oval that takes some neck
      and does not follow the chin; head stacking, so enlarged heads in a group blend rather than
      occlude; and the 3× range, which reverts to 1.55×. It also restores the known bug that the
      ellipse is sized from `faceWidth` as a half-extent, which enlarges the whole subject on some
      photos — fixed once in `9486c2b`, and the single cheapest thing to re-apply.
      **Do not re-patch the geometry.** The root cause is filed below: Vision returns one
      foreground instance for a whole group, and `VNGeneratePersonInstanceMaskRequest` is the fix
      that makes the compensation unnecessary rather than better.
- [x] ~~**BIG HEAD — shipped 2026-08-18, rebuilt as a composite.**~~ *(superseded by the reset above)* Cuts the head's outline out of
      the subject mask and scales it on the body. **The first version was a `CIBumpDistortion`
      and was rejected: "just seems like a slightly different fisheye"** — correctly, and the
      reason is worth keeping. A bump warps a disc of the image, so the head grows *and*
      everything near it smears; it is a lens artefact, not a bigger head, and no constant fixes
      that. Scaling a cutout keeps the head's own shape and lets it occlude the body.
      The head silhouette is the subject mask **intersected** with an ellipse round the face —
      the mask alone is the whole body, the ellipse alone is the oval that made ANIME read as a
      vignette. **So BIG HEAD depends on §1g**, which the original bump version did not.
      Constants set by render rather than guess: growth caps at 1.55× (1.85× overflowed the
      frame, and the joke needs the body visible underneath) and the pivot sits 30% up the head,
      not at its base (anchoring lower sent all the growth upward and clipped the ears).
      **`faceWidth`/`faceHeight` are full extents, not radii.** Using them as half-extents made
      the head ellipse up to 3.8× the face, so it enclosed the whole animal and the effect scaled
      the entire subject — reported as "only making the head larger" not happening. `HandsomeEffect`
      halves them for exactly this reason; anything reading these fields should check which it wants.
      **The chin cut follows the traced jaw, not a horizontal line (2026-08-18).** The first
      hybrid cut flat at the contour's lowest point — the chin — and a jaw *rises* toward the
      ears, so that line sat below the jaw on both sides and scooped up neck *(user-reported:
      "still including the neck and not outlining around the chin")*. The region is now the
      contour polygon extended upward: bounded below by the real jaw curve, open above, with the
      subject mask supplying crown and hair. Rendered once and cached on the face and frame size,
      as `AnimeBackgroundEffect` does, so it costs no render per frame. **A curve through
      arbitrary points is not a product of linear ramps** — that is why the gradient approach
      could not be tuned into this and had to be replaced.
      **Head region is a hybrid as of 2026-08-18.** Vision's traced `faceContourPoints` where a
      real contour exists, the ellipse otherwise. Note the contour is *not* a head outline — it
      runs ear-to-ear round the jaw with nothing above the brow, so filling it would cut the head
      off at the eyebrows. It is used only to place the chin cut and the side walls; the
      segmentation mask still supplies crown and hair. Three linear gradients multiplied, no render.
- [ ] 🔍 **The contour path of BIG HEAD is effectively unverified — the corpus cannot exercise
      it.** Every `showcase-*` photo either has an animal (contour comes from body-pose joints,
      not a face) or, in `showcase-3`, a person **facing away**: Vision returns 5 contour points
      at `.estimated` quality. So both device renders so far ran the *ellipse* fallback. The guard
      is now `>= 12 points && quality != .estimated`, which sends those cases to the ellipse
      deliberately — but it means the branch this was built for has never rendered. **Needs one
      frontal photo of a person to judge**, and until then the hybrid is code without a look.
      **Known artifact, not yet addressed:** where the original head extends past the region, its
      edge stays visible beside the enlarged one as a faint ghost. Covering it means filling the
      original head region first — `FaceRegionCompositor.fillRegion` is the existing tool — which
      needs something to fill *with*, so it is the same hole problem PARALLAX is blocked on.
- [ ] ~~**BIG HEAD** *(original note)*~~ — the cheapest item on the intake list, and a face effect
      rather than a visual one. `HandsomeEffect` (`HandsomeEffect.swift:19-27`) already scales
      `CIBumpDistortion` off `face.faceWidth` centred on face landmarks to elongate a jaw; big head
      is the same call with a head-sized radius and a positive scale, so it is one new file
      conforming to `FaceEffect` plus the §2 wiring checklist in EFFECTS.md. Two things to decide
      while building: whether it animates with `progress` (it should — a head that inflates as the
      zoom lands is the joke; a permanently big head is a still) and how it degrades on estimated
      landmarks, where it should distort *less* rather than vanish.
- [ ] **BIG HEAD in a group photo needs `VNGeneratePersonInstanceMaskRequest`, not a better wall.**
      *Measured 2026-08-19 on the fixture corpus.* `VNGenerateForegroundInstanceMaskRequest`
      returns **one** foreground instance for every photo tested — including a three-face and a
      ten-face one. It segments a group as a single blob, so `instanceMask(for:containing:)` has
      no per-person instance to pick and the mask cannot exclude a neighbour. Confirmed by
      reporting the index and count per photo, not inferred: `instances` is 1 across the board.
      **The consequence is that geometric side walls are currently the only thing separating one
      person's head from the next**, and they bound the head by geometry rather than anatomy —
      cutting a straight line through the subject's own hair, which reads as a cardboard cutout.
      Loosening them enlarges every head in the frame; that regression was shipped and reverted
      the same day.
      **`VNGeneratePersonInstanceMaskRequest` (iOS 17+) is the request that actually separates
      people** — up to four, per person rather than per foreground blob. Swapping it in for the
      face-driven effects would let the walls go and the boundary follow the silhouette, which is
      what the user asked for. Two things to check when doing it: behaviour past four people (the
      ten-face photo in the corpus is the test), and that it is *people*-only, so animals still
      need the foreground request — meaning the service likely offers both rather than replacing
      one with the other.
- [ ] **HATCHING (straight lines)** — `CILineScreen` / `CIHatchedScreen` take angle and width
      directly, which is closer than the `CIEdgeWork` route EFFECTS.md suggests. Three screens at
      15°/45°/75°, each masked by a luminance band, composited with darken. Grid effect: needs
      `FrameGeometry` for scale **and** phase, or it crawls exactly as DITHER did.

### 2b. Needs a spike first

- [x] ~~**Pixel Stretch**~~ — **shipped 2026-08-12 as STRETCH.** Built as a kernel, not a
      displacement field. **The spike was deliberately skipped for this one**, and the reasoning
      should be checked before reusing it: the spike existed to avoid *building* kernel
      infrastructure, and §1c has since made a kernel ordinary work. A displacement route would
      still need its offset field built as an image at 8 bits per channel, which bands on long
      smears, to express what the kernel does exactly in about ten lines.
- [ ] **Test whether `CIDisplacementDistortion` covers Pattern Refraction.** Still worth doing for
      *that* effect: it needs a procedural height field, three passes at different scales for
      per-channel dispersion, and that is the trick LENS already uses with `CIZoomBlur`. The
      pay-off is now "one fewer kernel to maintain" rather than "avoid the gate", so it is a
      smaller prize than when it was written.
- [x] **BITMAP — shipped 2026-08-18, and the spike is answered: no kernel needed.** The screen
      is a tiled 8×8 clustered-dot matrix built once as a tiny `CGImage`; thresholding is
      `CISubtractBlendMode` against it followed by a hard contrast, and `CIFalseColor` maps the
      two states to the outer gradient stops. Stock filters throughout — the §1c gate would have
      made a kernel ordinary, but it buys nothing here.
      Grid-aligned as DITHER is: cell scales with `geometry.scale`, phase follows `contentOrigin`.
      **CONTRAST row added 2026-08-18 on the user's call**, and it was the right lever: the first
      render read muddy, and pushing the tones apart *before* the screen compares them separates
      the subject cleanly. It also lifts brightness slightly with contrast, since pushing tones
      apart alone drags the whole image dark — which is how the first render failed.
      **A grid of seams appeared across the image at maximum contrast** *(user-reported)*, from
      two compounding causes, both fixed: the tile was transformed twice — once directly and
      again inside `CIAffineTile`, which transforms *then* tiles — and the cell size was
      fractional, so matrix entries fell between pixels. The cell is now rounded to whole matrix
      widths and the tile is sampled nearest. **A threshold screen must land on whole pixels**;
      interpolating a lookup table produces values that threshold inconsistently, and a steep
      threshold turns that into visible structure.
      **Note the MID gradient stop is inert**: a 1-bit screen has two states, and the picker shows
      three wells because it is the shared `.gradientStops` row.
- [ ] ~~**BITMAP** *(original note)*~~ — a 1-bit **clustered-dot** ordered dither in **two arbitrary
      spot colours**. Spec in [EFFECTS.md](EFFECTS.md#bitmap--1-bit-clustered-dot-duotone).
      **It is not DITHER's deferred MONO row**, and filing it there would build the wrong thing:
      DITHER is `CIDither`'s *noise* posterised toward grey levels (`DitherEffect.swift:96-105`),
      where the reference's midtones resolve into a regular crosshatch — the signature of a
      clustered-dot matrix, which noise cannot produce at any setting. DUOTONE has the colour
      mapping but no screen at all (`DuotoneEffect.swift:38-46`); HALFTONE has a screen but it is
      `CICMYKHalftone`'s four-channel rosette, in full colour.
      **The spike is where the screen comes from**: whether a stock route (desaturate → threshold
      against a tiled clustered-dot pattern → the two-colour matrix) reaches the look, or whether it
      wants a small ordered-dither kernel. The §1c gate passing makes the kernel branch ordinary
      work rather than a blocker, so the spike is about fidelity, not risk.
      **Grid effect either way** — the screen cell must scale with `FrameGeometry.scale` and
      phase-align to `contentOrigin` exactly as DITHER does (`DitherEffect.swift:55-90`), or the
      pattern crawls across the subject as the animation pans.
- [ ] **PARALLAX / SUBJECT MOTION** *(new, 2026-08-18; depends on §1g)* — the "3D photo" move, plus
      subject bounce, pulse and rotation. Grouped because they share one problem and it is the only
      genuine research risk on the intake list: **moving the subject reveals a hole where it was**.
      The spike is whether a cheap fill hides it — the background scaled ~5% about the subject
      centroid and blurred, which is what most "3D photo" implementations actually do — or whether
      the motion has to stay small enough that the hole never leaves the silhouette. If neither
      works it needs real inpainting, which is a different project. **Do not schedule the effects
      past this spike**; the bounce/pulse/rotate variants are trivial once the fill question is
      answered and unbuildable until it is.

### 2c. Kernel effects — **unblocked 2026-08-12**, the gate in §1c passed

The build rule, a working `CIKernel` load path, and a regression test that the canvas border's
library stays stock are all in place. These three are now ordinary work. Read EFFECTS.md's colour
space and ROI notes before starting any of them — the gate proved the pipeline, not the math.

- [x] ~~**Riso Print**~~ — **shipped 2026-08-12 as RISO**, the app's first custom kernel. Ported
      from `reference/riso-print.wgsl`: misregistration, Rec.601 luminance (deliberately — the
      band edges were tuned against it), contrast, tonal-band separation, three halftone screens
      at 15°/75°/45°, subtractive composite onto warm paper, additive grain.
      `GradientStops` supplies the three spot colours — kept **on its own merits**, since
      shadow/midtone/highlight *is* dark/mid/light, not to squeeze under a budget.
      Six rows: INTENSITY, SCALE, OFFSET, GRAIN, CONTRAST, COLOURS. CONTRAST is not decoration —
      without it a flat photo collapses into the midtone band and prints as one colour.
### Device check — queued 2026-08-12, all on one pass

The design pass changed things only a real screen settles. Build verified for `generic/platform=iOS`
(all four `.ci.metallib` files present and built for `air64_v27-apple-ios18.2.0`, `default.metallib`
still stock), so this is a Run-and-look, not a debugging session.

- [ ] 🔍 **Settings, unselected rows.** Went from `.white.opacity(0.5)` to full white. The largest
      visible change from the content-state decisions and **never seen** — Settings sits behind the
      gallery, which needs a saved GIF, and the simulator had none.
- [ ] 🔍 **Disabled brightness.** `contentInactive` (#D1D1D1, ~82% grey) replaced `.white` at
      0.3–0.5 on RESET, undo, redo and the save button. Flagged before implementing: disabled may
      now read as available. Look at the top bar with no history.
- [ ] 🔍 **Selection by colour alone.** Unselected is now identical to ordinary text, so `enhanceMint`
      is the only cue. Fine in the abstract; the question is whether a Settings row reads as
      "chosen" at a glance.
- [ ] 🔍 **RISO's six-row panel on device.** On an SE 3 *simulator* only the first three rows are
      reachable: a synthesized drag on a row moves that slider (the `minimumDistance: 0` gesture
      winning) and a drag in the margin does nothing. **The user reports the scroll working on a
      real device on 2026-08-11**, and synthesized touches are a poor instrument for exactly this
      kind of gesture conflict, so that is the better evidence — but confirm it, because if the
      simulator is right then GRAIN, CONTRAST and COLOURS are unreachable on the shortest screen.
      *Note what §1a does and does not establish here:* it verified a slider still works while the
      panel is scrollable. It never verified that a user can scroll **to a row below the fold** —
      different claims, and only the first was tested on the 4-row SLIDE preset.
- [x] ~~**Water Caustic**~~ — built and then **withdrawn 2026-08-12 on the user's call**: the look
      was not wanted. Added to `VisualEffectType.retired`, so it stays compiled and tested rather
      than deleted — one line brings it back, and meanwhile it is the second worked example of the
      kernel path. **Do not re-propose it without asking.**
      The technique was sound and is worth keeping in mind: a Worley cell-wall network built
      analytically, because the smeared-noise rule in LEARNINGS rules out noise-plus-blur for
      discrete structure. Its one genuinely reusable idea is the **seamless loop** — feature points
      orbit with period 1 and SPEED is quantised to a whole number of orbits, so progress 0 and 1
      render the same frame and the GIF does not jump on wrap. Any future animated procedural
      effect wants that, and `CausticTests` has the test that pins it.
- [ ] **Hatching line styles** — wave, zigzag, concentric. Arbitrary substitutions into the `sin`
      argument, with no stock equivalent. The straight-line version in §2a needs none of this.

### 2d. Control audit ✓ done 2026-08-11

Nine shipped effects collapse independent qualities into one INTENSITY slider, or hardcode a value
a user would reasonably want to change. Candidates are named with file and value in
[EFFECTS.md → Control audit](EFFECTS.md#control-audit--effects-with-hidden-parameters).

**Eight of the nine fit inside the verified three-row ceiling** — checked against each effect's
current row count, not assumed. An earlier version of this section called most of them blocked;
that was written while three rows was still believed marginal.

| effect | rows now | adds | after |
|---|---|---|---|
| MOTION BLUR | 1 | ANGLE | 2 |
| SWIRL | 1 | SIZE | 2 |
| CHROMA SHIFT | 1 | ANGLE | 2 |
| RAINBOW | 1 | SPEED | 2 |
| PIXELATE | 1 | SHAPE | 2 |
| HALFTONE | 1 | SHARPNESS + ANGLE | 3 |
| HEAT HAZE | 1 | FREQUENCY + SPEED | 3 |
| GRADIENT | 2 | MIDPOINT | 3 |
| **DITHER** | 2 | LEVELS + MONO | **4 — over** |

- [x] ~~**The eight that fit**~~ — all shipped 2026-08-11, each with its midpoint reproducing the
      constant it replaced, proved against the old implementation byte for byte: MOTION BLUR (ANGLE — a directional blur whose
      direction is hardcoded to 45°), SWIRL (SIZE — a parity gap, FISHEYE already exposes it),
      HALFTONE (SHARPNESS + ANGLE, both already supported by `CICMYKHalftone`), CHROMA SHIFT
      (ANGLE), HEAT HAZE (FREQUENCY + SPEED), GRADIENT (MIDPOINT), RAINBOW (SPEED, which the face
      variant already has), PIXELATE (SHAPE — `CIHexagonalPixellate` makes hex nearly free).
- [x] ~~**PIXELATE's SHAPE is not a `Double`**~~ — shipped as `PixelShape`, a typed property on the
      view model plus an `EditorSnapshot` field, with a new `EffectParameter.Kind.pixelShape`.
      Note this made `supportsColorPicker` and "has a picker row" stop being the same thing;
      `visualEffect_parameterDeclarationsAreWellFormed` now checks the colour kinds specifically.
- [x] ~~**DITHER: ship LEVELS, defer MONO.**~~ LEVELS shipped — it decouples posterisation depth
      from dither amplitude, which was the actual complaint. **MONO stays deferred, but the reason
      changed**: a fourth row was thought unrenderable, and text overlays has since shipped four
      rows on an SE 3. It would scroll, which is a worse panel rather than a broken one. Revisit as
      a UX call, not a blocked one.
- [ ] Prefer **splitting coupled qualities** over inventing new ones. Most of these are one slider
      driving two independent things; separating them makes currently-unreachable looks reachable
      without changing what the effect is.

### 2e. Follow-ups on shipped effects

- [ ] **Edit down the shipped set, the slider spans, and the card thumbnails** in EFFECTS LAB
      (SETTINGS → LABS) rather than by hand — see `FEATURE-EFFECTS-LAB.md`. COPY SWIFT hands back
      the `retired` literals and the `EffectTuningTables` tables; paste, RESET ALL, delete the lab.

- [ ] **THIRD EYE's ray colour should follow the COLOUR pick.** Currently hardcoded warm gold while
      the eye tints. LAZER EYES tints its whole glow, which is part of why it reads as cohesive.
      One `CIColor` in `ThirdEyeEffect`.
- [ ] **THIRD EYE edge cases**, opportunistic: the 4× 12-frame floor across Zoom In/Out/Pulse, and
      the animal/estimated-landmark fallback — it works from a pupil plus eye width, so it should
      degrade rather than vanish.
- [ ] 🔍 **DITHER motion during the zoom.** Cell size scales with `FrameGeometry.scale` and phase
      follows `contentOrigin`; the mechanism is proven by `dither_phaseIsPeriodicInCellSize`, but
      the result has never been watched in a real GIF. **If it still crawls, the prime suspect is
      the Y-flip in `GIFGenerator.frameGeometry`** — that line was reasoned about, not measured.
      Log `contentOrigin` per frame and confirm it moves monotonically with the pan.
- [ ] 🔍 **DITHER legibility after GIF palettisation** — does the stipple survive 256-colour
      quantisation, or read as noise? The SCALE slider is the first lever if it needs help.
- [ ] 🔍 **GRADIENT colour wells** — confirmed working, but never seen alongside the rest of the row
      on device.
- [ ] **The BACKGROUND ONLY row sits on the panel's bottom edge and I could not scroll to it.**
      *Seen in the Simulator 2026-08-18.* Adding the toggle takes CHROMA SHIFT to three rows, and
      the card is then clipped mid-height by the panel's lower edge. The scroll nudge appears — so
      `needsScroll` is true — but neither a swipe, a slow `touch_path`, nor tapping the nudge moved
      the content. Unclear whether that is a real scroll failure or synthetic-touch flakiness
      against this `ScrollView`; **a real finger on a device settles it in seconds**, which is why
      it is filed rather than fixed. Directly adjacent to the RISO six-row check above, and RISO is
      now seven rows, so the two should be looked at in one pass.

### 2f. Subject-mask effects — **blocked on §1g**

*Filed 2026-08-18.* Five effects that all consume the same segmentation mask and differ only in
what they do with the two halves.

**The shared half is built** — `Services/Animators/SubjectMaskCompositor.swift` (2026-08-18, 11
tests): `subject(of:over:mask:geometry:)` for the four "hold the subject, replace the background"
variants, `applyingToBackground(_:of:mask:...)` for the face-cutout case, and `cutout(of:mask:)`
for the ones that move or repeat the subject. Every entry point returns the frame untouched on a
`nil` mask, which is the §1g no-subject requirement honoured once instead of five times.

**It also forced a change to `FrameGeometry`, and the reason generalises.** Effects run *after*
the zoom/pan transform while the mask is produced in the photo's own pixel space, and mapping one
to the other needs the aspect-fill factor as well as the zoom — which `FrameGeometry` did not
carry, since a dither cell only ever needed the zoom. It now has `contentScale` (defaulting to 1,
so the preview path and all fifteen shipped effects are unaffected) and a `sourceToFrame`
transform. Without it the cutout drifts off the subject as the frame pans, and it would read as a
segmentation failure rather than a geometry one. Any future effect carrying *source-space* data
has the same problem and the same fix. None is buildable until §1g's spike proves the mask is good
enough at GIF resolution; all are ordinary compositing work after it. Specs are collected in
[EFFECTS.md](EFFECTS.md#subject-mask-effects--one-mask-five-composites) rather than repeated per
row, because the mask is the hard part and it is shared.

- [x] **FACE CUTOUT + background effects — shipped 2026-08-18 as the BACKGROUND ONLY toggle.**
      A `.toggle` `EffectParameter` on every selectable effect (last row, off by default),
      wrapping the built effect in `BackgroundOnlyEffect` at `activeVisualEffectList` — the one
      choke point the preview and the GIF both read. Segmentation is paid when the toggle is
      switched on, not on photo load, and absence follows the face precedent: a
      "NO SUBJECT DETECTED" toast with the card left live, gated to once per photo so it does
      **not** repeat the face tab's re-toast bug (§4).

      **The finding, from rendering it on device — and it is sharper than the banding note in
      §1g.** What matters is not how an effect handles colour but **whether it samples its
      neighbourhood**:
      - *Pointwise* effects (MONOTONE, DUOTONE, INVERT, RISO, DITHER) are **clean**. Each output
        pixel depends only on its own input, so the mask cuts exactly.
      - *Neighbourhood-sampling* effects **bleed the subject into the background**, because the
        effect runs on the whole frame — subject included — and the mask only chooses afterwards.
        MOTION BLUR leaves a faint warm halo around the silhouette; SWIRL drags a clearly visible
        brown smear of the cat out into the couch. The subject itself stays sharp, so it reads as
        a ghost beside a clean subject rather than as softness.

      **Open, and a taste call rather than a bug**: whether to keep the toggle on the
      neighbourhood-sampling effects. Renders were shown to the user on 2026-08-18. The fix if
      it is unwanted is not cheap — the background would have to be inpainted where the subject
      was before the effect runs, which is the same problem PARALLAX is blocked on — so the
      realistic options are *accept the ghost* or *withhold the toggle on those effects*. The highest-leverage idea on the list, because it
      is a *multiplier* on effects that already exist rather than a new effect. **It needs a design
      call before code**, and it is the same call §3d raises: is background-only application a
      per-effect toggle, a modifier like SHAKE, or a new set of cards? Decide it against §3d
      stacking, not in isolation — they are the same question about whether an effect can be scoped
      to part of the frame.
- [ ] **TEXT BEHIND SUBJECT** *(and "partially obscured by the subject" — the same composite)* —
      the text raster is drawn between background and subject, so the subject occludes it. **This
      touches the text-overlay system, which is owned by another session (§3a) and whose Stage G
      hardening is still open** — coordinate before starting, do not fork the rasteriser. The seam
      is already in the right place: the rasteriser keeps the glyph coverage mask as a distinct step
      (§3a), so compositing under the subject mask is a layering change, not a rasteriser change.
- [x] **SUBJECT REPEATED INTO A PATTERN — shipped 2026-08-18 as the ECHO visual effect.**
      Built to the user's brief: *outlines of the subject radiating out from it*. Mechanically the
      row as written — N transformed copies of the cutout behind the original — with two choices
      that change what it reads as: each copy is reduced to its edge by `CIMorphologyGradient`,
      and the copies scale about the subject rather than tiling, so it reads as one subject with
      an aura instead of several subjects. The rings travel outward with `progress`; static rings
      read as a sticker border.
      **Rendered on device before shipping** (`subjectEcho_rendersRadiatingOutlines`), at two
      spreads and two colours.
      **ECHOES row added 2026-08-18 on the user's call** — five was too few, and the ceiling of
      six came from a guess about the rings merging that the render did not bear out; with SPREAD
      open a dozen stay separate. Range is 3…14, the floor being where a lone offset outline
      still reads as a registration error. One thing left deliberately simple: 
      the rings expand about the mask's *extent centre* rather than a true centroid, because a
      real centroid needs a render and these graphs must stay lazy. A subject well off to one side
      will see the rings lean toward frame centre — the fix would be to carry a centroid on the
      mask from the service, which already has a `CIContext`.
      **BACKGROUND ONLY is deliberately not offered on it**: it is already a subject effect, so
      the modifier would mask it with the same mask it draws from.
- [x] ~~**ANIMATED BACKGROUND, STATIONARY SUBJECT**~~ — built and then **withdrawn 2026-08-18 on
      the user's call**, the fourth effect declined on look (after HATCHING, BOKEH and Water
      Caustic). The manga impact burst was not what "animated background" was wanted for; the
      subject-outline idea below is. The card is unwired and `AnimeBackgroundEffect` is back to
      being unreferenced — deliberately kept compiled rather than deleted, exactly as §2c does
      for Water Caustic, since its subject-mask cutout is a working example of the pattern.
      Original note follows.
- [x] **(original) shipped 2026-08-18 as the ANIME face card.**
      **Correction to what this row used to say:** `AnimeBackgroundEffect` was described here as
      an existing effect to upgrade. It was not — it had no `FaceFilterType` case and was
      unreferenced anywhere outside its own file, so it was dead code rather than something a
      user could reach. Wiring the card was therefore part of the work, not a given.
      It now takes the segmentation mask when there is one and falls back to its original
      feathered ellipse when there is not, which keeps the card live on the 1-in-8 photos with no
      subject (§1g). Controls are INTENSITY and LINES.
      **No `FrameGeometry` mapping is needed here, unlike the visual-effect path**: face effects
      run on the un-zoomed source (`GIFGenerator.faceEffectedSource`), so a source-space mask
      already aligns. Worth knowing before the next §2f effect — whether a mask needs mapping
      depends entirely on which of the two pipelines the effect sits in.
- [ ] 🔍 **Look at ANIME's two cutouts side by side.** The upgrade is only worth having if the
      silhouette visibly beats the ellipse. A device render was set up
      (`SubjectSegmentationDeviceTests.animeBackground_realMaskVersusEllipse`) but the phone went
      offline mid-run, so **this has never been looked at** — the effect is green and unseen,
      which per EFFECTS.md means nothing about how it reads. Any procedural background wants
      Water Caustic's **seamless-loop** trick — feature points orbit with period 1, speed quantised
      to whole orbits so progress 0 and 1 render identically — pinned by `CausticTests` and recorded
      in §2c, so the GIF does not jump on wrap.

### 2g. FACE SWAP — mechanism ready, look unproven

*Filed 2026-08-18; taste-gated, not blocked.* Swapping two faces within one photo. **The
compositing mechanism already exists**: `FaceRegionCompositor` samples a region, transforms it, and
re-composites under a feathered elliptical mask from `FaceRegionMaskBuilder` — a swap is two such
composites with the source and destination rects exchanged. Two things make it a taste gate rather
than a build task:

- **It is the first effect that requires ≥2 faces.** No effect today has a face-cardinality
  precondition; face effects run per selected face and degrade to one. Swap needs a defined,
  non-embarrassing behaviour on a one-face photo (do nothing? disable the card?) — decide it before
  building, not after a user reports a self-swap.
- **Skin tone and lighting will not match** between two arbitrary faces, and an unmatched swap reads
  as a collage rather than an effect. It likely needs a rough tone-match pass (mean-colour shift
  under the mask), and whether even that is enough is a looking question.

**Render one before committing to it.** This is the exact gate that stopped HATCHING, BOKEH and
Water Caustic — three effects declined on the user's call after the approach was proved — so treat
a working composite as the *start* of the decision, not the end.

---

## 3 — Product bets

Judged on upside; nothing is waiting on them.

### 3a. Animated text overlays — **owned by another session**

Stages A–F are on `main`. Full plan in [FEATURE-TEXT-EFFECTS.md](FEATURE-TEXT-EFFECTS.md)
(revision 2).

- [ ] **Stage G — hardening.** Emoji, composed characters, ligatures, multiline and RTL, plus
      profiling on the oldest supported device. Known gaps from device testing: preset cards render
      blank thumbnails; edge clamping has no rubber-band and rotation no haptic detents; no
      VoiceOver adjustable actions. One carries beyond this section — **STYLE is withdrawn** until
      the rasterizer can draw decoration in a second contrasting fill (a shadow currently renders in
      the text's own colour). *(The other, "a first-time save cannot restore its text", was the
      §1e asset-id gap and is **fixed** — `persistTextOverlay` now runs on both save paths.)*
- [ ] Deliberately after V1: **fill effects** (static and animated gradients, sparkle) and **font
      choice**. `TextFont` already models five cases; V1 ships Silkscreen Bold and no picker. The
      rasterizer keeps the glyph coverage mask as a distinct step so the seam is in the right place.

*Status here is intentionally thin — that session maintains it.*

### 3b. Themes — a migration, not a feature

Blocked on §1d. [FEATURE-THEMES.md](FEATURE-THEMES.md) holds the slot contract, the staged
migration, and the boundaries of what must *not* follow a theme.

- [ ] Appearance (light / dark / system) × user-authored colour schemes. Colours only.
- [ ] Custom app icons — pick a GIF from the gallery, set its thumbnail as the app icon.
- [ ] Pixel-art icons for the remaining UI elements.

### 3c. Design system, Phase 3 — beyond the CI split in §1b

- [ ] SwiftLint banning raw colours and fonts outside `Design/` (needs §1d complete to pass).
- [ ] A `ComponentGallery` catalog, and `#Preview`s for the 13 of 19 components that lack them.
- [ ] Snapshot tests and an accessibility baseline. **Note this will not cover effects** —
      EFFECTS.md is blunt that structural tests cannot see a wrong-looking effect, and both
      `extent ==` and `createCGImage != nil` passed while EDGES rendered cyan instead of green.
      Effect verification stays render-to-PNG-and-look, plus device QA.
- [ ] `AGENTS.md` — the contribution rules, enforceable once the lint exists.

### 3d. Effect reuse and stacking (needs design)

Both are more feasible than they look, because groundwork landed for other reasons.

- [ ] **Copy settings between photos.** `EditorSnapshot` is already the payload, and undo/redo
      round-trips it; the work is deciding what *not* to carry. `selectedFaceIndex` is meaningless
      on another photo, zoom should stay out, and a face filter pasted onto a faceless photo needs a
      defined outcome. **In-session copy avoids a migration concern that saved presets do not** —
      parameter ids are in-memory only today, so the "ids must not change once shipped" warning does
      not yet bite. Persist `GradientStops.resolved`, never the SwiftUI `Color`s.
- [ ] ⚠️ **Stacking reverses a documented decision.** The pipeline already supports it —
      `generateGIF` takes `[VisualEffect]`, chained lazily, so N effects still cost one render per
      frame — and values are keyed per effect, so each keeps its own settings. Only the single
      optional `selectedVisualEffect` stands in the way. But effects *were* stackable and were
      deliberately made exclusive: LEARNINGS 2026-03-08 records that chained CIFilters "produced
      unpredictable, unpleasant results." **Read that entry before starting.** Its own suggested
      path — curated presets rather than free-form combination — is the cheap first step, with the
      same visual payoff and no new UI concept to invent. Order matters either way; CIFilter chains
      are not commutative.

### 3e. Other bets

- [ ] **Effects rethink** (needs design): an IG-style colour-filter category; auto-zoom toward a
      detected face when no zoom is set; and making "toggle off all zoom types" reset the canvas to
      1× rather than holding the user's position.
      **The auto-zoom half now has a first step shipped**, behind the MAKE GIFS WITHOUT ZOOMING
      experiment (`FeatureFlags.zoomOptional`): with no pinch, generation falls back to
      `ZoomFraming.fallback` — 2.5× on the centre, the framing the ZOOM cards already preview in
      that state. Aiming that fallback at a *detected face* rather than the centre is the same
      substitution with a better target, and touches one property
      (`EditorViewModel.generationFraming`).
- [ ] **Onboarding**: five default photos demonstrating the app; a "give the gift of a GIF" viral
      unlock for face effects.
- [ ] **Settings & social**: RATE THE APP (`SKStoreReviewController`), SHARE WITH FRIENDS
      (a `ShareLink` with the App Store URL — nothing to design), and **BUY ME A COFFEE** *(new,
      2026-08-18)*. One constraint on the coffee tip that decides the whole shape of it: a tip for a
      *digital* good must be a **StoreKit consumable IAP**, not a link out to buymeacoffee.com or
      similar — an external payment link for digital content is an App Store rejection under the
      IAP rules. So it is a small StoreKit product plus a thank-you state, not a web link.
- [ ] **Editor UX**: a stateful save button; pause/edit during preview playback; RESET/X spacing in
      the header (RESET currently reads as a label for X); a crosshair showing the zoom focal point;
      fix the action-button copy.
- [ ] **New animation styles**: Bounce, Dramatic Zoom, Loop Zoom.
- [ ] **View transitions**: Gallery↔Editor open/save motion, effect-tab/carousel switching, and
      tile press feedback, tunable live via a proposed MOTION LAB. Full plan in
      [FEATURE-VIEW-TRANSITIONS.md](FEATURE-VIEW-TRANSITIONS.md).
- [ ] **UNDO for existing-GIF editing** — revert all changes back to the saved original.
- [ ] **Real-time preview via Metal shaders** (iOS 17+ `.colorEffect()` / `.distortionEffect()` /
      `.layerEffect()`), replacing the CIFilter preview path. Note this is a *preview* technology
      and cannot render GIF frames — it does not substitute for §1c.
- ~~**iMessage stickers / Messages extension**~~ — **parked 2026-08-18** on the user's call, from
      the same ten-idea intake. Not deleted, because two findings stay true if it is revived and are
      worth not re-deriving:
      - **The hard part is the export, not the framework.** `MSSticker` is trivial; Messages caps a
        sticker at roughly **500 KB and 618×618**, and the app's GIFs are 600×600 and routinely
        heavier. A sticker-optimised export (frame cap, palette reduction, resize) is the real work
        and would be the *first* work. The "reaction-sticker mode" pitched in the source chat —
        cutout, tight crop, big text — is just §1g's subject segmentation again, so the two programs
        converge rather than competing.
      - **The extension's storage requirement is already a P0 fix in disguise.** A Messages
        extension needs an **App Group** shared container to see the app's exports. §4 P0 Stage B
        already wants originals moved out of `Caches/`; pointing that move at an App Group container
        instead of `Application Support` solves the purge bug *and* pre-wires the extension — one
        migration, two payoffs. See the note left on that item.

### 3f. Open questions — decide either way, then record it

- [ ] **`ColorPicker` aesthetics.** The system colour wheel is a modal iOS sheet, against Silkscreen
      pixel-art styling. Accepted deliberately for the colour freedom; revisit if it grates in use.
- [x] ~~**Zoom is always on.**~~ **Decided 2026-08-12: it is not.** Every carousel now opens with an
      ORIGINAL card that clears its selection (`EffectChoice`), so the `nil`-animator paths are
      reachable and effects-only GIFs at 1× are possible. This section predicted correctly that
      reversing it would be a UI change rather than a re-implementation, and its warning was live:
      `activeAnimator` did discard the modifier when no zoom was selected, so ORIGINAL + SHAKE
      would have generated a still for a user who asked for movement. Fixed in the same change
      (`EditorViewModel.swift`, `activeAnimator`).
      **One known consequence, not fixed:** SHAKE over ORIGINAL with no pinch behind it jitters a
      1× framing, so up to ~4% of the frame edge can read black before the shake decays. It needs
      headroom to hide the pan, which any zoom provides and 1× does not.
- [ ] **Undo does not capture zoom.** `EditorSnapshot` has no `currentScale` / `visibleRect`, so
      pinch/pan is not undoable, and undo after a zoom restores effects against different framing.
      May be intentional — needs a decision either way.

---

## 4 — Defects

Ordered by severity. Each names the file where the defect lives. Found by code review unless marked
*(user-reported)*.

### P0 — Data loss (perceived)

**Gallery GIFs disappear after the app sits unused** *(user-reported)*. Four defects composed into
one failure; the assets were never lost, but the gallery could not re-resolve them and then deleted
its own cache. **Stage A is fixed** — see [HISTORY.md](HISTORY.md) for the four causes and their
repairs. Stage B remains:

- [ ] **Decouple display from URL resolution.** A GIF is still shown only when *both* thumbnail and
      URL resolve (`GIFLibraryService` intersection, `GalleryView.swift:50`), so any future URL
      failure still drops it from the grid — the trigger is fixed, the failure *mode* is not.
      Replace the three parallel arrays with one `[GifItem]` (`assetIdentifier`, `thumbnail`,
      `url: URL?`) and resolve lazily on tap. Around 9 sites in `GalleryView`.
- [ ] **Consider moving originals out of `Caches/`** to `Application Support/MyGIFs/` with
      `isExcludedFromBackup = true`, so iOS never purges them in the first place.
      **When this is done, weigh an App Group container against `Application Support`.** A future
      iMessage extension (parked, §3e) can only read the app's exports from a shared App Group
      container, and this is the migration that decides where they live — so targeting the App
      Group now costs nothing extra and pre-wires that feature, while `Application Support` forecloses
      it until a second migration. Don't build the extension; just don't move the files somewhere it
      can't reach them.

### P1 — Correctness

- ~~**Newly-saved GIFs never persist their zoom params**~~ — moved to §1e because the same missing
  asset id also blocked text-overlay restore, and **fixed there on 2026-08-11**. One fix, two
  features, as predicted.
- [ ] **Saving a photo sometimes uses a different photo's frame** in the gallery thumbnail.
- [ ] **Onboarding tagline truncates on SE 3** — "DRAMATIC ZOOMS AND S…". A fixed font size against
      a narrower screen.

### P2 — Performance

- [ ] _(deferred)_ **Frame streaming** — decode GIF frames during playback instead of loading all of
      them into memory.
- [ ] _(deferred)_ **Profile and reduce GIF generation time** — CGContext reuse, parallel frame
      rendering.

### P3 — Polish

- [ ] **`previewProgress` is implemented three times, and two of them are identical.** A card
      sampled at one shared instant misrepresents any effect that peaks at a different time, so
      each card-bearing type has grown its own answer:
      `VisualEffectType.swift:119` and `FaceFilterType.swift:78` are the *same logic with
      paraphrased comments* (`pixelate → 0.2`, everything else `1.0`), and
      `TextAnimationType.swift:122` is the same concept with genuinely per-case values.
      **Both duplicates conform to `ParameterizedEffect`** (`EffectParameter.swift:86`) and nothing
      else does, so folding them into a protocol default — 1.0, overridden per type — is a few
      lines rather than a refactor. The text one is legitimately separate; leave it, but have it
      point at the shared idea.
      *Who hits this next:* whoever adds an effect that peaks anywhere but full strength. They will
      edit one enum, ship, and find the other card still wrong. That has now happened twice.
- [x] ~~**Face boxes vanish on the face tab once a GIF exists.**~~ *Fixed in `143bf07`.* Residual of
      the `wantsLiveCanvas` fix (`84fea9e`), which consolidated the two sites deciding *which
      canvas* but left `EditorView.activeFaceOverlays` and `faceStatusOverlay` gating on the old
      `isSplit` proxy — so after ENHANCE the live canvas returned with the effect visible but **no
      tappable face boxes**. Both now consult `viewModel.showsLiveCanvas`
      (`EditorView.swift:1196` and `:1207`). Found by grepping the proxy the fix replaced — see
      LEARNINGS 2026-08-11 on converting every reader.
- [ ] **Face cards render blank when no faces are detected.** *Seen on device 2026-08-18.*
      `generateFaceFilterThumbnails` returns early on `guard let face = detectedFaces.first`
      (`EditorViewModel.swift:926`), so the FACE carousel on a photo with no faces is a row of
      empty grey rectangles with labels — the cards stay tappable, which is the intended pattern,
      but they look broken rather than inapplicable. Cheapest fix is to fall back to an unmodified
      crop of the photo so the card shows *something*. **Decide this before the first §2f effect
      ships**, because the subject carousel inherits the same shape (§1g).
- [ ] **"NO FACES DETECTED" toast repeats.** `detectFacesIfNeeded` guards on `detectedFaces.isEmpty`
      (`EditorViewModel.swift:346`), which stays true forever when detection legitimately finds
      nothing, so every return to the face tab re-runs detection and re-toasts. Needs a separate
      "has run" flag.
- [x] ~~**`PhotoManager` uses `assign(to:)`, contradicting LEARNINGS.**~~ *Resolved 2026-08-11 — the
      code is right and the rule was over-broad.* `assign(to: &$published)` republishes *through*
      the `@Published` wrapper and does fire `objectWillChange`; it is `assign(to:on:)`, the
      key-path overload, that bypasses it (and retains the target). The LEARNINGS entry has been
      narrowed rather than deleted — the 2026-03-08 bug was real, but its cause was misattributed.

### Device verification 🔍

Landed and green, never confirmed on hardware. Effect-specific items are in §2e.

- [ ] **`4×` and `0.25×` playback actually play at those rates.** The hazard:
      `frameCount = max(12, Int(1/speed/0.04))` floors at 12 above 2×, so 4× yields 12 frames at
      ~0.0208s — and **many decoders round delays under 0.04s up to 0.1s**, which would make 4× play
      *slower* than 1×. The range was unreachable before, so exposing it exposes the bug for the
      first time. If it misbehaves, floor the *delay* and cut the duration rather than flooring the
      frame count.
- [ ] **A `0s` pause reads as no pause.** `max(1, …)` still emits one ~0.04s frame; confirm that is
      invisible rather than a stutter.
- [ ] **Zoom card gallery scroll feel** with only three cards, which do not fill the width.

---

## Architecture

```
App/              → Entry point, font registration
Models/           → Data types (AnimatorType, ModifierType, VisualEffectType, EffectCategory,
                    DetailContent, GradientStops, Text/*, etc.)
Services/         → Business logic (GIF generation, photo library, permissions, face detection,
                    EffectThumbnailRenderer — the picker cards, shared by the editor and EFFECTS LAB)
  Animators/      → Animator + MotionModifier + VisualEffect protocols, CompositeAnimator,
                    per-effect files, FaceRegions/ compositor
  Text/           → Text layout, rasterization, tile compositing
Features/
  Gallery/        → Gallery screen + pinch-to-reflow grid
  Editor/         → Editor screen + logic (EditorView, EditorViewModel)
Views/            → Settings and the labs (GRADIENT, FACE MARKER, MOTION, HEAD MASK, BUTTON TEXT,
                    SHADER, EFFECTS) — scaffolding, each with a delete-on-graduation contract
Components/       → Shared reusable UI
Design/           → Tokens, modifiers, typography, PanelMetrics
Extensions/       → Swift extensions
Shaders/          → Pixellate.metal (SwiftUI [[stitchable]], canvas border only — see §1c)
Docs/             → This file, HISTORY, EFFECTS, LEARNINGS, DESIGN_SYSTEM, feature plans
```
