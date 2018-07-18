import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/validation/impl.dart';
import 'package:aqueduct/src/db/query/query.dart';

/// Validates properties of [ManagedObject] before an insert or update [Query].
///
/// Instances of this type are created during [ManagedDataModel] compilation.
abstract class ManagedValidator {
  ManagedValidator(this.attribute, this.definition);

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
      context.attribute = validator.attribute;
      context.event = event;
      if (!validator.definition.runOnInsert && event == Validating.insert) {
        return;
      }

      if (!validator.definition.runOnUpdate && event == Validating.update) {
        return;
      }

      if (validator is PresentValidator) {
        if (!object.backing.contents.containsKey(validator.attribute.name)) {
          context.addError(
              "Value for '${validator.attribute.name}' must be included "
              "for ${_getEventName(event)}s.");
        }
      } else if (validator is AbsentValidator) {
        if (object.backing.contents.containsKey(validator.attribute.name)) {
          context.addError(
              "Value for '${validator.attribute.name}' may not be included "
              "for ${_getEventName(event)}s.");
        }
      } else {
        var value = object.backing.contents[validator.attribute.name];
        if (value != null) {
          validator.validate(context, value);
        }
      }
    });

    return context;
  }

  /// The attribute this instance runs on.
  final ManagedAttributeDescription attribute;

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
