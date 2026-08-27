import 'dart:async';

import 'package:flureadium/src/reader/toc_skip_navigation_mixin.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_reader_channel.dart';

// Test class that uses the mixin.
class TestTocSkipNavigator with TocSkipNavigationMixin {}

/// A publication whose TOC nests Ch1..Ch3 under a single part, matching the
/// hierarchical shape Readium iOS produces for EPUB3 nav documents.
Publication _hierarchicalPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Hierarchical Book'),
    identifier: 'hierarchical-book',
  ),
  readingOrder: [
    Link(href: 'ch1.xhtml', type: 'application/xhtml+xml'),
    Link(href: 'ch2.xhtml', type: 'application/xhtml+xml'),
    Link(href: 'ch3.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(
      href: 'part.xhtml',
      type: 'application/xhtml+xml',
      children: [
        Link(href: 'ch1.xhtml', type: 'application/xhtml+xml'),
        Link(href: 'ch2.xhtml', type: 'application/xhtml+xml'),
        Link(href: 'ch3.xhtml', type: 'application/xhtml+xml'),
      ],
    ),
  ],
);

Publication _emptyTocPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('No TOC'),
    identifier: 'no-toc',
  ),
  readingOrder: [Link(href: 'ch1.xhtml', type: 'application/xhtml+xml')],
);

/// A publication whose TOC carries three entries inside `ch1.xhtml`, so the
/// remembered index and plain path matching resolve to different entries.
Publication _subSectionPublication() => Publication(
  metadata: Metadata(
    localizedTitle: LocalizedString.fromString('Sub-sectioned Book'),
    identifier: 'sub-sectioned-book',
  ),
  readingOrder: [
    Link(href: '/ch1.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ch2.xhtml', type: 'application/xhtml+xml'),
  ],
  tableOfContents: [
    Link(href: '/ch1.xhtml', type: 'application/xhtml+xml'),
    Link(href: '/ch1.xhtml#a', type: 'application/xhtml+xml'),
    Link(href: '/ch1.xhtml#b', type: 'application/xhtml+xml'),
    Link(href: '/ch2.xhtml', type: 'application/xhtml+xml'),
  ],
);

Locator _at(String href) => Locator(href: href, type: 'application/xhtml+xml');

