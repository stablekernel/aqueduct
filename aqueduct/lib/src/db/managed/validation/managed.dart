import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/validation/impl.dart';
import 'package:aqueduct/src/db/query/query.dart';

/// Validates properties of [ManagedObject] before an insert or update [Query].
///
/// Instances of this type are created during [ManagedDataModel] compilation.
class ManagedValidator {
  ManagedValidator(this.definition, this.state);

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
      context.state = validator.state;
      if (!validator.definition.runOnInsert && event == Validating.insert) {
        return;
      }

      if (!validator.definition.runOnUpdate && event == Validating.update) {
        return;
      }

      var contents = object.backing.contents;
      var key = validator.property.name;

      if (validator.definition.type == ValidateType.present) {
        if (validator.property is ManagedRelationshipDescription) {
          final inner = object[validator.property.name] as ManagedObject;
          if (inner == null || !inner.backing.contents.containsKey(inner.entity.primaryKey)) {
            context.addError(
              "key '${validator.property.name}' is required"
                "for ${_getEventName(event)}s.");
          }
        } else if (!contents.containsKey(key)) {
          context.addError(
              "key '${validator.property.name}' is required"
              "for ${_getEventName(event)}s.");
        }
      } else if (validator.definition.type == ValidateType.absent) {
        if (validator.property is ManagedRelationshipDescription) {
          final inner = object[validator.property.name] as ManagedObject;
          if (inner != null) {
            context.addError(
              "key '${validator.property.name}' is not allowed "
                "for ${_getEventName(event)}s.");
          }
        } else if (contents.containsKey(key)) {
          context.addError(
            "key '${validator.property.name}' is not allowed "
              "for ${_getEventName(event)}s.");
        }
      } else {
        if (validator.property is ManagedRelationshipDescription) {
          final inner = object[validator.property.name] as ManagedObject;
          if (inner == null || inner.backing.contents[inner.entity.primaryKey] == null) {
            return;
          }
          contents = inner.backing.contents;
          key = inner.entity.primaryKey;
        }

        final value = contents[key];
        if (value != null) {
          validator.validate(context, value);
        }
      }
    });

    return context;
  }

  /// The property being validated.
  ManagedPropertyDescription property;

  /// The metadata associated with this instance.
  final Validate definition;

  final dynamic state;

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
