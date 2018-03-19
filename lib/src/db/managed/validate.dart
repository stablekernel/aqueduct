import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';

/// Types of operations [ManagedValidator]s will be triggered for.
enum ValidateOperation { update, insert }

class ValidatorError extends Error {
  final String message;

  ValidatorError(this.message);

  @override
  String toString() {
    return "Validator Error: $message";
  }

  factory ValidatorError.empty(String name) {
    return new ValidatorError("Invalid input for Validator on '${name}'"
        "Input collection must have at least one element");
  }

  factory ValidatorError.invalidPropertyType(
      String name, String type, String reason) {
    return new ValidatorError(
        "Validator cannot be used on property '${name}' of type ${type}. ${reason}");
  }

  factory ValidatorError.invalidConstraintValue(String name, String reason) {
    return new ValidatorError(
        "Invalid constraint value(s) provided for Validator on '${name}'. ${reason}");
  }
}

/// Validates properties of [ManagedObject] before an insert or update [Query].
///
/// Instances of this type are created during [ManagedDataModel] compilation.

class ManagedValidator extends Validator {
  final ManagedAttributeDescription attribute;

  ManagedValidator(this.attribute, Validate definition)
      : this.definition = definition,
        super(attribute.name, attribute.type.kind, definition);

  @override
  Validate definition;

  @override
  _build() {
    try {
      super._build();
    } catch (e) {
      throw new ManagedDataModelError.invalidValidator(
          attribute.entity, e.toString());
    }
  }

  //todo: add custom validation back with operation parameter

  /// Executes all [Validate]s for [object].
  ///
  /// Validates the properties of [object] according to its declared validators. Validators
  /// are added to properties using [Validate] metadata. See [Validate].
  ///
  /// This method is invoked by [ManagedObject.validate]. Invoking this method directly will
  /// ignore any validations that occur by overriding [ManagedObject.validate] and should be avoided.
  ///
  /// Pass an empty list for [errors] to receive more details on any failed validations.
  static bool run(ManagedObject object,
      {ValidateOperation operation: ValidateOperation.insert,
      List<String> errors}) {
    errors ??= [];

    var isValid = true;
    var validators = object.entity.validators;
    validators.forEach((validator) {
      if (!validator.definition.runOnInsert &&
          operation == ValidateOperation.insert) {
        return;
      }

      if (!validator.definition.runOnUpdate &&
          operation == ValidateOperation.update) {
        return;
      }

      if (validator.definition._builtinValidate == _ValidationStrategy.absent) {
        if (object.backing.contents.containsKey(validator.name)) {
          isValid = false;

          errors.add("Value for '${validator.name}' may not be included "
              "for ${_errorStringForOperation(operation)}s.");
        }
      } else if (validator.definition._builtinValidate ==
          _ValidationStrategy.present) {
        if (!object.backing.contents.containsKey(validator.name)) {
          isValid = false;

          errors.add("Value for '${validator.name}' must be included "
              "for ${_errorStringForOperation(operation)}s.");
        }
      } else {
        var value = object.backing.contents[validator.name];
        if (value != null) {
          if (!validator.isValid(value, errors)) {
            isValid = false;
          }
        }
      }
    });

    return isValid;
  }

  @override
  bool isAssignableWith(dynamic dartValue) {
    return attribute.isAssignableWith(dartValue);
  }

  static String _errorStringForOperation(ValidateOperation op) {
    switch (op) {
      case ValidateOperation.insert:
        return "insert";
      case ValidateOperation.update:
        return "update";
      default:
        return "unknown";
    }
  }
}

class Validator {
  List<BaseValidator> validators = [];
  final ValidationDefinition definition;
  ManagedPropertyType type; //todo: factor out managed property type
  String name;

  _ValidationStrategy get validationStrategy => definition._builtinValidate;

  bool get _isExpectingComparable =>
      validationStrategy == _ValidationStrategy.comparison;

