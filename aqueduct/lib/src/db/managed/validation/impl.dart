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

  static List<ValidationExpression> comparisons(
      dynamic _equalTo,
      dynamic _lessThan,
      dynamic _lessThanEqualTo,
      dynamic _greaterThan,
      dynamic _greaterThanEqualTo) {
    final comparisons = <ValidationExpression>[];
    if (_equalTo != null) {
      comparisons
          .add(ValidationExpression(ValidationOperator.equalTo, _equalTo));
    }
    if (_lessThan != null) {
      comparisons
          .add(ValidationExpression(ValidationOperator.lessThan, _lessThan));
    }
    if (_lessThanEqualTo != null) {
      comparisons.add(ValidationExpression(
          ValidationOperator.lessThanEqualTo, _lessThanEqualTo));
    }
    if (_greaterThan != null) {
      comparisons.add(
          ValidationExpression(ValidationOperator.greaterThan, _greaterThan));
    }
    if (_greaterThanEqualTo != null) {
      comparisons.add(ValidationExpression(
          ValidationOperator.greaterThanEqualTo, _greaterThanEqualTo));
    }

    return comparisons;
  }

  final ValidationOperator operator;
  dynamic value;

  void compare(ValidationContext context, dynamic input) {
    Comparable comparisonValue = value;

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

class DefaultValidator extends ManagedValidator {
  DefaultValidator(ManagedAttributeDescription attribute, Validate validate)
      : super(attribute, validate);
}

class LengthValidator extends ManagedValidator {
  LengthValidator(ManagedAttributeDescription attribute, Validate validate,
      this.expressions)
      : super(attribute, validate) {
    expressions.forEach((expr) {
      expr.value = parse(expr.value);
    });
  }

  final List<ValidationExpression> expressions;

  @override
  void validate(ValidationContext context, dynamic value) {
    if (value is! String) {
      context.addError("unexpected value type");
      return;
    }

    expressions
        .forEach((expr) => expr.compare(context, (value as String).length));
  }

  int parse(dynamic referenceValue) {
    if (attribute.type.kind != ManagedPropertyType.string) {
      throw ManagedDataModelError.invalidValidator(attribute.entity,
          attribute.name, "Validate.length must annotate 'String' property.");
    }

    if (referenceValue is! int) {
      throw ManagedDataModelError.invalidValidator(attribute.entity,
          attribute.name, "Validate.length reference values must be integers");
    }

    return referenceValue as int;
  }
}

class RegexValidator extends ManagedValidator {
  RegexValidator(
      ManagedAttributeDescription attribute, Validate validate, dynamic value)
      : super(attribute, validate) {
    if (attribute.type.kind != ManagedPropertyType.string) {
      throw ManagedDataModelError.invalidValidator(attribute.entity,
          attribute.name, "Property type for Validate.matches must be String");
    }

    if (value is! String) {
      throw ManagedDataModelError.invalidValidator(attribute.entity,
          attribute.name, "Expression in annotation is not a String.");
    }

    expression = RegExp(value as String);
  }

  RegExp expression;

  @override
  void validate(ValidationContext context, dynamic value) {
    if (!expression.hasMatch(value as String)) {
      context.addError("does not match pattern ${expression.pattern}");
    }
  }
}

class ComparisonValidator extends ManagedValidator {
  ComparisonValidator(ManagedAttributeDescription attribute, Validate validate,
      this.expressions)
      : super(attribute, validate) {
    expressions.forEach((expr) {
      expr.value = parse(expr.value);
    });
  }

  final List<ValidationExpression> expressions;

  @override
  void validate(ValidationContext context, dynamic value) {
    if (value.runtimeType != value.runtimeType) {
      context.addError("unexpected value type");
      return;
    }

    expressions.forEach((expr) => expr.compare(context, value));
  }

  Comparable parse(dynamic referenceValue) {
    if (attribute.type.kind == ManagedPropertyType.datetime) {
      if (referenceValue is String) {
        try {
          return DateTime.parse(referenceValue);
        } on FormatException {
          throw ManagedDataModelError.invalidValidator(
              attribute.entity,
              attribute.name,
              "'$referenceValue' cannot be parsed as DateTime, or is not a String.");
        }
      }

      throw ManagedDataModelError.invalidValidator(
          attribute.entity,
          attribute.name,
          "'$referenceValue' cannot be parsed as DateTime, or is not a String.");
    }

    if (!attribute.isAssignableWith(referenceValue)) {
      throw ManagedDataModelError.invalidValidator(
          attribute.entity,
          attribute.name,
          "'$referenceValue' is not assignable to property type.");
    }

    return referenceValue as Comparable;
  }
}

class OneOfValidator extends ManagedValidator {
  OneOfValidator(
      ManagedAttributeDescription attribute, Validate validate, dynamic value)
      : super(attribute, validate) {
    if (value is! List) {
      throw ManagedDataModelError.invalidValidator(
          attribute.entity,
          attribute.name,
          "Validate.oneOf value must be a List, where each element matches the type of the decorated attribute.");
    }

    options = value as List;
    if (options.any((v) => !attribute.isAssignableWith(v))) {
      throw ManagedDataModelError.invalidValidator(
          attribute.entity,
          attribute.name,
          "Validate.oneOf value must be a List, where each element matches the type of the decorated attribute.");
    }

    final supportedOneOfTypes = [
      ManagedPropertyType.string,
      ManagedPropertyType.integer,
      ManagedPropertyType.bigInteger
    ];
    if (!supportedOneOfTypes.contains(attribute.type.kind)) {
      throw ManagedDataModelError.invalidValidator(
          attribute.entity,
          attribute.name,
          "Validate.oneOf is only valid for String or int types.");
    }
    if (options.isEmpty) {
      throw ManagedDataModelError.invalidValidator(attribute.entity,
          attribute.name, "Validate.oneOf must have at least one element");
    }
  }

  List<dynamic> options;

  @override
  void validate(ValidationContext context, dynamic value) {
    if (options.every((v) => value != v)) {
      context
          .addError("must be one of: ${options.map((v) => "'$v'").join(",")}.");
    }
  }
}

class PresentValidator extends ManagedValidator {
  PresentValidator(ManagedAttributeDescription attribute, Validate validate)
      : super(attribute, validate);

  @override
  void validate(ValidationContext context, dynamic value) {
    throw StateError("PresentValidator.validate ran unexpectedly.");
  }
}

class AbsentValidator extends ManagedValidator {
  AbsentValidator(ManagedAttributeDescription attribute, Validate validate)
      : super(attribute, validate);

  @override
  void validate(ValidationContext context, dynamic value) {
    throw StateError("AbsentValidator.validate ran unexpectedly.");
  }
}
