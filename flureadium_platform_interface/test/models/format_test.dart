import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('PublicationFormat', () {
    group('fromMIMEType', () {
      test('returns epub for application/epub+zip', () {
        final format = PublicationFormat.fromMIMEType('application/epub+zip');
        expect(format, equals(PublicationFormat.epub));
      });

      test('returns epub for application/oebps-package+xml', () {
        final format = PublicationFormat.fromMIMEType(
          'application/oebps-package+xml',
        );
        expect(format, equals(PublicationFormat.epub));
      });

      test('returns pdf for application/pdf', () {
        final format = PublicationFormat.fromMIMEType('application/pdf');
        expect(format, equals(PublicationFormat.pdf));
      });

      test('falls back to file extension when MIME type unknown', () {
        final format = PublicationFormat.fromMIMEType(
          'application/octet-stream',
          fileExtension: 'epub',
        );
        expect(format, equals(PublicationFormat.epub));
      });

      test('falls back to pdf file extension', () {
        final format = PublicationFormat.fromMIMEType(
          'application/octet-stream',
          fileExtension: 'pdf',
        );
        expect(format, equals(PublicationFormat.pdf));
      });

      test('returns null for unknown MIME type and extension', () {
        final format = PublicationFormat.fromMIMEType(
          'application/unknown',
          fileExtension: 'xyz',
        );
        expect(format, isNull);
      });
    });

    group('fromMIMETypes', () {
      test('finds pdf in list of MIME types', () {
        final format = PublicationFormat.fromMIMETypes([
          'text/plain',
          'application/pdf',
          'application/octet-stream',
        ]);
        expect(format, equals(PublicationFormat.pdf));
      });

      test('prioritizes first matching MIME type', () {
        final format = PublicationFormat.fromMIMETypes([
          'application/epub+zip',
          'application/pdf',
        ]);
        expect(format, equals(PublicationFormat.epub));
      });
    });

    group('fromPath', () {
      test('detects epub from path', () {
        final format = PublicationFormat.fromPath(
          '/path/to/book.epub',
          mimetype: 'application/epub+zip',
        );
        expect(format, equals(PublicationFormat.epub));
      });

      test('detects pdf from path extension when MIME unknown', () {
        final format = PublicationFormat.fromPath(
          '/path/to/document.pdf',
          mimetype: 'application/octet-stream',
        );
        expect(format, equals(PublicationFormat.pdf));
      });

      test('handles uppercase PDF extension', () {
        final format = PublicationFormat.fromPath(
          '/path/to/document.PDF',
          mimetype: 'application/octet-stream',
        );
        expect(format, equals(PublicationFormat.pdf));
      });

      test('handles mixed case PDF extension', () {
        final format = PublicationFormat.fromPath(
          '/path/to/document.Pdf',
          mimetype: 'application/octet-stream',
        );
        expect(format, equals(PublicationFormat.pdf));
      });

      test('prioritizes MIME type over extension', () {
        final format = PublicationFormat.fromPath(
          '/path/to/file.pdf',
          mimetype: 'application/epub+zip',
        );
        expect(format, equals(PublicationFormat.epub));
      });
    });

    group('equality', () {
      test('two pdf formats built separately are equal', () {
        // Runtime instance, so equality compares props, not identity.
        expect(
          PublicationFormat(PublicationFormatEnum.pdf),
          equals(PublicationFormat.pdf),
        );
      });

      test('pdf format is different from epub', () {
        expect(PublicationFormat.pdf, isNot(equals(PublicationFormat.epub)));
      });
    });
  });

  group('PublicationFormatEnum', () {
    test('contains pdf value', () {
      expect(PublicationFormatEnum.values, contains(PublicationFormatEnum.pdf));
    });

    test('has three values: epub, video, pdf', () {
      expect(PublicationFormatEnum.values.length, equals(3));
    });
  });
}