  bool get _isExpectingString => [
        _ValidationStrategy.regex,
        _ValidationStrategy.length
      ].contains(validationStrategy);

  bool get _shouldAttemptDateTimeConversion =>
      type == ManagedPropertyType.datetime;

  Comparable get _greaterThan => _shouldAttemptDateTimeConversion
      ? _attemptDateTimeConversion(definition._greaterThan)
      : definition._greaterThan;

  Comparable get _greaterThanEqualTo => _shouldAttemptDateTimeConversion
      ? _attemptDateTimeConversion(definition._greaterThanEqualTo)
      : definition._greaterThanEqualTo;

  Comparable get _equalTo => _shouldAttemptDateTimeConversion
      ? _attemptDateTimeConversion(definition._equalTo)
      : definition._equalTo;

  Comparable get _lessThan => _shouldAttemptDateTimeConversion
      ? _attemptDateTimeConversion(definition._lessThan)
      : definition._lessThan;

  Comparable get _lessThanEqualTo => _shouldAttemptDateTimeConversion
      ? _attemptDateTimeConversion(definition._lessThanEqualTo)
      : definition._lessThanEqualTo;

  /// Creates an instance of this type.
  ///
  /// Instances of this type are created by adding [Validate] metadata
  /// to [ManagedObject] properties.
  Validator(this.name, this.type, this.definition) {
    if (definition._builtinValidate != null) {
      _build();
    } else {
      var validator = new CustomValidator(definition.validate);
      validators.add(validator);
    }
  }

  bool isValid(
      dynamic valueUnderEvalutation, List<String> failureDescriptions) {
    if (_isExpectingString && valueUnderEvalutation is! String) {
      failureDescriptions.add(
          "Validator cannot evaluate value for ${name}. The value must be a string but got ${valueUnderEvalutation
              .runtimeType}.");
      return false;
    }
    if (_isExpectingComparable && valueUnderEvalutation is! Comparable) {
      failureDescriptions.add(
          "Validator cannot evaluate value for ${name}. The value of type, ${valueUnderEvalutation
              .runtimeType}, does not implement Comparable");
      return false;
    }

    var value = validationStrategy == _ValidationStrategy.length
        ? valueUnderEvalutation.length
        : valueUnderEvalutation;

    return validators.every((v) => v.validate(value, failureDescriptions));
  }

  void _build() {
    switch (validationStrategy) {
      case _ValidationStrategy.regex:
        _addStringPatternValidator();
        break;
      case _ValidationStrategy.comparison:
        _addComparisonValidators();
        break;
      case _ValidationStrategy.length:
        _addStringLengthValidators();
        break;
      case _ValidationStrategy.oneOf:
        _addSetValidator();
        break;
    }
  }

  void _addStringPatternValidator() {
    if (type != ManagedPropertyType.string) {
      throw new ValidatorError.invalidPropertyType(name, type.toString(),
          "Validate.matches can only be used to evaluate properties of type String.");
    }
    validators.add(new StringPatternValidator(definition._pattern));
  }

  void _addComparisonValidators() {
    if (_greaterThan != null) {
      validators.add(new ComparableValidator.greaterThan(_greaterThan));
    }

    if (_greaterThanEqualTo != null) {
      validators
          .add(new ComparableValidator.greaterThanEqualTo(_greaterThanEqualTo));
    }

    if (_lessThan != null) {
      validators.add(new ComparableValidator.lessThan(_lessThan));
    }

    if (_lessThanEqualTo != null) {
      validators.add(new ComparableValidator.lessThanEqualTo(_lessThanEqualTo));
    }

    if (_equalTo != null) {
      validators.add(new ComparableValidator.equalTo(_equalTo));
    }
  }

  void _addStringLengthValidators() {
    if (type != ManagedPropertyType.string) {
      throw new ValidatorError.invalidPropertyType(name, type.toString(),
          "Validate.length can only be used to evaluate properties of type String");
    }
    _addComparisonValidators();
  }

