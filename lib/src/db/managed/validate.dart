import '../db.dart';

enum ValidateOperation { update, insert }

enum _BuiltinValidate { regex, comparison, length, present, absent, oneOf }

abstract class Validate<T> {
  static bool run(
      ManagedObject object, ValidateOperation operation, List<String> errors) {
    var entity = object.entity;
  }

  const Validate({bool onUpdate, bool onInsert})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        this.value = null,
        this.values = null,
        this.lessThan = null,
        this.lessThanEqualTo = null,
        this.greaterThan = null,
        this.greaterThanEqualTo = null,
        this.equalTo = null,
        _builtinValidate = null;

  const Validate._(
      {bool onUpdate,
      bool onInsert,
      _BuiltinValidate validator,
      this.value,
      this.values,
      this.greaterThan,
      this.greaterThanEqualTo,
      this.equalTo,
      this.lessThan,
      this.lessThanEqualTo})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        _builtinValidate = validator;

  const Validate.matches(String pattern, {bool onUpdate: true, onInsert: true})
      : this._(
            value: pattern,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.regex);

  const Validate.compare(
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

  const Validate.oneOf(List<T> values,
      {bool onUpdate: true, bool onInsert: true})
      : this._(
            values: values,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _BuiltinValidate.oneOf);

  final bool runOnUpdate;
  final bool runOnInsert;
  final dynamic value;
  final List<dynamic> values;
  final num greaterThan;
  final num greaterThanEqualTo;
  final num equalTo;
  final num lessThan;
  final num lessThanEqualTo;
  final _BuiltinValidate _builtinValidate;

  bool validate(ValidateOperation operation, String propertyName, T value, List<String> errors) {
    switch (_builtinValidate) {
      case _BuiltinValidate.oneOf:
        return _validateOneOf(operation, propertyName, value, errors);
      case _BuiltinValidate.regex:
        return _validateMatches(operation, propertyName, value as String, errors);
      case _BuiltinValidate.length:
        return _validateLength(operation, propertyName, value as String, errors);
      case _BuiltinValidate.comparison:
        return _validateComparison(operation, propertyName, value as Comparable, errors);
      default:
        return true;
    }
  }

  bool _validateOneOf(
      ValidateOperation operation, String propertyName, dynamic value, List<String> errors) {
    if (!values.any((v) => value == v)) {
      errors.add("The value for '$propertyName' is invalid. Must be one of: ${values.map((v) => "'$v'").join(",")}.");
      return false;
    }

    return true;
  }

  bool _validateLength(
      ValidateOperation operation, String propertyName, String value, List<String> errors) {
    if (greaterThan != null) {
      if (value.length <= greaterThan) {
        errors.add("The value for '$propertyName' is invalid. Must have length greater than '$greaterThan'.");
        return false;
      }
    }

    if (greaterThanEqualTo != null) {
      if (value.length < greaterThanEqualTo) {
        errors.add("The value for '$propertyName' is invalid. Must have length greater than or equal to '$greaterThanEqualTo'.");
        return false;
      }
    }

    if (lessThan != null) {
      if (value.length < lessThan) {
        errors.add("The value for '$propertyName' is invalid. Must have length less than '$lessThan'.");
        return false;
      }
    }

    if (lessThanEqualTo != null) {
      if (value.length < lessThanEqualTo) {
        errors.add("The value for '$propertyName' is invalid. Must have length less than or equal to '$lessThanEqualTo'.");
        return false;
      }
    }

    if (equalTo != null) {
      if (value.length != equalTo) {
        errors.add("The value for '$propertyName' is invalid. Must have length equal to '$equalTo'.");
        return false;
      }
    }

    return true;
  }

  bool _validateComparison(
      ValidateOperation operation, String propertyName, Comparable value, List<String> errors) {
    if (greaterThan != null) {
      if (value.compareTo(greaterThan) <= 0) {
        errors.add("The value for '$propertyName' is invalid. Must be greater than '$greaterThan'.");
        return false;
      }
    }

    if (greaterThanEqualTo != null) {
      if (value.compareTo(greaterThanEqualTo) < 0) {
        errors.add("The value for '$propertyName' is invalid. Must be greater than or equal to '$greaterThanEqualTo'.");
        return false;
      }
    }

    if (lessThan != null) {
      if (value.compareTo(lessThan) >= 0) {
        errors.add("The value for '$propertyName' is invalid. Must be less than '$lessThan'.");
        return false;
      }
    }

    if (lessThanEqualTo != null) {
      if (value.compareTo(lessThanEqualTo) > 0) {
        errors.add("The value for '$propertyName' is invalid. Must be less than or equal to '$lessThanEqualTo'.");
        return false;
      }
    }

    if (equalTo != null) {
      if (value.compareTo(equalTo) != 0) {
        errors.add("The value for '$propertyName' is invalid. Must be equal to '$equalTo'.");
        return false;
      }
    }

    return true;
  }

  bool _validateMatches(
      ValidateOperation operation, String propertyName, String value, List<String> errors) {
    var regex = new RegExp(value);
    if (!regex.hasMatch(value)) {
      errors.add("The value for '$propertyName' is invalid. Must match pattern ${regex.pattern}.");
      return false;
    }

    return true;
  }
}
