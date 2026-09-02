import Foundation

/// The site's own look: one stylesheet, one small script, one icon.
///
/// Kept as text inside the target rather than as resources so the command
/// stays one binary with nothing to find at run time. The design is system
/// type, hairline rules, and generous space, in a light scheme and a dark one
/// that follow the reader's own setting, so the figures' dark variants and the
/// chrome switch together.
enum SiteStyle {

    /// The placeholder mark until the logo lands: a plain circle.
    static let favicon = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="26" fill="none" stroke="#1d1d1f" stroke-width="7"/><style>@media (prefers-color-scheme: dark) { circle { stroke: #f0eeee; } }</style></svg>
    """

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
    .mark { width: 16px; height: 16px; border-radius: 50%; border: 2.5px solid currentColor; }
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
    .hero-canvas { width: 100%; aspect-ratio: 1; max-height: 460px; color: var(--text); }
    .cards { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1.25rem; margin-bottom: 3rem; }
    .card { display: block; padding: 1.5rem; background: var(--surface); border-radius: 18px; color: var(--text); transition: transform 400ms var(--ease), background 150ms; }
    .card:hover { text-decoration: none; transform: translateY(-2px); background: var(--surface-2); }
    .card h2 { font-size: 21px; font-weight: 600; letter-spacing: -0.015em; margin: 0 0 0.4rem; }
    .card p { color: var(--text-2); font-size: 15px; margin: 0; }
    .prose.home { max-width: 760px; }

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
      .hero-canvas { max-height: 320px; order: -1; }
      .cards { grid-template-columns: minmax(0, 1fr); }
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
    """

    /// The front page's canvas: a ring of drifting, breathing circles, the
    /// first thing the Guide draws, so the site opens on motion the way a
    /// sketch does. It stands still for a reader who asked for less motion.
    static let script = """
    (() => {
      const canvas = document.querySelector('.hero-canvas');
      if (!canvas) return;
      const context = canvas.getContext('2d');
      const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
      const count = 28;
      let width = 0, height = 0;

      function size() {
        const scale = devicePixelRatio || 1;
        width = canvas.clientWidth;
        height = canvas.clientHeight;
        canvas.width = Math.round(width * scale);
        canvas.height = Math.round(height * scale);
        context.setTransform(scale, 0, 0, scale, 0, 0);
      }

      function frame(now) {
        const time = now / 1000;
        context.clearRect(0, 0, width, height);
        context.strokeStyle = getComputedStyle(canvas).color;
        context.lineWidth = 1.25;
        const cx = width / 2, cy = height / 2;
        const ring = Math.min(width, height) * 0.3;
        for (let i = 0; i < count; i++) {
          const angle = (i / count) * Math.PI * 2 + time * 0.06;
          const drift = Math.sin(time * 0.7 + i * 1.31) * ring * 0.08;
          const x = cx + Math.cos(angle) * (ring + drift);
          const y = cy + Math.sin(angle) * (ring + drift);
          const radius = ring * 0.19 + Math.sin(time * 1.1 + i * 0.83) * ring * 0.07;
          context.globalAlpha = 0.28 + 0.22 * Math.sin(time * 0.9 + i * 0.5);
          context.beginPath();
          context.arc(x, y, Math.max(1, radius), 0, Math.PI * 2);
          context.stroke();
        }
        context.globalAlpha = 1;
        if (!still) requestAnimationFrame(frame);
      }

      size();
      addEventListener('resize', () => { size(); if (still) frame(0); });
      requestAnimationFrame(frame);
    })();
    """
}
