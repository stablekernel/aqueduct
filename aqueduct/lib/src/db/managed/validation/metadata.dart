import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/managed/validation/impl.dart';
import 'package:aqueduct/src/openapi/openapi.dart';

/// Types of operations [ManagedValidator]s will be triggered for.
enum Validating { update, insert }

/// Information about a validation being performed.
class ValidationContext {
  /// Whether this validation is occurring during update or insert.
  Validating event;

  /// The entity attribute being validated.
  ManagedAttributeDescription attribute;

  /// Errors that have occurred in this context.
  List<String> errors = [];

  /// Adds a validation error to the context.
  ///
  /// A validation will fail if this method is invoked.
  void addError(String reason) {
    errors.add("${attribute.entity.name}.${attribute.name}: $reason");
  }

  /// Whether this validation context passed all validations.
  bool get isValid => errors.isEmpty;
}

/// Add as metadata to persistent properties to validate their values before insertion or updating.
///
/// When executing update or insert queries, any properties with this metadata will be validated
/// against the condition declared by this instance. Example:
///
///         class Person extends ManagedObject<_Person> implements _Person {}
///         class _Person {
///           @primaryKey
///           int id;
///
///           @Validate.length(greaterThan: 10)
///           String name;
///         }
///
/// Properties may have more than one metadata of this type. All validations must pass
/// for an insert or update to be valid.
///
/// By default, validations occur on update and insert queries. Constructors have arguments
/// for only running a validation on insert or update. See [runOnUpdate] and [runOnInsert].
///
/// This class may be subclassed to create custom validations. Subclasses must override [validate].
class Validate {
  /// Invoke this constructor when creating custom subclasses.
  ///
  /// This constructor is used so that subclasses can pass [onUpdate] and [onInsert].
  /// Example:
  ///         class CustomValidate extends Validate<String> {
  ///           CustomValidate({bool onUpdate: true, bool onInsert: true})
  ///             : super(onUpdate: onUpdate, onInsert: onInsert);
  ///
  ///            bool validate(
  ///              ValidateOperation operation,
  ///              ManagedAttributeDescription property,
  ///              String value,
  ///              List<String> errors) {
  ///                return someCondition;
  ///            }
  ///         }
  const Validate({bool onUpdate = true, bool onInsert = true})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        this._value = null,
        this._lessThan = null,
        this._lessThanEqualTo = null,
        this._greaterThan = null,
        this._greaterThanEqualTo = null,
        this._equalTo = null,
        _type = null;

  const Validate._(
      {bool onUpdate = true,
      bool onInsert = true,
      ValidateType validator,
      dynamic value,
      Comparable greaterThan,
      Comparable greaterThanEqualTo,
      Comparable equalTo,
      Comparable lessThan,
      Comparable lessThanEqualTo})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        _type = validator,
        this._value = value,
        this._greaterThan = greaterThan,
        this._greaterThanEqualTo = greaterThanEqualTo,
        this._equalTo = equalTo,
        this._lessThan = lessThan,
        this._lessThanEqualTo = lessThanEqualTo;

