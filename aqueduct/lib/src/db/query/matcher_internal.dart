abstract class AbstractUnaryNode<E> {
  final E operand;
  const AbstractUnaryNode(this.operand);
}

abstract class AbstractBinaryNode<E> extends AbstractUnaryNode<E> {
  final E operand2;
  const AbstractBinaryNode(E operand, this.operand2): super(operand);
}

abstract class AbstractLeaf {}

abstract class PredicateExpressionLeaf<E> {}

abstract class UnaryOperantNode<E, O> extends AbstractUnaryNode<E> {
  final O operant;

  const UnaryOperantNode(E lhs, this.operant) : super(lhs);
}

abstract class BinaryOperantNode<E, O> extends AbstractBinaryNode<E> {
  final O operant;

  const BinaryOperantNode(E lhs, E rhs, this.operant) : super(lhs, rhs);
}

abstract class ComparisonBinaryNode<E> extends BinaryOperantNode<E, ComparisonOperant> {
  const ComparisonBinaryNode(E lhs, E rhs, ComparisonOperant operant) : super(lhs, rhs, operant);
}

abstract class StringComparisonOperantNode<String> extends BinaryOperantNode<String, StringComparisonOperant> {
  StringComparisonOperantNode(String lhs, String rhs, StringComparisonOperant operant) : super(lhs, rhs, operant);
}

abstract class LogicalOperantNode<E> extends BinaryOperantNode<E, LogicalOperant> {
  const LogicalOperantNode(E lhs, E rhs, LogicalOperant operant) : super(lhs, rhs, operant);
}

abstract class ComparisonUnaryNode<E> extends UnaryOperantNode<E, ComparisonOperant> {
  const ComparisonUnaryNode(E lhs, ComparisonOperant operant) : super(lhs, operant);
}

enum LogicalOperant { and, or }

/// The operator in a comparison matcher.
enum ComparisonOperant {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

/// The operator in a string matcher.
enum StringComparisonOperant { beginsWith, contains, endsWith, equals }

abstract class PredicateExpression {
  PredicateExpression get inverse;
}

class ComparisonExpression<E> extends ComparisonUnaryNode<E> implements PredicateExpression {
  const ComparisonExpression(E value, ComparisonOperant operant): super(value, operant);

  @override
  PredicateExpression get inverse {
    return ComparisonExpression(operand, inverseOperator);
  }

  ComparisonOperant get inverseOperator {
    switch (operant) {
      case ComparisonOperant.lessThan:
        return ComparisonOperant.greaterThanEqualTo;
      case ComparisonOperant.greaterThan:
        return ComparisonOperant.lessThanEqualTo;
      case ComparisonOperant.notEqual:
        return ComparisonOperant.equalTo;
      case ComparisonOperant.lessThanEqualTo:
        return ComparisonOperant.greaterThan;
      case ComparisonOperant.greaterThanEqualTo:
        return ComparisonOperant.lessThan;
      case ComparisonOperant.equalTo:
        return ComparisonOperant.notEqual;
    }

    // this line just shuts up the analyzer
    return null;
  }
}

enum RangeOperant {
  between,
  notBetween
}

class RangeExpression<E> extends BinaryOperantNode<E, RangeOperant> implements PredicateExpression {
  const RangeExpression(E operand, E operand2, {RangeOperant scope = RangeOperant.between}): super(operand, operand2, scope);

  @override
  PredicateExpression get inverse {
    final inverseOperant = operant == RangeOperant.between
        ? RangeOperant.notBetween
        : RangeOperant.between;
    return RangeExpression(operand, operand2, scope: inverseOperant);
  }
}

class NullCheckExpression extends AbstractUnaryNode<bool> implements PredicateExpression {
  const NullCheckExpression({bool shouldBeNull = true}): super(shouldBeNull);

  @override
  PredicateExpression get inverse {
    return NullCheckExpression(shouldBeNull: !operand);
  }
}

class SetMembershipExpression<E> extends AbstractUnaryNode<List<E>> implements PredicateExpression {
  const SetMembershipExpression(List<E> values, {this.within = true}): super(values);

  final bool within;

  @override
  PredicateExpression get inverse {
    return SetMembershipExpression(operand, within: !within);
  }
}

class StringExpression extends AbstractUnaryNode<String> implements PredicateExpression {
  const StringExpression(String value, this.operator,
      {this.caseSensitive = true, this.invertOperator = false}): super(value);

  final StringComparisonOperant operator;
  final bool invertOperator;
  final bool caseSensitive;

  @override
  PredicateExpression get inverse {
    return StringExpression(operand, operator,
        caseSensitive: caseSensitive, invertOperator: !invertOperator);
  }
}

class AndExpression<E> extends LogicalOperantNode<E> implements PredicateExpression {
  const AndExpression(E lhs, E rhs, {this.isGrouped = false})
      : super(lhs, rhs, LogicalOperant.and);

  final bool isGrouped;

  @override
  PredicateExpression get inverse {
    return RangeExpression(operand, operand2);
  }
}

class OrExpression<E> extends LogicalOperantNode<E> implements PredicateExpression {
  const OrExpression(E lhs, E rhs, {this.isGrouped = false})
      : super(lhs, rhs, LogicalOperant.or);

  final bool isGrouped;

  @override
  PredicateExpression get inverse {
    return RangeExpression(operand, operand2);
  }
}