  void _addSetValidator() {
    var supportedOneOfTypes = [
      ManagedPropertyType.string,
      ManagedPropertyType.integer,
      ManagedPropertyType.bigInteger
    ];
    if (!supportedOneOfTypes.contains(type)) {
      throw new ValidatorError.invalidPropertyType(name, type.toString(),
          "Validate.oneOf can only be used to evaluate properties of type String or Int");
    }
    if (definition._validValues.isEmpty) {
      throw new ValidatorError.invalidConstraintValue(name,
          "Validate.oneOf requires at least one element represnting a valid value");
    }
    if (definition._validValues.any((v) => !isAssignableWith(v))) {
      throw new ValidatorError.invalidConstraintValue(name,
          "Validate.oneOf requires all elements representing valid values to be assignable to '${type}'");
    }
    final options = definition._validValues.toSet();
    validators.add(new SetValidator(options));
  }

  Comparable<dynamic> _attemptDateTimeConversion(dynamic inputValue) {
    if (inputValue != null && type == ManagedPropertyType.datetime) {
      try {
        return DateTime.parse(inputValue);
      } on FormatException {
        throw new ValidatorError.invalidConstraintValue(
            name, "'$inputValue' cannot be parsed as DateTime");
      }
    }

    return inputValue;
  }

//todo: review for refactoring
  bool isAssignableWith(dynamic dartValue) {
    if (dartValue == null) {
      return true;
    }
    switch (type) {
      case ManagedPropertyType.integer:
        return dartValue is int;
      case ManagedPropertyType.bigInteger:
        return dartValue is int;
      case ManagedPropertyType.boolean:
        return dartValue is bool;
      case ManagedPropertyType.datetime:
        return dartValue is DateTime;
      case ManagedPropertyType.doublePrecision:
        return dartValue is double;
      case ManagedPropertyType.string:
        return dartValue is String;
      case ManagedPropertyType.map:
        return dartValue is Map;
      case ManagedPropertyType.list:
        return dartValue is List;
      case ManagedPropertyType.document:
        return dartValue is Document;
    }
    return false;
  }
}

abstract class BaseValidator<T> {
  bool validate(T value, List<String> failureDescriptions);
}

class CustomValidator implements BaseValidator {
  final _isValid;

  CustomValidator(this._isValid);

  bool validate(dynamic value, List<String> failureDescriptions) {
    return _isValid(value, failureDescriptions);
  }
}

class ComparableValidator<T extends Comparable> implements BaseValidator<T> {
  final Comparable _thresholdValue;
  final _isValid;

  static bool isLessThan(num comparator) => comparator < 0;

  static bool isGreaterThan(num comparator) => comparator > 0;

  static bool isEqualTo(num comparator) => comparator == 0;

  static bool isGreaterThanEqualTo(num comparator) =>
      isGreaterThan(comparator) || isEqualTo(comparator);

  static bool isLessThanEqualTo(num comparator) =>
      isLessThan(comparator) || isEqualTo(comparator);

  const ComparableValidator.lessThan(this._thresholdValue)
      : _isValid = isLessThan;

  const ComparableValidator.greaterThan(this._thresholdValue)
      : _isValid = isGreaterThan;

  const ComparableValidator.equalTo(this._thresholdValue)
      : _isValid = isEqualTo;

  const ComparableValidator.greaterThanEqualTo(this._thresholdValue)
      : _isValid = isGreaterThanEqualTo;

  const ComparableValidator.lessThanEqualTo(this._thresholdValue)
      : _isValid = isLessThanEqualTo;

  /**
   * Compares this object to another [Comparable]
   *
   * Returns a value like a [Comparator] when comparing `this` to [other].
   * That is, it returns a negative integer if `this` is ordered before [other],
   * a positive integer if `this` is ordered after [other],
   * and zero if `this` and [other] are ordered together.
   *
   * The [other] argument must be a value that is comparable to this object.
   */
  bool validate(T value, List<String> failureDescriptions) {
    num comparator = value.compareTo(_thresholdValue);
    bool isValid = _isValid(comparator);
    if (isValid == false) {
      failureDescriptions
          .add("${value} failed comparison check against '$_thresholdValue'.");
    }
    return isValid;
  }
}

