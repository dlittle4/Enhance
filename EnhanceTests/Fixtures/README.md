# Test fixtures

Photos dropped here are picked up automatically by
`SubjectSegmentationDeviceTests.bigHead_onFixturePhotos`, which renders BIG HEAD over each one
and attaches the result plus the face data Vision found.

**Why this folder exists.** Every `showcase-*` asset is either an animal — whose contour comes
from body-pose joints rather than a face — or a person facing away. So none of them reaches the
contour branch of `BigHeadEffect`, and that branch was written, twice, without ever being seen.
Real photos of real faces are the only way to judge it: a profile, a hat, tall hair, and two
people close together are all cases the shipped corpus cannot produce.

Any `.jpg`, `.jpeg`, `.png` or `.heic` here is used. Nothing else reads them, and they are not
compiled into the app.
