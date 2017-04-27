import '../db.dart';

typedef bool _Validation(ValidateOperation operation, ManagedAttributeDescription property, dynamic value, List<String> errors);

enum ValidateOperation { update, insert }

enum _BuiltinValidate { regex, comparison, length, present, absent, oneOf }

class ManagedValidator {
  static bool validate(
      ManagedObject object, {ValidateOperation operation: ValidateOperation.insert, List<String> errors}) {
    errors ??= [];

    var valid = true;
    var validators = object.entity.validators;
    validators.forEach((validator) {
      if (!validator.definition.runOnInsert && operation == ValidateOperation.insert) {
        return;
      }

      if (!validator.definition.runOnUpdate && operation == ValidateOperation.update) {
        return;
      }

      if (validator.definition._builtinValidate == _BuiltinValidate.absent) {
        if (object.backingMap.containsKey(validator.attribute.name)) {
          valid = false;

          errors.add("Value for '${validator.attribute.name}' may not be included "
              "for ${_errorStringForOperation(operation)}s.");
        }
      } else if (validator.definition._builtinValidate == _BuiltinValidate.present) {
        if (!object.backingMap.containsKey(validator.attribute.name)) {
          valid = false;

          errors.add("Value for '${validator.attribute.name}' must be included "
              "for ${_errorStringForOperation(operation)}s.");
        }
      } else {
        var value = object.backingMap[validator.attribute.name];
        if (value != null) {
          if (!validator._isValidFor(operation, validator.attribute, value, errors)) {
            valid = false;
          }
        }
      }
    });

    return valid;
  }

  ManagedValidator(this.attribute, this.definition) {
    if (definition._builtinValidate != null) {
      _build();
    } else {
      _validationMethod = definition.validate;
    }
  }

  final ManagedAttributeDescription attribute;
  final Validate definition;

  _Validation _validationMethod;
  RegExp _regex;
  List<_Validation> _expressionValidations;
  List<dynamic> _options;

  bool _isValidFor(ValidateOperation operation, ManagedAttributeDescription property, dynamic value, List<String> errors) {
    return _validationMethod(operation, property, value, errors);
  }

  void _build() {
    if (definition._builtinValidate == _BuiltinValidate.regex) {
      if (attribute.type != ManagedPropertyType.string) {
        throw new ManagedDataModelException.invalidValidator(
            attribute.entity, attribute.name, "Property type for Validate.matches must be String");
      }
      _regex = new RegExp(definition._value);
      _validationMethod = _validateRegex;
    } else if (definition._builtinValidate == _BuiltinValidate.comparison) {
      _buildComparisonExpressions();
      _validationMethod = _validateExpressions;
    } else if (definition._builtinValidate == _BuiltinValidate.length) {
      if (attribute.type != ManagedPropertyType.string) {
        throw new ManagedDataModelException.invalidValidator(
            attribute.entity, attribute.name, "Property type for Validate.length must be String");
      }
      _buildLengthExpressions();
      _validationMethod = _validateExpressions;
    } else if (definition._builtinValidate == _BuiltinValidate.oneOf) {
      if (definition._values.isEmpty) {
        throw new ManagedDataModelException.invalidValidator(
            attribute.entity, attribute.name, "Validate.oneOf must have at least one element");
      }
      if (definition._values.any((v) => !attribute.isAssignableWith(v))) {
        throw new ManagedDataModelException.invalidValidator(
            attribute.entity, attribute.name, "All elements of Validate.oneOf must be assignable to '${attribute.type}'");
      }
      _options = definition._values;
      _validationMethod = _validateOneOf;
    }
  }

