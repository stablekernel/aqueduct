import 'package:aqueduct/src/db/managed/managed.dart';

enum ValidateType { regex, comparison, length, present, absent, oneOf }

enum ValidationOperator {
  equalTo,
  lessThan,
  lessThanEqualTo,
  greaterThan,
  greaterThanEqualTo
}

class ValidationExpression {
  ValidationExpression(this.operator, this.value);

  final ValidationOperator operator;
  dynamic value;

  void compare(ValidationContext context, dynamic input) {
    final comparisonValue = value as Comparable;

    switch (operator) {
      case ValidationOperator.equalTo:
        {
          if (comparisonValue.compareTo(input) != 0) {
            context.addError("must be equal to '$comparisonValue'.");
          }
        }
        break;
      case ValidationOperator.greaterThan:
        {
          if (comparisonValue.compareTo(input) >= 0) {
            context.addError("must be greater than '$comparisonValue'.");
          }
        }
        break;

      case ValidationOperator.greaterThanEqualTo:
        {
          if (comparisonValue.compareTo(input) > 0) {
            context.addError(
              "must be greater than or equal to '$comparisonValue'.");
          }
        }
        break;

      case ValidationOperator.lessThan:
        {
          if (comparisonValue.compareTo(input) <= 0) {
            context.addError("must be less than to '$comparisonValue'.");
          }
        }
        break;
      case ValidationOperator.lessThanEqualTo:
        {
          if (comparisonValue.compareTo(input) < 0) {
            context
              .addError("must be less than or equal to '$comparisonValue'.");
          }
        }
        break;
    }
  }
}