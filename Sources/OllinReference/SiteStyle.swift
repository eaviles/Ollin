import Foundation

/// The site's own look: one stylesheet and one small script.
///
/// Kept as text inside the target rather than as resources so the command
/// stays one binary with nothing to find at run time. The design is system
/// type, hairline rules, and generous space, in a light scheme and a dark one
/// that follow the reader's own setting, so the figures' dark variants, the
/// front page's ring, the mark, and the chrome switch together. The mark and
/// the favicon are the logo's own files, read from the checkout (`SiteLogo`).
enum SiteStyle {

    /// The page's ground in the light scheme and in the dark one. The
    /// stylesheet's `--bg` and the color a phone's browser tints its own bars
    /// with (`theme-color`) are both written from these, so the bars and the
    /// page cannot drift apart.
    static let ground = "#ffffff"
    static let groundDark = "#0e0d0d"

    static let css = """
    /* Ollin · site */

    *, ::before, ::after { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; scroll-padding-top: 72px; }
    body, h1, h2, h3, h4, h5, h6, p, figure, blockquote, dl, dd, pre { margin: 0; }
    img, picture, video, canvas, svg { display: block; max-width: 100%; }
    /* A picture says its size in its tag, so its place is held before it
       arrives; its height follows whatever width the column leaves it. */
    img { height: auto; }
    /* A control that waits for its script says so with `hidden`, and a
       rule here that sets how it is laid out must not show it early. With
       no script it takes no room at all. With one on its way, its room is
       held from the first paint and only the control is kept out of sight,
       so nothing beside it moves when it arrives. */
    [hidden] { display: none !important; }
    .js .search-toggle[hidden], .js button.button[hidden] { display: inline-flex !important; visibility: hidden; }
    /* A reader who asked for less motion gets none, and gets each change
       of style at once. A transition of no length and no delay is not a
       transition, so what a script sets it can read back in the same
       breath; one too short to see would still start a frame later and
       begin from the old value, and the menu on a phone, hidden for that
       frame, could not take the focus. */
    @media (prefers-reduced-motion: reduce) {
      *, ::before, ::after { animation-duration: 0.01ms !important; transition-duration: 0s !important; transition-delay: 0s !important; scroll-behavior: auto !important; }
    }

    :root {
      color-scheme: light dark;
      --bg: \(ground);
      --surface: #f5f5f7;
      --surface-2: #ececef;
      --border: rgba(0, 0, 0, 0.09);
      --text: #1d1d1f;
      /* Every text color reads at 4.5 to 1 or better on each ground it is
         set on, which is why the faint labels are no fainter than the
         secondary text. */
      --text-2: #69696e;
      --muted: #69696e;
      --accent: #8e44e6;
      --accent-ink: #ffffff;
      --tab: #1d1d1f;
      --tab-ink: #ffffff;
      --bar: rgba(255, 255, 255, 0.72);
      --code-bg: #f5f5f7;
      --tk-comment: #6e6e73;
      --tk-string: #c41a16;
      --tk-number: #1c00cf;
      --tk-keyword: #ad3da4;
      --tk-type: #3f6e74;
      --tk-attribute: #836c28;
      --font: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif;
      --mono: "SF Mono", ui-monospace, Menlo, "Cascadia Code", "Fira Code", monospace;
      --ease: cubic-bezier(0.16, 1, 0.3, 1);
      --bar-height: 52px;
      --max: 1440px;
      --pad: clamp(1.25rem, 4vw, 3rem);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: \(groundDark);
        --surface: #1c1a1a;
        --surface-2: #262323;
        --border: rgba(255, 255, 255, 0.08);
        --text: #f0eeee;
        --text-2: #8d8c8c;
        --muted: #8d8c8c;
        --accent: #bf5af2;
        --accent-ink: #0e0d0d;
        --tab: #f0eeee;
        --tab-ink: #0e0d0d;
        --bar: rgba(14, 13, 13, 0.72);
        --code-bg: #1c1a1a;
        --tk-comment: #868484;
        --tk-string: #fc6a5d;
        --tk-number: #d0bf69;
        --tk-keyword: #fc5fa3;
        --tk-type: #9ef1dd;
        --tk-attribute: #d9c97c;
      }
    }

    html, body { background: var(--bg); color: var(--text); }
    body {
      font-family: var(--font);
      font-size: 17px;
      line-height: 1.47;
      -webkit-font-smoothing: antialiased;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
      /* A word too long for its line (an address written out, a run of
         names joined by slashes) breaks at the line's end and nowhere
         else, so no line of prose is wider than its column. */
      overflow-wrap: break-word;
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; text-underline-offset: 0.15em; }
    /* A link set in gray text has only its hue to tell it from the words
       around it, and a reader who does not see the hue has nothing. There
       it takes a thin underline; in ordinary prose the ink is far enough
       from the link's color to do without one. */
    .prose blockquote a, .home-opening > ul > li a, .home-whats-in-it > ul > li a, .band-code > p a { text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 0.18em; text-decoration-color: color-mix(in srgb, currentColor 45%, transparent); }
    .prose blockquote a:hover, .home-opening > ul > li a:hover, .home-whats-in-it > ul > li a:hover, .band-code > p a:hover { text-decoration-color: currentColor; }
    code, pre, kbd { font-family: var(--mono); font-size: 0.88em; }
    /* A long name in code type breaks where the line ends, since it has no
       space to break at and would otherwise push the page wider than a
       phone. Inside a block of code and inside a table it stays whole: both
       scroll within their own box. */
    code { background: var(--surface); padding: 0.1em 0.35em; border-radius: 6px; overflow-wrap: anywhere; }
    pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 14px; padding: 1.1rem 1.25rem; overflow-x: auto; line-height: 1.6; font-size: 13.5px; }
    pre code { background: none; padding: 0; font-size: inherit; overflow-wrap: normal; }
    table code { overflow-wrap: normal; }
    /* A long call carries marks between its labels where it may fold. They
       count only where the column is narrow: on a wide page a name moves
       whole to the next line, and in a table it stays whole. */
    wbr { display: none; }
    @media (max-width: 860px) {
      wbr { display: inline; }
      table wbr { display: none; }
    }
    hr { border: 0; border-top: 1px solid var(--border); margin: 2.5rem 0; }
    sup { font-size: 0.75em; line-height: 0; }

    /* The keyboard: one ring in the page's ink wherever the focus is, and
       a link ahead of everything else that steps over the bar and the menu
       to the page. It stays out of sight until a Tab reaches it. */
    :focus-visible { outline: 2px solid var(--text); outline-offset: 2px; }
    main:focus { outline: 0; }
    .search-results a:focus-visible { outline-offset: -2px; }
    .sidebar:focus { outline: 0; }
    .skip { position: absolute; left: var(--pad); top: 0.55rem; z-index: 20; padding: 0.5rem 1rem; border-radius: 999px; background: var(--text); color: var(--bg); font-size: 14px; font-weight: 500; transform: translateY(-300%); transition: transform 150ms var(--ease); }
    .skip:focus { transform: none; }
    .skip:hover { text-decoration: none; }

    /* The bar */
    .bar {
      position: sticky; top: 0; z-index: 10;
      background: var(--bar);
      -webkit-backdrop-filter: saturate(180%) blur(20px);
      backdrop-filter: saturate(180%) blur(20px);
      border-bottom: 1px solid var(--border);
      height: var(--bar-height);
    }
    .bar-inner { max-width: var(--max); margin: 0 auto; padding: 0 var(--pad); height: 100%; display: flex; align-items: center; gap: 1.5rem; }
    .wordmark { display: inline-flex; align-items: center; gap: 0.6rem; color: var(--text); font-weight: 600; font-size: 17px; letter-spacing: -0.01em; }
    .wordmark:hover { text-decoration: none; }
    .mark { width: 30px; height: 30px; flex: none; }
    .sections { margin-left: auto; display: flex; align-items: stretch; height: 100%; gap: 0.25rem; }
    .sections a { position: relative; display: inline-flex; align-items: center; padding: 0 0.85rem; color: var(--text-2); font-size: 14px; font-weight: 500; letter-spacing: -0.005em; transition: color 150ms var(--ease); }
    .sections a:hover { color: var(--text); text-decoration: none; }
    .sections a.active { color: var(--tab-ink); }
    .sections a.active::before {
      content: ""; position: absolute; left: 0; right: 0; top: -12px; bottom: 7px; z-index: -1;
      background: var(--tab); border-radius: 0 0 8px 8px;
    }

    /* What opens the section's menu on a phone: the tab of the section the
       page is in, as a button with a small arrow, standing where the link
       stands on a wide screen. It is shown further down, only where the
       screen is narrow and a script is there to answer it. */
    .menu-toggle { display: none; position: relative; align-items: center; gap: 0.3rem; padding: 0 0.55rem; border: 0; background: none; color: var(--tab-ink); font: inherit; font-size: 13px; font-weight: 500; letter-spacing: -0.005em; cursor: pointer; -webkit-tap-highlight-color: transparent; }
    .menu-toggle::before { content: ""; position: absolute; left: 0; right: 0; top: -12px; bottom: 7px; z-index: -1; background: var(--tab); border-radius: 0 0 8px 8px; }
    .menu-toggle .icon { width: 10px; height: 10px; flex: none; transition: transform 300ms var(--ease); }
    .menu-toggle[aria-expanded="true"] .icon { transform: rotate(180deg); }
    .menu-toggle.beside-mark { height: 100%; width: 30px; padding: 0; justify-content: center; margin-left: -1.25rem; color: var(--text-2); }
    .menu-toggle.beside-mark::before { content: none; }

    /* The layout */
    .layout { flex: 1; width: 100%; max-width: var(--max); margin: 0 auto; padding: 0 var(--pad); display: grid; gap: 3rem; grid-template-columns: minmax(0, 1fr); }
    .layout.with-sidebar { grid-template-columns: 240px minmax(0, 1fr); }
    .layout.with-rail { grid-template-columns: 240px minmax(0, 1fr) 200px; }
    /* Where the page is already as wide as prose is read at, the room left
       over goes to the list of its sections. */
    @media (min-width: 1424px) {
      .layout.with-rail { grid-template-columns: 240px minmax(0, 1fr) 232px; }
    }
    main { min-width: 0; padding: 2.5rem 0 5rem; max-width: 760px; }
    .layout.single main, .layout.home main { max-width: none; }
    .layout.home main { padding-top: 0; }

    /* The two lists beside the page. Each is a window of its own that
       scrolls, a rem wider on either side than the column it sits in, so a
       row's highlight and the ring around a row the keyboard is on are
       drawn whole. `--cut` is how far the layout's end has risen into the
       window: the script takes that much off the list's height near a
       page's end, so the list stops at the foot and is not pushed up under
       the bar. Where a list runs past its window, the edge it runs past
       fades (`more-above`, `more-below`, set by the same script). */
    .sidebar, .rail {
      position: sticky; top: var(--bar-height); align-self: start;
      max-height: calc(100dvh - var(--bar-height) - var(--cut, 0px));
      overflow-y: auto; overscroll-behavior: contain;
      padding: 2.5rem 1rem 3rem; margin: 0 -1rem; font-size: 13.5px; scrollbar-width: thin;
      -webkit-mask-image: linear-gradient(to bottom, transparent, #000 var(--fade-above, 0px), #000 calc(100% - var(--fade-below, 0px)), transparent);
      mask-image: linear-gradient(to bottom, transparent, #000 var(--fade-above, 0px), #000 calc(100% - var(--fade-below, 0px)), transparent);
    }
    .more-above { --fade-above: 2.5rem; }
    .more-below { --fade-below: 3.5rem; }
    .sidebar ul, .rail ul { list-style: none; margin: 0; padding: 0; }
    .sidebar li a, .rail li a { display: block; padding: 0.3rem 0.6rem; margin: 0 -0.6rem; border-radius: 8px; color: var(--text-2); line-height: 1.35; }
    .sidebar li a:hover, .rail li a:hover { color: var(--text); text-decoration: none; }
    .sidebar li a:hover { background: var(--surface); }
    /* The page open, or the row that holds it: a sketch filed under an
       artist marks the artist, so every page has its place in the menu. */
    .sidebar li a[aria-current] { color: var(--text); font-weight: 600; background: var(--surface); }
    .sidebar-title, .rail-title { font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); margin: 0 0 0.6rem; }
    .sidebar details { margin-top: 1rem; }
    .sidebar summary { cursor: pointer; font-weight: 600; color: var(--text); padding: 0.3rem 0; list-style: none; display: flex; align-items: center; gap: 0.4rem; }
    .sidebar summary::-webkit-details-marker { display: none; }
    .sidebar summary::before { content: ""; width: 6px; height: 6px; border-right: 1.5px solid var(--muted); border-bottom: 1.5px solid var(--muted); transform: rotate(-45deg); transition: transform 200ms var(--ease); margin-right: 0.1rem; }
    .sidebar details[open] > summary::before { transform: rotate(45deg); }
    .sidebar details ul { margin-top: 0.2rem; }
    /* The list of the page's own sections hangs off a hairline, and the
       section being read is marked on it: its name in the page's ink, and a
       short bar on the line that slides to it as the page scrolls. */
    .rail ul { position: relative; border-left: 1px solid var(--border); }
    .rail li a { margin: 0; padding-left: 0.9rem; border-radius: 0 8px 8px 0; transition: color 150ms var(--ease); }
    .rail li.level-3 a { padding-left: 1.75rem; font-size: 12.5px; }
    .rail li a[aria-current] { color: var(--text); }
    .rail ul::before { content: ""; position: absolute; left: -1px; top: 0; width: 2px; height: var(--marker-height, 0px); transform: translateY(var(--marker-top, 0px)); background: var(--text); border-radius: 1px; opacity: 0; transition: opacity 150ms var(--ease); }
    .rail ul.following::before { opacity: 1; transition: opacity 150ms var(--ease), transform 300ms var(--ease), height 300ms var(--ease); }

    /* The same list as a fold under the page's title, where the screen is
       too narrow for the list beside the page. */
    .onpage { display: none; margin: 0 0 1.5rem; background: var(--surface); border-radius: 14px; }
    .onpage summary { display: flex; align-items: center; justify-content: space-between; padding: 0.8rem 1.1rem; font-size: 14px; font-weight: 600; cursor: pointer; list-style: none; border-radius: 14px; -webkit-tap-highlight-color: transparent; }
    .onpage summary::-webkit-details-marker { display: none; }
    .onpage summary::after { content: ""; width: 7px; height: 7px; margin: -3px 0.2rem 0 0; border-right: 1.5px solid var(--text-2); border-bottom: 1.5px solid var(--text-2); transform: rotate(45deg); transition: transform 200ms var(--ease); }
    .onpage[open] > summary::after { transform: rotate(225deg); margin-top: 3px; }
    .prose .onpage ul { list-style: none; margin: 0; padding: 0 0.5rem 0.6rem; }
    .prose .onpage li { margin: 0; }
    .onpage li a { display: block; padding: 0.45rem 0.6rem; border-radius: 8px; font-size: 15px; line-height: 1.35; color: var(--text-2); }
    .onpage li a:hover { color: var(--text); text-decoration: none; }
    .onpage li.level-3 a { padding-left: 1.6rem; font-size: 14px; }

    /* A chapter's end: the chapter before and the chapter after as two
       cards, and the way back to the contents under them. */
    .pager { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; margin-top: 3.5rem; padding-top: 2.5rem; border-top: 1px solid var(--border); }
    .pager-card { display: flex; flex-direction: column; gap: 0.35rem; padding: 1rem 1.25rem 1.1rem; border: 1px solid var(--border); border-radius: 14px; color: var(--text); transition: background 150ms var(--ease); }
    .pager-card:hover { background: var(--surface); text-decoration: none; }
    .pager-previous { grid-column: 1; }
    .pager-next { grid-column: 2; align-items: flex-end; text-align: right; }
    .pager-way { display: inline-flex; align-items: center; gap: 0.45rem; font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
    .pager-previous .pager-way::before, .pager-next .pager-way::after { content: ""; width: 6px; height: 6px; border-right: 1.5px solid var(--muted); border-bottom: 1.5px solid var(--muted); transition: transform 300ms var(--ease); }
    .pager-previous .pager-way::before { transform: rotate(135deg); }
    .pager-next .pager-way::after { transform: rotate(-45deg); }
    .pager-previous:hover .pager-way::before { transform: translateX(-3px) rotate(135deg); }
    .pager-next:hover .pager-way::after { transform: translateX(3px) rotate(-45deg); }
    .pager-name { font-size: 17px; font-weight: 600; line-height: 1.3; letter-spacing: -0.01em; }
    .pager-up { grid-column: 1 / -1; justify-self: center; padding: 0.25rem 0.75rem; font-size: 13px; color: var(--text-2); }
    .pager-up:hover { color: var(--text); }

    /* The trail */
    .trail { font-size: 13px; color: var(--text-2); margin-bottom: 1.75rem; }
    .trail a { color: var(--text-2); }
    .trail a:hover { color: var(--text); }
    .trail sup { font-size: inherit; line-height: inherit; }
    .trail code { background: none; padding: 0; font-size: 0.95em; }

    /* Prose */
    .prose h1 { font-size: 40px; line-height: 1.1; font-weight: 700; letter-spacing: -0.025em; margin: 0 0 1.25rem; }
    .prose h2 { font-size: 28px; line-height: 1.2; font-weight: 700; letter-spacing: -0.02em; margin: 3rem 0 1rem; }
    .prose h3 { font-size: 21px; line-height: 1.25; font-weight: 600; letter-spacing: -0.015em; margin: 2.25rem 0 0.75rem; }
    .prose h4 { font-size: 17px; font-weight: 600; margin: 1.75rem 0 0.5rem; }
    .prose h5, .prose h6 { font-size: 15px; font-weight: 600; margin: 1.5rem 0 0.5rem; color: var(--text-2); }
    .prose h1 code, .prose h2 code, .prose h3 code, .prose h4 code { font-size: 0.85em; background: none; padding: 0; }
    .prose p, .prose ul, .prose ol, .prose blockquote, .prose .table, .prose pre, .prose picture, .prose > img { margin: 0 0 1.1rem; }
    .prose ul, .prose ol { padding-left: 1.4rem; }
    .prose li { margin: 0.3rem 0; }
    .prose li > ul, .prose li > ol { margin: 0.3rem 0 0; }
    /* A list written with a blank line between its items, or with paragraphs
       and code under them: the items stand as far apart as paragraphs do,
       and what an item holds ends flush with it. */
    .spread > li { margin: 1.1rem 0; }
    .prose li > pre { margin-top: 0.5rem; }
    .prose li > :last-child { margin-bottom: 0; }
    .prose blockquote { border-left: 3px solid var(--border); padding: 0.25rem 0 0.25rem 1.1rem; color: var(--text-2); }
    .prose blockquote p:last-child { margin-bottom: 0; }
    .prose picture, .prose > img { margin-top: 1.5rem; margin-bottom: 1.5rem; }
    .prose picture img, .prose > img { border-radius: 14px; }
    /* A picture or a clip that is white at its edge has no edge on a white
       page, and then it floats and the column beside it looks out of line.
       A hairline just inside its own frame gives every one the same edge,
       in the color every other hairline here is drawn in, and takes no
       room. A picture carries the line itself. A clip's is drawn on the
       frame around it, over the video: a browser that hands a video to its
       compositor draws the video over anything set on the video's own box,
       and the line would show only where the corners are cut. A thumbnail
       takes the frame's way too, since a clip stands in for it on hover;
       its frame is the link around it, made a box of its own, because a
       frame laid out in a line of text is measured by that line in one
       browser, and a link around a picture has no text. */
    .prose picture img, .prose > img { outline: 1px solid var(--border); outline-offset: -1px; }
    .gallery figure > a, .example-clip, .page-hero, .band-slide figure { position: relative; }
    .gallery figure > a { display: block; }
    .gallery figure > a::after, .example-clip::after, .page-hero::after, .band-slide figure::after { content: ""; position: absolute; inset: 0; border-radius: 14px; box-shadow: inset 0 0 0 1px var(--border); pointer-events: none; }
    .gallery figure > a::after { border-radius: 12px; }
    .prose .badges { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: -0.25rem; }
    .prose .badges img { display: inline-block; height: 20px; border-radius: 4px; }
    .prose .lede { font-size: 21px; line-height: 1.4; color: var(--text-2); letter-spacing: -0.01em; margin-bottom: 1.75rem; }
    .prose strong { font-weight: 600; }
    .prose .table { overflow-x: auto; border: 1px solid var(--border); border-radius: 14px; }
    .prose table { border-collapse: collapse; width: 100%; font-size: 15px; }
    .prose th, .prose td { text-align: left; vertical-align: top; padding: 0.7rem 1rem; border-top: 1px solid var(--border); }
    .prose th { border-top: 0; font-weight: 600; background: var(--surface); }
    .prose td:first-child { white-space: nowrap; }
    .prose a[name], .prose a[id] { display: block; position: relative; top: -72px; visibility: hidden; }

    /* The front page's band: one sketch at a time beside the whole program
       that draws it, paged by the dots under it. The track is a scroller
       that snaps, so a swipe is the browser's own and no script is needed
       to move between them. */
    .home-band > h2 { margin-bottom: 0.4rem; }
    .band-lede { margin: 0 0 2rem; color: var(--text-2); }
    .band-track { display: grid; grid-auto-flow: column; grid-auto-columns: 100%; overflow-x: auto; overscroll-behavior-x: contain; scroll-snap-type: x mandatory; scrollbar-width: none; }
    .band-track::-webkit-scrollbar { display: none; }
    .band-track:focus-visible { outline: 2px solid var(--text); outline-offset: 8px; border-radius: 14px; }
    .band-slide { display: grid; grid-template-columns: minmax(0, 0.9fr) minmax(0, 1.1fr); gap: 1.75rem; align-items: center; min-width: 0; scroll-snap-align: start; scroll-snap-stop: always; }
    .band-slide figure { margin: 0; }
    .band-slide video { width: 100%; height: auto; border-radius: 14px; background: var(--surface); }
    .band-code { min-width: 0; }
    .band-code > h3 { margin: 0 0 0.85rem; font-size: 19px; font-weight: 600; letter-spacing: -0.015em; }
    .band-code pre { margin: 0; font-size: 12.5px; line-height: 1.55; }
    .band-code > p { margin: 1rem 0 0; font-size: 15px; line-height: 1.5; color: var(--text-2); }
    .band-code > p code { background: var(--surface-2); }
    .band-controls { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; margin-top: 1.75rem; }
    .band-pager { display: flex; align-items: center; gap: 0.3rem; }
    .band-arrow { display: inline-flex; align-items: center; justify-content: center; width: 34px; height: 34px; padding: 0; border: 1px solid var(--border); border-radius: 999px; background: none; color: var(--text-2); cursor: pointer; transition: color 150ms var(--ease), background 150ms var(--ease); }
    .band-arrow:hover { color: var(--text); background: var(--surface); }
    .band-arrow .icon { width: 16px; height: 16px; }
    .band-arrow[data-band-step="-1"] .icon { transform: scaleX(-1); }
    .band-dots { display: flex; align-items: center; margin: 0 0.35rem; }
    /* The mark is small and the button is not: a dot you can hit with a
       thumb is 24px of target around 8px of ink. */
    .band-dot { position: relative; width: 24px; height: 24px; padding: 0; border: 0; border-radius: 999px; background: none; cursor: pointer; }
    .band-dot::before { content: ''; position: absolute; top: 50%; left: 50%; width: 8px; height: 8px; margin: -4px 0 0 -4px; border-radius: 999px; background: var(--border); transition: background 150ms var(--ease), transform 150ms var(--ease); }
    .band-dot:hover::before { background: var(--text-2); }
    .band-dot[aria-current="true"]::before { background: var(--text); transform: scale(1.25); }
    .page-hero { margin: 0 0 2rem; }
    .page-hero video { width: 100%; height: auto; border-radius: 14px; background: var(--surface); }
    .gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 1rem; margin: 0 0 2rem; }
    .gallery figure { margin: 0; }
    .gallery img, .gallery video { width: 100%; aspect-ratio: 1; object-fit: contain; border-radius: 12px; background: var(--surface); }
    .gallery figcaption { margin-top: 0.4rem; font-size: 13px; line-height: 1.3; color: var(--text-2); }
    .example-clip { margin: 0 0 1.75rem; }
    .example-clip video { width: 100%; height: auto; border-radius: 14px; background: var(--surface); }
    .facts { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 0.45rem 1.25rem; font-size: 15px; margin: 0 0 1.75rem; padding: 1rem 1.25rem; background: var(--surface); border-radius: 14px; }
    .facts dt { color: var(--text-2); }
    .facts dd { margin: 0; overflow-wrap: anywhere; }
    .facts code { background: var(--surface-2); }

    .tk-comment { color: var(--tk-comment); font-style: italic; }
    .tk-string { color: var(--tk-string); }
    .tk-number { color: var(--tk-number); }
    .tk-keyword { color: var(--tk-keyword); }
    .tk-type { color: var(--tk-type); }
    .tk-attribute { color: var(--tk-attribute); }

    /* The front page */
    .hero { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, 0.9fr); align-items: center; gap: 3rem; padding: clamp(3rem, 8vw, 6rem) 0 clamp(2rem, 5vw, 4rem); }
    .eyebrow { font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: var(--text-2); margin-bottom: 1rem; }
    .hero h1 { font-size: clamp(36px, 5vw, 60px); line-height: 1.05; font-weight: 700; letter-spacing: -0.03em; margin: 0 0 1.75rem; }
    .hero-actions { display: flex; flex-wrap: wrap; gap: 0.75rem; }
    .button { display: inline-flex; align-items: center; padding: 0.7rem 1.25rem; border-radius: 999px; background: var(--text); color: var(--bg); font-weight: 500; font-size: 15px; transition: transform 300ms var(--ease), opacity 150ms; }
    .button:hover { text-decoration: none; transform: translateY(-1px); opacity: 0.9; }
    .button.quiet { background: transparent; color: var(--text); border: 1.5px solid var(--text); }
    button.button { border: 0; font-family: inherit; cursor: pointer; }
    /* The page for a wrong address: two lines and a way to search, held to
       the width prose is read at, over the three sections. */
    .notfound { max-width: 760px; padding-top: clamp(1rem, 5vw, 3.5rem); margin-bottom: 2.5rem; }
    .notfound p:last-child { margin-bottom: 0; }
    .hero-canvas { width: 100%; max-width: 460px; justify-self: center; }
    .hero-canvas canvas { width: 100%; height: auto; }
    .cards { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1.25rem; margin-bottom: 3rem; }
    .card { display: block; padding: 1.5rem; background: var(--surface); border-radius: 18px; color: var(--text); transition: transform 400ms var(--ease), background 150ms; }
    .card:hover { text-decoration: none; transform: translateY(-2px); background: var(--surface-2); }
    .card h2 { font-size: 21px; font-weight: 600; letter-spacing: -0.015em; margin: 0 0 0.4rem; }
    .card p { color: var(--text-2); font-size: 15px; margin: 0; }

    /* The front page below the cards: the README's opening and a few of its
       sections, each laid out for the width of a page. The blocks are the
       README's own markup; only the classes on the sections are the site's. */
    .home-section { padding: 3.5rem 0; border-top: 1px solid var(--border); }
    .home-section > h2:first-child, .home-pair h2 { font-size: 34px; letter-spacing: -0.025em; margin: 0 0 1.5rem; }
    .home-opening { border-top: 0; padding-top: 0.5rem; }
    .home-opening > p, .home-opening > blockquote { max-width: 820px; }
    .home-opening > p:first-child { font-size: 22px; line-height: 1.4; letter-spacing: -0.012em; margin-bottom: 1.5rem; }
    .home-opening > ul { list-style: none; padding: 0; margin: 2rem 0; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; }
    .home-opening > ul > li { margin: 0; padding: 1.1rem 1.25rem; background: var(--surface); border-radius: 14px; font-size: 15px; line-height: 1.5; color: var(--text-2); }
    .home-opening > ul > li strong { color: var(--text); }
    .home-opening > ul > li code { background: var(--surface-2); }
    .home-pair { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 3rem; padding: 3.5rem 0; border-top: 1px solid var(--border); }
    .home-pair > .home-section { border-top: 0; padding: 0; min-width: 0; }
    .home-pair p:last-child, .home-pair pre:last-child { margin-bottom: 0; }
    /* The section is the grid: the README's list dissolves into it and
       every item is a card. */
    .home-whats-in-it { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1.25rem; }
    .home-whats-in-it > h2, .home-whats-in-it > p { grid-column: 1 / -1; max-width: 820px; margin: 0; }
    .home-section.home-whats-in-it > h2:first-child { margin-bottom: 0.25rem; }
    .home-whats-in-it > p:last-child { margin-top: 0.5rem; }
    .home-whats-in-it > ul { display: contents; }
    .home-whats-in-it > ul > li { list-style: none; margin: 0; padding: 1.5rem 1.6rem; background: var(--surface); border-radius: 18px; font-size: 15px; line-height: 1.5; color: var(--text-2); }
    .home-whats-in-it > ul > li > strong:first-child, .home-whats-in-it > ul > li > p > strong:first-child { display: block; color: var(--text); font-size: 19px; line-height: 1.3; letter-spacing: -0.015em; margin-bottom: 0.5rem; }
    .home-whats-in-it > ul > li code { background: var(--surface-2); }
    .home-more > ul { list-style: none; padding: 0; margin: 0; display: flex; flex-wrap: wrap; gap: 0.6rem; }
    .home-more > ul > li { margin: 0; }
    .home-more a { display: inline-flex; align-items: center; padding: 0.55rem 1rem; border: 1px solid var(--border); border-radius: 999px; color: var(--text); font-size: 15px; font-weight: 500; transition: background 150ms var(--ease); }
    .home-more a:hover { text-decoration: none; background: var(--surface); }

    /* The foot */
    .foot { border-top: 1px solid var(--border); margin-top: auto; }
    .foot-inner { max-width: var(--max); margin: 0 auto; padding: 2rem var(--pad); font-size: 13px; color: var(--text-2); }
    .foot a { color: var(--text-2); text-decoration: underline; text-underline-offset: 0.15em; }

    /* Narrower */
    @media (max-width: 1100px) {
      .layout.with-rail { grid-template-columns: 240px minmax(0, 1fr); }
      .rail { display: none; }
      .onpage { display: block; }
    }
    @media (max-width: 860px) {
      .layout.with-sidebar, .layout.with-rail { grid-template-columns: minmax(0, 1fr); gap: 0; }
      /* With no script, the section's map goes under the page on a phone,
         where a reader wants the page first and the map after. */
      .sidebar { order: 2; position: static; max-height: none; margin: 0; padding: 1.5rem 0 2.5rem; border-top: 1px solid var(--border); -webkit-mask-image: none; mask-image: none; }
      .sidebar details { margin-top: 0.5rem; }
      /* With one, the map is a sheet under the bar, opened by the tab of
         the section the page is in. It is out of the page's flow from the
         first paint, so the page never waits on it or moves for it, and it
         opens on the row of the page being read. */
      .js .sidebar { position: fixed; z-index: 9; inset: var(--bar-height) 0 0 0; align-self: stretch; order: 0; padding: 1.5rem var(--pad) 4rem; border-top: 0; background: var(--bg); font-size: 16px; visibility: hidden; opacity: 0; transform: translateY(-0.6rem); transition: opacity 200ms var(--ease), transform 300ms var(--ease), visibility 0s linear 300ms; }
      .js.menu-open .sidebar { visibility: visible; opacity: 1; transform: none; transition-delay: 0s; }
      .js.menu-open { overflow: hidden; }
      .js .sidebar li a { padding: 0.55rem 0.75rem; margin: 0 -0.75rem; }
      .js .sidebar summary { padding: 0.55rem 0; }
      .js .sidebar-title { font-size: 13px; }
      .js .menu-toggle { display: inline-flex; }
      .js .sections a.has-menu { display: none; }
      .pager { grid-template-columns: minmax(0, 1fr); margin-top: 2.5rem; padding-top: 2rem; }
      .pager-previous, .pager-next { grid-column: 1; }
      main { padding-top: 1.75rem; padding-bottom: 2.5rem; }
      .hero { grid-template-columns: minmax(0, 1fr); }
      .hero-canvas { max-width: 320px; order: -1; }
      /* Stacked, the cards' own spacing already separates them from what
         follows, so the margin under the row reads as a hole, not a break. */
      .cards { grid-template-columns: minmax(0, 1fr); margin-bottom: 1.5rem; }
      /* Stacked, the sketch goes over its program rather than beside it,
         and the clip is capped so the two together still read as one
         screenful. One at a time is what makes that fit at all. */
      .band-slide { grid-template-columns: minmax(0, 1fr); gap: 1.1rem; }
      .band-slide figure { width: 100%; max-width: 340px; margin: 0 auto; }
      .band-code pre { font-size: 11.5px; }
      .band-controls { justify-content: center; margin-top: 1.25rem; }
      .home-section { padding: 2.5rem 0; }
      .home-section > h2:first-child, .home-pair h2 { font-size: 28px; }
      .home-opening > p:first-child { font-size: 19px; }
      .home-opening > ul, .home-pair, .home-whats-in-it { grid-template-columns: minmax(0, 1fr); }
      .home-pair { gap: 2.5rem; padding: 2.5rem 0; }
      .prose h1 { font-size: 32px; }
      .prose h2 { font-size: 24px; }
      .sections a { padding: 0 0.55rem; font-size: 13px; }
    }
    @media (max-width: 480px) {
      .wordmark .name { display: none; }
      .bar-inner { gap: 0.75rem; }
      .sections { gap: 0; }
      .sections a, .sections .menu-toggle { padding: 0 0.5rem; font-size: 12.5px; }
      .menu-toggle.beside-mark { margin-left: -0.75rem; width: 24px; }
      /* A phone's bar holds the mark, the three sections, and the search;
         the link out to the repository waits in the foot. With no script
         there is no search and no arrow in the bar, and the link stays
         until the screen is narrower still. */
      .js .sections a[rel] { display: none; }
    }
    @media (max-width: 350px) {
      .sections a[rel] { display: none; }
      .bar-inner { gap: 0.5rem; }
      .sections a, .sections .menu-toggle { padding: 0 0.35rem; }
      .search-toggle { margin-left: 0; }
    }

    /* Search: a button in the bar, a panel over the page */
    .search-toggle { display: inline-flex; align-items: center; gap: 0.45rem; height: 30px; padding: 0 0.6rem 0 0.55rem; margin-left: 0.25rem; border: 1px solid var(--border); border-radius: 999px; background: var(--surface); color: var(--text-2); font: inherit; font-size: 13px; cursor: pointer; transition: color 150ms var(--ease), background 150ms var(--ease); }
    .search-toggle:hover { color: var(--text); background: var(--surface-2); }
    .search-toggle .icon { width: 15px; height: 15px; }
    .search-toggle .key { font-size: 11.5px; color: var(--muted); letter-spacing: 0.02em; }
    .search-toggle .key:empty { display: none; }
    dialog.search { position: fixed; inset: 0; width: 100vw; height: 100dvh; max-width: none; max-height: none; margin: 0; padding: 0; border: 0; background: transparent; color: var(--text); }
    dialog.search::backdrop { background: rgba(0, 0, 0, 0.35); -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px); }
    .search-panel { display: flex; flex-direction: column; width: min(640px, calc(100% - 2rem)); max-height: min(70dvh, 640px); margin: clamp(2rem, 10vh, 7rem) auto 0; background: var(--bg); border: 1px solid var(--border); border-radius: 18px; box-shadow: 0 24px 80px rgba(0, 0, 0, 0.28); overflow: hidden; }
    .search-box { display: flex; align-items: center; gap: 0.75rem; padding: 0.9rem 1.1rem; border-bottom: 1px solid var(--border); }
    .search-box .icon { width: 18px; height: 18px; color: var(--text-2); flex: none; }
    .search-box input { flex: 1; min-width: 0; border: 0; outline: 0; background: transparent; color: var(--text); font: inherit; font-size: 19px; letter-spacing: -0.01em; }
    .search-box input::-webkit-search-cancel-button, .search-box input::-webkit-search-decoration { -webkit-appearance: none; appearance: none; }
    .search-box input::placeholder { color: var(--muted); }
    .search kbd { font-family: var(--font); font-size: 11px; line-height: 1; color: var(--text-2); border: 1px solid var(--border); border-radius: 6px; padding: 0.25em 0.45em; background: var(--surface); }
    .search-status { padding: 0.6rem 1.1rem 0; font-size: 12.5px; color: var(--muted); }
    .search-status:empty { display: none; }
    .search-results { list-style: none; margin: 0; padding: 0.5rem; overflow-y: auto; flex: 1; scrollbar-width: thin; }
    .search-results:empty { display: none; }
    .search-results li a { display: grid; grid-template-columns: 82px minmax(0, 1fr); gap: 0.1rem 0.9rem; padding: 0.6rem 0.75rem; border-radius: 12px; color: var(--text); font-size: 15px; line-height: 1.35; }
    .search-results li a:hover { text-decoration: none; }
    .search-results li.active a { background: var(--surface); }
    .search-results .kind { grid-row: 1 / span 2; padding-top: 0.3em; font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
    .search-results .where { font-weight: 600; letter-spacing: -0.005em; overflow-wrap: anywhere; }
    .search-results .where .sep { color: var(--muted); font-weight: 400; }
    .search-results .excerpt { font-size: 13.5px; color: var(--text-2); display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .search mark { background: none; color: inherit; font-weight: 700; text-decoration: underline; text-decoration-color: var(--accent); text-decoration-thickness: 2px; text-underline-offset: 0.12em; }
    .search-hints { display: flex; align-items: center; gap: 0.4rem; padding: 0.6rem 1.1rem; border-top: 1px solid var(--border); font-size: 12px; color: var(--muted); }
    .search-hints kbd { margin-right: 0.15rem; }
    @media (max-width: 860px) {
      .search-toggle .key { display: none; }
      .search-panel { margin-top: 1rem; max-height: calc(100dvh - 2rem); }
      .search-results li a { grid-template-columns: minmax(0, 1fr); }
      .search-results .kind { grid-row: auto; padding-top: 0; }
      .search-hints { display: none; }
    }
    """