  void _buildComparisonExpressions() {
    _expressionValidations = [];

    if (definition._greaterThan != null) {
      var comparisonValue = _comparisonValueForAttributeType(definition._greaterThan);
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
        if (value.compareTo(comparisonValue) <= 0) {
          errors.add("The value for '${property.name}' is invalid. Must be greater than '$comparisonValue'.");
          return false;
        }
      });
    }

    if (definition._greaterThanEqualTo != null) {
      var comparisonValue = _comparisonValueForAttributeType(definition._greaterThanEqualTo);
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
        if (value.compareTo(comparisonValue) < 0) {
          errors.add("The value for '${property.name}' is invalid. Must be greater than or equal to '$comparisonValue'.");
          return false;
        }
      });
    }

    if (definition._lessThan != null) {
      var comparisonValue = _comparisonValueForAttributeType(definition._lessThan);
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
        if (value.compareTo(comparisonValue) >= 0) {
          errors.add("The value for '${property.name}' is invalid. Must be less than to '$comparisonValue'.");
          return false;
        }
      });
    }

    if (definition._lessThanEqualTo != null) {
      var comparisonValue = _comparisonValueForAttributeType(definition._lessThanEqualTo);
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
        if (value.compareTo(comparisonValue) > 0) {
          errors.add("The value for '${property.name}' is invalid. Must be less than or equal to '$comparisonValue'.");
          return false;
        }
      });
    }

    if (definition._equalTo != null) {
      var comparisonValue = _comparisonValueForAttributeType(definition._equalTo);
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
        if (value.compareTo(comparisonValue) != 0) {
          errors.add("The value for '${property.name}' is invalid. Must be equal to '$comparisonValue'.");
          return false;
        }
      });
    }
  }

  void _buildLengthExpressions() {
    _expressionValidations = [];

    if (definition._greaterThan != null) {
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
        if (value.length <= definition._greaterThan) {
          errors.add("The value for '${property.name}' is invalid. Length be greater than '${definition._greaterThan}'.");
          return false;
        }
      });
    }

    if (definition._greaterThanEqualTo != null) {
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
        if (value.length < definition._greaterThanEqualTo) {
          errors.add("The value for '${property.name}' is invalid. Length must be greater than or equal to '${definition._greaterThanEqualTo}'.");
          return false;
        }
      });
    }

    if (definition._lessThan != null) {
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
        if (value.length >= definition._lessThan) {
          errors.add("The value for '${property.name}' is invalid. Length must be less than to '${definition._lessThan}'.");
          return false;
        }
      });
    }

    if (definition._lessThanEqualTo != null) {
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
        if (value.length > definition._lessThanEqualTo) {
          errors.add("The value for '${property.name}' is invalid. Length must be less than or equal to '${definition._lessThanEqualTo}'.");
          return false;
        }
      });
    }

    if (definition._equalTo != null) {
      _expressionValidations.add((ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
        if (value.length != definition._equalTo) {
          errors.add("The value for '${property.name}' is invalid. Length must be equal to '${definition._equalTo}'.");
          return false;
        }
      });
    }
  }

  dynamic  _comparisonValueForAttributeType(dynamic inputValue) {
    if (attribute.type == ManagedPropertyType.datetime) {
      try {
        return DateTime.parse(inputValue);
      } on FormatException {
        throw new ManagedDataModelException.invalidValidator(
            attribute.entity, attribute.name,
            "'$inputValue' cannot be parsed as DateTime");
      }
    }

    return inputValue;
  }

  bool _validateRegex(ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
    if (!_regex.hasMatch(value)) {
      errors.add("The value for '${property.name}' is invalid. Must match pattern ${_regex.pattern}.");
      return false;
    }

    return true;
  }

  bool _validateExpressions(ValidateOperation op, ManagedAttributeDescription property, dynamic value, List<String> errors) {
    // If any are false, then this validation failed and this returns false. Otherwise none are false and this method returns true.
    return !_expressionValidations.any((expr) => expr(op, property, value, errors) == false);
  }

  bool _validateOneOf(
      ValidateOperation operation, ManagedAttributeDescription property, dynamic value, List<String> errors) {
    if (_options.every((v) => value != v)) {
      errors.add("The value for '${property.name}' is invalid. Must be one of: ${_options.map((v) => "'$v'").join(",")}.");
      return false;
    }

    return true;
  }

  static String _errorStringForOperation(ValidateOperation op) {
    if (op == ValidateOperation.insert) {
      return "insert";
    } else if (op == ValidateOperation.update) {
      return "update";
    }

    return "unknown";
  }
}

class Validate<T> {
  const Validate({bool onUpdate: true, bool onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        this._value = null,
        this._values = null,
        this._lessThan = null,
        this._lessThanEqualTo = null,
        this._greaterThan = null,
        this._greaterThanEqualTo = null,
        this._equalTo = null,
        _builtinValidate = null;

  const Validate._(
      {bool onUpdate: true,
      bool onInsert: true,
      _BuiltinValidate validator,
        dynamic value,
        List<dynamic> values,
        Comparable greaterThan,
        Comparable greaterThanEqualTo,
        Comparable equalTo,
        Comparable lessThan,
        Comparable lessThanEqualTo
      })
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        _builtinValidate = validator,
        this._value = value,
        this._values = values,
        this._greaterThan = greaterThan,
        this._greaterThanEqualTo = greaterThanEqualTo,
        this._equalTo = equalTo,
        this._lessThan = lessThan,
        this._lessThanEqualTo = lessThanEqualTo;

  const Validate.matches(String pattern, {bool onUpdate: true, onInsert: true})
      : this._(
            value: pattern,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.regex);

  const Validate.compare(
      {Comparable lessThan,
        Comparable greaterThan,
        Comparable equalTo,
        Comparable greaterThanEqualTo,
        Comparable lessThanEqualTo,
      bool onUpdate: true,
      onInsert: true})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.comparison);

  const Validate.length(
      {int lessThan,
        int greaterThan,
        int equalTo,
        int greaterThanEqualTo,
        int lessThanEqualTo,
      bool onUpdate: true,
      onInsert: true})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.length);

  const Validate.present({bool onUpdate: true, bool onInsert: true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.present);

  const Validate.absent({bool onUpdate: true, bool onInsert: true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.absent);

  const Validate.oneOf(List<dynamic> values,
      {bool onUpdate: true, bool onInsert: true})
      : this._(
            values: values,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.oneOf);

  final bool runOnUpdate;
  final bool runOnInsert;
  final dynamic _value;
  final List<dynamic> _values;
  final Comparable _greaterThan;
  final Comparable _greaterThanEqualTo;
  final Comparable _equalTo;
  final Comparable _lessThan;
  final Comparable _lessThanEqualTo;
  final _BuiltinValidate _builtinValidate;

  bool validate(ValidateOperation operation, ManagedAttributeDescription property, T value, List<String> errors) {
    return false;
  }
}
