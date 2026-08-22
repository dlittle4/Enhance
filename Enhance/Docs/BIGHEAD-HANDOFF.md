# BIG HEAD — handoff for a fresh pair of eyes

*Written 2026-08-21 after three days and ~26 commits on one effect. Audience: an agent or person
who has not seen any of it and is being asked for ideas we have not had. Everything here is
either measured on real photos/hardware or marked as a guess. Please do not re-derive what is
marked measured; please do challenge anything marked as a decision.*

---

## 1. The goal, and what "working" means

**BIG HEAD**: a face effect in an iOS GIF-maker. The subject's *head* — hair, hat, ears, chin —
is cut out and scaled up (up to ~3×) on the body, growing as the animation plays, so it reads as
a cartoon big head sitting on a normal body. A composite, not a distortion.

**Acceptance, as set by the user across reviews:**

| Case | Must |
|---|---|
| Solo, front-facing | Head outline follows hair/hat/chin; neck and collar stay behind |
| Profile / tilted head | Back of the skull included; cut follows the actual jaw, not a horizontal line |
| Groups (2–10 people) | Each head grows as its own cutout; heads **occlude**, never cross-fade; no neighbour's pixels ride along |
| Animals (cats are the app's showcase content) | Still works via a fallback; must not regress |
| No face / no subject | Frame returned untouched; a toast, cards stay live |

The user judges by eye, on an 11-photo fixture corpus they supplied (`EnhanceTests/Fixtures/`,
git-ignored, personal photos): solos, a profile, a cap-wearer, 2/3/4/8/10-person groups, a
24MP photo. Every render claim below was checked against those, on a physical iPhone.

## 2. Platform facts we measured (do not re-derive)

1. **`VNGenerateForegroundInstanceMaskRequest` cannot separate people.** Returns ONE instance
   for every group photo in the corpus (3, 4, 8, 10 faces alike; one 24MP photo returned 2).
2. **`VNGeneratePersonInstanceMaskRequest` does separate people**, cleanly up to its cap of
   four instances (2→2, 3→3, 4→4 on the corpus); beyond four it merges neighbours into shared
   instances that are still 2–3-person subsets. Warm cost 10–16 ms; ~97 ms cold model load.
   Hair/hat edges in its masks are good. Instance label at a face centre is occasionally the
   neighbour's (a tilted head whose centre lands near the collar) — a small patch vote fixes it.
3. **Vision's face contour is the face oval — cheeks, not the jaw, and nothing above the brow.**
   17 points by default; the 76-point constellation (revision 3) is denser but the same shape.
   Ears sit *outside* it. Usable to place a chin cut; useless for the crown.
4. **`VNFaceObservation` gives roll/yaw/pitch** on the same observation — free head pose.
5. **Vision segmentation throws on the iOS Simulator.** Only device runs exercise it; unit tests
   inject stub providers. This shaped the whole test strategy.
6. **Apple ships no head-segmentation primitive.** Person silhouettes yes; the head/body split
   inside them is left to the app. The industry's answer (TikTok Effect House, Snapchat Portrait
   Head) is a purpose-trained head-segmentation model — see §7.
7. **Portrait-mode photos embed hair + skin mattes** (`AVSemanticSegmentationMatte`) readable
   from the file — the best head boundary available anywhere, but only on Portrait captures.
8. **The accurate person matte** (`VNGeneratePersonSegmentationRequest`, `.accurate`) is a soft
   confidence matte with better hair edges than instance masks; people-only.

## 3. What we tried, in order, and what happened

Each row: approach → why → result → verdict. Commits are in this branch's history.

