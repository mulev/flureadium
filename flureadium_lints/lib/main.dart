import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

final plugin = FlureadiumLintsPlugin();

class FlureadiumLintsPlugin extends Plugin {
  @override
  String get name => 'flureadium_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerLintRule(VacuousTypeAssertion())
      ..registerLintRule(VacuousNotNullAssertion());
  }
}

/// Flags `expect(x, isA<T>())` where `x`'s static type is already a subtype
/// of `T`, so the matcher cannot fail.
class VacuousTypeAssertion extends AnalysisRule {
  static const LintCode code = LintCode(
    'vacuous_type_assertion',
    "This 'isA' check cannot fail: the value's static type is already the "
        'asserted type.',
    correctionMessage: 'Assert the value the test names instead.',
  );

  VacuousTypeAssertion()
    : super(
        name: 'vacuous_type_assertion',
        description: 'An isA check on a statically known type cannot fail.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _TypeVisitor(this, context));
  }
}

/// Flags `expect(x, isNotNull)` where `x`'s static type is non-nullable.
class VacuousNotNullAssertion extends AnalysisRule {
  static const LintCode code = LintCode(
    'vacuous_not_null_assertion',
    "This 'isNotNull' check cannot fail: the value's static type is "
        'non-nullable.',
    correctionMessage: 'Assert the value the test names instead.',
  );

  VacuousNotNullAssertion()
    : super(
        name: 'vacuous_not_null_assertion',
        description: 'An isNotNull check on a non-nullable type cannot fail.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _NotNullVisitor(this, context));
  }
}

/// The `actual` and `matcher` arguments of an `expect(actual, matcher)` call,
/// or `null` when [node] is not such a call.
({Expression actual, Expression matcher})? _expectArguments(
  MethodInvocation node,
) {
  if (node.methodName.name != 'expect') return null;
  // Only the top-level `expect` from package:matcher takes an actual and a
  // matcher. An instance member, an extension member or `helper.expect(...)`
  // is some other object's method, whatever it is called, and its arguments
  // mean nothing to these rules.
  if (node.methodName.element is! TopLevelFunctionElement) return null;
  final arguments = node.argumentList.arguments;
  if (arguments.length < 2) return null;
  final actual = arguments[0];
  final matcher = arguments[1];
  if (actual is NamedExpression || matcher is NamedExpression) return null;

  return (actual: actual, matcher: matcher);
}

class _TypeVisitor extends SimpleAstVisitor<void> {
  _TypeVisitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = _expectArguments(node);
    if (arguments == null) return;
    final actualType = arguments.actual.staticType;
    if (actualType == null) return;
    final matcher = arguments.matcher;
    if (matcher is! MethodInvocation) return;
    if (matcher.methodName.name != 'isA' || matcher.target != null) return;
    final matcherType = matcher.staticType;
    if (matcherType is! InterfaceType) return;
    if (matcherType.element.name != 'TypeMatcher') return;
    final matcherLibraryUri = matcherType.element.library.uri.toString();
    if (!matcherLibraryUri.startsWith('package:matcher/')) return;
    final typeArguments = matcherType.typeArguments;
    if (typeArguments.length != 1) return;
    if (context.typeSystem.isSubtypeOf(actualType, typeArguments.single)) {
      rule.reportAtNode(matcher);
    }
  }
}

class _NotNullVisitor extends SimpleAstVisitor<void> {
  _NotNullVisitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final arguments = _expectArguments(node);
    if (arguments == null) return;
    final actualType = arguments.actual.staticType;
    if (actualType == null) return;
    final matcher = arguments.matcher;
    if (matcher is! SimpleIdentifier || matcher.name != 'isNotNull') return;
    final matcherType = matcher.staticType;
    if (matcherType is! InterfaceType) return;
    final matcherLibraryUri = matcherType.element.library.uri.toString();
    if (!matcherLibraryUri.startsWith('package:matcher/')) return;
    if (!context.typeSystem.isNullable(actualType)) {
      rule.reportAtNode(matcher);
    }
  }
}
