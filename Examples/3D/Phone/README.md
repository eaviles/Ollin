#### <sup>[Ollin](../../../README.md) → [Examples](../../README.md) → [3D](../README.md) → Phone</sup>

---

## Phone

These sketches read the **Ollin Capture** iPhone app, which streams ARKit perception over USB.


| Sketch | What it shows |
| --- | --- |
| [PhoneBodyPose](PhoneBodyPose/) | A live 3D body skeleton streamed from **Ollin Capture** on a tethered iPhone. ARKit body pose arrives over USB and is orbited as a stick figure. Needs `import OllinPhone`. |
| [PhoneBodyFigure](PhoneBodyFigure/) | A solid mannequin posed by the richer half of that same stream. Joint orientations turn its parts, the world anchor stands it where the person stands, the scale sizes it, and the tracked flags tint it. Needs `import OllinPhone`. |
| [PhoneCostume](PhoneCostume/) | A costume worn by the live skeleton, inspired by Universal Everything's *Super You*. It is either ribbon trails that only exist in motion, or plumage whose twist follows the joint rotations. Needs `import OllinPhone`. |
| [PhoneFace](PhoneFace/) | Ollin Capture's live face mesh and its 52 expression blendshapes, orbited as a point cloud with expression bars. Tap **Face** on the phone. Needs `import OllinPhone`. |
| [PhoneGaze](PhoneGaze/) | The eyes and the gaze from that same Face mode. Eyeballs stand at the streamed eye poses and blink with their blendshapes, beams converge on the look-at point, and a bead marks where they meet. Needs `import OllinPhone`. |
| [PhoneDepthCloud](PhoneDepthCloud/) | A live rear-LiDAR RGBD cloud from Ollin Capture (tap **World**). This is the world-facing depth feed from Ollin's own app, unprojected with the stream's true intrinsics and orbited. Needs `import OllinPhone`. |
| [PhoneWorldScan](PhoneWorldScan/) | Sweep the phone (tap **World**). Each depth frame is lined up against the scan so far. The frames fuse into one `WorldCloud` of the room. **C** turns the drift correction off, and **R** resets. Needs `import OllinPhone`. |
| [PhoneSegmentation](PhoneSegmentation/) | Ollin Capture's on-device person matte (tap **Segment**). The cutout is placed on a live gradient backdrop, and the tinted matte serves as its drop shadow. Needs `import OllinPhone`. |
| [PhoneRoomMesh](PhoneRoomMesh/) | Walk the phone around (tap **Room**), and the room arrives as a solid surface, with each triangle painted by what it is. Keys: **space**, **F**, **R**. Needs `import OllinPhone`. |
| [PhoneRoomPlanes](PhoneRoomPlanes/) | The flat surfaces in that same room, each drawn as its real outline. A ball stands on the biggest one, and the scene is lit by the room's own light. Keys: **space**, **F**, **M**, **L**, **R**. Needs no LiDAR. Needs `import OllinPhone`. |
| [PhoneHands](PhoneHands/) | The hands the phone sees (tap **Hands**, up to 4), drawn as small solid skeletons standing in the room. They are lifted to metric 3D through the LiDAR depth. A pinch closes into a bright bead. Without LiDAR the same stream draws as a flat overlay. Needs `import OllinPhone`. |
| [PhoneWorldText](PhoneWorldText/) | The words the phone can read (tap **Text**), placed where they sit in the room. Each line is wire-frame type on a framed panel, lifted through the LiDAR depth. Without LiDAR it draws as a flat overlay. Needs `import OllinPhone`. |
| [PhoneMarkers](PhoneMarkers/) | The pictures and objects the phone knows (tap **Markers**), found in the room. A city of columns rises from every print it recognizes, framed by the print's own edge. A scanned object arrives as the box its scan measured. To add a picture, drop it into the app's folder, named with its printed width. Needs `import OllinPhone`. |
| [PhonePointer](PhonePointer/) | The phone held as a pointer (tap **Wand**). A beam from the back of the phone lands on a ball. A press on the pad picks the ball up, sliding the thumb pushes it away or pulls it in, and letting go drops it. Needs no LiDAR. Needs `import OllinPhone`. |
| [PhoneAttention](PhoneAttention/) | Where the phone's picture draws the eye (tap **Attention**). The heat map shows as a warm glow over the live frame. A frame surrounds each region the model picks out, and an eased bead trails where the attention has been. Needs no LiDAR. Needs `import OllinPhone`. |

Run one with `swift run Example-3D-Phone-<Name>`, for example `swift run Example-3D-Phone-PhoneBodyPose`.
