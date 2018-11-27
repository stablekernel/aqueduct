abstract class AbstractUnaryNode<E> {
  final E operand;
  const AbstractUnaryNode(this.operand);
}

abstract class AbstractBinaryNode<E> extends AbstractUnaryNode<E> {
  final E operand2;
  const AbstractBinaryNode(E operand, this.operand2): super(operand);
}

abstract class UnaryOperatorNode<E, O> extends AbstractUnaryNode<E> {
  final O operator;
  const UnaryOperatorNode(E lhs, this.operator) : super(lhs);
}

abstract class BinaryOperatorNode<E, O> extends AbstractBinaryNode<E> {
  final O operator;
  const BinaryOperatorNode(E lhs, E rhs, this.operator) : super(lhs, rhs);
}

abstract class LogicalOperatorNode<E> extends BinaryOperatorNode<E, LogicalOperator> {
  const LogicalOperatorNode(E lhs, E rhs, LogicalOperator operator) : super(lhs, rhs, operator);
}

abstract class ComparisonUnaryNode<E> extends UnaryOperatorNode<E, ComparisonOperator> {
  const ComparisonUnaryNode(E lhs, ComparisonOperator operator) : super(lhs, operator);
}

enum LogicalOperator { and, or }

/// The operator in a comparison matcher.
enum ComparisonOperator {
  lessThan,
  greaterThan,
  notEqual,
  lessThanEqualTo,
  greaterThanEqualTo,
  equalTo
}

/// The operator in a string matcher.
enum StringComparisonOperator { beginsWith, contains, endsWith, equals }

abstract class PredicateExpression {
  PredicateExpression get inverse;
}

class ComparisonExpression<E> extends ComparisonUnaryNode<E> implements PredicateExpression {
  const ComparisonExpression(E value, ComparisonOperator operator): super(value, operator);

  @override
  PredicateExpression get inverse {
    return ComparisonExpression(operand, inverseOperator);
  }

  ComparisonOperator get inverseOperator {
    switch (operator) {
      case ComparisonOperator.lessThan:
        return ComparisonOperator.greaterThanEqualTo;
      case ComparisonOperator.greaterThan:
        return ComparisonOperator.lessThanEqualTo;
      case ComparisonOperator.notEqual:
        return ComparisonOperator.equalTo;
      case ComparisonOperator.lessThanEqualTo:
        return ComparisonOperator.greaterThan;
      case ComparisonOperator.greaterThanEqualTo:
        return ComparisonOperator.lessThan;
      case ComparisonOperator.equalTo:
        return ComparisonOperator.notEqual;
    }

    // this line just shuts up the analyzer
    return null;
  }
}

enum RangeOperator {
  between,
  notBetween
}

class RangeExpression<E> extends BinaryOperatorNode<E, RangeOperator> implements PredicateExpression {
  const RangeExpression(E operand, E operand2, {RangeOperator scope = RangeOperator.between}): super(operand, operand2, scope);

  @override
  PredicateExpression get inverse {
    final inverseOperator = operator == RangeOperator.between
        ? RangeOperator.notBetween
        : RangeOperator.between;
    return RangeExpression(operand, operand2, scope: inverseOperator);
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

  final StringComparisonOperator operator;
  final bool invertOperator;
  final bool caseSensitive;

  @override
  PredicateExpression get inverse {
    return StringExpression(operand, operator,
        caseSensitive: caseSensitive, invertOperator: !invertOperator);
  }
}

abstract class Tree<E> {}

class LeafNode<E> implements Tree<E> {
 E value;
 LeafNode(this.value);
}

class AndNode<E> extends LogicalOperatorNode<Tree<E>> implements Tree<E> {
  const AndNode(Tree<E> lhs, Tree<E> rhs)
      : super(lhs, rhs, LogicalOperator.and);
}

class OrNode<E> extends LogicalOperatorNode<Tree<E>> implements Tree<E> {
  const OrNode(Tree<E> lhs, Tree<E> rhs)
      : super(lhs, rhs, LogicalOperator.or);
}
