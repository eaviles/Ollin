# Third-party notices

Ollin's own source is under the MIT license (see [`LICENSE`](LICENSE)). It also
**bundles** the third-party components listed below, each under its own license.
This file is the aggregate record; the full license text and the original
copyright headers are kept alongside each component's source.

This is distinct from the projects Ollin is merely *inspired by* or *studied as a
reference* — those contribute no code and no license obligations (see the
README's "Influences & attribution"). The components here are actual source
redistributed inside this repository.

---

## libtess2

- **Used for:** triangulating concave polygons and polygons with holes, behind the vector `Shape`/`Contour` fill path (`drawShape`).
- **Location in this repo:** [`External/CLibtess2/`](External/CLibtess2/)
- **Upstream:** https://github.com/memononen/libtess2
- **Version:** commit `8dbd6483e920311a58c9af10a10beb278efebc36` (2025-10-15)
- **License:** SGI Free Software License B, Version 2.0 — full text at [`External/CLibtess2/LICENSE.txt`](External/CLibtess2/LICENSE.txt)

> Copyright (C) [dates of first publication] Silicon Graphics, Inc. All Rights Reserved.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction, including without limitation the rights to use, copy,
> modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
> and to permit persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice including the dates of first publication and either this
> permission notice or a reference to http://oss.sgi.com/projects/FreeB/ shall be
> included in all copies or substantial portions of the Software.
>
> (The software is provided "as is", without warranty of any kind. See `LICENSE.txt`
> for the full text, including the warranty disclaimer and the trademark clause.)

---

## Box2D

- **Used for:** the rigid-body solver behind `OllinPhysics` — bodies with rotation, polygon colliders, joints, and stable stacking — wrapped behind Ollin's own `World`/`Body` API.
- **Location in this repo:** [`External/CBox2D/`](External/CBox2D/)
- **Upstream:** https://github.com/erincatto/box2d
- **Version:** v3.1.1 — commit `8c661469c9507d3ad6fbd2fea3f1aa71669c2fe3`
- **License:** MIT — full text at [`External/CBox2D/LICENSE`](External/CBox2D/LICENSE)

> MIT License
>
> Copyright (c) 2022 Erin Catto
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction… (see `LICENSE` for the full text, including the
> warranty disclaimer).

---

## Clipper2

- **Used for:** polygon clipping and offsetting, behind `Shape`'s boolean set operations (`union`, `intersection`, `subtracting`, `symmetricDifference`) and `Shape.offset(by:join:)` — wrapped behind Ollin's own API.
- **Location in this repo:** [`External/CClipper2/`](External/CClipper2/)
- **Upstream:** https://github.com/AngusJohnson/Clipper2
- **Version:** v2.0.1 — tag `Clipper2_2.0.1`, commit `21ebba05db8894f0c7217ad35ea518080f324946` (2026-06-10)
- **License:** Boost Software License 1.0 — full text at [`External/CClipper2/LICENSE`](External/CClipper2/LICENSE)

> Boost Software License - Version 1.0 - August 17th, 2003
>
> Permission is hereby granted, free of charge, to any person or organization
> obtaining a copy of the software and accompanying documentation covered by
> this license (the "Software") to use, reproduce, display, distribute,
> execute, and transmit the Software… (see `LICENSE` for the full text,
> including the warranty disclaimer.)

---

## Syphon Framework

- **Used for:** sharing live GPU frames with other apps on the Mac (openFrameworks via `ofxSyphon`, Resolume, MadMapper, VDMX, …), behind `OllinSyphon`'s `SyphonServer`/`SyphonClient` API. Only the Metal portion is vendored; the OpenGL path is omitted.
- **Location in this repo:** [`External/CSyphon/`](External/CSyphon/)
- **Upstream:** https://github.com/Syphon/Syphon-Framework
- **Version:** commit `71351d4b484cd2d1917867f7846a5cdca724552d` (2025-10-06)
- **License:** BSD 2-Clause — full text at [`External/CSyphon/License.txt`](External/CSyphon/License.txt)
- **Local changes:** the framework-style `<Syphon/…>` imports were rewritten to quoted includes for the flat SwiftPM target; `SyphonServerRendererMetal.m` was changed to compile its (unchanged) blit shader from embedded source at runtime instead of loading a precompiled metallib from a bundle (the `swift run` build produces no metallib); and `SyphonMetalClient.m`'s frame texture gains `MTLTextureUsagePixelFormatView` so the consumer can read the surface through an sRGB view. All are documented in [`External/CSyphon/README.md`](External/CSyphon/README.md); the per-file copyright headers are intact.

> Copyright the Syphon Project contributors — bangnoise (Tom Butterworth), vade
> (Anton Marini), Maxime Touroute & Philippe Chaurand. All rights reserved. See
> `License.txt` and the per-file headers for the exact notices.
>
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the conditions of the BSD 2-Clause license are met
> (see `License.txt` for the full text, including the warranty disclaimer).

---

## Cozette

- **Used for:** the bundled default bitmap font (`BitmapFont.builtin`), loaded at runtime from its BDF by the font loader and rendered by `drawText`.
- **Location in this repo:** [`Sources/Ollin/Resources/cozette.bdf`](Sources/Ollin/Resources/cozette.bdf)
- **Upstream:** https://github.com/the-moonwitch/Cozette
- **Version:** v1.30.0
- **License:** MIT — full text at [`Sources/Ollin/Resources/Cozette-LICENSE.txt`](Sources/Ollin/Resources/Cozette-LICENSE.txt)

> MIT License
>
> Copyright (c) 2020 Samhain &lt;samhain@moonwit.ch&gt; & contributors &lt;https://github.com/the-moonwitch/Cozette/contributors&gt;
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of
> this software and associated documentation files (the "Software"), to deal in the
> Software without restriction… (see `Cozette-LICENSE.txt` for the full text,
> including the warranty disclaimer).

---

## Hershey fonts

- **Used for:** the bundled default stroke (single-line) font (`StrokeFont.builtin`, "Hershey Sans" / `futural`), loaded at runtime from its `.jhf` by the stroke-font parser and drawn by `drawText`.
- **Location in this repo:** [`Sources/Ollin/Resources/futural.jhf`](Sources/Ollin/Resources/futural.jhf) (provenance in [`Sources/Ollin/Resources/Hershey-NOTICE.txt`](Sources/Ollin/Resources/Hershey-NOTICE.txt))
- **Upstream:** the public-domain Hershey data, as widely mirrored (e.g. https://github.com/kamalmostafa/hershey-fonts and https://paulbourke.net/dataformats/hershey/)
- **License:** public domain.

> The Hershey vector fonts were originally created by Dr. A. V. Hershey while
> working at the U.S. National Bureau of Standards, and are in the public domain.
> The public domain carries no attribution requirement; the credit above is given
> freely, and provenance is recorded for the bundled asset.

---

## Marble Madness (example font)

- **Used for:** the `PlaydateFont` example sketch only — a sample Playdate `.fnt` font, loaded at runtime to demonstrate the loader. Not part of the Ollin framework; Ollin bundles no `.fnt` fonts itself.
- **Location in this repo:** [`Examples/Text/PlaydateFont/MarbleMadness.fnt`](Examples/Text/PlaydateFont/MarbleMadness.fnt)
- **Upstream:** https://github.com/idleberg/playdate-arcade-fonts (an original homage to classic arcade typography)
- **License:** CC0 1.0 (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/

> The fonts in playdate-arcade-fonts are released into the public domain under CC0,
> which carries no attribution requirement; the credit above is given freely.

---

## El Fandanguito (example audio)

- **Used for:** the `FilePlayer` example sketch only — a sample audio clip, to demonstrate `AudioPlayer` reacting to a file. Not part of the Ollin framework; Ollin (and `OllinAudio`) bundle no audio themselves.
- **Location in this repo:** [`Examples/Audio/FilePlayer/fandanguito.m4a`](Examples/Audio/FilePlayer/fandanguito.m4a)
- **Work:** *El Fandanguito*, a traditional Mexican *son huasteco* (the composition is traditional / public domain). Performed on violin by Cynthia Molina; recorded and edited by Wikimedia Commons users Emropa and ClawisJM (students of Tec de Monterrey).
- **Upstream:** https://commons.wikimedia.org/wiki/File:Viol%C3%ADn_SonHuasteco_ELFandanguito.ogg
- **License:** CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0

> Licensed CC BY-SA 4.0 (Attribution-ShareAlike). Attribution is given above as
> required. **Changes:** the original Ogg Vorbis file was transcoded to AAC (with
> short fades) for AVFoundation playback; no other edits. As a ShareAlike work
> this clip remains under CC BY-SA 4.0 — that obligation rides on the audio file
> and its adaptations, not on Ollin's source, which stays MIT (the clip is merely
> bundled alongside it). The root [`LICENSE`](LICENSE) is unaffected.

---

## Voladores de Papantla (example video)

- **Used for:** the `VideoPlayback` and `VideoTrace` example sketches only — a sample video clip, to demonstrate `VideoPlayer` drawing a file as a live image and a vision tracker analyzing it as it plays. Not part of the Ollin framework; Ollin (and `OllinVideo`) bundle no video themselves.
- **Location in this repo:** [`Examples/Video/VideoPlayback/voladores.mp4`](Examples/Video/VideoPlayback/voladores.mp4) and an identical copy at [`Examples/Vision/VideoTrace/voladores.mp4`](Examples/Vision/VideoTrace/voladores.mp4) (each example bundles its own assets)
- **Work:** *Voladores de Papantla México* — a recording of the *Danza de los Voladores*, the Totonac pole-flying ritual dance from Papantla, Veracruz (performed at an exhibition in Mexico City, 2018). Filmed by José Millán (Wikimedia Commons user Jmillan325).
- **Upstream:** https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_M%C3%A9xico.webm
- **License:** CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0

> Licensed CC BY-SA 4.0 (Attribution-ShareAlike). Attribution is given above as
> required. **Changes:** a ~28-second excerpt was trimmed from the original
> 3-minute VP9/WebM file and re-encoded to H.264 MP4 at 960×540 (mono AAC audio)
> for AVFoundation playback and a small repository footprint; no other edits. As
> a ShareAlike work this clip remains under CC BY-SA 4.0 — that obligation rides
> on the video file and its adaptations, not on Ollin's source, which stays MIT
> (the clip is merely bundled alongside it). The root [`LICENSE`](LICENSE) is
> unaffected.

---

## Depth Anything V2, small (example model — downloaded, not bundled)

- **Used for:** the `DepthRelief` example sketch only — a monocular depth-estimation model, to demonstrate `ModelTracker` running a custom Core ML model. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *Depth Anything V2* (the **small** checkpoint), Lihe Yang, Bingyi Kang, Zilong Huang, Zhen Zhao, Xiaogang Xu, Jiashi Feng, Hengshuang Zhao (2024) — in Apple's official Core ML conversion (`DepthAnythingV2SmallF16.mlpackage`).
- **Upstream:** https://huggingface.co/apple/coreml-depth-anything-v2-small (conversion), via Apple's model gallery https://developer.apple.com/machine-learning/models/ — original model https://github.com/DepthAnything/Depth-Anything-V2
- **License:** Apache-2.0 — https://www.apache.org/licenses/LICENSE-2.0 (the small checkpoint; the larger Depth Anything V2 checkpoints are CC BY-NC 4.0 and are not used)

> Apache-2.0 applies to the model weights the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## YOLOv3-tiny (example model — downloaded, not bundled)

- **Used for:** the `ObjectDetection` example sketch only — an object-detection model (80 COCO classes), to demonstrate `ModelTracker`'s labeled-box surface. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *YOLOv3-tiny*, Joseph Redmon and Ali Farhadi — "YOLOv3: An Incremental Improvement" (2018) — in Apple's Core ML conversion (`YOLOv3TinyFP16.mlmodel`).
- **Upstream:** https://developer.apple.com/machine-learning/models/ (conversion) — original model https://github.com/pjreddie/darknet, https://pjreddie.com/darknet/yolo/
- **License:** YOLO License, Version 2 (a public-domain dedication: "Darknet is public domain. Do whatever you want with it.") — https://github.com/pjreddie/darknet/blob/master/LICENSE

> The YOLO License applies to the model the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.

---

## MNIST drawing classifier (example model — downloaded, not bundled)

- **Used for:** the `DigitReader` example sketch only — a handwritten-digit classifier, to demonstrate `ModelTracker` reading a sketch's own pixel-authored drawing through the still `detect(in:)` path. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *MNISTClassifier* — Apple's Turi Create-trained drawing classifier from the Core ML model gallery, trained on the MNIST dataset of handwritten digits (LeCun, Cortes, Burges).
- **Upstream:** https://developer.apple.com/machine-learning/models/ — dataset http://yann.lecun.com/exdb/mnist/
- **License:** MIT (Copyright 2019 Apple Inc.) — https://docs-assets.developer.apple.com/coreml/models/Image/DrawingClassification/MNISTClassifier/LICENSE-MIT.txt

> MIT applies to the model the script downloads; nothing from the model is
> redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.
> (The `StyleMirror` example needs no entry here at all: its style-transfer
> model is trained by the user — `Scripts/train-style-model.swift`, over the
> CreateML framework — so the weights are the user's own work; nothing is
> fetched or redistributed.)

---

## DeepLabV3 (example model — downloaded, not bundled)

- **Used for:** the `PaintByClass` example sketch only — a semantic-segmentation model (21 PASCAL VOC classes), to demonstrate `ModelTracker`'s class-mask surface. Not part of the Ollin framework; Ollin (and `OllinVision`) bundle no model weights themselves.
- **Location in this repo:** none. The weights are **not committed**: [`Scripts/fetch-models.sh`](Scripts/fetch-models.sh) downloads them into the gitignored `Models/` directory on a developer's machine.
- **Work:** *DeepLabV3* (MobileNetV2 backbone), Liang-Chieh Chen, Yukun Zhu, George Papandreou, Florian Schroff, Hartwig Adam — "Encoder-Decoder with Atrous Separable Convolution for Semantic Image Segmentation" (2018) — in Apple's Core ML conversion (`DeepLabV3FP16.mlmodel`).
- **Upstream:** https://developer.apple.com/machine-learning/models/ (conversion) — original model https://github.com/tensorflow/models/tree/master/research/deeplab (TensorFlow)
- **License:** Apache-2.0 — https://github.com/tensorflow/models/blob/master/LICENSE (per the model's own embedded license metadata, which points at the TensorFlow repositories)

> Apache-2.0 applies to the model weights the script downloads; nothing from the
> model is redistributed in this repository, so the root [`LICENSE`](LICENSE) is
> unaffected. This entry records the provenance of what the script fetches.
