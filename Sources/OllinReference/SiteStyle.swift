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

    static let css = """
    /* Ollin · site */

    *, ::before, ::after { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; scroll-padding-top: 72px; }
    body, h1, h2, h3, h4, h5, h6, p, figure, blockquote, dl, dd, pre { margin: 0; }
    img, picture, video, canvas, svg { display: block; max-width: 100%; }
    picture img { height: auto; }
    @media (prefers-reduced-motion: reduce) {
      *, ::before, ::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; scroll-behavior: auto !important; }
    }

    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --surface: #f5f5f7;
      --surface-2: #ececef;
      --border: rgba(0, 0, 0, 0.09);
      --text: #1d1d1f;
      --text-2: #6e6e73;
      --muted: #a1a1a6;
      --accent: #8e44e6;
      --accent-ink: #ffffff;
      --tab: #1d1d1f;
      --tab-ink: #ffffff;
      --bar: rgba(255, 255, 255, 0.72);
      --code-bg: #f5f5f7;
      --tk-comment: #8a8a8e;
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
        --bg: #0e0d0d;
        --surface: #1c1a1a;
        --surface-2: #262323;
        --border: rgba(255, 255, 255, 0.08);
        --text: #f0eeee;
        --text-2: #8d8c8c;
        --muted: #5a5858;
        --accent: #bf5af2;
        --accent-ink: #0e0d0d;
        --tab: #f0eeee;
        --tab-ink: #0e0d0d;
        --bar: rgba(14, 13, 13, 0.72);
        --code-bg: #1c1a1a;
        --tk-comment: #7f7c7c;
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
    }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; text-underline-offset: 0.15em; }
    code, pre, kbd { font-family: var(--mono); font-size: 0.88em; }
    code { background: var(--surface); padding: 0.1em 0.35em; border-radius: 6px; }
    pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 14px; padding: 1.1rem 1.25rem; overflow-x: auto; line-height: 1.6; font-size: 13.5px; }
    pre code { background: none; padding: 0; font-size: inherit; }
    hr { border: 0; border-top: 1px solid var(--border); margin: 2.5rem 0; }
    sup { font-size: 0.75em; line-height: 0; }

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

    /* The layout */
    .layout { flex: 1; width: 100%; max-width: var(--max); margin: 0 auto; padding: 0 var(--pad); display: grid; gap: 3rem; grid-template-columns: minmax(0, 1fr); }
    .layout.with-sidebar { grid-template-columns: 240px minmax(0, 1fr); }
    .layout.with-rail { grid-template-columns: 240px minmax(0, 1fr) 200px; }
    main { min-width: 0; padding: 2.5rem 0 5rem; max-width: 760px; }
    .layout.single main, .layout.home main { max-width: none; }
    .layout.home main { padding-top: 0; }

    .sidebar, .rail { position: sticky; top: var(--bar-height); align-self: start; max-height: calc(100dvh - var(--bar-height)); overflow-y: auto; padding: 2.5rem 0 3rem; font-size: 13.5px; scrollbar-width: thin; }
    .sidebar ul, .rail ul { list-style: none; margin: 0; padding: 0; }
    .sidebar li a, .rail li a { display: block; padding: 0.3rem 0.6rem; margin: 0 -0.6rem; border-radius: 8px; color: var(--text-2); line-height: 1.35; }
    .sidebar li a:hover, .rail li a:hover { color: var(--text); background: var(--surface); text-decoration: none; }
    .sidebar li a[aria-current="page"] { color: var(--text); font-weight: 600; background: var(--surface); }
    .sidebar-title, .rail-title { font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); margin: 0 0 0.6rem; }
    .sidebar details { margin-top: 1rem; }
    .sidebar summary { cursor: pointer; font-weight: 600; color: var(--text); padding: 0.3rem 0; list-style: none; display: flex; align-items: center; gap: 0.4rem; }
    .sidebar summary::-webkit-details-marker { display: none; }
    .sidebar summary::before { content: ""; width: 6px; height: 6px; border-right: 1.5px solid var(--muted); border-bottom: 1.5px solid var(--muted); transform: rotate(-45deg); transition: transform 200ms var(--ease); margin-right: 0.1rem; }
    .sidebar details[open] > summary::before { transform: rotate(45deg); }
    .sidebar details ul { margin-top: 0.2rem; }
    .rail li.level-3 a { padding-left: 1.4rem; font-size: 12.5px; }

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
    .prose blockquote { border-left: 3px solid var(--border); padding: 0.25rem 0 0.25rem 1.1rem; color: var(--text-2); }
    .prose blockquote p:last-child { margin-bottom: 0; }
    .prose picture, .prose > img { margin-top: 1.5rem; margin-bottom: 1.5rem; }
    .prose picture img, .prose > img { border-radius: 14px; }
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
    .home-hello-circle { display: grid; grid-template-columns: minmax(0, 1.05fr) minmax(0, 0.95fr); gap: 1.5rem 3rem; align-items: start; }
    .home-hello-circle > h2 { grid-column: 1 / -1; margin-bottom: 0.25rem; }
    .home-hello-circle > pre { margin: 0; }
    .home-hello-circle > p { margin: 0; font-size: 18px; line-height: 1.5; }
    .home-pair { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 3rem; padding: 3.5rem 0; border-top: 1px solid var(--border); }
    .home-pair > .home-section { border-top: 0; padding: 0; min-width: 0; }
    .home-pair p:last-child, .home-pair pre:last-child { margin-bottom: 0; }
    /* The section is the grid, since the README's spaced bullets render as
       one list each; the lists dissolve into it and every item is a card. */
    .home-whats-in-it { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1.25rem; }
    .home-whats-in-it > h2, .home-whats-in-it > p { grid-column: 1 / -1; max-width: 820px; margin: 0; }
    .home-section.home-whats-in-it > h2:first-child { margin-bottom: 0.25rem; }
    .home-whats-in-it > p:last-child { margin-top: 0.5rem; }
    .home-whats-in-it > ul { display: contents; }
    .home-whats-in-it > ul > li { list-style: none; margin: 0; padding: 1.5rem 1.6rem; background: var(--surface); border-radius: 18px; font-size: 15px; line-height: 1.5; color: var(--text-2); }
    .home-whats-in-it > ul > li > strong:first-child { display: block; color: var(--text); font-size: 19px; line-height: 1.3; letter-spacing: -0.015em; margin-bottom: 0.5rem; }
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
    }
    @media (max-width: 860px) {
      .layout.with-sidebar, .layout.with-rail { grid-template-columns: minmax(0, 1fr); gap: 0; }
      /* The section's map goes under the page on a phone, where a reader
         wants the page first and the map after. */
      .sidebar { order: 2; position: static; max-height: none; padding: 1.5rem 0 2.5rem; border-top: 1px solid var(--border); }
      .sidebar details { margin-top: 0.5rem; }
      main { padding-top: 1.75rem; padding-bottom: 2.5rem; }
      .hero { grid-template-columns: minmax(0, 1fr); }
      .hero-canvas { max-width: 320px; order: -1; }
      .cards { grid-template-columns: minmax(0, 1fr); }
      .home-section { padding: 2.5rem 0; }
      .home-section > h2:first-child, .home-pair h2 { font-size: 28px; }
      .home-opening > p:first-child { font-size: 19px; }
      .home-opening > ul, .home-hello-circle, .home-pair, .home-whats-in-it { grid-template-columns: minmax(0, 1fr); }
      .home-pair { gap: 2.5rem; padding: 2.5rem 0; }
      .prose h1 { font-size: 32px; }
      .prose h2 { font-size: 24px; }
      .sections a { padding: 0 0.55rem; font-size: 13px; }
    }
    @media (max-width: 480px) {
      .wordmark .name { display: none; }
      .bar-inner { gap: 0.75rem; }
      .sections { gap: 0; }
      .sections a { padding: 0 0.5rem; font-size: 12.5px; }
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

    /// The magnifier, drawn in the page's ink, for the bar's button and the
    /// search box.
    static let searchIcon = """
    <svg class="icon" aria-hidden="true" focusable="false" viewBox="0 0 20 20"><circle cx="8.5" cy="8.5" r="5.75" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12.75 12.75 17 17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
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
      const marked = (text, terms) => {
        text = String(text);
        if (!terms.length) return escape(text);
        const alternatives = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|');
        const pattern = new RegExp('(^|[^\\p{L}\\p{N}])(' + alternatives + ')', 'giu');
        let out = '', last = 0;
        for (const match of text.matchAll(pattern)) {
          const start = match.index + match[1].length;
          out += escape(text.slice(last, start)) + '<mark>' + escape(match[2]) + '</mark>';
          last = start + match[2].length;
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
