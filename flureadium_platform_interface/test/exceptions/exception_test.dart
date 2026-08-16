import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flureadium_platform_interface/flureadium_platform_interface.dart';

void main() {
  group('ReadiumException', () {
    group('constructor', () {
      test('creates exception with message', () {
        const exception = ReadiumException('Test error message');

        expect(exception.message, equals('Test error message'));
        expect(exception.type, isNull);
      });

      test('creates exception with message and type', () {
        const exception = ReadiumException(
          'Test error',
          type: OpeningReadiumExceptionType.notFound,
        );

        expect(exception.message, equals('Test error'));
        expect(exception.type, equals(OpeningReadiumExceptionType.notFound));
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        const exception = ReadiumException('Error occurred');

        expect(
          exception.toString(),
          equals('ReadiumException{Error occurred}'),
        );
      });
    });

    group('fromPlatformException', () {
      test('parses PlatformException with known type', () {
        final platformException = PlatformException(
          code: 'notFound',
          message: 'Resource not found',
          details: 'The requested resource was not found',
        );

        final exception = ReadiumException.fromPlatformException(
          platformException,
        );

        expect(
          exception.message,
          equals('The requested resource was not found'),
        );
        expect(exception.type, equals(OpeningReadiumExceptionType.notFound));
      });

      test('parses PlatformException with forbidden type', () {
        final platformException = PlatformException(
          code: 'forbidden',
          message: 'Access denied',
          details: 'You do not have permission',
        );

        final exception = ReadiumException.fromPlatformException(
          platformException,
        );

        expect(exception.type, equals(OpeningReadiumExceptionType.forbidden));
      });

      test('parses PlatformException with unknown code', () {
        final platformException = PlatformException(
          code: 'unknownCode',
          message: 'Unknown error',
          details: 'Something went wrong',
        );

        final exception = ReadiumException.fromPlatformException(
          platformException,
        );

        expect(exception.message, equals('Something went wrong'));
        expect(exception.type, isNull);
      });

      test('handles null details', () {
        final platformException = PlatformException(
          code: 'error',
          message: 'Error message',
        );

        final exception = ReadiumException.fromPlatformException(
          platformException,
        );

        expect(exception.message, equals('unknown'));
      });
    });

    group('fromError', () {
      test('handles PlatformException', () {
        final error = PlatformException(
          code: 'unavailable',
          message: 'Service unavailable',
          details: 'The service is temporarily unavailable',
        );

        final exception = ReadiumException.fromError(error);

        expect(exception.type, equals(OpeningReadiumExceptionType.unavailable));
      });

      test('handles generic error', () {
        final error = Exception('Generic error');

        final exception = ReadiumException.fromError(error);

        expect(exception.message, contains('Generic error'));
      });

      test('handles string error', () {
        const error = 'String error message';

        final exception = ReadiumException.fromError(error);

        expect(exception.message, equals('String error message'));
      });

      test('handles null error', () {
        final exception = ReadiumException.fromError(null);

        expect(exception.message, equals('null'));
      });
    });
  });

  group('PublicationNotSetReadiumException', () {
    test('creates exception with message', () {
      const exception = PublicationNotSetReadiumException(
        'No publication loaded',
      );

      expect(exception.message, equals('No publication loaded'));
    });

    test('toString returns formatted string', () {
      const exception = PublicationNotSetReadiumException(
        'Publication required',
      );

      expect(
        exception.toString(),
        equals('PublicationNotSetReadiumException{Publication required}'),
      );
    });
  });

  group('OfflineReadiumException', () {
    test('creates exception with message', () {
      const exception = OfflineReadiumException('Network unavailable');

      expect(exception.message, equals('Offline: Network unavailable'));
    });

    test('creates exception with null message', () {
      const exception = OfflineReadiumException();

      expect(exception.message, equals('Offline: null'));
    });

    test('toString returns formatted string', () {
      const exception = OfflineReadiumException('No connection');

      expect(exception.toString(), equals('OfflineReadiumException'));
    });
  });

  group('OpeningReadiumException', () {
    test('creates exception with type', () {
      const exception = OpeningReadiumException(
        'File not found',
        type: OpeningReadiumExceptionType.notFound,
      );

      expect(exception.message, equals('File not found'));
      expect(exception.type, equals(OpeningReadiumExceptionType.notFound));
    });

    test('toString returns formatted string with type', () {
      const exception = OpeningReadiumException(
        'Access denied',
        type: OpeningReadiumExceptionType.forbidden,
      );

      expect(
        exception.toString(),
        equals(
          'OpeningReadiumException{OpeningReadiumExceptionType.forbidden,Access denied}',
        ),
      );
    });
  });

  group('OpeningReadiumExceptionType', () {
    test('has all expected values', () {
      expect(
        OpeningReadiumExceptionType.values,
        containsAll([
          OpeningReadiumExceptionType.formatNotSupported,
          OpeningReadiumExceptionType.readingError,
          OpeningReadiumExceptionType.notFound,
          OpeningReadiumExceptionType.forbidden,
          OpeningReadiumExceptionType.unavailable,
          OpeningReadiumExceptionType.incorrectCredentials,
          OpeningReadiumExceptionType.unknown,
        ]),
      );
    });

    test('values have correct names', () {
      expect(
        OpeningReadiumExceptionType.formatNotSupported.name,
        equals('formatNotSupported'),
      );
      expect(
        OpeningReadiumExceptionType.readingError.name,
        equals('readingError'),
      );
      expect(OpeningReadiumExceptionType.notFound.name, equals('notFound'));
      expect(OpeningReadiumExceptionType.forbidden.name, equals('forbidden'));
      expect(
        OpeningReadiumExceptionType.unavailable.name,
        equals('unavailable'),
      );
      expect(
        OpeningReadiumExceptionType.incorrectCredentials.name,
        equals('incorrectCredentials'),
      );
      expect(OpeningReadiumExceptionType.unknown.name, equals('unknown'));
    });
  });

  group('ReadiumError', () {
    group('constructor', () {
      test('creates error with message', () {
        final error = ReadiumError('Error message');

        expect(error.message, equals('Error message'));
        expect(error.code, isNull);
        expect(error.data, isNull);
        expect(error.stackTrace, isNotNull);
      });

      test('creates error with all parameters', () {
        final stackTrace = StackTrace.current;
        final error = ReadiumError(
          'Test error',
          code: 'ERR_001',
          data: {'key': 'value'},
          stackTrace: stackTrace,
        );

        expect(error.message, equals('Test error'));
        expect(error.code, equals('ERR_001'));
        expect(error.data, equals({'key': 'value'}));
        expect(error.stackTrace, equals(stackTrace));
      });
    });

    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'message': 'Parsed error',
          'code': 'PARSE_ERR',
          'data': 'Additional data',
          'stackTrace': 'at line 1\nat line 2',
        };

        final error = ReadiumError.fromJson(json);

        expect(error.message, equals('Parsed error'));
        expect(error.code, equals('PARSE_ERR'));
        expect(error.data, equals('Additional data'));
        expect(error.stackTrace.toString(), equals('at line 1\nat line 2'));
      });

      test('parses JSON with minimal data', () {
        final json = {'message': 'Minimal error'};

        final error = ReadiumError.fromJson(json);

        expect(error.message, equals('Minimal error'));
        expect(error.code, isNull);
        expect(error.data, isNull);
      });
    });

    group('toJson', () {
      test('serializes error to JSON', () {
        final error = ReadiumError(
          'Serialized error',
          code: 'SER_001',
          data: {'info': 'test'},
        );

        final json = error.toJson();

        expect(json['message'], equals('Serialized error'));
        expect(json['code'], equals('SER_001'));
        expect(json.containsKey('data'), isTrue);
        expect(json.containsKey('stackTrace'), isTrue);
      });

      test('omits null code and data from JSON', () {
        final error = ReadiumError('Simple error');

        final json = error.toJson();

        expect(json['message'], equals('Simple error'));
        expect(json.containsKey('code'), isFalse);
        expect(json.containsKey('data'), isFalse);
      });
    });

    group('equality', () {
      test('equal errors are equal', () {
        final error1 = ReadiumError('Same message', code: 'CODE');
        final error2 = ReadiumError('Same message', code: 'CODE');

        expect(error1, equals(error2));
        expect(error1.hashCode, equals(error2.hashCode));
      });

      test('different errors are not equal', () {
        final error1 = ReadiumError('Message 1', code: 'CODE1');
        final error2 = ReadiumError('Message 2', code: 'CODE2');

        expect(error1, isNot(equals(error2)));
      });
    });

    group('toString', () {
      test('returns formatted string', () {
        final error = ReadiumError('Test error', code: 'TEST');

        final str = error.toString();

        expect(str, contains('ReadiumError'));
        expect(str, contains('Test error'));
        expect(str, contains('TEST'));
      });
    });
  });

  group('PlatformExceptionCodeExtension', () {
    test('intCode parses numeric code', () {
      final exception = PlatformException(code: '404');

      expect(exception.intCode, equals(404));
    });

    test('intCode returns null for non-numeric code', () {
      final exception = PlatformException(code: 'notFound');

      expect(exception.intCode, isNull);
    });

    test('intCode returns null for empty code', () {
      final exception = PlatformException(code: '');

      expect(exception.intCode, isNull);
    });
  });
}