    /// The front page's ring, dressed in the page's colors. The ring is the
    /// sketch's own web page (`SiteHero.fragment`), which plays on its own,
    /// stands still for a reader who asked for less motion, and leaves a
    /// handle on its canvas; this sets the ring's `ink` and `paper` through
    /// that handle from the stylesheet's own variables, and again when the
    /// reader's color scheme changes, so the ring follows the site rather
    /// than keeping the black on white it was recorded in.
    static let heroScript = """
    (() => {
      const canvas = document.querySelector('.hero-canvas canvas');
      const player = canvas && canvas.ollin;
      if (!player) return;
      const paint = () => {
        const style = getComputedStyle(document.documentElement);
        player.set('paper', style.getPropertyValue('--bg').trim());
        player.set('ink', style.getPropertyValue('--text').trim());
      };
      paint();
      matchMedia('(prefers-color-scheme: dark)').addEventListener('change', paint);
    })();
    """

    /// A block of code or a table too wide for its column scrolls sideways
    /// inside its own box, and a box that scrolls has to be reachable from the
    /// keyboard or its right half is out of reach without a pointer. Only the
    /// blocks that do overflow take a place in the Tab order, so a page of
    /// short listings adds nothing between its links, and the check runs
    /// again when the window changes width.
    static let scrollerScript = """
    <script>(()=>{const mark=()=>{for(const box of document.querySelectorAll('pre, .table')){\
    if(box.scrollWidth>box.clientWidth)box.tabIndex=0;else box.removeAttribute('tabindex');}};\
    mark();addEventListener('resize',mark);})();</script>
    """

