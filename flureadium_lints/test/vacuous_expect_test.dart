import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:flureadium_lints/main.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(VacuousTypeAssertionTest);
    defineReflectiveTests(VacuousNotNullAssertionTest);
  });
}

const _matcherStub = r'''
class Matcher {
  const Matcher();
}

class TypeMatcher<T> extends Matcher {
  const TypeMatcher();

  TypeMatcher<T> having(
    Object? Function(T) feature,
    String description,
    Object? matcher,
  ) => this;
}

TypeMatcher<T> isA<T>() => TypeMatcher<T>();

const Matcher isNotNull = Matcher();

Matcher throwsA(Object? matcher) => const Matcher();

void expect(dynamic actual, dynamic matcher, {String? reason}) {}
''';

/// A package that declares its own `TypeMatcher` and `isA`, so the only guard
/// that can reject it is the `package:matcher/` library check.
const _otherMatcherStub = r'''
class TypeMatcher<T> {
  const TypeMatcher();
}

TypeMatcher<T> isA<T>() => TypeMatcher<T>();

void expect(dynamic actual, dynamic matcher) {}
''';

@reflectiveTest
class VacuousTypeAssertionTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('matcher').addFile('lib/matcher.dart', _matcherStub);
    newPackage('other').addFile('lib/other.dart', _otherMatcherStub);
    rule = VacuousTypeAssertion();
    super.setUp();
  }

  Future<void> test_identicalType_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(List<String> values) {
  expect(values, isA<List<String>>());
}
''',
      [lint(87, 19)],
    );
  }

  Future<void> test_subtype_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(List<String> values) {
  expect(values, isA<List<Object>>());
}
''',
      [lint(87, 19)],
    );
  }

  Future<void> test_supertype_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(List<String> values) {
  expect(values, isA<Object>());
}
''',
      [lint(87, 13)],
    );
  }

  Future<void> test_bareIsA_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(int value) {
  expect(value, isA());
}
''',
      [lint(76, 5)],
    );
  }

  Future<void> test_dynamicTarget_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(dynamic value) {
  expect(value, isA<int>());
}
''');
  }

  Future<void> test_downcast_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(num value) {
  expect(value, isA<int>());
}
''');
  }

  Future<void> test_nullableTarget_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(List<String>? values) {
  expect(values, isA<List<String>>());
}
''');
  }

  Future<void> test_havingChain_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(int value) {
  expect(value, isA<int>().having((v) => v, 'value', 1));
}
''');
  }

  Future<void> test_insideThrowsA_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f() {
  expect(() => int.parse('x'), throwsA(isA<FormatException>()));
}
''');
  }

  Future<void> test_isAFromOtherLibrary_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:other/other.dart';

void f(int value) {
  expect(value, isA<int>());
}
''');
  }

  Future<void> test_isNotNullMatcher_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(String value) {
  expect(value, isNotNull);
}
''');
  }

  Future<void> test_singleArgumentExpect_isNotFlagged() async {
    await assertNoDiagnostics(r'''
void expect(Object? actual) {}

void f(String value) {
  expect(value);
}
''');
  }

  Future<void> test_namedArgumentExpect_isNotFlagged() async {
    await assertNoDiagnostics(r'''
void expect({Object? actual, Object? matcher}) {}

void f(String value) {
  expect(actual: value, matcher: null);
}
''');
  }
}

@reflectiveTest
class VacuousNotNullAssertionTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('matcher').addFile('lib/matcher.dart', _matcherStub);
    rule = VacuousNotNullAssertion();
    super.setUp();
  }

  Future<void> test_nonNullableTarget_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(String value) {
  expect(value, isNotNull);
}
''',
      [lint(79, 9)],
    );
  }

  Future<void> test_promotedTarget_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(String? value) {
  if (value == null) return;
  expect(value, isNotNull);
}
''',
      [lint(109, 9)],
    );
  }

  Future<void> test_reasonArgument_isFlagged() async {
    await assertDiagnostics(
      r'''
import 'package:matcher/matcher.dart';

void f(String value) {
  expect(value, isNotNull, reason: 'must exist');
}
''',
      [lint(79, 9)],
    );
  }

  Future<void> test_nullableTarget_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(String? value) {
  expect(value, isNotNull);
}
''');
  }

  Future<void> test_dynamicTarget_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(dynamic value) {
  expect(value, isNotNull);
}
''');
  }

  Future<void> test_methodNamedExpect_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

class Helper {
  void expect(Object? actual, Object? matcher) {}
}

void f(Helper helper, String value) {
  helper.expect(value, isNotNull);
}
''');
  }

  Future<void> test_isAMatcher_isNotFlagged() async {
    await assertNoDiagnostics(r'''
import 'package:matcher/matcher.dart';

void f(int value) {
  expect(value, isA<int>());
}
''');
  }
}
