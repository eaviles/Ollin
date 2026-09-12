# Media

`media.json` is the one place the addresses of the site's video and stills are
written down. The files themselves live in Cloudflare R2 behind
`media.ollin.art` rather than in git, because a repository should not carry
hundreds of megabytes of rendered video that changes whenever a sketch does.

It sat under `Examples/` while the examples were the only thing with clips. It
carries four kinds of thing now, so it lives here instead:

- **`examples`** — a clip and a still for each example, at two sizes, plus what
  each one is made of so an unchanged example is not re-rendered. Written by
  `Scripts/media.sh`.
- **`chapters`** — the sketch each Guide chapter builds, recorded. The committed
  still stays in `Guide/Images` and becomes the video's poster, so a clone,
  GitHub, `ollin docs` and a reader who blocks video all see what they always
  did. Written by `Scripts/guide-clips.sh`.
- **`heroes`** — the two pictures that open the site's own pages. Written by
  `Scripts/example-heroes.sh`.
- **`covers`, `groups`, `showcase`, `passedOver`** — which example stands for a
  group, which ones the front page shows running, and which are waiting for
  somebody at the desk with a camera or a controller plugged in.

`base` is the host. Moving it is one edit here.

Uploading needs `~/.config/ollin/r2.env`; every script that writes the manifest
reads that file and pushes with rclone, or renders only when told to.

The site reads this at build time (`ExampleMedia.read(inRepository:)`), so a
change to it changes what pages render without touching a page. That is why
`.github/workflows/site.yml` watches this file alongside the pages themselves.