class StringPatternValidator implements BaseValidator<String> {
  final String _pattern;

  const StringPatternValidator(String pattern) : _pattern = pattern;

  bool validate(String value, List<String> failureDescriptions) {
    final regexp = new RegExp(_pattern);
    bool isValid = regexp.hasMatch(value);
    if (isValid == false) {
      failureDescriptions.add(
          "Value ${value} failed comparison check against pattern '$_pattern'.");
    }
    return isValid;
  }
}

class SetValidator implements BaseValidator<dynamic> {
  final Set _validValues;

  const SetValidator(Set validValues) : _validValues = validValues;

  bool validate(dynamic value, List<String> failureDescriptions) {
    bool isValid = _validValues.contains(value);
    if (isValid == false) {
      failureDescriptions
          .add("${value} not found in set '${_validValues.toString()}'.");
    }
    return isValid;
  }
}

//todo: edit comments
class Validate<T> extends ValidationDefinition<T> {
  /// Whether or not this validation is checked on update queries.
  final bool runOnUpdate;

  /// Whether or not this validation is checked on insert queries.
  final bool runOnInsert;

  const Validate({bool onUpdate: true, bool onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super();

  const Validate._(
      {bool onUpdate: true, bool onInsert: true, _ValidationStrategy validator})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super._(validator: validator);

  /// A validator for matching an input String against a regular expression.
  ///
  /// Values passing through validators of this type must match a regular expression
  /// created by [pattern]. See [RegExp] in the Dart standard library for behavior.
  ///
  /// This validator is only valid for [String] properties.
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.matches(String pattern, {bool onUpdate: true, onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super.matches(pattern);

  /// A validator for comparing a value.
  ///
  /// Values passing through validators of this type must be [lessThan],
  /// [greaterThan], [lessThanEqualTo], [equalTo], or [greaterThanEqualTo
  /// to the value provided for each argument.
  ///
  /// Any argument not specified is not evaluated. A typical validator
  /// only uses one argument:
  ///
  ///         @Validate.compare(lessThan: 10.0)
  ///         double value;
  ///
  /// All provided arguments are evaluated. Therefore, the following
  /// requires an input value to be between 6 and 10:
  ///
  ///         @Validate.compare(greaterThanEqualTo: 6, lessThanEqualTo: 10)
  ///         int value;
  ///
  /// This validator can be used for [String], [double], [int] and [DateTime] properties.
  ///
  /// When creating a validator for [DateTime] properties, the value for an argument
  /// is a [String] that will be parsed by [DateTime.parse].
  ///
  ///       @Validate.compare(greaterThan: "2017-02-11T00:30:00Z")
  ///       DateTime date;
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.compare(
      {Comparable lessThan,
      Comparable greaterThan,
      Comparable equalTo,
      Comparable greaterThanEqualTo,
      Comparable lessThanEqualTo,
      bool onUpdate: true,
      onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super.compare(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo);

  /// A validator for validating the length of a [String].
  ///
  /// Values passing through validators of this type must a [String] with a length that is[lessThan],
  /// [greaterThan], [lessThanEqualTo], [equalTo], or [greaterThanEqualTo
  /// to the value provided for each argument.
  ///
  /// Any argument not specified is not evaluated. A typical validator
  /// only uses one argument:
  ///
  ///         @Validate.length(lessThan: 10)
  ///         String foo;
  ///
  /// All provided arguments are evaluated. Therefore, the following
  /// requires an input string to have a length to be between 6 and 10:
  ///
  ///         @Validate.length(greaterThanEqualTo: 6, lessThanEqualTo: 10)
  ///         String foo;
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.length(
      {int lessThan,
      int greaterThan,
      int equalTo,
      int greaterThanEqualTo,
      int lessThanEqualTo,
      bool onUpdate: true,
      onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super.length(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo);

  /// A validator for ensuring a property always has a value when being inserted or updated.
  ///
  /// This metadata requires that a property must be set in [Query.values] before an update
  /// or insert. The value may be null, if the property's [Column.isNullable] allow it.
  ///
  /// If [onUpdate] is true (the default), this validation requires a property to be present for update queries.
  /// If [onInsert] is true (the default), this validation requires a property to be present for insert queries.
  const Validate.present({bool onUpdate: true, bool onInsert: true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _ValidationStrategy.present);

  /// A validator for ensuring a property does not have a value when being inserted or updated.
  ///
  /// This metadata requires that a property must NOT be set in [Query.values] before an update
  /// or insert.
  ///
  /// This validation is used to restrict input during either an insert or update query. For example,
  /// a 'dateCreated' property would use this validator to ensure that property isn't set during an update.
  ///
  ///       @Validate.absent(onUpdate: true, onInsert: false)
  ///       DateTime dateCreated;
  ///
  /// If [onUpdate] is true (the default), this validation requires a property to be absent for update queries.
  /// If [onInsert] is true (the default), this validation requires a property to be absent for insert queries.
  const Validate.absent({bool onUpdate: true, bool onInsert: true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: _ValidationStrategy.absent);

  /// A validator for ensuring a value is one of a set of values.
  ///
  /// An input value must be one of [values].
  ///
  /// [values] must be homogenous - every value must be the same type -
  /// and the property with this metadata must also match the type
  /// of the objects in [values].
  ///
  ///         @Validate.oneOf(const ["A", "B", "C")
  ///         String foo;
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.oneOf(List<dynamic> values,
      {bool onUpdate: true, bool onInsert: true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super.oneOf(values);
}

//todo: document with comments
class ValidationDefinition<T> {
  const ValidationDefinition()
      : this._pattern = null,
        this._validValues = null,
        this._lessThan = null,
        this._lessThanEqualTo = null,
        this._greaterThan = null,
        this._greaterThanEqualTo = null,
        this._equalTo = null,
        _builtinValidate = null;

  const ValidationDefinition._(
      {_ValidationStrategy validator,
      dynamic pattern,
      List<dynamic> values,
      Comparable greaterThan,
      Comparable greaterThanEqualTo,
      Comparable equalTo,
      Comparable lessThan,
      Comparable lessThanEqualTo})
      : _builtinValidate = validator,
        this._pattern = pattern,
        this._validValues = values,
        this._greaterThan = greaterThan,
        this._greaterThanEqualTo = greaterThanEqualTo,
        this._equalTo = equalTo,
        this._lessThan = lessThan,
        this._lessThanEqualTo = lessThanEqualTo;

  const ValidationDefinition.matches(String pattern)
      : this._(pattern: pattern, validator: _ValidationStrategy.regex);

  const ValidationDefinition.compare(
      {Comparable lessThan,
      Comparable greaterThan,
      Comparable equalTo,
      Comparable greaterThanEqualTo,
      Comparable lessThanEqualTo})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            validator: _ValidationStrategy.comparison);

  const ValidationDefinition.length(
      {int lessThan,
      int greaterThan,
      int equalTo,
      int greaterThanEqualTo,
      int lessThanEqualTo})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            validator: _ValidationStrategy.length);

  const ValidationDefinition.oneOf(List<dynamic> values)
      : this._(values: values, validator: _ValidationStrategy.oneOf);

  final dynamic _pattern;
  final List<dynamic> _validValues;
  final Comparable _greaterThan;
  final Comparable _greaterThanEqualTo;
  final Comparable _equalTo;
  final Comparable _lessThan;
  final Comparable _lessThanEqualTo;
  final _ValidationStrategy _builtinValidate;

//  void readFromMap(Map<String, dynamic> map) {
//    _value = map['_value'];
//    _values = map['_values'];
//    _greaterThan = map['_greaterThan'];
//    _greaterThanEqualTo = map['_greaterThanEqualTo'];
//    _equalTo = map['_equalTo'];
//    _lessThan = map['_lessThan'];
//    _lessThanEqualTo = map['_lessThanEqualTo'];
//    _bultinValidate = _builtInValidateFromString(map['_builtInValidate']);
//  }

  Map<String, dynamic> asMap() {
    Map<String, dynamic> map = {
      "value": _pattern,
      "values": _validValues,
      "greaterThan": _greaterThan,
      "greaterThanEqualTo": _greaterThanEqualTo,
      "equalTo": _equalTo,
      "lessThan": _lessThan,
      "lessThanEqualTo": _lessThanEqualTo,
      "bultinValidate": _builtInValidateToString(_builtinValidate)
    };
    return map;
  }

  String _builtInValidateToString(_ValidationStrategy validate) {
    switch (validate) {
      case _ValidationStrategy.regex:
        return "regex";
      case _ValidationStrategy.comparison:
        return "comparison";
      case _ValidationStrategy.length:
        return "length";
      case _ValidationStrategy.oneOf:
        return "oneOf";
      case _ValidationStrategy.absent:
        return "absent";
      case _ValidationStrategy.present:
        return "present";
    }
  }

  _builtInValidateFromString(String string) {
    switch (string) {
      case "regex":
        return _ValidationStrategy.regex;
      case "comparison":
        return _ValidationStrategy.comparison;
      case "length":
        return _ValidationStrategy.length;
      case "oneOf":
        return _ValidationStrategy.oneOf;
      case "absent":
        return _ValidationStrategy.absent;
      case "present":
        return _ValidationStrategy.present;
    }
  }

  bool validate(T value, List<String> failureDescriptions) {
    return false;
  }

  //todo: move this out of class look into moving into Validate or ManagedAttributeDescription

  /// Adds constraints to an [APISchemaObject] imposed by this validator.
  ///
  /// Used during documentation process. When creating custom validator subclasses, override this method
  /// to modify [object] for any constraints the validator imposes.
  void constrainSchemaObject(
      APIDocumentContext context, APISchemaObject object) {
    switch (_builtinValidate) {
      case _ValidationStrategy.regex:
        {
          object.pattern = _pattern;
        }
        break;
      case _ValidationStrategy.comparison:
        {
          if (_greaterThan is num) {
            object.exclusiveMinimum = true;
            object.minimum = _greaterThan;
          } else if (_greaterThanEqualTo is num) {
            object.exclusiveMinimum = false;
            object.minimum = _greaterThanEqualTo;
          }

          if (_lessThan is num) {
            object.exclusiveMaximum = true;
            object.maximum = _lessThan;
          } else if (_lessThanEqualTo is num) {
            object.exclusiveMaximum = false;
            object.maximum = _lessThanEqualTo;
          }
        }
        break;
      case _ValidationStrategy.length:
        {
          if (_equalTo != null) {
            object.maxLength = _equalTo;
            object.minLength = _equalTo;
          } else {
            if (_greaterThan is int) {
              object.minLength = 1 + _greaterThan;
            } else if (_greaterThanEqualTo is int) {
              object.minLength = _greaterThanEqualTo;
            }

            if (_lessThan is int) {
              object.maxLength = (-1) + _lessThan;
            } else if (_lessThanEqualTo != null) {
              object.maximum = _lessThanEqualTo;
            }
          }
        }
        break;
      case _ValidationStrategy.present:
        {}
        break;
      case _ValidationStrategy.absent:
        {}
        break;
      case _ValidationStrategy.oneOf:
        {
          object.enumerated = _validValues;
        }
        break;
    }
  }
}

//todo: split into regular and managed version (regular + present/absent)
enum _ValidationStrategy { regex, comparison, length, present, absent, oneOf }