  /// A validator for matching an input String against a regular expression.
  ///
  /// Values passing through validators of this type must match a regular expression
  /// created by [pattern]. See [RegExp] in the Dart standard library for behavior.
  ///
  /// This validator is only valid for [String] properties.
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.matches(String pattern,
      {bool onUpdate = true, bool onInsert = true})
      : this._(
            value: pattern,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.regex);

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
      bool onUpdate = true,
      bool onInsert = true})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.comparison);

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
      bool onUpdate = true,
      bool onInsert = true})
      : this._(
            lessThan: lessThan,
            lessThanEqualTo: lessThanEqualTo,
            greaterThan: greaterThan,
            greaterThanEqualTo: greaterThanEqualTo,
            equalTo: equalTo,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.length);

  /// A validator for ensuring a property always has a value when being inserted or updated.
  ///
  /// This metadata requires that a property must be set in [Query.values] before an update
  /// or insert. The value may be null, if the property's [Column.isNullable] allow it.
  ///
  /// If [onUpdate] is true (the default), this validation requires a property to be present for update queries.
  /// If [onInsert] is true (the default), this validation requires a property to be present for insert queries.
  const Validate.present({bool onUpdate = true, bool onInsert = true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.present);

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
  const Validate.absent({bool onUpdate = true, bool onInsert = true})
      : this._(
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.absent);

  /// A validator for ensuring a value is one of a set of values.
  ///
  /// An input value must be one of [values].
  ///
  /// [values] must be homogenous - every value must be the same type -
  /// and the property with this metadata must also match the type
  /// of the objects in [values].
  ///
  /// This validator can be used for [String] and [int] properties.
  ///
  ///         @Validate.oneOf(const ["A", "B", "C")
  ///         String foo;
  ///
  /// If [onUpdate] is true (the default), this validation is run on update queries.
  /// If [onInsert] is true (the default), this validation is run on insert queries.
  const Validate.oneOf(List<dynamic> values,
      {bool onUpdate = true, bool onInsert = true})
      : this._(
            value: values,
            onUpdate: onUpdate,
            onInsert: onInsert,
            validator: ValidateType.oneOf);

  /// Whether or not this validation is checked on update queries.
  final bool runOnUpdate;

  /// Whether or not this validation is checked on insert queries.
  final bool runOnInsert;

  /// Returns a [ManagedValidator] for the validation described by this object.
  ManagedValidator getValidator(ManagedAttributeDescription forAttribute) {
    switch (_type) {
      case ValidateType.absent:
        return AbsentValidator(forAttribute, this);
      case ValidateType.present:
        return PresentValidator(forAttribute, this);
      case ValidateType.oneOf:
        return OneOfValidator(forAttribute, this, _value);
      case ValidateType.comparison:
        return ComparisonValidator(forAttribute, this, _expressions);
      case ValidateType.regex:
        return RegexValidator(forAttribute, this, _value);
      case ValidateType.length:
        return LengthValidator(forAttribute, this, _expressions);
      default:
        return DefaultValidator(forAttribute, this);
    }
  }

  final dynamic _value;
  final Comparable _greaterThan;
  final Comparable _greaterThanEqualTo;
  final Comparable _equalTo;
  final Comparable _lessThan;
  final Comparable _lessThanEqualTo;
  final ValidateType _type;

  List<ValidationExpression> get _expressions {
    return ValidationExpression.comparisons(_equalTo, _lessThan,
        _lessThanEqualTo, _greaterThan, _greaterThanEqualTo);
  }

  /// Custom validations override this method to provide validation behavior.
  ///
  /// [input] is the value being validated. If the value is invalid, the reason
  /// is added to [context] via [ValidationContext.addError].
  ///
  /// Additional information about the validation event and the attribute being evaluated
  /// is available in [context].
  /// in [context].
  ///
  /// This method is not run when [input] is null.
  ///
  /// The type of [input] will have already been type-checked prior to executing this method.
  void validate(ValidationContext context, dynamic input) {}

  /// Adds constraints to an [APISchemaObject] imposed by this validator.
  ///
  /// Used during documentation process. When creating custom validator subclasses, override this method
  /// to modify [object] for any constraints the validator imposes.
  void constrainSchemaObject(
      APIDocumentContext context, APISchemaObject object) {
    switch (_type) {
      case ValidateType.regex:
        {
          object.pattern = _value as String;
        }
        break;
      case ValidateType.comparison:
        {
          if (_greaterThan is num) {
            object.exclusiveMinimum = true;
            object.minimum = _greaterThan as num;
          } else if (_greaterThanEqualTo is num) {
            object.exclusiveMinimum = false;
            object.minimum = _greaterThanEqualTo as num;
          }

          if (_lessThan is num) {
            object.exclusiveMaximum = true;
            object.maximum = _lessThan as num;
          } else if (_lessThanEqualTo is num) {
            object.exclusiveMaximum = false;
            object.maximum = _lessThanEqualTo as num;
          }
        }
        break;
      case ValidateType.length:
        {
          if (_equalTo != null) {
            object.maxLength = _equalTo as int;
            object.minLength = _equalTo as int;
          } else {
            if (_greaterThan is int) {
              object.minLength = 1 + (_greaterThan as int);
            } else if (_greaterThanEqualTo is int) {
              object.minLength = _greaterThanEqualTo as int;
            }

            if (_lessThan is int) {
              object.maxLength = (-1) + (_lessThan as int);
            } else if (_lessThanEqualTo != null) {
              object.maximum = _lessThanEqualTo as int;
            }
          }
        }
        break;
      case ValidateType.present:
        {}
        break;
      case ValidateType.absent:
        {}
        break;
      case ValidateType.oneOf:
        {
          object.enumerated = _value as List<dynamic>;
        }
        break;
    }
  }
}
