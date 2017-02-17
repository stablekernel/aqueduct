import 'query.dart';

abstract class MatcherExpression {}

class ComparisonMatcherExpression implements MatcherExpression {
  const ComparisonMatcherExpression(this.value, this.operator);

  final dynamic value;
  final MatcherOperator operator;
}

class RangeMatcherExpression implements MatcherExpression {
  const RangeMatcherExpression(this.lhs, this.rhs, this.within);

  final bool within;
  final dynamic lhs, rhs;
}

class NullMatcherExpression implements MatcherExpression {
  const NullMatcherExpression(this.shouldBeNull);

  final bool shouldBeNull;
}

class WithinMatcherExpression implements MatcherExpression {
  WithinMatcherExpression(this.values);

  List<dynamic> values;
}

class StringMatcherExpression implements MatcherExpression {
  StringMatcherExpression(this.value, this.operator, {this.caseSensitive});

  StringMatcherOperator operator;
  bool caseSensitive;
  String value;
}
