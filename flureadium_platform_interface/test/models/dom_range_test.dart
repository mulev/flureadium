import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('Point', () {
    group('constructor', () {
      test('creates point with required fields', () {
        final point = Point(cssSelector: '#paragraph1', textNodeIndex: 0);

        expect(point.cssSelector, equals('#paragraph1'));
        expect(point.textNodeIndex, equals(0));
        expect(point.charOffset, isNull);
      });

      test('creates point with all fields', () {
        final point = Point(
          cssSelector: '.section > p',
          textNodeIndex: 2,
          charOffset: 45,
        );

        expect(point.cssSelector, equals('.section > p'));
        expect(point.textNodeIndex, equals(2));
        expect(point.charOffset, equals(45));
      });
    });

    group('fromJson', () {
      test('parses point from JSON', () {
        final json = {
          'cssSelector': '#element',
          'textNodeIndex': 1,
          'charOffset': 10,
        };

        final point = Point.fromJson(json);

        expect(point, isNotNull);
        expect(point!.cssSelector, equals('#element'));
        expect(point.textNodeIndex, equals(1));
        expect(point.charOffset, equals(10));
      });

      test('returns null for null JSON', () {
        expect(Point.fromJson(null), isNull);
      });

      test('returns null when cssSelector is missing', () {
        final json = {'textNodeIndex': 0, 'charOffset': 5};

        expect(Point.fromJson(json), isNull);
      });

      test('returns null when textNodeIndex is missing', () {
        final json = {'cssSelector': '#test', 'charOffset': 5};

        expect(Point.fromJson(json), isNull);
      });

      test('parses point without charOffset', () {
        final json = {'cssSelector': '#paragraph', 'textNodeIndex': 0};

        final point = Point.fromJson(json);

        expect(point, isNotNull);
        expect(point!.cssSelector, equals('#paragraph'));
        expect(point.textNodeIndex, equals(0));
        expect(point.charOffset, isNull);
      });

      test('handles legacy offset field for backward compatibility', () {
        final json = {'cssSelector': '#old', 'textNodeIndex': 1, 'offset': 20};

        final point = Point.fromJson(json);

        expect(point, isNotNull);
        expect(point!.charOffset, equals(20));
      });

      test('prefers charOffset over legacy offset field', () {
        final json = {
          'cssSelector': '#element',
          'textNodeIndex': 0,
          'charOffset': 15,
          'offset': 20,
        };

        final point = Point.fromJson(json);

        expect(point, isNotNull);
        expect(point!.charOffset, equals(15));
      });

      test('validates textNodeIndex is positive', () {
        final validJson = {'cssSelector': '#test', 'textNodeIndex': 1};

        final invalidJson = {'cssSelector': '#test', 'textNodeIndex': -1};

        expect(Point.fromJson(validJson), isNotNull);
        expect(Point.fromJson(invalidJson), isNull);
      });

      test('validates charOffset is positive when present', () {
        final validJson = {
          'cssSelector': '#test',
          'textNodeIndex': 0,
          'charOffset': 0,
        };

        final invalidJson = {
          'cssSelector': '#test',
          'textNodeIndex': 0,
          'charOffset': -5,
        };

        expect(Point.fromJson(validJson), isNotNull);
        expect(Point.fromJson(invalidJson)!.charOffset, isNull);
      });
    });

    group('toJson', () {
      test('serializes point to JSON', () {
        final point = Point(
          cssSelector: '#section1',
          textNodeIndex: 3,
          charOffset: 42,
        );

        final json = point.toJson();

        expect(json['cssSelector'], equals('#section1'));
        expect(json['textNodeIndex'], equals(3));
        expect(json['charOffset'], equals(42));
      });

      test('omits null charOffset from JSON', () {
        final point = Point(cssSelector: '#para', textNodeIndex: 0);

        final json = point.toJson();

        expect(json['cssSelector'], equals('#para'));
        expect(json['textNodeIndex'], equals(0));
        // putOpt omits null values
        expect(json.containsKey('charOffset'), isFalse);
      });

      test('roundtrip serialization preserves data', () {
        final original = Point(
          cssSelector: '.content > p:nth-child(3)',
          textNodeIndex: 1,
          charOffset: 100,
        );

        final json = original.toJson();
        final restored = Point.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.cssSelector, equals(original.cssSelector));
        expect(restored.textNodeIndex, equals(original.textNodeIndex));
        expect(restored.charOffset, equals(original.charOffset));
      });
    });

    group('equality', () {
      test('equal points have same hashCode', () {
        final point1 = Point(
          cssSelector: '#test',
          textNodeIndex: 0,
          charOffset: 10,
        );

        final point2 = Point(
          cssSelector: '#test',
          textNodeIndex: 0,
          charOffset: 10,
        );

        expect(point1, equals(point2));
        expect(point1.hashCode, equals(point2.hashCode));
      });

      test('different points are not equal', () {
        final point1 = Point(cssSelector: '#test1', textNodeIndex: 0);

        final point2 = Point(cssSelector: '#test2', textNodeIndex: 0);

        expect(point1, isNot(equals(point2)));
      });

      test('points with different textNodeIndex are not equal', () {
        final point1 = Point(cssSelector: '#test', textNodeIndex: 0);

        final point2 = Point(cssSelector: '#test', textNodeIndex: 1);

        expect(point1, isNot(equals(point2)));
      });

      test('points with different charOffset are not equal', () {
        final point1 = Point(
          cssSelector: '#test',
          textNodeIndex: 0,
          charOffset: 5,
        );

        final point2 = Point(
          cssSelector: '#test',
          textNodeIndex: 0,
          charOffset: 10,
        );

        expect(point1, isNot(equals(point2)));
      });
    });

    group('CSS selectors', () {
      test('handles simple ID selector', () {
        final point = Point(cssSelector: '#main', textNodeIndex: 0);

        expect(point.cssSelector, equals('#main'));
      });

      test('handles class selector', () {
        final point = Point(cssSelector: '.paragraph', textNodeIndex: 0);

        expect(point.cssSelector, equals('.paragraph'));
      });

      test('handles complex selector', () {
        final point = Point(
          cssSelector: 'body > div.content > p:nth-child(2)',
          textNodeIndex: 0,
        );

        expect(
          point.cssSelector,
          equals('body > div.content > p:nth-child(2)'),
        );
      });

      test('handles attribute selector', () {
        final point = Point(
          cssSelector: '[data-id="section1"]',
          textNodeIndex: 0,
        );

        expect(point.cssSelector, equals('[data-id="section1"]'));
      });
    });
  });

  group('DomRange', () {
    group('constructor', () {
      test('creates DomRange with start and end', () {
        final start = Point(cssSelector: '#start', textNodeIndex: 0);
        final end = Point(cssSelector: '#end', textNodeIndex: 1);

        final range = DomRange(start: start, end: end);

        expect(range.start, equals(start));
        expect(range.end, equals(end));
      });

      test('creates collapsed DomRange with only start', () {
        final start = Point(
          cssSelector: '#point',
          textNodeIndex: 0,
          charOffset: 5,
        );

        final range = DomRange(start: start);

        expect(range.start, equals(start));
        expect(range.end, isNull);
      });
    });

    group('fromJson', () {
      test('parses DomRange with start and end', () {
        final json = {
          'start': {
            'cssSelector': '#para1',
            'textNodeIndex': 0,
            'charOffset': 10,
          },
          'end': {
            'cssSelector': '#para2',
            'textNodeIndex': 0,
            'charOffset': 20,
          },
        };

        final range = DomRange.fromJson(json);

        expect(range, isNotNull);
        expect(range!.start.cssSelector, equals('#para1'));
        expect(range.start.charOffset, equals(10));
        expect(range.end, isNotNull);
        expect(range.end!.cssSelector, equals('#para2'));
        expect(range.end!.charOffset, equals(20));
      });

      test('parses collapsed DomRange with only start', () {
        final json = {
          'start': {'cssSelector': '#point', 'textNodeIndex': 0},
        };

        final range = DomRange.fromJson(json);

        expect(range, isNotNull);
        expect(range!.start.cssSelector, equals('#point'));
        expect(range.end, isNull);
      });

      test('returns null for null JSON', () {
        expect(DomRange.fromJson(null), isNull);
      });

      test('returns null when start is missing', () {
        final json = {
          'end': {'cssSelector': '#end', 'textNodeIndex': 0},
        };

        expect(DomRange.fromJson(json), isNull);
      });

      test('returns null when start is invalid', () {
        final json = {
          'start': {
            'textNodeIndex': 0,
            // Missing cssSelector
          },
        };

        expect(DomRange.fromJson(json), isNull);
      });

      test('parses range when end is invalid', () {
        final json = {
          'start': {'cssSelector': '#start', 'textNodeIndex': 0},
          'end': {
            'textNodeIndex': 0,
            // Missing cssSelector - end will be null
          },
        };

        final range = DomRange.fromJson(json);

        expect(range, isNotNull);
        expect(range!.start.cssSelector, equals('#start'));
        expect(range.end, isNull);
      });
    });

    group('toJson', () {
      test('serializes DomRange with start and end', () {
        final range = DomRange(
          start: Point(cssSelector: '#s', textNodeIndex: 0, charOffset: 5),
          end: Point(cssSelector: '#e', textNodeIndex: 1, charOffset: 15),
        );

        final json = range.toJson();

        expect(json['start'], isNotNull);
        expect(json['start']['cssSelector'], equals('#s'));
        expect(json['start']['charOffset'], equals(5));
        expect(json['end'], isNotNull);
        expect(json['end']['cssSelector'], equals('#e'));
        expect(json['end']['charOffset'], equals(15));
      });

      test('serializes collapsed DomRange', () {
        final range = DomRange(
          start: Point(cssSelector: '#point', textNodeIndex: 0),
        );

        final json = range.toJson();

        expect(json['start'], isNotNull);
        expect(json.containsKey('end'), isFalse);
      });

      test('roundtrip serialization preserves data', () {
        final original = DomRange(
          start: Point(cssSelector: '#start', textNodeIndex: 0, charOffset: 10),
          end: Point(cssSelector: '#end', textNodeIndex: 2, charOffset: 50),
        );

        final json = original.toJson();
        final restored = DomRange.fromJson(json);

        expect(restored, isNotNull);
        expect(restored!.start.cssSelector, equals(original.start.cssSelector));
        expect(
          restored.start.textNodeIndex,
          equals(original.start.textNodeIndex),
        );
        expect(restored.start.charOffset, equals(original.start.charOffset));
        expect(restored.end, isNotNull);
        expect(restored.end!.cssSelector, equals(original.end!.cssSelector));
        expect(
          restored.end!.textNodeIndex,
          equals(original.end!.textNodeIndex),
        );
        expect(restored.end!.charOffset, equals(original.end!.charOffset));
      });
    });

    group('equality', () {
      test('equal DomRanges have same hashCode', () {
        final start = Point(cssSelector: '#s', textNodeIndex: 0);
        final end = Point(cssSelector: '#e', textNodeIndex: 1);

        final range1 = DomRange(start: start, end: end);
        final range2 = DomRange(start: start, end: end);

        expect(range1, equals(range2));
        expect(range1.hashCode, equals(range2.hashCode));
      });

      test('different DomRanges are not equal', () {
        final range1 = DomRange(
          start: Point(cssSelector: '#s1', textNodeIndex: 0),
        );

        final range2 = DomRange(
          start: Point(cssSelector: '#s2', textNodeIndex: 0),
        );

        expect(range1, isNot(equals(range2)));
      });

      test('DomRanges with different end are not equal', () {
        final start = Point(cssSelector: '#s', textNodeIndex: 0);

        final range1 = DomRange(
          start: start,
          end: Point(cssSelector: '#e1', textNodeIndex: 1),
        );

        final range2 = DomRange(
          start: start,
          end: Point(cssSelector: '#e2', textNodeIndex: 1),
        );

        expect(range1, isNot(equals(range2)));
      });

      test('collapsed range not equal to non-collapsed', () {
        final start = Point(cssSelector: '#s', textNodeIndex: 0);

        final collapsed = DomRange(start: start);
        final nonCollapsed = DomRange(
          start: start,
          end: Point(cssSelector: '#e', textNodeIndex: 1),
        );

        expect(collapsed, isNot(equals(nonCollapsed)));
      });
    });

    group('use cases', () {
      test('represents text selection within single element', () {
        final range = DomRange(
          start: Point(
            cssSelector: '#paragraph1',
            textNodeIndex: 0,
            charOffset: 10,
          ),
          end: Point(
            cssSelector: '#paragraph1',
            textNodeIndex: 0,
            charOffset: 50,
          ),
        );

        expect(range.start.cssSelector, equals(range.end!.cssSelector));
        expect(range.start.textNodeIndex, equals(range.end!.textNodeIndex));
        expect(range.start.charOffset! < range.end!.charOffset!, isTrue);
      });

      test('represents text selection across multiple elements', () {
        final range = DomRange(
          start: Point(
            cssSelector: '#para1',
            textNodeIndex: 0,
            charOffset: 100,
          ),
          end: Point(cssSelector: '#para3', textNodeIndex: 0, charOffset: 20),
        );

        expect(range.start.cssSelector, isNot(equals(range.end!.cssSelector)));
      });

      test('represents caret position with collapsed range', () {
        final range = DomRange(
          start: Point(cssSelector: '#input', textNodeIndex: 0, charOffset: 15),
        );

        expect(range.end, isNull);
        expect(range.start.charOffset, equals(15));
      });

      test('represents element boundary without character offset', () {
        final range = DomRange(
          start: Point(cssSelector: '#section1', textNodeIndex: 0),
          end: Point(cssSelector: '#section1', textNodeIndex: 3),
        );

        expect(range.start.charOffset, isNull);
        expect(range.end!.charOffset, isNull);
        expect(range.start.textNodeIndex < range.end!.textNodeIndex, isTrue);
      });
    });
  });
}