| # | Approach | Result | Verdict |
|---|---|---|---|
| 1 | **`CIBumpDistortion`** on the face (like the app's HANDSOME effect) | User: "just a slightly different fisheye" — warps the disc, smears ears and background | **Rejected.** Wrong mechanism, not wrong constants |
| 2 | **Composite: ellipse ∩ subject silhouette, scaled on the body** (`ea96ce3`) | Right mechanism. Takes neck with it; oversized ellipse (a half-extent arithmetic bug) sometimes scaled whole animals | **The approved baseline** — the user later chose to return to *exactly* this and tweak |
| 3 | **Traced-jaw head region** (contour as the bottom bound) | Chin correct. Cut on the trace clipped ears and drew a seam along the cheeks; dropping the cut ~12% below the trace hid the seam | Kept as a **lab option** |
| 4 | **Geometric side walls** to stop neighbours growing (tight/loose, flared, crowded/solo split, midline between faces) | Every wall tight enough to exclude a neighbour cut the subject's own hair; every loose wall grew the neighbour. A full day of trading one artifact for another | **Dead end — recorded as such.** Do not propose walls |
| 5 | **Per-person instance masks** (fact #2) replacing the union | Groups ≤4 separate cleanly; the genuinely good trio render came from this | Kept as **lab option PERSON MASKS** |
| 6 | **Layered single pass** (all heads cut from the *original* frame, composited back-to-front, hard edges) replacing the pipeline's sequential per-face loop | Fixes the structural cause of heads cross-fading into ghosts. Needed a new batch method on the `FaceEffect` protocol (as a *requirement*, not an extension — extension-only binds statically through the existential and the override never runs) | Kept as **lab option STACKED PASS** |
| 7 | **The full rebuild** (3+5+6 together, per the staged plan) | Trio and profile looked genuinely good in *final frames*; mid-animation showed the middle head growing only its jaw (wrong instance label), a profile losing hair (contour sorted by x scrambles a tilted curve), a 10-person photo duplicating torsos (frame-wide region × shared mask). **User: "objectively worse than our original."** Three of those had fixes that landed after the verdict | **Parked on the user's call**, then mined for the lab switches |
| 8 | **Reset to `ea96ce3` + chin-cut ramp** (vertical fade below the face box) | Solos clean. Groups still ghost — the sequential pass, untouched by any mask change | Current shipped default |
| 9 | **HEAD MASK LAB** — every mask number as a live slider, every approach as a toggle, overlay on any photo | The user's key finding: **"settings that work for one photo don't work for others."** Constants in face units encode per-photo facts (hair height, neck position) | The lab stays; it proved the parameter space has no universal point |
| 10 | **AUTO FIT** — derive neck (narrowest silhouette row below chin) and crown (top of head silhouette) per face; sliders become fallbacks | Built from the finding in #9 and from prior art; rendered, not yet judged by the user across the corpus | Lab option |
| 11 | **FOLLOW POSE** (roll rotation, yaw shift), **76-point landmarks**, **accurate matte**, **portrait matte**, **SILHOUETTE off** (classic box cutout, background included) | All built as switches; not yet walked through the corpus by the user | Lab options |

**Three non-mask bugs that cost days and are worth knowing about:**
- **Coordinate space.** The preview renders a downsampled copy and scales the face it passes in; a version storing full-res face lists drew everything off-frame and rendered *nothing* in the app while every fixture render passed — the harness fed matched full-res inputs. Now pinned by a Simulator test that fails with the fix disabled.
- **Memory.** Full-frame region bitmaps on a 24MP photo killed the process; rasters are capped at 1400px and scaled into place.
- **Unclamped mask filters** fade the region at the frame edge and ghosted crowns near the top of frame.

## 4. Where the code is now

| File | Role |
|---|---|
| `Enhance/Services/Animators/BigHeadEffect.swift` (379 lines) | The effect. `headMask(for:subject:extent:tuning:…)` builds the mask in one place; the lab calls the same function. Batch override implements STACKED PASS |
| `Enhance/Models/HeadMaskTuning.swift` | Every number and switch, persisted; `.default` = the approved baseline, byte-identical |
| `Enhance/Views/HeadMaskLabView.swift` | The lab: photo picker, MASK/RESULT overlay, per-face selection, sliders, toggles, COPY PARAMETERS |
| `Enhance/Services/Animators/FaceRegions/HeadRegionBuilder.swift` | Traced-jaw region raster (capped, cached per face) |
| `Enhance/Services/Animators/FaceRegions/HeadGeometryScanner.swift` | AUTO FIT's neck/crown scan |
| `Enhance/Services/SubjectSegmentationService.swift` | Foreground union, per-person instances (patch-voted label lookup), accurate matte, portrait matte; all stubbable |
| `EnhanceTests/SubjectSegmentationDeviceTests.swift` | Device-only renders of the corpus with CSV diagnostics (faces, contour points, quality, instances, label per face) |
| `EnhanceTests/BigHeadTests.swift`, `HeadMaskTuningTests.swift` | Simulator contract tests: coordinate space, occlusion-vs-blend probe, default tuning pinned |
| `Enhance/Docs/ROADMAP.md` §2a, `LEARNINGS.md` (2026-08-19/20 entries) | The decisions and the paid-for lessons |

**Lab switchboard:** PERSON MASKS · JAW REGION (+DROP/FEATHER/WIDTH) · STACKED PASS · SILHOUETTE ·
AUTO FIT · FOLLOW POSE (+YAW SHIFT) · union source (foreground / accurate matte / portrait
matte) · ellipse WIDTH/HEIGHT/CENTER Y/FEATHER · chin HEIGHT/FADE · growth MAX/PIVOT Y. All apply
in the real editor too (re-tap the card after changing PERSON MASKS or the matte source).

## 5. Honest status per photo class (current shipped default = switches off)

| Case | Default | Best lab combination seen so far |
|---|---|---|
| Solo front | Good | Good |
| Profile / tilt | Back of head partly missed; chin line horizontal | FOLLOW POSE + JAW REGION plausible, **unjudged** |
| 2–4 people | Heads ghost where they overlap | PERSON MASKS + STACKED PASS gave the one genuinely good trio render |
| 8–10 people | Ghosting; with loose regions, torso duplication | Shared instances past the cap; midline bound built, unjudged |
| Hair / hats | Ellipse guesses; cap tops sometimes clipped | AUTO FIT's crown scan, **unjudged**; portrait matte where available |
| Cats | Good (ellipse ∩ foreground) | Unchanged — person paths fall through to the ellipse |

## 6. Things we considered and did not build

- **Single-face-only mode** (`requiresSingleFace`, as three other effects use): one head grows — the selected face. Sidesteps every multi-head problem; "single out your friend" may be the actual meme. Recommended twice, declined in favour of solving groups.
- **Damping growth on overlap.** Shrinks ghosting without removing it.
- **Google ML Kit Face Mesh** — Android-only, face-not-head, ≤2 faces, selfie range. Not applicable.
- **MediaPipe FaceLandmarker on iOS** — solves a problem we've already solved (dense landmarks), not the head boundary.

## 7. The escalation we have sized but not started

Bundle a **face-parsing model** (hair / skin / ears / hat as classes — BiSeNet-family, trained on
CelebAMask-HQ or EasyPortrait), converted to Core ML, as one more mask source behind the same
switchboard. Union of head classes = the head mask we keep reconstructing. ~2–4 sessions to a
judgeable lab toggle. **Gating risk is licensing**, not code: CelebAMask-HQ-trained weights are
research-only. Training our own is a different league (weeks; needs a permissively licensed
dataset); the user's 11 photos are a benchmark, not training data.

## 8. What we'd like from you

Fresh angles, specifically:

1. **Is there a per-photo signal for "where the head ends" we haven't used?** We use the
   silhouette's width profile (neck = narrowest row), the traced jaw, and head pose. Depth
   (`AVDepthData` on photos that carry it), colour/texture discontinuity at the collar, the
   eye-line-to-chin ratio as a skull-height prior, the person matte's confidence gradient — any
   of these exploitable cheaply?
2. **Is a geometric approach doomed without a head model?** Prior art says the industry uses one.
   If you agree, is there a better candidate model or dataset than §7 names, with a shippable
   license?
3. **Groups beyond four people.** Vision caps at four instances. Any way to split a shared
   instance between two faces that isn't a wall (k-means on the mask by face proximity? watershed
   from face seeds?).
4. **Is the whole framing wrong?** The user once said "maybe one approach for solo photos and a
   different one for groups." Product-level alternatives welcome — including the single-face mode
   in §6 if you think it's the right call.
5. **Anything in the three days of commits that looks like a wrong turn we normalised.** The
   walls are the obvious one; we'd rather hear about the non-obvious ones.

What we do *not* need: re-proposals of walls, fisheye-style warps, or "just use a bigger
ellipse." Those are measured.
