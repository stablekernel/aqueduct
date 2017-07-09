/// The operator in a comparison matcher.
enum MatcherOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

/// The operator in a string matcher.
enum StringMatcherOperator {
  beginsWith,
  contains,
  endsWith,
  equals
}


abstract class MatcherExpression {
  MatcherExpression get inverse;
}

class ComparisonMatcherExpression implements MatcherExpression {
  const ComparisonMatcherExpression(this.value, this.operator);

  final dynamic value;
  final MatcherOperator operator;

  @override
  MatcherExpression get inverse {
    return new ComparisonMatcherExpression(value, inverseOperator);
  }

  MatcherOperator get inverseOperator {
    switch (operator) {
      case MatcherOperator.lessThan:
        return MatcherOperator.greaterThanEqualTo;
      case MatcherOperator.greaterThan:
        return MatcherOperator.lessThanEqualTo;
      case MatcherOperator.notEqual:
        return MatcherOperator.equalTo;
      case MatcherOperator.lessThanEqualTo:
        return MatcherOperator.greaterThan;
      case MatcherOperator.greaterThanEqualTo:
        return MatcherOperator.lessThan;
      case MatcherOperator.equalTo:
        return MatcherOperator.notEqual;
    }

    // this line just shuts up the analyzer
    return null;
  }
}

class RangeMatcherExpression implements MatcherExpression {
  const RangeMatcherExpression(this.lhs, this.rhs, this.within);

  final bool within;
  final dynamic lhs, rhs;

  @override
  MatcherExpression get inverse {
    return new RangeMatcherExpression(lhs, rhs, !within);
  }
}

class NullMatcherExpression implements MatcherExpression {
  const NullMatcherExpression(this.shouldBeNull);

  final bool shouldBeNull;

  @override
  MatcherExpression get inverse {
    return new NullMatcherExpression(!shouldBeNull);
  }
}

class SetMembershipMatcherExpression implements MatcherExpression {
  const SetMembershipMatcherExpression(this.values, {this.within: true});

  final List<dynamic> values;
  final bool within;

  @override
  MatcherExpression get inverse {
    return new SetMembershipMatcherExpression(values, within: !within);
  }
}

class StringMatcherExpression implements MatcherExpression {
  const StringMatcherExpression(this.value, this.operator, {this.caseSensitive: true, this.invertOperator: false});

  final StringMatcherOperator operator;
  final bool invertOperator;
  final bool caseSensitive;
  final String value;

  @override
  MatcherExpression get inverse {
    return new StringMatcherExpression(value, operator, caseSensitive: caseSensitive, invertOperator: !invertOperator);
  }
}
