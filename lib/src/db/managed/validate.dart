import '../db.dart';

enum ValidateOperation { update, insert }

enum _BuiltinValidate { regex, comparison, length, present, absent, oneOf }

class Validate<T> {
  static bool run(
      ManagedObject object, {ValidateOperation operation, List<String> errors}) {
    errors ??= [];

    var valid = true;
    var validators = object.entity.validators;
    validators.forEach((propertyKey, validators) {
      if (validators.isEmpty) {
        return;
      }

      var value = object.backingMap[propertyKey.name];
      validators.forEach((v) {
        if (v._builtinValidate == _BuiltinValidate.absent) {
          if (object.backingMap.containsKey(propertyKey.name)) {
            errors.add("Value for '${propertyKey.name}' may not be included for ${_errorStringForOperation(operation)}s.");
            valid = false;
          }
        } else if (v._builtinValidate == _BuiltinValidate.present) {
          if (!object.backingMap.containsKey(propertyKey.name)) {
            errors.add("Value for '${propertyKey.name}' must be included for ${_errorStringForOperation(operation)}s.");
            valid = false;
          }

        } else if (value != null) {
          if (!v.validate(operation, propertyKey, value, errors)) {
            valid = false;
          }
        }
      });
    });

    return valid;
  }

  static String _errorStringForOperation(ValidateOperation op) {
    if (op == ValidateOperation.insert) {
      return "insert";
    } else if (op == ValidateOperation.update) {
      return "update";
    }

    return "unknown";
  }

  const Validate({bool onUpdate, bool onInsert})
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
      {bool onUpdate,
      bool onInsert,
      _BuiltinValidate validator,
        dynamic value,
        List<dynamic> values,
        Comparable greaterThan,
        dynamic greaterThanEqualTo,
        num equalTo,
        num lessThan,
        num lessThanEqualTo
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
      {dynamic lessThan,
       dynamic greaterThan,
        dynamic equalTo,
        dynamic greaterThanEqualTo,
        dynamic lessThanEqualTo,
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
      {num lessThan,
      num greaterThan,
      num equalTo,
      num greaterThanEqualTo,
      num lessThanEqualTo,
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
  final num _greaterThan;
  final num _greaterThanEqualTo;
  final num _equalTo;
  final num _lessThan;
  final num _lessThanEqualTo;
  final _BuiltinValidate _builtinValidate;

  bool validate(ValidateOperation operation, ManagedAttributeDescription property, T value, List<String> errors) {
    switch (_builtinValidate) {
      case _BuiltinValidate.oneOf:
        return _validateOneOf(operation, property, value, errors);
      case _BuiltinValidate.regex:
        return _validateMatches(operation, property, value as String, errors);
      case _BuiltinValidate.length:
        return _validateLength(operation, property, value as String, errors);
      case _BuiltinValidate.comparison:
        return _validateComparison(operation, property, value as Comparable, errors);
      default:
        return true;
    }
  }

  bool _validateOneOf(
      ValidateOperation operation, ManagedAttributeDescription property, dynamic value, List<String> errors) {
    if (!_values.any((v) => value == v)) {
      errors.add("The value for '${property.name}' is invalid. Must be one of: ${_values.map((v) => "'$v'").join(",")}.");
      return false;
    }

    return true;
  }

  bool _validateLength(
      ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
    if (_greaterThan != null) {
      if (value.length <= _greaterThan) {
        errors.add("The value for '${property.name}' is invalid. Must have length greater than '$_greaterThan'.");
        return false;
      }
    }

    if (_greaterThanEqualTo != null) {
      if (value.length < _greaterThanEqualTo) {
        errors.add("The value for '${property.name}' is invalid. Must have length greater than or equal to '$_greaterThanEqualTo'.");
        return false;
      }
    }

    if (_lessThan != null) {
      if (value.length < _lessThan) {
        errors.add("The value for '${property.name}' is invalid. Must have length less than '$_lessThan'.");
        return false;
      }
    }

    if (_lessThanEqualTo != null) {
      if (value.length < _lessThanEqualTo) {
        errors.add("The value for '${property.name}' is invalid. Must have length less than or equal to '$_lessThanEqualTo'.");
        return false;
      }
    }

    if (_equalTo != null) {
      if (value.length != _equalTo) {
        errors.add("The value for '${property.name}' is invalid. Must have length equal to '$_equalTo'.");
        return false;
      }
    }

    return true;
  }

  bool _validateComparison(
      ValidateOperation operation, ManagedAttributeDescription property, Comparable value, List<String> errors) {
    if (_greaterThan != null) {
      if (value.compareTo(_greaterThan) <= 0) {
        errors.add("The value for '${property.name}' is invalid. Must be greater than '$_greaterThan'.");
        return false;
      }
    }

    if (_greaterThanEqualTo != null) {
      if (value.compareTo(_greaterThanEqualTo) < 0) {
        errors.add("The value for '${property.name}' is invalid. Must be greater than or equal to '$_greaterThanEqualTo'.");
        return false;
      }
    }

    if (_lessThan != null) {
      if (value.compareTo(_lessThan) >= 0) {
        errors.add("The value for '${property.name}' is invalid. Must be less than '$_lessThan'.");
        return false;
      }
    }

    if (_lessThanEqualTo != null) {
      if (value.compareTo(_lessThanEqualTo) > 0) {
        errors.add("The value for '${property.name}' is invalid. Must be less than or equal to '$_lessThanEqualTo'.");
        return false;
      }
    }

    if (_equalTo != null) {
      if (value.compareTo(_equalTo) != 0) {
        errors.add("The value for '${property.name}' is invalid. Must be equal to '$_equalTo'.");
        return false;
      }
    }

    return true;
  }

  bool _validateMatches(
      ValidateOperation operation, ManagedAttributeDescription property, String value, List<String> errors) {
    var regex = new RegExp(_value);

    if (!regex.hasMatch(value)) {
      errors.add("The value for '${property.name}' is invalid. Must match pattern ${regex.pattern}.");
      return false;
    }

    return true;
  }
}
