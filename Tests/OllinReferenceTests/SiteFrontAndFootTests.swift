import Foundation
import OllinWebGate
import Testing
@testable import OllinReference

/// The front page's arrangement, the foot under every page, and what a block
/// of code can do: the parts of the site's chrome that are laid out or made
/// by a script, which the whole-site test can count and cannot see.
@Suite("The site's front page, foot, and code blocks")
struct SiteFrontAndFootTests {

    // MARK: - The boxes the front page is laid out by

    @Test("A section's parts each get a box that opens on the part's own heading, tag and all")
    func partsGetBoxes() {
        let section = """
        <h2 id="install">Install</h2>
        <p>Two ways.</p>
        <h3 id="one-way">One way</h3>
        <p>Do this.</p>
        <h3 id="another">Another</h3>
        <p>Or this.</p>

        """
        let parted = SiteHome.parted(section)
        // What comes before the first part stays outside the boxes.
        #expect(parted.hasPrefix("<h2 id=\"install\">Install</h2>\n<p>Two ways.</p>\n<div class=\"home-part\">"), "\(parted)")
        // Each box opens on its heading as the renderer wrote it: the space
        // ahead of the tag's first attribute is part of the tag.
        #expect(parted.contains("<div class=\"home-part\">\n<h3 id=\"one-way\">One way</h3>\n<p>Do this.</p>\n</div>\n"), "\(parted)")
        #expect(parted.contains("<div class=\"home-part\">\n<h3 id=\"another\">Another</h3>\n<p>Or this.</p>\n</div>\n"), "\(parted)")
        #expect(parted.components(separatedBy: "<div class=\"home-part\">").count - 1 == 2)
        #expect(parted.components(separatedBy: "</div>").count - 1 == 2)
        // Nothing is lost or written twice.
        #expect(parted.replacingOccurrences(of: "<div class=\"home-part\">\n", with: "").replacingOccurrences(of: "\n</div>", with: "")
                    == section.trimmingCharacters(in: .newlines) + "\n")
        // One part beside nothing is not a layout.
        let single = "<h2 id=\"a\">A</h2>\n<h3 id=\"b\">B</h3>\n<p>Only one.</p>"
        #expect(SiteHome.parted(single) == single)
        #expect(SiteHome.parted("<h2 id=\"a\">A</h2>\n<p>None.</p>") == "<h2 id=\"a\">A</h2>\n<p>None.</p>")
    }

    @Test("The opening's paragraphs and its facts get a box each, in the README's order")
    func openingGetsTwoBoxes() {
        let opening = "<p>What it is.</p>\n<p>Where it comes from.</p>\n<ul>\n<li><strong>Platform:</strong> a Mac</li>\n</ul>\n<blockquote><p>Where it stands.</p></blockquote>\n"
        let boxed = SiteHome.openingColumns(opening)
        #expect(boxed == """
        <div class="home-lede">
        <p>What it is.</p>
        <p>Where it comes from.</p>
        </div>
        <div class="home-facts">
        <ul>
        <li><strong>Platform:</strong> a Mac</li>
        </ul>
        <blockquote><p>Where it stands.</p></blockquote>
        </div>
        """, "\(boxed)")
        // An opening with no list, or with nothing ahead of its list, is
        // left as it came.
        #expect(SiteHome.openingColumns("<p>Only words.</p>") == "<p>Only words.</p>")
        #expect(SiteHome.openingColumns("<ul><li>Only facts.</li></ul>") == "<ul><li>Only facts.</li></ul>")
    }

    @Test("Each row of the front page says how it is laid out, and names one section")
    func rowsSayTheirLayout() {
        #expect(SiteHome.Row.section("A").layoutClass.isEmpty)
        #expect(SiteHome.Row.flowing("A").layoutClass == " home-flow")
        #expect(SiteHome.Row.split("A").layoutClass == " home-split")
        #expect(SiteHome.Row.carousel("A", running: "B/C").layoutClass.isEmpty)
        #expect(SiteHome.rows.allSatisfy { $0.headings.count == 1 })
        #expect(Set(SiteHome.shown).count == SiteHome.shown.count, "a section is shown twice")
    }

    // MARK: - The frame around a block of code

    @Test("Every block the renderer wrote is framed, and a block a page wrote by hand is left alone")
    func codeIsFramed() {
        let block = HTML.codeBlock("let x = 1", language: "swift")
        #expect(block.hasPrefix("<pre><code"), "the renderer's own markup for a block changed: \(block)")
        let body = "<p>Before.</p>\n\(block)\n<p>Between.</p>\n\(block)\n<p>After.</p>"
        let framed = SiteBuilder.framingCode(in: body)
        #expect(framed == "<p>Before.</p>\n<div class=\"code\">\(block)</div>\n<p>Between.</p>\n<div class=\"code\">\(block)</div>\n<p>After.</p>", "\(framed)")
        // A block written by hand, with attributes of its own, is not the
        // renderer's and gains no frame; one that never closes gains none.
        let byHand = "<pre class=\"plain\">as written</pre>"
        #expect(SiteBuilder.framingCode(in: byHand) == byHand)
        #expect(SiteBuilder.framingCode(in: "<pre>never closed") == "<pre>never closed")
        #expect(SiteBuilder.framingCode(in: "<p>No code.</p>") == "<p>No code.</p>")
    }

    // MARK: - A heading's own address

    @Test("Every heading with an address of its own ends on a link to itself, named for the heading, and a page's title does not")
    func headingsLinkToThemselves() {
        let body = """
        <h1 id="page">The page</h1>
        <p>Words with <h in them, and a rule:</p><hr>
        <h2 id="first">First <code>call(_:)</code> &amp; more</h2>
        <h3 id="second">A "quoted" one</h3>
        <h4 id="third">Third</h4>
        <h5 id="fifth">Too deep</h5>
        <h3>No address</h3>
        """
        let linked = SiteBuilder.linkingHeadings(in: body)
        let mark = SiteStyle.linkIcon + SiteStyle.copiedIcon
        #expect(linked.contains("<h2 id=\"first\">First <code>call(_:)</code> &amp; more<a class=\"anchor\" href=\"#first\" aria-label=\"Link to this section: First call(_:) &amp; more\">\(mark)</a></h2>"), "\(linked)")
        // A quote in a heading cannot close the attribute that names it.
        #expect(linked.contains("<a class=\"anchor\" href=\"#second\" aria-label=\"Link to this section: A &quot;quoted&quot; one\">"), "\(linked)")
        #expect(linked.contains("<a class=\"anchor\" href=\"#third\""))
        #expect(linked.components(separatedBy: "class=\"anchor\"").count - 1 == 3, "the title, a fifth-level heading, or one with no address gained a link: \(linked)")
        #expect(linked.contains("<h1 id=\"page\">The page</h1>") && linked.contains("<h5 id=\"fifth\">Too deep</h5>") && linked.contains("<h3>No address</h3>"))
        // Nothing else moved, and a second pass adds nothing.
        #expect(linked.replacingOccurrences(of: mark, with: "").components(separatedBy: "<a class=\"anchor\"").count == 4)
        #expect(SiteBuilder.linkingHeadings(in: linked) == linked)
        #expect(SiteBuilder.linkingHeadings(in: "<p>No headings.</p>") == "<p>No headings.</p>")
        // The mark has no words, so the heading still reads as it is written.
        #expect(SiteBuilder.plainText(of: Substring(mark)).isEmpty)
    }

    // MARK: - A chapter's opening picture

    @Test("The picture a chapter opens on stands in the frame a chapter's clip does, and a picture further down keeps its own width")
    func chapterOpensInAFrame() {
        let picture = "<img src=\"images/a.jpg\" alt=\"A > B\" width=\"560\">"
        let opens = "<h1 id=\"t\">Title</h1>\n\(picture)\n<p>Words.</p>\n\(picture)"
        let framed = SiteBuilder.framingOpeningPicture(in: opens)
        #expect(framed == "<h1 id=\"t\">Title</h1>\n<figure class=\"page-hero\">\n\(picture)\n</figure>\n<p>Words.</p>\n\(picture)", "\(framed)")
        // A chapter that opens on words, on a clip, or on a picture in two
        // schemes is left as it is, and so is a page with no title.
        for body in ["<h1 id=\"t\">Title</h1>\n<p>Words first.</p>\n\(picture)",
                     "<h1 id=\"t\">Title</h1>\n<figure class=\"page-hero\">\n<video></video>\n</figure>\n\(picture)",
                     "<h1 id=\"t\">Title</h1>\n<picture>\n\(picture)\n</picture>",
                     "<p>No title.</p>\n\(picture)",
                     "<h1 id=\"t\">Title</h1>"] {
            #expect(SiteBuilder.framingOpeningPicture(in: body) == body, "\(body)")
        }
    }

    // MARK: - The foot

    @Test("Every project page the plan knows has one row in the foot, and the foot names no page the plan does not")
    func footHoldsEveryProjectPage() {
        let rows = SiteBuilder.footGroups.flatMap(\.pages)
        #expect(Set(rows).count == rows.count, "a page has two rows in the foot")
        let named = Set(rows).subtracting(["README.md"])
        #expect(named == Set(SiteBuilder.aboutPages),
                "the foot is missing \(Set(SiteBuilder.aboutPages).subtracting(named).sorted()), or names \(named.subtracting(SiteBuilder.aboutPages).sorted()), which the plan does not hold")
        #expect(rows.contains("README.md"), "the foot has no row for the About page")
        // Each row goes by a short name, never a file's own long title.
        for file in SiteBuilder.aboutPages {
            #expect(SiteBuilder.aboutLabels[file] != nil, "\(file) has no short name for its row")
        }
        #expect(SiteBuilder.footGroups.allSatisfy { !$0.title.isEmpty && !$0.pages.isEmpty })
    }

    @Test("The release the foot names is the changelog's newest numbered section, with that section's anchor")
    func footReadsTheNewestRelease() throws {
        let changelog = """
        # Changelog

        ## [Unreleased]

        ### Added

        - Something not out yet.

        ```
        ## [9.9.9] - a heading inside code is code
        ```

        ## [0.18.0] - 2026-11-14

        - The newest release.

        ## [0.17.0] - 2026-10-25
        """
        let release = try #require(SiteBuilder.latestRelease(inChangelog: changelog))
        #expect(release.version == "0.18.0")
        // The anchor is the one the page gives that heading.
        let page = HTML.render(changelog, asPage: true) { target, _ in target }
        let heading = try #require(page.headings.first { $0.text.contains("0.18.0") })
        #expect(release.anchor == heading.anchor, "the foot links #\(release.anchor), and the page has #\(heading.anchor)")
        #expect(SiteBuilder.latestRelease(inChangelog: "# Changelog\n\n## [Unreleased]\n") == nil)
        #expect(SiteBuilder.latestRelease(inChangelog: "") == nil)
    }

    @Test("The bar's mark is named at the end of its own tag, and the foot draws it by that name")
    func markIsDrawnOnceAndNamed() {
        let mark = "<svg class=\"mark\" aria-hidden=\"true\" focusable=\"false\" viewBox=\"0 0 100 100\" fill=\"currentColor\">\n<path d=\"M0 0h1\"/>\n</svg>"
        let named = SiteBuilder.named(mark)
        #expect(named == "<svg class=\"mark\" aria-hidden=\"true\" focusable=\"false\" viewBox=\"0 0 100 100\" fill=\"currentColor\" id=\"\(SiteBuilder.markName)\">\n<path d=\"M0 0h1\"/>\n</svg>")
        #expect(SiteBuilder.markAgain.contains("<use href=\"#\(SiteBuilder.markName)\"/>") && !SiteBuilder.markAgain.contains("<path"))
        #expect(SiteBuilder.named("").isEmpty)
    }

    // MARK: - What a link unfurls as

    @Test("A wide picture is shown large and a square one small and whole")
    func cardShapes() {
        #expect(SiteBuilder.ShareCard(address: "a", width: 1200, height: 630, alt: "").isWide)
        #expect(SiteBuilder.ShareCard(address: "a", width: 1600, height: 800, alt: "").isWide)
        #expect(SiteBuilder.ShareCard(address: "a", width: 1080, height: 720, alt: "").isWide)
        #expect(!SiteBuilder.ShareCard(address: "a", width: 1080, height: 1080, alt: "").isWide)
        #expect(!SiteBuilder.ShareCard(address: "a", width: 1080, height: 1350, alt: "").isWide)
    }

    // MARK: - A block of code in a browser

    /// The site's stylesheet and the script every page loads, over three
    /// blocks of code as the site frames them (one too long for its column,
    /// one that fits, one more to touch), with a clipboard that writes down
    /// what it is handed. The probe reports in steps, since copying answers
    /// a moment later and takes its mark back a moment after that.
    static func codeProbe() -> String {
        let long = "let aLine = \"of code that is far too long to fit the column it is set in and has to scroll inside its own box, further than one screen\""
        let framed = SiteBuilder.framingCode(in: [
            HTML.codeBlock(long + "\nlet second = 2\n", language: "swift"),
            HTML.codeBlock("let x = 1", language: "swift"),
            HTML.codeBlock("swift run", language: "sh"),
        ].joined(separator: "\n"))
        // Nothing here eases in: a page read by a browser that draws no
        // frames would be read at the start of every transition.
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>\(SiteStyle.css)</style>
        <style>*, ::before, ::after { transition: none !important; }</style></head><body>
        <div id="column" style="width: 420px; flex: none;"><article class="prose">
        \(SiteBuilder.linkingHeadings(in: "<h2 id=\"sec\">A heading whose words fill its line to the very</h2>"))
        \(SiteBuilder.linkingHeadings(in: "<h3 id=\"full\"><span style=\"display: inline-block; width: 100%; height: 1em;\"></span></h3>"))
        <h2 id="bare">A heading whose words fill its line to the very</h2>
        \(framed)
        </article></div>
        <script>
        window.handed = [];
        Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: function (text) { window.handed.push(text); return Promise.resolve(); } } });
        </script>
        <script>
        \(SiteStyle.pageScript)
        </script>
        <pre id="r0">PENDING</pre>
        <script>
        (function () {
          var out = document.getElementById('r0');
          var frames = Array.prototype.slice.call(document.querySelectorAll('.code'));
          var lines = [];
          var flags = function (frame) { return (frame.classList.contains('more-before') ? 1 : 0) + '' + (frame.classList.contains('more-after') ? 1 : 0); };
          var later = function (ms) { return new Promise(function (done) { setTimeout(done, ms); }); };
          var long = frames[0], block = long.querySelector('pre'), button = long.querySelector('.copy');
          lines.push('frames ' + frames.length + ' ' + document.querySelectorAll('.code > .copy').length + ' ' + document.querySelectorAll('.spoken[aria-live=polite]').length);
          lines.push('long ' + flags(long) + ' ' + block.tabIndex + ' ' + (block.scrollWidth > block.clientWidth ? 1 : 0));
          lines.push('short ' + flags(frames[1]) + ' ' + frames[1].querySelector('pre').tabIndex);
          // The fade is the frame's, so it stays put: laid over the frame's
          // right edge, out of the pointer's way, shown only where a line
          // runs on.
          var fadeLine = function () {
            var fade = getComputedStyle(long, '::after'), none = getComputedStyle(frames[1], '::after');
            return 'fade ' + fade.position + ' ' + fade.pointerEvents + ' ' + fade.opacity + ' ' + none.opacity + ' ' + getComputedStyle(long).position;
          };
          lines.push('button ' + button.getAttribute('aria-label') + ' ' + button.type + ' ' + getComputedStyle(button).position + ' ' + (button.parentElement === long ? 1 : 0)
            + ' ' + button.querySelectorAll('svg[aria-hidden=true]').length);
          // Scrolled to its end, the block fades at the edge it has left.
          block.scrollLeft = block.scrollWidth;
          block.dispatchEvent(new Event('scroll'));
          lines.push('end ' + flags(long));
          block.scrollLeft = 40;
          block.dispatchEvent(new Event('scroll'));
          lines.push('middle ' + flags(long));
          // A touch on a block shows that block's button and no other's.
          var touch = function (frame) { frame.querySelector('pre').dispatchEvent(new PointerEvent('pointerdown', { pointerType: 'touch', bubbles: true })); };
          var touched = function () { return frames.map(function (frame) { return frame.classList.contains('touched') ? 1 : 0; }).join(''); };
          touch(frames[1]); var first = touched();
          touch(frames[2]); var second = touched();
          document.body.dispatchEvent(new PointerEvent('pointerdown', { pointerType: 'touch', bubbles: true }));
          var third = touched();
          frames[0].querySelector('pre').dispatchEvent(new PointerEvent('pointerdown', { pointerType: 'mouse', bubbles: true }));
          lines.push('touch ' + first + ' ' + second + ' ' + third + ' ' + touched());
          // A heading's link takes no room in the line: the heading is as
          // tall as its twin with no link. Pressed, it hands over the
          // section's whole address.
          var heading = document.getElementById('sec'), link = heading.querySelector('a.anchor');
          lines.push('heading ' + (heading.getBoundingClientRect().height === document.getElementById('bare').getBoundingClientRect().height ? 1 : 0)
            + ' ' + (heading.getBoundingClientRect().height > 40 ? 1 : 0) + ' ' + link.getAttribute('href') + ' ' + link.querySelectorAll('svg[aria-hidden=true]').length);
          // The mark hangs inside its heading wherever the words end, here
          // at the very end of the line: a heading is no wider inside than
          // its own box, and neither is the column that holds it.
          var words = document.getElementById('full'), hung = words.querySelector('a.anchor');
          lines.push('hangs ' + (words.scrollWidth <= words.clientWidth ? 1 : 0) + ' ' + (hung.getBoundingClientRect().right <= words.getBoundingClientRect().right + 0.5 ? 1 : 0)
            + ' ' + (hung.getBoundingClientRect().width > 8 ? 1 : 0) + ' ' + (document.getElementById('column').scrollWidth <= 420 ? 1 : 0));
          link.addEventListener('click', function (event) { event.preventDefault(); });
          link.click();
          later(100).then(function () {
            lines.push('linked ' + (link.classList.contains('copied') ? 1 : 0) + ' ' + (window.handed.length === 1 && window.handed[0] === link.href && /#sec$/.test(window.handed[0]) && window.handed[0].indexOf('://') > 0 ? 1 : 0)
              + ' ' + document.querySelector('.spoken').textContent.replace(' ', '-'));
            window.handed = [];
            return later(3000);
          }).then(function () {
          lines.push('unlinked ' + (link.classList.contains('copied') ? 1 : 0));
          button.click();
          return later(600);
          }).then(function () {
            lines.push(fadeLine());
            var said = document.querySelector('.spoken');
            lines.push('copied ' + (long.classList.contains('copied') ? 1 : 0) + ' ' + button.getAttribute('aria-label') + ' ' + said.textContent
              + ' ' + getComputedStyle(button.querySelector('.icon-copy')).display + ' ' + getComputedStyle(button.querySelector('.icon-done')).display);
            lines.push('text ' + (window.handed.length === 1 && window.handed[0] === block.textContent.replace(/\\n$/, '') && !/\\n$/.test(window.handed[0]) && window.handed[0].split('\\n').length === 2 ? 1 : 0));
            return later(3000);
          }).then(function () {
            var said = document.querySelector('.spoken');
            lines.push('after ' + (long.classList.contains('copied') ? 1 : 0) + ' ' + button.getAttribute('aria-label') + ' [' + said.textContent + ']');
            out.textContent = lines.join('|');
          });
        })();
        </script>
        </body></html>
        """
    }

    @Test("A block of code that runs past its column fades at that edge, and its button copies it as written and says so",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func aBlockCopiesAndFades() async throws {
        // Virtual time, so the moment the button takes its mark back is
        // reached before the page is read.
        let flags = HeadlessBrowser.baseFlags + ["--virtual-time-budget=10000", "--window-size=1280,900"]
        let dom = try await HeadlessBrowser.dom(of: Self.codeProbe(), flags: flags, timeout: 90)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(report != "PENDING", "the probe did not finish")
        var read: [String: [String]] = [:]
        for line in report.split(separator: "|") {
            let parts = line.split(separator: " ").map(String.init)
            read[parts[0]] = Array(parts.dropFirst())
        }
        // Every frame gains one button; the place that says what happened
        // is made when there is first something to say.
        #expect(read["frames"] == ["3", "3", "0"], "\(report)")
        // A heading's link: no taller a heading for it, two lines of words
        // in this column, the heading's own anchor, and two drawings (the
        // links of a chain, and the check that stands in once pressed).
        #expect(read["heading"] == ["1", "1", "#sec", "2"], "\(report)")
        // A heading whose words run to the very end of their line still
        // holds its mark inside itself, so the page never scrolls sideways
        // for a mark nobody can see.
        #expect(read["hangs"] == ["1", "1", "1", "1"], "a heading's mark hangs out past its heading: \(report)")
        #expect(read["linked"] == ["1", "1", "Link-copied"], "pressing a heading's link did not hand over its address, or did not say so: \(report)")
        #expect(read["unlinked"] == ["0"], "\(report)")
        // The long block scrolls, can be reached from the keyboard, and
        // fades on the right, where its line runs on, and not on the left,
        // where it starts. The short one does neither.
        #expect(read["long"] == ["01", "0", "1"], "\(report)")
        #expect(read["short"] == ["00", "-1"], "\(report)")
        // (Read with the block scrolled to its middle, where both edges fade.)
        #expect(read["fade"] == ["absolute", "none", "1", "0", "relative"], "the fade is not laid over the frame, or shows where nothing runs on: \(report)")
        #expect(read["button"] == ["Copy", "button", "absolute", "1", "2"], "\(report)")
        // At its end it fades on the left alone; in between, on both.
        #expect(read["end"] == ["10"], "\(report)")
        #expect(read["middle"] == ["11"], "\(report)")
        // One block at a time shows its button to a touch, a touch
        // elsewhere takes it away, and a mouse sets nothing.
        #expect(read["touch"] == ["010", "001", "000", "000"], "\(report)")
        // Copied: the frame says so, the button's name and the spoken line
        // change, the check stands in for the sheets, and the clipboard
        // holds the block as written with no line added at its end.
        #expect(read["copied"] == ["1", "Copied", "Copied", "none", "block"], "\(report)")
        #expect(read["text"] == ["1"], "the clipboard was not handed the block as written: \(report)")
        // And a moment later everything is as it was.
        #expect(read["after"] == ["0", "Copy", "[]"], "\(report)")
    }

    // MARK: - The front page's columns in a browser

    /// The stylesheet over the front page's own boxes, with enough words in
    /// each to fill it: the bar's name, the hero, the opening's two boxes, a
    /// section that flows, a section in two parts, and the foot.
    ///
    /// The page is shown inside a frame of the width asked for, and reports
    /// to the page around it. A frame is as wide as it is told to be, which
    /// a browser's own window is not (it will not go as narrow as a phone),
    /// and the stylesheet's rules for a width are decided by the frame's.
    static func frontProbe(width: Int) -> String {
        let words = String(repeating: "Ollin is for generative art, live visuals, and installations. ", count: 5)
        let paragraph = "<p>\(words)</p>"
        let inner = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>\(SiteStyle.css)</style></head><body>
        <header class="bar"><div class="bar-inner"><a class="wordmark" href="#"><span class="name" id="bar-name">Ollin</span></a></div></header>
        <div class="layout home"><main>
        <section class="hero"><div class="hero-text" id="words"><p class="eyebrow">Ollin</p><h1>A framework.</h1></div>
        <div class="hero-canvas" id="ring"><canvas width="460" height="460"></canvas></div></section>
        <article class="prose home">
        <section class="home-section home-opening">
        <div class="home-lede" id="lede">\(paragraph)\(paragraph)</div>
        <div class="home-facts" id="facts"><ul><li id="fact"><strong>Platform:</strong> \(words)</li><li><strong>License:</strong> MIT</li></ul><blockquote><p>\(words)</p></blockquote></div>
        </section>
        <section class="home-section home-run-it home-flow" id="flow"><h2 id="flow-title">Run it</h2><p id="f1">\(words)</p><p>\(words)</p><p>\(words)</p><p id="f4">\(words)</p></section>
        <section class="home-section home-install home-split" id="split"><h2 id="split-title">Install</h2>
        <div class="home-part" id="p1"><h3>One way</h3>\(paragraph)</div>
        <div class="home-part" id="p2"><h3>Another</h3>\(paragraph)</div></section>
        </article></main></div>
        <footer class="foot"><div class="foot-inner"><div class="foot-lead" id="lead"><a class="wordmark" href="#"><span class="name" id="foot-name">Ollin</span></a><p class="foot-line">A framework.</p></div>
        <nav class="foot-nav" id="nav"><div class="foot-group" id="g1"><p class="foot-title">Learn</p><ul><li><a href="#">Guide</a></li></ul></div>
        <div class="foot-group" id="g2"><p class="foot-title">Project</p><ul><li><a href="#">About</a></li></ul></div>
        <div class="foot-group" id="g3"><p class="foot-title">How it is built</p><ul><li><a href="#">Architecture</a></li></ul></div></nav>
        <p class="foot-note" id="note">Ollin is MIT licensed.</p></div></footer>
        <script>
        (function () {
          var box = function (id) { return document.getElementById(id).getBoundingClientRect(); };
          var r = function (n) { return Math.round(n); };
          var lines = ['width ' + innerWidth];
          // 1 when the second starts where the first ends, level with it;
          // 0 when it is under it; 2 when it is to its right and they
          // share some height, as two things centered on one row do.
          var beside = function (a, b) {
            var first = box(a), second = box(b);
            if (second.left >= first.right - 1 && Math.abs(second.top - first.top) < 2) return 1;
            if (second.top >= first.bottom - 1) return 0;
            if (second.left >= first.right - 1 && second.top < first.bottom && second.bottom > first.top) return 2;
            return -1;
          };
          lines.push('opening ' + beside('lede', 'facts') + ' ' + r(box('lede').width) + ' ' + r(box('facts').width));
          var label = document.querySelector('#fact strong').getBoundingClientRect(), fact = box('fact');
          lines.push('fact ' + getComputedStyle(document.querySelector('#fact strong')).position + ' ' + (label.left - fact.left < 2 ? 1 : 0) + ' ' + getComputedStyle(document.getElementById('fact')).borderTopStyle);
          lines.push('flow ' + (box('f4').left > box('f1').right ? 1 : 0) + ' ' + (r(box('flow-title').width) >= r(box('flow').width) - 1 ? 1 : 0));
          // What separates one block of a flowing section from the next:
          // its margin, or its own padding.
          var first = getComputedStyle(document.getElementById('f1'));
          lines.push('gap ' + (parseFloat(first.marginBottom) > 0 ? 1 : 0) + ' ' + (parseFloat(first.paddingBottom) > 0 ? 1 : 0) + ' ' + (r(box('f4').top) === r(box('f1').top) ? 1 : 0)
            + ' ' + parseFloat(getComputedStyle(document.getElementById('f4')).paddingBottom));
          lines.push('split ' + beside('p1', 'p2') + ' ' + (r(box('split-title').width) >= r(box('split').width) - 1 ? 1 : 0) + ' ' + (r(box('p1').width) === r(box('p2').width) ? 1 : 0));
          lines.push('hero ' + beside('words', 'ring'));
          lines.push('foot ' + beside('lead', 'nav') + ' ' + beside('g1', 'g2') + ' ' + beside('g2', 'g3') + ' ' + (box('note').top >= box('nav').bottom ? 1 : 0));
          lines.push('names ' + getComputedStyle(document.getElementById('bar-name')).display + ' ' + getComputedStyle(document.getElementById('foot-name')).display);
          // What the page needs across, beside what it has: a window that
          // shows its scroll bar has that bar's width less than the frame.
          lines.push('wide ' + document.documentElement.scrollWidth + ' ' + document.documentElement.clientWidth);
          parent.document.getElementById('r0').textContent = lines.join('|');
        })();
        </script></body></html>
        """
        return """
        <!doctype html><html><head><meta charset="utf-8"></head><body style="margin: 0">
        <div id="r0">PENDING</div>
        <iframe style="border: 0; width: \(width)px; height: 1000px;" srcdoc="\(HTML.escape(inner))"></iframe>
        </body></html>
        """
    }

    /// The probe's report in a frame `width` wide. `scrollBarShown` asks for
    /// a scroll bar that takes room beside the page, as on a Mac with a mouse
    /// and no trackpad, in place of one drawn over it.
    static func frontReport(width: Int, scrollBarShown: Bool = false) async throws -> (read: [String: [String]], text: String) {
        let flags = HeadlessBrowser.baseFlags + ["--window-size=1280,1000"]
            + (scrollBarShown ? ["--disable-features=OverlayScrollbar"] : [])
        let dom = try await HeadlessBrowser.dom(of: Self.frontProbe(width: width), flags: flags, timeout: 90)
        let report = try #require(HeadlessBrowser.text(of: "r0", in: dom))
        try #require(report != "PENDING", "the probe did not run")
        var read: [String: [String]] = [:]
        for line in report.split(separator: "|") {
            let parts = line.split(separator: " ").map(String.init)
            read[parts[0]] = Array(parts.dropFirst())
        }
        try #require(read["width"] == ["\(width)"], "the frame is not \(width) wide: \(report)")
        return (read, report)
    }

    @Test("On a wide page the facts stand beside the opening, a section flows in two columns, its parts stand side by side, and the foot is a row",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func theFrontPageOnAWideScreen() async throws {
        let (read, report) = try await Self.frontReport(width: 1440)
        let opening = try #require(read["opening"], "\(report)")
        #expect(opening.first == "1", "the facts are not beside the paragraphs: \(report)")
        // Neither column is a sliver: the facts take at least a third and
        // the paragraphs the larger share.
        let lede = Int(opening[1]) ?? 0, facts = Int(opening[2]) ?? 0
        #expect(lede > facts && facts * 3 >= lede + facts, "the opening's columns are \(lede) and \(facts) wide: \(report)")
        // A fact's name hangs to the left of what it says, under a rule.
        #expect(read["fact"] == ["absolute", "1", "solid"], "\(report)")
        // The flowing section's last paragraph is in a second column, and
        // its heading runs across both.
        #expect(read["flow"] == ["1", "1"], "\(report)")
        // In columns, the space under a block is its own padding and no
        // margin: one browser carries a margin over a column's end, and the
        // second column would start lower than the first. The last block
        // ends the section flush.
        #expect(read["gap"]?.prefix(2) == ["0", "1"] && read["gap"]?.last == "0", "a block of a flowing section is spaced by a margin: \(report)")
        // The two parts stand side by side, equal, under a heading that
        // runs across both.
        #expect(read["split"] == ["1", "1", "1"], "\(report)")
        // The words beside the ring, centered on one row.
        #expect(read["hero"] == ["2"] || read["hero"] == ["1"], "\(report)")
        // The foot: its columns beside its lead and beside each other, and
        // the closing sentence under them.
        #expect(read["foot"] == ["1", "1", "1", "1"], "\(report)")
        #expect(read["names"] == ["block", "block"], "a name beside the mark is hidden on a wide page: \(report)")
        #expect(read["wide"]?.first == read["wide"]?.last && read["wide"]?.count == 2, "the page is wider than its window: \(report)")
    }

    @Test("At a thousand pixels the facts go under the opening as a sheet, while a section still flows and splits",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func theFrontPageOnAMiddlingScreen() async throws {
        let (read, report) = try await Self.frontReport(width: 1000)
        #expect(read["opening"]?.first == "0", "the facts are beside the paragraphs at a thousand pixels: \(report)")
        #expect(read["fact"] == ["absolute", "1", "solid"], "\(report)")
        #expect(read["flow"] == ["1", "1"], "\(report)")
        #expect(read["split"] == ["1", "1", "1"], "\(report)")
        #expect(read["hero"] == ["2"] || read["hero"] == ["1"], "\(report)")
        #expect(read["wide"]?.first == read["wide"]?.last && read["wide"]?.count == 2, "the page is wider than its window: \(report)")
    }

    @Test("On a phone everything stacks, the words come before the ring, and a fact's name goes over what it says",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled })
    func theFrontPageOnAPhone() async throws {
        let (read, report) = try await Self.frontReport(width: 390)
        #expect(read["opening"]?.first == "0", "\(report)")
        #expect(read["fact"] == ["static", "1", "solid"], "a fact's name still hangs beside it on a phone: \(report)")
        #expect(read["flow"] == ["0", "1"], "a section still runs in two columns on a phone: \(report)")
        // In one column a margin meets no column's end, and stays a margin.
        #expect(read["gap"]?.prefix(2) == ["1", "0"], "\(report)")
        #expect(read["split"]?.first == "0", "a section's parts are still side by side on a phone: \(report)")
        // The words end before the ring begins.
        #expect(read["hero"] == ["0"], "the ring comes before the words: \(report)")
        // The foot's lead over its columns, the columns two across, the
        // closing sentence last.
        #expect(read["foot"] == ["0", "1", "0", "1"], "\(report)")
        // A phone's bar has no room for the name beside the mark; the foot
        // has, and keeps it.
        #expect(read["names"] == ["none", "block"], "\(report)")
        #expect(read["wide"]?.first == read["wide"]?.last && read["wide"]?.count == 2, "the page is wider than a phone: \(report)")
    }

    @Test("A window that shows its scroll bar beside the page leaves the page inside what is left",
          .enabled("a browser is needed") { HeadlessBrowser.isInstalled }, arguments: [1440, 1000, 390])
    func theFrontPageBesideAScrollBar(width: Int) async throws {
        let (read, report) = try await Self.frontReport(width: width, scrollBarShown: true)
        let wide = try #require(read["wide"], "\(report)")
        try #require(wide.count == 2, "\(report)")
        // The bar took its room, or this run proved nothing a plain one did not.
        #expect((Int(wide[1]) ?? width) < width, "the window showed no scroll bar beside the page: \(report)")
        #expect(wide[0] == wide[1], "the page is wider than the room beside the scroll bar: \(report)")
    }
}
