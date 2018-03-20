import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:validate/validate.dart';

/// Types of operations [ManagedValidator]s will be triggered for.
enum DatabaseOperation { update, insert }


/// Validates properties of [ManagedObject] before an insert or update [Query].
///
/// Instances of this type are created during [ManagedDataModel] compilation.

class ManagedValidator extends Validator {
  final ManagedAttributeDescription attribute;

  ///can we just pass the type itself e.g. return String. can we make it to where value / values hold the type. if the constarint value is datetime then... we can convert to proper type here (or higher) before passing to the Validator super constructor
  static PropertyType propertyTypeConverter(ManagedPropertyType managedPropertyType) {
    switch (managedPropertyType) {
      case ManagedPropertyType.integer:
        return PropertyType.integer;
      case ManagedPropertyType.bigInteger:
        return PropertyType.bigInteger;
      case ManagedPropertyType.doublePrecision:
        return PropertyType.doublePrecision;
      case ManagedPropertyType.string:
        return PropertyType.string;
      case ManagedPropertyType.datetime:
        return PropertyType.datetime;
      case ManagedPropertyType.boolean:
        return PropertyType.boolean;
      case ManagedPropertyType.list:
        return PropertyType.boolean;
      case ManagedPropertyType.map:
        return PropertyType.boolean;
      case ManagedPropertyType.document:
        return PropertyType.boolean;
    }
  }

  ManagedValidator(this.attribute, Validate definition)
      :
        runOnUpdate = definition.runOnUpdate,
        runOnInsert = definition.runOnInsert,
        super(attribute.name,
          ManagedValidator.propertyTypeConverter(attribute.type.kind),
          definition);


  bool runOnUpdate;
  bool runOnInsert;

  @override
  build() {
    try {
      super.build();
//    } on ValidatorError catch (e) {
    }  catch (e) {
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
      {DatabaseOperation operation: DatabaseOperation.insert,
      List<String> errors}) {
    errors ??= [];

    var isValid = true;
    var validators = object.entity.validators;
    validators.forEach((validator) {
      if (!validator.runOnInsert &&
          operation == DatabaseOperation.insert) {
        return;
      }

      if (!validator.runOnUpdate &&
          operation == DatabaseOperation.update) {
        return;
      }

      if (validator.validationStrategy == ValidationStrategy.absent) {
        if (object.backing.contents.containsKey(validator.name)) {
          isValid = false;

          errors.add("Value for '${validator.name}' may not be included "
              "for ${_errorStringForOperation(operation)}s.");
        }
      } else if (validator.definition.validationStrategy ==
          ValidationStrategy.present) {
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

  static String _errorStringForOperation(DatabaseOperation op) {
    switch (op) {
      case DatabaseOperation.insert:
        return "insert";
      case DatabaseOperation.update:
        return "update";
      default:
        return "unknown";
    }
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
      {bool onUpdate: true, bool onInsert: true, ValidationStrategy validator})
      : runOnUpdate = onUpdate,
        runOnInsert = onInsert,
        super.any(validator: validator);

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
            validator: ValidationStrategy.present);

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
            validator: ValidationStrategy.absent);

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

  //todo: move this out of class look into moving into Validate or ManagedAttributeDescription

  /// Adds constraints to an [APISchemaObject] imposed by this validator.
  ///
  /// Used during documentation process. When creating custom validator subclasses, override this method
  /// to modify [object] for any constraints the validator imposes.
  void constrainSchemaObject(
      APIDocumentContext context, APISchemaObject object) {
    switch (validationStrategy) {
      case ValidationStrategy.regex:
        {
          object.pattern = pattern;
        }
        break;
      case ValidationStrategy.comparison:
        {
          if (greaterThan is num) {
            object.exclusiveMinimum = true;
            object.minimum = greaterThan;
          } else if (greaterThanEqualTo is num) {
            object.exclusiveMinimum = false;
            object.minimum = greaterThanEqualTo;
          }

          if (lessThan is num) {
            object.exclusiveMaximum = true;
            object.maximum = lessThan;
          } else if (lessThanEqualTo is num) {
            object.exclusiveMaximum = false;
            object.maximum = lessThanEqualTo;
          }
        }
        break;
      case ValidationStrategy.length:
        {
          if (equalTo != null) {
            object.maxLength =equalTo;
            object.minLength =equalTo;
          } else {
            if (greaterThan is int) {
              object.minLength = 1 +greaterThan;
            } else if (greaterThanEqualTo is int) {
              object.minLength =greaterThanEqualTo;
            }

            if (lessThan is int) {
              object.maxLength = (-1) + lessThan;
            } else if (lessThanEqualTo != null) {
              object.maximum = lessThanEqualTo;
            }
          }
        }
        break;
      case ValidationStrategy.present:
        {}
        break;
      case ValidationStrategy.absent:
        {}
        break;
      case ValidationStrategy.oneOf:
        {
          object.enumerated = validValues;
        }
        break;
    }
  }
}