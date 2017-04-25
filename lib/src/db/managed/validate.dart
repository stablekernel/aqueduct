import '../db.dart';

enum ValidateOperation { update, insert }

enum _BuiltinValidate { regex, comparison, length, present, absent, oneOf }

abstract class Validate<T> {
  static bool run(
      ManagedObject object, ValidateOperation operation, List<String> errors) {
    var entity = object.entity;

    var validations = entity.validators;

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

  bool validate(ValidateOperation operation, T value, List<String> errors) {
    switch (_builtinValidate) {
      case _BuiltinValidate.oneOf:
        return _validateOneOf(operation, value, errors);
      case _BuiltinValidate.regex:
        return _validateMatches(operation, value as String, errors);
      case _BuiltinValidate.length:
        return _validateLength(operation, value as String, errors);
      case _BuiltinValidate.comparison:
        return _validateComparison(operation, value as num, errors);
      default:
        return true;
    }
  }

  bool _validateOneOf(
      ValidateOperation operation, dynamic value, List<String> errors) {
    return false;
  }

  bool _validateLength(
      ValidateOperation operation, String value, List<String> errors) {
    return false;
  }

  bool _validateComparison(
      ValidateOperation operation, num value, List<String> errors) {
    return false;
  }

  bool _validateMatches(
      ValidateOperation operation, String value, List<String> errors) {
    return false;
  }
}
