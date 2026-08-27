# Feature Camera — In-App Photo Capture

> Status: experiment, gated behind `FeatureFlags.cameraCapture` (GENERAL SETTINGS →
> EXPERIMENTS → IN-APP CAMERA). Delete-on-graduation contract: this either becomes the
> unconditional second way to start a GIF, or the whole `Features/Camera/` +
> `Services/Camera/` tree goes.
>
> Design: [ZoomGif Figma — CAMERA SPECS](https://www.figma.com/design/c6pLcnIn0n4OaAP3sa5TGF/ZoomGif?node-id=10393-5268)

## Summary

A camera launched from the gallery so a GIF can start from a photo taken now, not just one
picked from the library. The camera is an overlay, not a screen: a square viewfinder card
(32pt corners, per the spec's `spacing/large`) that scales up out of the camera button and
comes to rest low over the scrimmed gallery, with four controls inside it — close
(pixel chevron), shutter (the primary-CTA gradient in a Liquid Glass rim), zoom pill, and
front/rear flip (`switch-camera-sharp`, the user's pick over the spec's `more-horizontal`).
The small controls sit in Liquid Glass wells. Taking a photo freezes the frame, fades the
chrome, and flies the photo into the editor canvas; from there everything is the ordinary
`.newImage` editor flow, including the staggered chrome entrance if `motionEntrance` is on.

The capture is **not** saved anywhere on its own — exactly like a picked photo, it reaches the
photo library only when the user saves a generated GIF.

## Architecture

| Piece | File | Role |
| --- | --- | --- |
| `CameraServing` | `Services/Camera/CameraService.swift` | Protocol seam + factory (device → `AVCameraService`, simulator → `MockCameraService`) |
| `AVCameraService` | `Services/Camera/AVCameraService.swift` | `AVCaptureSession` on a private queue; zoom ramps, flip, capture-to-continuation |
| `MockCameraService` | `Services/Camera/MockCameraService.swift` | Simulator stand-in; returns non-square, non-`.up` captures on purpose |
| `CameraImageProcessor` | `Services/Camera/CameraImageProcessor.swift` | Orientation/mirroring → `.up`, then center-square crop (pure, tested) |
| `CameraZoomLadder` | `Models/CameraZoomLadder.swift` | Switchover factors → labelled zoom stops (pure, tested) |
| `CameraViewModel` | `Features/Camera/CameraViewModel.swift` | Permission, session state mirror, capture pipeline (`@Observable`, injectable) |
| `CameraOverlayView` | `Features/Camera/CameraOverlayView.swift` | Scrim + viewfinder card + controls + freeze frame |
| Gallery wiring | `Features/Gallery/GalleryView.swift` | Camera button, overlay stack, `presentEditorFromCamera`, handoff state |

## Decisions

- **Overlay, not sheet.** Same presentation as the editor itself: the gallery stays mounted
  underneath, which is what lets one overlay's flight land on another overlay's canvas. The
  flight overlay sits *above* the editor overlay so the captured photo flies over the
  incoming editor rather than under it.
- **The flight is the gallery zoom's flyer, shared.** Originally a `matchedGeometryEffect`
  pair (freeze frame ↔ canvas), rewritten 2026-08-26 when a device pass showed the photo
  chasing the canvas's *bordered* rect — landing 6pt oversized with the stroke animating in
  underneath it — plus the two measurement bugs the grid zoom had already hit (the
  `contentWidth` placeholder and the chrome entrance's transform contaminating global
  frames). The freeze frame now just reports its rect (`onFreezeFrameChange`) and hides
  while `GalleryView`'s `ZoomFlight` — the same overlay the grid-cell zoom flies — carries
  the photo to the canvas's *reported* rect, corner radius flown 32 → canvas clip, picture
  covered beneath until the flyer dissolves. One flight implementation is also what makes
  the two entrances feel the same, which is the point. See FEATURE-VIEW-TRANSITIONS.md,
  Idea 1, for the full measured record.
- **Not gated on `motionSharedZoom`.** Considered and rejected: that flag answers "should
  tapping an existing GIF zoom?", and requiring it here would make a camera user flip a second
  toggle to see this feature as designed. The flight is part of the camera experiment.
- **Reduce Motion** skips the flight entirely — capture cross-fades into the editor
  (`presentEditorFromCamera` takes the `selectPhoto` path), per the house rule that decorative
  motion is ANDed with the accessibility setting.
- **Normalization happens once, at capture.** Camera frames arrive sideways and (front) also
  mirrored. `CameraViewModel.capture()` bakes both into a `.up` bitmap and center-crops to the
  square the aspect-fill viewfinder showed, so `GIFGenerator.fixImageOrientation`'s `.up`
  short-circuit, Vision, and segmentation all stay on the path picker images already exercise.
- **The zoom pill cycles optical stops.** `CameraZoomLadder` maps
  `virtualDeviceSwitchOverVideoZoomFactors` to labels (triple camera → 0.5X / 1X / 3X);
  single-module devices get 1X plus a digital 2X. Labels divide by the wide module's factor,
  because on virtual devices `videoZoomFactor == 1` is the ultra-wide.
- **Permission lives in the view model,** not `PermissionManager` (Photos-only, and the
  camera's one consumer is the overlay). Denied state renders inside the viewfinder with an
  OPEN SETTINGS button; a Settings round-trip recovers live via the `scenePhase` re-check.
- **The launch is explicit state, not an insertion `.transition`.** Every transition variant
  tried on this overlay's insertion popped instead of animating (frame captures, three
  attempts); the card now mounts at its start pose and animates to rest from `onAppear` —
  the mechanism the editor's chrome entrance already trusts. Its knobs live in MOTION LAB →
  CAMERA LAUNCH (`MotionTuning.cameraScaleFrom` / `.cameraCurve` / `.cameraBottomPadding`,
  surfaced as START SCALE, SPEED, VERTICAL POSITION, and the shared curve editor). Unlike
  the editor knobs these default **live**, per the ambient-effects precedent: the camera
  flag is the off-switch, so the launch works without a lab visit.
- **Reopen is generation-guarded.** The overlay stays mounted (invisible) through its
  shrink-out; a reopen inside that window tears the remnant down instantly and presents a
  fresh instance under a bumped `.id` token, and each instance's delayed close carries its
  birth token so a stale close cannot kill its successor. The UI test walks the full
  open → close → reopen cycle because exactly that revival shipped broken once.
- **Rotation comes from `RotationCoordinator`, per device.** A hardcoded 90° left the front
  camera sideways; the coordinator's preview/capture angles are applied after every
  configure (start and flip), with a short poll for the asynchronously recreated preview
  connection — and no hardcoded fallback anywhere that could clobber the answer.
- **Liquid Glass renders as a `.background`, never on the label.** `glassEffect` applied to
  a button's label hoists it into an effect layer and its taps stop landing (the zoom and
  flip buttons went dead on device). Glass behind + explicit `contentShape` owns the visuals
  and the hit area separately; plain `.regular`, since `EnhancePressButtonStyle` owns the
  press and interactive glass swells past the resting shape.

## QA checklist

Automated: `EnhanceTests/Camera*Tests.swift` (orientation/crop math, zoom ladder, view model)
and `EnhanceUITests/CameraCaptureUITests.swift` (capture → editor → ENHANCE → SAVE → grid, plus
control hittability — the guard against the viewfinder mis-sizing and pushing controls
off-screen). The UI tests force the flags via launch arguments and need photo + camera TCC
grants (`xcrun simctl privacy <udid> grant photos|camera Enhance.Enhance`).

Simulator (mock service — overlay, controls, permission flow and flight are all drivable):

1. EXPERIMENTS → IN-APP CAMERA on: camera button appears beside MAKE A GIF (which narrows);
   off: reverts. Toggle animates live under the settings sheet.
2. Open camera: scrim over the visible gallery, square card low on screen. Parallax (if on)
   stops while the camera is up.
3. Zoom pill cycles 0.5X → 1X → 3X; the switch-camera button flips REAR/FRONT (ladder resets
   to 1X); chevron and scrim tap both close — and the camera opens again after closing.
4. Shutter: chrome+scrim fade, frozen frame flies into the canvas, editor chrome enters as
   normal — check with STAGGERED EDITOR ENTRANCE both on and off. ENHANCE the capture, save,
   and confirm it lands in the grid.
5. Settings → Accessibility → Reduce Motion: capture cross-fades, no flight.
6. `xcrun simctl privacy booted revoke camera <bundle-id>`: denied card + OPEN SETTINGS;
   `grant` and reopen: recovers.

Device-only (the simulator cannot answer these):

- Real preview latency and session start time; optical switchover continuity while ramping
  through the zoom ladder.
- Front capture matches the mirrored preview (the photo connection is mirrored to match).
- Capture orientation in all four device holds (the app is portrait-only, but the sensor
  isn't).
- Interruptions: phone call mid-preview, backgrounding mid-preview, both recovering on return.
- Thermal/battery sanity on a long open-viewfinder session.
