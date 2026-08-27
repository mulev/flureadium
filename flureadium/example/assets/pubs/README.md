
# Test publications

These test publications should be in the public domain or otherwise free of copyright.
Some ones prefixed with a number are self-produced by Nota.

## Publications

| File                      | Media-type        | Contents                    |
| ------------------------- | ----------------- | --------------------------- |
| moby_dick.epub            | epub              | Ebook                       |
| 712199_ebook.epub         | epub              | Ebook                       |
| 712199_ebook.webpub       | webpub/ebook      | Ebook                       |
| 41654_overlay.epub        | epub              | Ebook /w MediaOverlays      |
| 38533_overlay.webpub      | webpub/ebook      | Ebook /w MediaOverlays      |
| 38533.audiobook           | webpub/audiobook  | Readium Audiobook           |
| flatland_remote.audiobook | webpub/audiobook  | Readium Audiobook (remote)  |
| sample_comic.cbz          | cbz               | Minimal image-based comic   |
| sample_visual.divina      | divina            | Minimal visual narrative    |
| tap_targets.epub          | epub              | Full-viewport link, then plain page |
| fixed_layout.epub         | epub              | Single pre-paginated page   |
| hierarchical_toc.epub     | epub              | Nested nav document         |
| frontmatter_toc.epub      | epub              | Six front-matter entries on one page |
| backlink_chapter.epub     | epub              | Chapters opening with a back-to-contents link |

Both are self-produced minimal fixtures for the tap chain, but they are consumed
differently.

`tap_targets.epub` drives `integration_test/tap_test.dart`. It has two spine items:
`page1.xhtml` is one anchor filling the viewport, `page2.xhtml` is plain text — tapping
page 1 must follow the link and must not report a tap, and tapping page 2 must report
one. Without that second half a link assertion passes just as well when no tap ever
reached native.

`fixed_layout.epub` is `rendition:layout` `pre-paginated`, which Readium serves through
a different script path than reflowable content. It is **not** used by an automated
test: a synthesized tap reaches the native view and that script path never reports it,
so it is exercised by hand through the app's **Open Fixed Layout** button as part of the
`user | tap` row in `validators.conf`. See "What a synthesized tap can reach" in
`docs/05-testing/integration-tests.md`.

`frontmatter_toc.epub` drives the `navigation (frontmatter_toc)` group in
`integration_test/epub_navigation_test.dart`. Its nav document anchors six front-matter
entries — a title, a byline, an imprint line — inside one short document that
renders as a single page, with the chapters at the same nesting depth in later
documents. A cover resource sits ahead of it and carries no TOC entry, so the
first skip resolves from "no current entry" exactly as the reported book did.
Without the visibility walk in `TocSkipNavigationMixin`, the second skip targets
an entry on the page already shown and the reader does not move.

`backlink_chapter.epub` drives the `navigation (backlink_chapter)` groups in
`integration_test/epub_navigation_test.dart`. It copies the shape ebookmaker
produces: each chapter is its own resource and opens with a back-to-contents
link, so the reader lands above the chapter's own heading rather than on it, and
the heading id the nav document points at sits on the `div` wrapping the `h2`
instead of on the `h2` itself. A cover resource with no TOC entry sits ahead of
the chapters, so the first skip resolves from "no current entry". A heading
search that only looks backwards finds nothing in a document like this and falls
through to the body, which carries no id — every chapter then reports a `toc=`
fragment with no value, and no TOC entry can ever match it.