    /// The first thing a page's head runs: it says a script is here. The
    /// stylesheet reads that for the one arrangement that only works with
    /// one, the section's menu as a sheet on a phone, and it has to be said
    /// before the first paint, or a phone would draw the menu under the page
    /// and then take it away.
    static let scriptedMark = "<script>document.documentElement.className='js'</script>"

    /// The section's menu opens on the page being read.
    ///
    /// The script sits right after the menu in the page, so it runs as soon
    /// as the menu is there and before anything is drawn: a reader never
    /// sees the menu at its top and then somewhere else. A page near the
    /// menu's top leaves it at its top; a page further down is put two
    /// fifths of the way down the menu's window, which is the same place on
    /// every page, so stepping from one chapter to the next moves the menu
    /// by one row. A page with no row of its own (a folder's index) shows
    /// the first group it opened. Nothing is stored between pages.
    static let menuPlaceScript = """
    <script>(()=>{const m=document.currentScript.previousElementSibling,\
    c=m&&(m.querySelector('[aria-current]')||m.querySelector('details[open]'));if(!c)return;\
    const b=m.getBoundingClientRect(),r=c.getBoundingClientRect();\
    if(r.bottom>b.bottom-96)m.scrollTop=r.top-b.top-(b.height-r.height)*0.4;})();</script>
    """

