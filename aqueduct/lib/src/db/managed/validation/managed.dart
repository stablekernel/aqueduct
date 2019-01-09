import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/validation/impl.dart';
import 'package:aqueduct/src/db/query/query.dart';

/// Validates properties of [ManagedObject] before an insert or update [Query].
///
/// Instances of this type are created during [ManagedDataModel] compilation.
abstract class ManagedValidator {
  ManagedValidator(this.property, this.definition);

  /// Executes all [Validate]s for [object].
  ///
  /// Validates the properties of [object] according to its validator annotations. Validators
  /// are added to properties using [Validate] metadata.
  ///
  /// This method does not invoke [ManagedObject.validate] - any customization provided
  /// by a [ManagedObject] subclass that overrides this method will not be invoked.
  static ValidationContext run(ManagedObject object,
      {Validating event = Validating.insert}) {
    final context = ValidationContext();

    object.entity.validators.forEach((validator) {
      context.property = validator.property;
      context.event = event;
      if (!validator.definition.runOnInsert && event == Validating.insert) {
        return;
      }

      if (!validator.definition.runOnUpdate && event == Validating.update) {
        return;
      }

      // Switch object.backing with map that is either object.bacing or
      // the internal map of a nested object if attribute is from another entity
      var contents = object.backing.contents;
      var key = validator.property.name;
      if (validator.property is ManagedRelationshipDescription) {
        final inner = object[validator.property.name];
        if (inner is ManagedObject) {
          contents = inner.backing.contents;
          key = inner.entity.primaryKey;
        }
      }

      if (validator is PresentValidator) {
        if (!contents.containsKey(key)) {
          context.addError(
              "key '${validator.property.name}' is required"
              "for ${_getEventName(event)}s.");
        }
      } else if (validator is AbsentValidator) {
        if (contents.containsKey(key)) {
          context.addError(
              "key '${validator.property.name}' is not allowed "
              "for ${_getEventName(event)}s.");
        }
      } else {
        final value = contents[key];
        if (value != null) {
          validator.validate(context, value);
        }
      }
    });

    return context;
  }

  /// The property being validated.
  final ManagedPropertyDescription property;

  /// The metadata associated with this instance.
  final Validate definition;

  void validate(ValidationContext context, dynamic value) {
    definition.validate(context, value);
  }

  static String _getEventName(Validating op) {
    switch (op) {
      case Validating.insert:
        return "insert";
      case Validating.update:
        return "update";
      default:
        return "unknown";
    }
  }
}
