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
enum PredicateStringOperator { beginsWith, contains, endsWith, equals }

abstract class PredicateExpression {
  PredicateExpression get inverse;
}

class ComparisonExpression implements PredicateExpression {
  const ComparisonExpression(this.value, this.operator);

  final dynamic value;
  final PredicateOperator operator;

  @override
  PredicateExpression get inverse {
    return ComparisonExpression(value, inverseOperator);
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
  const RangeExpression(this.lhs, this.rhs, {this.within = true});

  final bool within;
  final dynamic lhs, rhs;

  @override
  PredicateExpression get inverse {
    return RangeExpression(lhs, rhs, within: !within);
  }
}

class NullCheckExpression implements PredicateExpression {
  const NullCheckExpression({this.shouldBeNull = true});

  final bool shouldBeNull;

  @override
  PredicateExpression get inverse {
    return NullCheckExpression(shouldBeNull: !shouldBeNull);
  }
}

class SetMembershipExpression implements PredicateExpression {
  const SetMembershipExpression(this.values, {this.within = true});

  final List<dynamic> values;
  final bool within;

  @override
  PredicateExpression get inverse {
    return SetMembershipExpression(values, within: !within);
  }
}

class StringExpression implements PredicateExpression {
  const StringExpression(this.value, this.operator,
    {this.caseSensitive = true, this.invertOperator = false, this.allowSpecialCharacters = true});

  final PredicateStringOperator operator;
  final bool invertOperator;
  final bool caseSensitive;
  final bool allowSpecialCharacters;
  final String value;

  @override
  PredicateExpression get inverse {
    return StringExpression(value, operator,
      caseSensitive: caseSensitive, invertOperator: !invertOperator, allowSpecialCharacters: allowSpecialCharacters);
  }
}
