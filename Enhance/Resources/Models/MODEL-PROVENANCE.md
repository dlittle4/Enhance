# Bundled vision models

The app pins model bytes so a silent upstream update cannot change an effect between builds.

| Model | Source | SHA-256 |
|---|---|---|
| `selfie_multiclass_256x256.tflite` | [MediaPipe Selfie Multiclass segmentation](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite) | `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0` |
| `blaze_face_full_range.tflite` | [MediaPipe BlazeFace full range](https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_full_range/float16/1/blaze_face_full_range.tflite) | `3698b18f063835bc609069ef052228fbe86d9c9a6dc8dcb7c7c2d69aed2b181b` |

MediaPipe is distributed under the Apache License 2.0. Product/legal review of model
redistribution and required notices remains a release gate; provenance and hashes alone are not
a licensing approval.