Locator _atFragment(String href, String fragment) => Locator(
  href: href,
  type: 'application/xhtml+xml',
  locations: Locations(fragments: [fragment]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TocSkipNavigationMixin', () {
    late TestTocSkipNavigator navigator;
    late MockReaderChannel channel;

    setUp(() {
      navigator = TestTocSkipNavigator();
      channel = MockReaderChannel();
    });

    test('skipToNextChapter does nothing when the TOC is empty', () async {
      await navigator.skipToNextChapter(
        publication: _emptyTocPublication(),
        currentLocator: _at('ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, isEmpty);
    });

    test('skipToNextChapter does nothing without a current locator', () async {
      await navigator.skipToNextChapter(
        publication: _hierarchicalPublication(),
        currentLocator: null,
        channel: channel,
      );

      expect(channel.goCallLog, isEmpty);
    });

    test(
      'skipToNextChapter waits for the reader when the cache is cold',
      () async {
        final ready = Completer<Locator>();

        final skip = navigator.skipToNextChapter(
          publication: _hierarchicalPublication(),
          currentLocator: null,
          channel: channel,
          whenReady: ready.future,
        );

        // The widget's cache is filled by onPageChanged, which lands after the
        // host's subscribe-time locator — the window this fix closes.
        expect(channel.goCallLog, isEmpty);

        ready.complete(_at('ch1.xhtml'));
        await skip;

        expect(channel.goCallLog, hasLength(1));
        expect(channel.goCallLog.single.locator.href, 'ch2.xhtml');
      },
    );

    test(
      'skipToNextChapter returns quietly when the view was released',
      () async {
        final ready = Completer<Locator>();

        final skip = navigator.skipToNextChapter(
          publication: _hierarchicalPublication(),
          currentLocator: null,
          channel: channel,
          whenReady: ready.future,
        );
        // What _teardownCurrentView does to an unsettled completer on a
        // publication swap (reader_widget.dart).
        ready.completeError(
          ReadiumError(
            'Reader view was released before it reported a locator.',
          ),
        );

        await skip;

        expect(channel.goCallLog, isEmpty);
      },
    );

    test('skipToNextChapter does not wait when the cache is warm', () async {
      // Never completes: if the skip awaited it, this test would time out.
      final ready = Completer<Locator>();

      await navigator.skipToNextChapter(
        publication: _hierarchicalPublication(),
        currentLocator: _at('ch1.xhtml'),
        channel: channel,
        whenReady: ready.future,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, 'ch2.xhtml');
    });

    test('skipToNextChapter moves to the next flattened TOC entry', () async {
      await navigator.skipToNextChapter(
        publication: _hierarchicalPublication(),
        currentLocator: _at('ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, 'ch2.xhtml');
      expect(channel.goCallLog.single.animated, isTrue);
      expect(channel.goCallLog.single.isAudioBookWithText, isFalse);
    });

    test('skipToPreviousChapter moves back one TOC entry', () async {
      await navigator.skipToPreviousChapter(
        publication: _hierarchicalPublication(),
        currentLocator: _at('ch2.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, 'ch1.xhtml');
    });

    test('the remembered index drives the next resolution', () async {
      final publication = _subSectionPublication();

      // Lands the remembered index on TOC entry 0 via a fragment-matched
      // backward skip from sub-section "a".
      await navigator.skipToPreviousChapter(
        publication: publication,
        currentLocator: _atFragment('/ch1.xhtml', 'toc=a'),
        channel: channel,
      );
      // Native now reports the file with no toc= fragment. Path matching alone
      // would resolve to the file's LAST entry (index 2) and skip out to ch2;
      // the remembered index 0 keeps the reader inside ch1.
      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _at('/ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(2));
      expect(channel.goCallLog[1].locator.href, '/ch1.xhtml');
    });

    test('resetSkipNavigationState drops the remembered index', () async {
      final publication = _subSectionPublication();

      await navigator.skipToPreviousChapter(
        publication: publication,
        currentLocator: _atFragment('/ch1.xhtml', 'toc=a'),
        channel: channel,
      );
      navigator.resetSkipNavigationState();
      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _at('/ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(2));
      // Without the memory, path matching resolves to the file's last entry
      // and the skip leaves ch1 entirely.
      expect(channel.goCallLog[1].locator.href, '/ch2.xhtml');
    });

    test('a reset landing mid-navigation is not undone by that skip', () async {
      final publication = _subSectionPublication();
      // A publication swap tears down state while `go` is still in flight.
      channel.duringGo = navigator.resetSkipNavigationState;

      await navigator.skipToPreviousChapter(
        publication: publication,
        currentLocator: _atFragment('/ch1.xhtml', 'toc=a'),
        channel: channel,
      );
      channel.duringGo = null;

      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _at('/ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(2));
      // The reset must hold: if the in-flight skip wrote its index back after
      // the await, this resolves from the old book's entry instead.
      expect(channel.goCallLog[1].locator.href, '/ch2.xhtml');
    });

    test('a null channel is tolerated', () async {
      final publication = _hierarchicalPublication();

      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _at('ch1.xhtml'),
        channel: null,
      );

      expect(channel.goCallLog, isEmpty);

      // The mixin is still usable after the dropped call.
      await navigator.skipToNextChapter(
        publication: publication,
        currentLocator: _at('ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, 'ch2.xhtml');
    });

    test(
      'a fragment in the reader\'s own resource still drives the skip',
      () async {
        // Pins 0.17.2 behaviour: `toc=b` names entry 2, so "next" is entry 3.
        await navigator.skipToNextChapter(
          publication: _subSectionPublication(),
          currentLocator: _atFragment('/ch1.xhtml', 'toc=b'),
          channel: channel,
        );

        expect(channel.goCallLog, hasLength(1));
        expect(channel.goCallLog.single.locator.href, '/ch2.xhtml');
      },
    );

    test('a fragment living only in another resource is ignored', () async {
      // `a` names an entry inside ch1 while the reader is in ch2. Accepting it
      // would resolve to entry 1 and send "previous" to entry 0; path matching
      // resolves entry 3, so "previous" is entry 2.
      await navigator.skipToPreviousChapter(
        publication: _subSectionPublication(),
        currentLocator: _atFragment('/ch2.xhtml', 'toc=a'),
        channel: channel,
      );

      expect(channel.goCallLog, hasLength(1));
      expect(channel.goCallLog.single.locator.href, '/ch1.xhtml');
      expect(channel.goCallLog.single.locator.locations?.cssSelector, '#b');
    });

    test('skipToNextChapter stops at the last TOC entry', () async {
      await navigator.skipToNextChapter(
        publication: _hierarchicalPublication(),
        currentLocator: _at('ch3.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, isEmpty);
    });

    test('skipToPreviousChapter stops at the first TOC entry', () async {
      await navigator.skipToPreviousChapter(
        publication: _hierarchicalPublication(),
        currentLocator: _at('ch1.xhtml'),
        channel: channel,
      );

      expect(channel.goCallLog, isEmpty);
    });
  });
}