    /// The small arrow on what opens the section's menu on a phone. It
    /// points down, and turns over while the menu is open.
    static let disclosure = """
    <svg class="icon" aria-hidden="true" focusable="false" viewBox="0 0 12 12"><path d="m2.25 4.25 3.75 3.75 3.75-3.75" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>
    """

    /// The two lists beside a page follow the reader, written to
    /// `assets/menus.js` and loaded by every page that has a menu.
    ///
    /// **The section being read.** The list of the page's own sections marks
    /// the last heading that has passed a line just under the bar, and keeps
    /// that entry inside the list's own window when the list is long. The
    /// last sections of a page can never reach that line, since the page
    /// stops scrolling first, so over the last screenful the line slides
    /// down to the window's foot: every section is marked somewhere, in
    /// order, and the last one at the page's end. A section a reader asked
    /// for by name (a click on its entry, a link that ends in its anchor)
    /// stays marked whatever the line says, until the reader scrolls by
    /// hand.
    ///
    /// **The lists' own windows.** A list longer than its window fades at
    /// the edge it runs past. Near a page's end, where the layout stops
    /// short of the window's foot, the lists are shortened by that much, so
    /// they stop at the foot and are not pushed up under the bar.
    ///
    /// **The menu on a phone.** The tab of the section the page is in opens
    /// the section's menu as a sheet under the bar, on the row of the page
    /// being read. While it is open the page behind it is out of reach of a
    /// Tab and of a screen reader; the tab again, or Escape, closes it and
    /// hands the focus back.
    ///
    /// With no script none of this runs: the lists are plain links, and a
    /// phone has the menu under the page.
    static let menusScript = #"""
    (() => {
      const root = document.documentElement;
      const side = document.querySelector('.sidebar');
      const rail = document.querySelector('.rail');
      const layout = document.querySelector('.layout');
      const bar = document.querySelector('.bar');
      const still = matchMedia('(prefers-reduced-motion: reduce)');
      const narrow = matchMedia('(max-width: 860px)');
      const boxes = [side, rail].filter(Boolean);

      // A list that runs past its window fades at that edge.
      const edges = (box) => {
        const more = box.scrollHeight - box.clientHeight;
        box.classList.toggle('more-above', more > 1 && box.scrollTop > 1);
        box.classList.toggle('more-below', more > 1 && box.scrollTop < more - 1);
      };
      boxes.forEach((box) => box.addEventListener('scroll', () => edges(box), { passive: true }));

      // The row a list should not lose sight of, brought back inside the
      // list's window when it has slipped out of it.
      const inside = (box, row, margin) => {
        const frame = box.getBoundingClientRect(), at = row.getBoundingClientRect();
        return at.top >= frame.top + margin && at.bottom <= frame.bottom - margin;
      };
      const center = (box, row, smooth) => {
        const frame = box.getBoundingClientRect(), at = row.getBoundingClientRect();
        const top = box.scrollTop + at.top - frame.top - (frame.height - at.height) / 2;
        box.scrollTo({ top, behavior: smooth && !still.matches ? 'smooth' : 'auto' });
      };

      // Near the page's end the lists stop where the layout does. A list
      // made shorter keeps the row it was showing: the section being read
      // in the list of sections, and the page being read in the menu,
      // unless the reader has scrolled the menu somewhere else by hand.
      let cut = -1, handled = false;
      if (side) ['wheel', 'touchmove', 'keydown'].forEach((kind) => side.addEventListener(kind, () => { handled = true; }, { passive: true }));
      const fit = () => {
        if (!layout) return false;
        const over = Math.max(0, Math.round(innerHeight - layout.getBoundingClientRect().bottom));
        if (over === cut) return false;
        cut = over;
        boxes.forEach((box) => box.style.setProperty('--cut', over + 'px'));
        return true;
      };
      const keep = () => {
        const page = side && !handled && !narrow.matches ? side.querySelector('[aria-current]') : null;
        if (page && !inside(side, page, 0)) center(side, page, false);
        if (current >= 0 && !inside(rail, pairs[current].link, 0)) center(rail, pairs[current].link, false);
        boxes.forEach(edges);
      };

      // The section being read.
      const list = rail && rail.querySelector('ul');
      const pairs = [];
      if (list) {
        list.querySelectorAll('a[href^="#"]').forEach((link) => {
          let heading = null;
          try { heading = document.getElementById(decodeURIComponent(link.hash.slice(1))); } catch (error) {}
          if (heading) pairs.push({ link, heading });
        });
      }
      let current = -1, pinned = -1, landed = null, settling = 0, settled = false;
      const show = (index) => {
        if (index === current) return;
        if (current >= 0) pairs[current].link.removeAttribute('aria-current');
        current = index;
        if (index < 0) { list.classList.remove('following'); return; }
        const link = pairs[index].link, item = link.parentElement;
        link.setAttribute('aria-current', 'location');
        list.style.setProperty('--marker-top', item.offsetTop + 'px');
        list.style.setProperty('--marker-height', item.offsetHeight + 'px');
        if (!list.classList.contains('following')) {
          // The bar appears where it belongs rather than sliding in from
          // the list's top: its place is read before it is shown.
          getComputedStyle(list, '::before').transform;
          list.classList.add('following');
        }
        if (!inside(rail, link, 64)) center(rail, link, settled);
      };
      // Where a section asked for by name comes to rest under the bar (the
      // stylesheet's `scroll-padding-top`), and the line a heading has to
      // pass to be the one being read, a little under that.
      const rests = parseFloat(getComputedStyle(root).scrollPaddingTop) || 72;
      const reading = () => {
        if (pinned >= 0) return pinned;
        const most = Math.max(0, root.scrollHeight - innerHeight);
        const tops = pairs.map((pair) => pair.heading.getBoundingClientRect().top);
        let line = rests + 16;
        // The page's last sections cannot be brought up to that line: the
        // page ends first. From where the last section that can be has
        // come to rest, the line slides down, and reaches the last heading
        // exactly as the page reaches its end.
        const tail = tops.findIndex((top) => top + scrollY - rests > most - 1);
        if (tail >= 0) {
          const from = tail > 0 ? Math.min(most, tops[tail - 1] + scrollY - rests + 1) : 0;
          const end = Math.max(line, tops[tops.length - 1] + scrollY - most + 1);
          if (most > from && scrollY > from) line += (end - line) * Math.min(1, (scrollY - from) / Math.max(1, most - 2 - from));
        }
        let found = -1;
        for (let n = 0; n < tops.length; n++) {
          if (tops[n] > line) break;
          found = n;
        }
        return found;
      };
      // A section asked for by name stays marked until the page moves off
      // the place the asking brought it to.
      const rest = () => { clearTimeout(settling); settling = setTimeout(() => { landed = scrollY; }, 180); };
      const pin = (id) => {
        const index = pairs.findIndex((pair) => pair.heading.id === id);
        if (index < 0) return false;
        pinned = index;
        landed = null;
        rest();
        return true;
      };
      const release = () => { pinned = -1; landed = null; clearTimeout(settling); };

      // A list that was just made shorter is looked at in the same breath:
      // nothing that sets its height is a transition, with motion or
      // without it.
      let queued = false;
      const follow = () => {
        queued = false;
        if (pairs.length) show(reading());
        if (fit()) keep();
        settled = true;
      };
      const ask = () => { if (!queued) { queued = true; requestAnimationFrame(follow); } };
      // A browser hands a page its scrolling once a frame, so the answer is
      // worked out right there and needs no frame of its own.
      addEventListener('scroll', () => {
        if (pinned >= 0) { if (landed === null) rest(); else if (Math.abs(scrollY - landed) > 2) release(); }
        follow();
      }, { passive: true });
      addEventListener('resize', () => { boxes.forEach(edges); follow(); });
      addEventListener('load', ask);
      if (pairs.length) {
        const named = (hash) => { try { if (pin(decodeURIComponent(hash.slice(1)))) ask(); } catch (error) {} };
        addEventListener('hashchange', () => named(location.hash));
        document.addEventListener('click', (event) => {
          const link = event.target.closest && event.target.closest('a[href^="#"]');
          if (link) named(link.hash);
        });
        // A scroll by hand lets the line decide again at once.
        ['wheel', 'touchmove', 'keydown'].forEach((kind) => addEventListener(kind, release, { passive: true, capture: true }));
        named(location.hash);
      }

      // The fold under the title closes as it sends the reader on, so the
      // page is its own length again before the browser works out where the
      // section is.
      const fold = document.querySelector('.onpage');
      if (fold) fold.addEventListener('click', (event) => { if (event.target.closest('a')) fold.open = false; });

      // The menu on a phone.
      const toggle = document.querySelector('.menu-toggle');
      if (side && toggle) {
        const behind = [document.querySelector('main'), document.querySelector('.foot')].filter(Boolean);
        const place = () => {
          const row = side.querySelector('[aria-current]') || side.querySelector('details[open]');
          if (!row) { side.scrollTop = 0; return; }
          const box = side.getBoundingClientRect(), at = row.getBoundingClientRect();
          side.scrollTop += at.top - box.top - (box.height - at.height) * 0.4;
        };
        const isOpen = () => root.classList.contains('menu-open');
        const set = (open) => {
          if (open === isOpen()) return;
          root.classList.toggle('menu-open', open);
          toggle.setAttribute('aria-expanded', String(open));
          behind.forEach((element) => { element.inert = open; });
          if (open) { place(); side.focus({ preventScroll: true }); }
          else if (side.contains(document.activeElement) || document.activeElement === side) toggle.focus({ preventScroll: true });
        };
        toggle.addEventListener('click', () => set(!isOpen()));
        document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && isOpen()) { set(false); toggle.focus({ preventScroll: true }); } });
        narrow.addEventListener('change', () => { if (!narrow.matches) set(false); });
        // A page brought back by the Back button comes back closed.
        addEventListener('pageshow', (event) => { if (event.persisted) set(false); });
      }

      boxes.forEach(edges);
      follow();
    })();
    """#

    /// The magnifier, drawn in the page's ink, for the bar's button and the
    /// search box.
    static let searchIcon = """
    <svg class="icon" aria-hidden="true" focusable="false" viewBox="0 0 20 20"><circle cx="8.5" cy="8.5" r="5.75" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12.75 12.75 17 17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
    """

    /// The arrow on the band's buttons, pointing right; the button that goes
    /// back turns it over in the stylesheet rather than carrying a second
    /// drawing.
    static let chevron = """
    <svg class="icon" aria-hidden="true" focusable="false" viewBox="0 0 20 20"><path d="m7.75 4.5 7 5.5-7 5.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>
    """

    /// The front page's band of sketches, paged one at a time.
    ///
    /// The moving is the browser's own: the track is a scroller that snaps,
    /// so a swipe, a trackpad, and the arrow keys all work with the script
    /// turned off, and what the script adds is the buttons, the dots that
    /// say where you are, and the rule that only the sketch on screen plays.
    /// That last one is why the other clips carry neither `autoplay` nor a
    /// preload: they are not asked for until somebody pages to them.
    ///
    /// A reader who asked for less motion gets no sketch playing at all and
    /// the controls to start one, which is the same bargain the clips on an
    /// example's own page strike.
    static let bandScript = """
    <script>
    (() => {
      const band = document.querySelector('[data-band]');
      if (!band) return;
      const track = band.querySelector('.band-track');
      const slides = Array.from(track.children);
      const dots = Array.from(band.querySelectorAll('.band-dot'));
      const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
      let at = 0;
      const show = (index) => {
        at = index;
        dots.forEach((dot, n) => dot.setAttribute('aria-current', String(n === index)));
        // The run command further down the page names the sketch on screen.
        // Looked up on each move rather than held, since this runs while the
        // page is still being parsed and that section is not there yet.
        const command = document.querySelector('[data-run-target]');
        const target = slides[index].dataset.target;
        if (command && target) command.textContent = target;
        slides.forEach((slide, n) => {
          const clip = slide.querySelector('video');
          if (!clip) return;
          if (n !== index) { clip.pause(); return; }
          if (still) return;
          const playing = clip.play();
          if (playing) playing.catch(() => {});
        });
      };
      const go = (index) => {
        const wanted = Math.max(0, Math.min(slides.length - 1, index));
        track.scrollTo({ left: wanted * track.clientWidth, behavior: still ? 'auto' : 'smooth' });
        show(wanted);
      };
      band.querySelectorAll('[data-band-step]').forEach((button) => {
        button.addEventListener('click', () => go(at + Number(button.dataset.bandStep)));
      });
      dots.forEach((dot, n) => dot.addEventListener('click', () => go(n)));
      let settling;
      track.addEventListener('scroll', () => {
        clearTimeout(settling);
        settling = setTimeout(() => {
          const landed = Math.round(track.scrollLeft / track.clientWidth);
          if (landed !== at) show(landed);
        }, 90);
      }, { passive: true });
      if (still) {
        slides.forEach((slide) => {
          const clip = slide.querySelector('video');
          if (!clip) return;
          clip.autoplay = false;
          clip.controls = true;
          clip.pause();
        });
      }
      show(0);
    })();
    </script>
    """

    /// The library that does the matching, MiniSearch (MIT), pinned to one
    /// release on a content network and checked against its published hash
    /// on the way in, so the page runs the bytes that were reviewed and
    /// nothing else. It is loaded on the first search rather than with the
    /// page, so a reader who never searches never asks the network for it.
    static let searchLibrary = "https://cdnjs.cloudflare.com/ajax/libs/minisearch/7.2.0/umd/index.min.js"
    static let searchLibraryIntegrity = "sha512-bxNn8csqHSaI1AgYVvi4ejDdG9GfPbmth/TBcxd6J02ShNFQRqRJVPqqCvRHYV1nnvwCTeteqWuoOAeNewQ9CQ=="

    /// The search, written to `assets/search.js` and loaded by every page.
    ///
    /// The button in the bar, `/`, or the command (or control) key with K
    /// opens the dialog; the first time, the library and then the index come
    /// in, and the index is built in the browser in small steps so the field
    /// stays live while it does. A query matches by prefix (so `kuwa` finds
    /// `kuwahara`), tolerates a typo in a longer word, and needs every word
    /// it has, with a page's title counting most, its heading next, its first
    /// line after that, and the words of its prose least. A page's own entry
    /// stands ahead of its sections when both match, no page takes more than
    /// three of the thirty rows shown, and the words that matched are marked
    /// where they appear. Arrow keys move, return opens, escape closes; a
    /// click on the dimmed page closes too.
    static let searchScript = #"""
    (() => {
      const dialog = document.getElementById('search');
      const toggle = document.querySelector('.search-toggle');
      if (!dialog || !toggle || typeof dialog.showModal !== 'function') return;
      const input = dialog.querySelector('input');
      const status = dialog.querySelector('.search-status');
      const list = dialog.querySelector('.search-results');
      const root = dialog.dataset.root || '';
      const library = '\#(searchLibrary)';
      const integrity = '\#(searchLibraryIntegrity)';
      const labels = { docs: 'Reference', guide: 'Guide', examples: 'Examples', home: 'Ollin' };
      const order = { docs: 0, guide: 1, examples: 2, home: 3 };
      const perPage = 3, atMost = 30;
      let engine = null, count = 0, loading = false, failed = '', active = -1;

      toggle.hidden = false;
      const key = toggle.querySelector('.key');
      const shortcut = /Mac|iPhone|iPad/.test(navigator.platform) ? '⌘K' : 'Ctrl K';
      if (key) key.textContent = shortcut;
      toggle.title = 'Search (' + shortcut + ')';
      // The button's spoken name holds what the button shows: the keys
      // beside the magnifier on a wide screen, and the word alone where
      // the keys are not shown. The keys follow a comma, not brackets: a
      // checker of names sets aside whatever a name says in brackets.
      const roomy = matchMedia('(min-width: 861px)');
      const name = () => toggle.setAttribute('aria-label', roomy.matches ? 'Search, ' + shortcut : 'Search');
      name();
      roomy.addEventListener('change', name);

      const fold = (text) => String(text).normalize('NFD').replace(/\p{M}/gu, '');

      const script = (src, sri) => new Promise((resolve, reject) => {
        const element = document.createElement('script');
        element.src = src;
        if (sri) { element.integrity = sri; element.crossOrigin = 'anonymous'; }
        element.onload = () => resolve();
        element.onerror = () => reject(new Error(src));
        document.head.appendChild(element);
      });

      const load = async () => {
        if (engine || loading || failed) return;
        loading = true;
        status.textContent = 'Loading…';
        try {
          if (!window.MiniSearch) await script(library, integrity);
          if (!window.ollinSearchIndex) await script(root + 'assets/search-index.js');
          const entries = window.ollinSearchIndex.map((entry, id) => Object.assign({ id }, entry));
          const built = new MiniSearch({
            fields: ['t', 'h', 'x', 'w'],
            storeFields: ['k', 't', 'h', 'u', 'x'],
            // A name is found with or without its accents: the index and the
            // query both drop them, so `bonacic` reaches Bonačić.
            processTerm: (term) => fold(term).toLowerCase(),
            searchOptions: {
              boost: { t: 6, h: 4, x: 2, w: 1 },
              boostDocument: (id, term, fields) => (fields && fields.h === '' ? 1.25 : 1),
              prefix: (term) => term.length >= 2,
              fuzzy: (term) => (term.length >= 5 ? 0.2 : false),
              combineWith: 'AND'
            }
          });
          await built.addAllAsync(entries);
          engine = built;
          count = entries.length;
        } catch (error) {
          failed = String(error && error.message).indexOf('search-index') >= 0
            ? 'The index did not load.'
            : 'The search library did not load. It comes from a content network, so this needs a connection.';
        }
        loading = false;
        render();
      };

      const escape = (text) => String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
      // The matched terms arrive without accents, so they are looked for in
      // the text with each accented letter as its plain one, letter for
      // letter: a match sits at the same place in the text that is shown.
      const unaccented = (text) => text.replace(/[À-ɏḀ-ỿ]/g, (c) => { const plain = fold(c); return plain.length === 1 ? plain : c; });
      const marked = (text, terms) => {
        text = String(text);
        if (!terms.length) return escape(text);
        const alternatives = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
        const pattern = new RegExp('(^|[^\\p{L}\\p{N}])(' + alternatives + ')', 'giu');
        let out = '', last = 0;
        for (const match of unaccented(text).matchAll(pattern)) {
          const start = match.index + match[1].length;
          const end = start + match[2].length;
          out += escape(text.slice(last, start)) + '<mark>' + escape(text.slice(start, end)) + '</mark>';
          last = end;
        }
        return out + escape(text.slice(last));
      };

      const setActive = (index) => {
        const items = list.children;
        if (!items.length) { active = -1; return; }
        index = (index + items.length) % items.length;
        if (active >= 0 && items[active]) items[active].classList.remove('active');
        active = index;
        items[index].classList.add('active');
        items[index].scrollIntoView({ block: 'nearest' });
      };

      const render = () => {
        const query = input.value.trim();
        active = -1;
        list.innerHTML = '';
        if (failed) { status.textContent = failed; return; }
        if (!engine) { if (!loading) status.textContent = ''; return; }
        if (!query) { status.textContent = count.toLocaleString() + ' sections of the Guide, the reference, and the examples.'; return; }
        const results = engine.search(query);
        results.sort((a, b) => (b.score - a.score) || ((order[a.k] ?? 3) - (order[b.k] ?? 3)));
        const taken = new Map();
        const shown = [];
        for (const result of results) {
          const page = result.u.split('#')[0];
          const had = taken.get(page) || 0;
          if (had >= perPage) continue;
          taken.set(page, had + 1);
          shown.push(result);
          if (shown.length >= atMost) break;
        }
        if (!shown.length) { status.textContent = 'Nothing matches “' + query + '”.'; return; }
        status.textContent = shown.length < results.length
          ? shown.length + ' of ' + results.length + ' matches'
          : shown.length + (shown.length === 1 ? ' match' : ' matches');
        list.innerHTML = shown.map((result) => {
          // A page, then its section; for an example, its category, then its name.
          const pair = result.k === 'examples' ? [result.h, result.t] : [result.t, result.h];
          const where = pair[1]
            ? marked(pair[0], result.terms) + '<span class="sep"> › </span>' + marked(pair[1], result.terms)
            : marked(pair[0], result.terms);
          const excerpt = result.x ? '<span class="excerpt">' + marked(result.x, result.terms) + '</span>' : '';
          return '<li><a href="' + escape(root + result.u) + '"><span class="kind">' + (labels[result.k] || '') + '</span><span class="where">' + where + '</span>' + excerpt + '</a></li>';
        }).join('');
        setActive(0);
      };

      const open = () => {
        if (dialog.open) return;
        dialog.showModal();
        load();
        render();
        input.focus();
        input.select();
      };
      const close = () => { if (dialog.open) dialog.close(); };

      toggle.addEventListener('click', open);
      // A page may carry a button of its own that opens the search, hidden
      // like the bar's until this script is here to answer it.
      document.querySelectorAll('[data-search-open]').forEach((button) => {
        button.hidden = false;
        button.addEventListener('click', open);
      });
      dialog.addEventListener('click', (event) => { if (event.target === dialog) close(); });
      dialog.querySelector('form').addEventListener('submit', (event) => event.preventDefault());
      input.addEventListener('input', render);
      input.addEventListener('keydown', (event) => {
        if (event.key === 'ArrowDown') { event.preventDefault(); setActive(active + 1); }
        else if (event.key === 'ArrowUp') { event.preventDefault(); setActive(active - 1); }
        else if (event.key === 'Enter') {
          const link = active >= 0 && list.children[active] && list.children[active].querySelector('a');
          if (link) { event.preventDefault(); window.location.href = link.href; }
        }
      });
      list.addEventListener('mouseover', (event) => {
        const item = event.target.closest('li');
        if (item) setActive(Array.prototype.indexOf.call(list.children, item));
      });
      document.addEventListener('keydown', (event) => {
        const element = document.activeElement;
        const typing = element && (/^(input|textarea|select)$/i.test(element.tagName) || element.isContentEditable);
        if ((event.key === 'k' || event.key === 'K') && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          if (dialog.open) close(); else open();
        } else if (event.key === '/' && !typing && !event.metaKey && !event.ctrlKey && !event.altKey) {
          event.preventDefault();
          open();
        }
      });
    })();
    """#
}
