/// The operator in a comparison matcher.
enum PredicateOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

/// The operator in a string matcher.
enum PredicateStringOperator {
  beginsWith,
  contains,
  endsWith,
  equals
}


abstract class PredicateExpression {
  PredicateExpression get inverse;
}

class ComparisonExpression implements PredicateExpression {
  const ComparisonExpression(this.value, this.operator);

  final dynamic value;
  final PredicateOperator operator;

  @override
  PredicateExpression get inverse {
    return new ComparisonExpression(value, inverseOperator);
  }

  PredicateOperator get inverseOperator {
    switch (operator) {
      case PredicateOperator.lessThan:
        return PredicateOperator.greaterThanEqualTo;
      case PredicateOperator.greaterThan:
        return PredicateOperator.lessThanEqualTo;
      case PredicateOperator.notEqual:
        return PredicateOperator.equalTo;
      case PredicateOperator.lessThanEqualTo:
        return PredicateOperator.greaterThan;
      case PredicateOperator.greaterThanEqualTo:
        return PredicateOperator.lessThan;
      case PredicateOperator.equalTo:
        return PredicateOperator.notEqual;
    }

    // this line just shuts up the analyzer
    return null;
  }
}

class RangeExpression implements PredicateExpression {
  const RangeExpression(this.lhs, this.rhs, this.within);

  final bool within;
  final dynamic lhs, rhs;

  @override
  PredicateExpression get inverse {
    return new RangeExpression(lhs, rhs, !within);
  }
}

class NullCheckExpression implements PredicateExpression {
  const NullCheckExpression(this.shouldBeNull);

  final bool shouldBeNull;

  @override
  PredicateExpression get inverse {
    return new NullCheckExpression(!shouldBeNull);
  }
}

class SetMembershipExpression implements PredicateExpression {
  const SetMembershipExpression(this.values, {this.within: true});

  final List<dynamic> values;
  final bool within;

  @override
  PredicateExpression get inverse {
    return new SetMembershipExpression(values, within: !within);
  }
}

class StringExpression implements PredicateExpression {
  const StringExpression(this.value, this.operator, {this.caseSensitive: true, this.invertOperator: false});

  final PredicateStringOperator operator;
  final bool invertOperator;
  final bool caseSensitive;
  final String value;

  @override
  PredicateExpression get inverse {
    return new StringExpression(value, operator, caseSensitive: caseSensitive, invertOperator: !invertOperator);
  }
}
