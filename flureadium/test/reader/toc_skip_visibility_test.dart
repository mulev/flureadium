import 'package:flureadium/src/reader/toc_skip_navigation_mixin.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_reader_channel.dart';

// Test class that uses the mixin.
class TestTocSkipNavigator with TocSkipNavigationMixin {}

/// A publication in the reported book's shape: one front-matter resource
/// carrying six entries at the same nesting depth as the chapters, which live
/// in later resources.
Publication _frontmatterPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Front-matter Book'),
    identifier: 'frontmatter-book',
  ),
  readingOrder: [
    Link(href: '/front.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ch1.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ch2.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    for (var i = 0; i < 6; i++)
      Link(href: '/front.xhtml#a$i', type: 'application/xhtml+xml'),
    Link(href: '/ch1.xhtml#c1', type: 'application/xhtml+xml'),
    Link(href: '/ch2.xhtml#c2', type: 'application/xhtml+xml'),
  ],
);

/// A PDF outline: every entry shares one href and differs only by page.
Publication _pdfPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('PDF Book'),
    identifier: 'pdf-book',
  ),
  readingOrder: [Link(href: '/doc.pdf', type: 'application/pdf')],
  tableOfContents: [
    Link(href: '/doc.pdf#page=1', type: 'application/pdf'),
    Link(href: '/doc.pdf#page=5', type: 'application/pdf'),
    Link(href: '/doc.pdf#page=9', type: 'application/pdf'),
  ],
);

/// The reader's position at the TOC entry named [fragment], as native reports
/// it: the resource href plus a `toc=` fragment.
Locator _atEntry(String href, String fragment) => Locator(
  href: href,
  type: 'application/xhtml+xml',
  locations: Locations(fragments: ['toc=$fragment']),
);

/// The entry a candidate locator points at — `locatorFromLink` carries the
/// TOC entry's fragment in `cssSelector`, not in the href.
String? _entryOf(Locator locator) {
  final selector = locator.locations?.cssSelector;
  return selector != null && selector.startsWith('#')
      ? selector.substring(1)
      : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TocSkipNavigationMixin visibility walk', () {
    late TestTocSkipNavigator navigator;
    late MockReaderChannel channel;

    setUp(() {
      navigator = TestTocSkipNavigator();
      channel = MockReaderChannel();
    });

    test('a skip walks past entries already on screen', () async {
      channel.visible = (locator) =>
          const ['a1', 'a2'].contains(_entryOf(locator));

      await navigator.skipToNextChapter(
        publication: _frontmatterPublication(),
        currentLocator: _atEntry('/front.xhtml', 'a0'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(_entryOf(channel.goCallLog.single.locator), 'a3');
    });

    test('three taps reach the first chapter', () async {
      final publication = _frontmatterPublication();
      // Two entries share each rendered page, so a tap that targets the
      // reader's own page moves nothing.
      const page = {
        'a0': 0,
        'a1': 0,
        'a2': 1,
        'a3': 1,
        'a4': 2,
        'a5': 2,
        'c1': 3,
      };
      var reader = 'a0';
      channel.visible = (locator) => page[_entryOf(locator)] == page[reader];

      for (var tap = 0; tap < 3; tap++) {
        await navigator.skipToNextChapter(
          publication: publication,
          currentLocator: _atEntry(
            reader.startsWith('a') ? '/front.xhtml' : '/ch1.xhtml',
            reader,
          ),
          channel: channel,
        );
        reader = _entryOf(channel.goCallLog.last.locator)!;
      }

      expect(channel.goCallLog.map((c) => _entryOf(c.locator)).toList(), [
        'a2',
        'a4',
        'c1',
      ]);
    });

    test('a target in another resource is never probed', () async {
      channel.visible = (_) => true;

      await navigator.skipToNextChapter(
        publication: _frontmatterPublication(),
        currentLocator: _atEntry('/front.xhtml', 'a5'),
        channel: channel,
      );

      expect(channel.visibilityProbeLog, isEmpty);
      expect(channel.goCallLog, hasLength(1));
      expect(_entryOf(channel.goCallLog.single.locator), 'c1');
    });

    test('a PDF outline never walks', () async {
      channel.visible = (_) => true;

      await navigator.skipToNextChapter(
        publication: _pdfPublication(),
        currentLocator: Locator(
          href: '/doc.pdf',
          type: 'application/pdf',
          locations: Locations(position: 1),
        ),
        channel: channel,
      );

      expect(channel.visibilityProbeLog, isEmpty);
      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.locations?.position, 5);
    });

    test('a failing visibility probe still navigates', () async {
      // The real channel answers `true` when the probe errors, so every
      // same-resource entry looks visible and only the resource boundary
      // stops the walk.
      channel.visible = (_) => throw StateError('probe failed');

      await navigator.skipToNextChapter(
        publication: _frontmatterPublication(),
        currentLocator: _atEntry('/front.xhtml', 'a0'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(_entryOf(channel.goCallLog.single.locator), 'c1');
    });

    test('an entry with no resource of its own stops the walk', () async {
      // `locatorFromLink` answers null when the entry's file is missing from
      // the reading order, so there is nothing to probe and nothing to skip.
      final publication = Publication(
        metadata: Metadata(
          localizedTitle: LocalizedString.fromString('Ghost Entry Book'),
          identifier: 'ghost-entry-book',
        ),
        readingOrder: [Link(href: '/ch1.xhtml', type: 'application/xhtml+xml')],
        tableOfContents: [
          Link(href: '/ghost.xhtml#g0', type: 'application/xhtml+xml'),
          Link(href: '/ghost.xhtml#g1', type: 'application/xhtml+xml'),
        ],
      );
      channel.visible = (_) => true;

      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _atEntry('/ghost.xhtml', 'g0'),
        channel: channel,
      );

      expect(channel.visibilityProbeLog, isEmpty);
      expect(channel.goCallLog, isEmpty);
    });

    test('skipToPreviousChapter walks symmetrically', () async {
      channel.visible = (locator) =>
          const ['a4', 'a3'].contains(_entryOf(locator));

      await navigator.skipToPreviousChapter(
        publication: _frontmatterPublication(),
        currentLocator: _atEntry('/front.xhtml', 'a5'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(_entryOf(channel.goCallLog.single.locator), 'a2');
    });
  });
}
