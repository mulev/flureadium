import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium/flureadium.dart';

import '../mocks/mock_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlureadiumPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockFlureadiumPlatform();
    FlureadiumPlatform.instance = mockPlatform;
  });

  tearDown(() {
    mockPlatform.dispose();
  });

  Publication createTestPublication() {
    return Publication(
      metadata: Metadata(
        localizedTitle: LocalizedString.fromString('Test Book'),
        identifier: 'test-book-id',
      ),
      readingOrder: [
        Link(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
          title: 'Chapter 1',
        ),
        Link(
          href: 'chapter2.xhtml',
          type: 'application/xhtml+xml',
          title: 'Chapter 2',
        ),
      ],
      tableOfContents: [
        Link(href: 'chapter1.xhtml', title: 'Chapter 1'),
        Link(href: 'chapter2.xhtml', title: 'Chapter 2'),
      ],
    );
  }

  group('ReadiumReaderWidget', () {
    group('construction', () {
      test('creates widget with required parameters', () {
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(publication: publication);

        expect(widget.publication, equals(publication));
        expect(widget.initialLocator, isNull);
      });

      test('creates widget with all parameters', () {
        final publication = createTestPublication();
        final locator = Locator(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
        );

        final widget = ReadiumReaderWidget(
          publication: publication,
          initialLocator: locator,
          onTap: (_) {},
        );

        expect(widget.publication, equals(publication));
        expect(widget.initialLocator, equals(locator));
        expect(widget.onTap, isNotNull);
      });
    });

    group('initial locator', () {
      test('accepts initial locator with position', () {
        final publication = createTestPublication();
        final locator = Locator(
          href: 'chapter2.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(position: 2, progression: 0.5),
        );

        final widget = ReadiumReaderWidget(
          publication: publication,
          initialLocator: locator,
        );

        expect(widget.initialLocator, isNotNull);
        expect(widget.initialLocator!.href, equals('chapter2.xhtml'));
        expect(widget.initialLocator!.locations?.position, equals(2));
      });

      test('accepts initial locator with fragments', () {
        final publication = createTestPublication();
        final locator = Locator(
          href: 'chapter1.xhtml',
          type: 'application/xhtml+xml',
          locations: Locations(
            fragments: ['section1', 'paragraph2'],
            cssSelector: '#my-section',
          ),
        );

        final widget = ReadiumReaderWidget(
          publication: publication,
          initialLocator: locator,
        );

        expect(widget.initialLocator!.locations?.fragments, isNotEmpty);
        expect(
          widget.initialLocator!.locations?.cssSelector,
          equals('#my-section'),
        );
      });
    });

    group('onReady callback', () {
      test('onReady defaults to null', () {
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(publication: publication);

        expect(widget.onReady, isNull);
      });

      test('onReady callback is stored', () {
        var called = false;
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(
          publication: publication,
          onReady: () => called = true,
        );

        widget.onReady!();
        expect(called, isTrue);
      });

      test('widget with onReady is accepted alongside other callbacks', () {
        var readyCalled = false;
        var tappedCalled = false;
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(
          publication: publication,
          onReady: () => readyCalled = true,
          onTap: (_) => tappedCalled = true,
        );

        widget.onReady!();
        widget.onTap!(Offset.zero);
        expect(readyCalled, isTrue);
        expect(tappedCalled, isTrue);
      });
    });

    group('callbacks', () {
      test('onTap callback is stored and receives the tap position', () {
        Offset? tapped;
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(
          publication: publication,
          onTap: (position) => tapped = position,
        );

        widget.onTap!(const Offset(4, 8));
        expect(tapped, const Offset(4, 8));
      });

      test('createReadiumReaderChannel carries onExternalLinkActivated', () {
        void onExternalLink(String _) {}

        final channel = createReadiumReaderChannel(
          42,
          onPageChanged: (_) {},
          onExternalLinkActivated: onExternalLink,
        );

        expect(channel.onExternalLinkActivated, same(onExternalLink));
      });

      test('createReadiumReaderChannel carries onTap', () {
        void onTap(Offset _) {}

        final channel = createReadiumReaderChannel(
          43,
          onPageChanged: (_) {},
          onTap: onTap,
        );

        expect(channel.onTap, same(onTap));
      });
    });

    group('publication data', () {
      test('publication is accessible from widget', () {
        final publication = createTestPublication();

        final widget = ReadiumReaderWidget(publication: publication);

        expect(widget.publication.metadata.title, equals('Test Book'));
        expect(widget.publication.readingOrder.length, equals(2));
        expect(widget.publication.tableOfContents.length, equals(2));
      });

      test('publication with cover link', () {
        final publication = Publication(
          metadata: Metadata(
            localizedTitle: LocalizedString.fromString('Book with Cover'),
          ),
          readingOrder: [
            Link(href: 'chapter1.xhtml', type: 'application/xhtml+xml'),
          ],
          resources: [
            Link(href: 'cover.jpg', type: 'image/jpeg', rels: ['cover']),
          ],
        );

        final widget = ReadiumReaderWidget(publication: publication);

        expect(widget.publication.coverLink, isNotNull);
        expect(widget.publication.coverLink!.href, equals('cover.jpg'));
      });
    });
  });

  group('ReadiumReaderWidget publication swap', () {
    // On the test host `_buildNativeReader` returns the keyed fallback
    // branch, so element replacement is directly observable.
    final readerView = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.key is ValueKey<int>,
    );

    Widget host(Publication publication) =>
        MaterialApp(home: ReadiumReaderWidget(publication: publication));

    ReadiumReaderWidgetInterface readerOf(WidgetTester tester) =>
        tester.state(find.byType(ReadiumReaderWidget))
            as ReadiumReaderWidgetInterface;

    testWidgets('swapping to a different publication replaces the view', (
      tester,
    ) async {
      await tester.pumpWidget(host(createTestPublication()));
      final before = tester.element(readerView);

      await tester.pumpWidget(host(createTestPublication()));

      expect(tester.element(readerView), isNot(same(before)));
    });

    testWidgets('passing the same publication instance does not rebuild', (
      tester,
    ) async {
      final publication = createTestPublication();

      await tester.pumpWidget(host(publication));
      final before = tester.element(readerView);

      await tester.pumpWidget(host(publication));

      expect(tester.element(readerView), same(before));
    });

    testWidgets('a swap clears the registered reader widget', (tester) async {
      await tester.pumpWidget(host(createTestPublication()));
      // _onPlatformViewCreated never fires on the host, so stand in for the
      // registration the native side would have made.
      mockPlatform.currentReaderWidget = readerOf(tester);

      await tester.pumpWidget(host(createTestPublication()));

      expect(mockPlatform.currentReaderWidget, isNull);
    });

    testWidgets('a getLocatorFragments call in flight resolves to null', (
      tester,
    ) async {
      await tester.pumpWidget(host(createTestPublication()));

      // Recorded rather than awaited: before the fix this future never
      // settles, and awaiting it would hang the suite instead of failing.
      Object? outcome = 'never settled';
      readerOf(tester)
          .getLocatorFragments(
            Locator(href: 'chapter1.xhtml', type: 'application/xhtml+xml'),
          )
          .then((value) => outcome = value, onError: (Object e) => outcome = e)
          .ignore();

      await tester.pumpWidget(host(createTestPublication()));
      await tester.pump();

      expect(outcome, isNull);
    });

    testWidgets('getLocatorFragments after dispose resolves to null', (
      tester,
    ) async {
      await tester.pumpWidget(host(createTestPublication()));
      final reader = readerOf(tester);

      // Unmount the reader. A host that captured the interface can still call
      // into it, and that call must settle rather than wait on a view that no
      // longer exists.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      Object? outcome = 'never settled';
      reader
          .getLocatorFragments(
            Locator(href: 'chapter1.xhtml', type: 'application/xhtml+xml'),
          )
          .then((value) => outcome = value, onError: (Object e) => outcome = e)
          .ignore();
      await tester.pump();

      expect(outcome, isNull);
    });
  });
}
