import 'dart:mirrors';
import 'package:aqueduct/src/db/managed/key_path.dart';

import 'managed.dart';
import '../query/matcher_internal.dart';
import 'relationship_type.dart';
import 'exception.dart';

class ManagedValueBacking extends ManagedBacking {
  @override
  Map<String, dynamic> valueMap = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    return valueMap[property.name];
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (value != null) {
      if (!property.isAssignableWith(value)) {
        throw new ValidationException(["invalid input value for '${property.name}'"]);
      }
    }

    valueMap[property.name] = value;
  }
}

class ManagedMatcherBacking extends ManagedBacking {
  @override
  Map<String, dynamic> valueMap = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (!valueMap.containsKey(property.name)) {
      // For any relationships, automatically insert them into valueMap
      // so that their properties can be accessed when building queries.
      if (property is ManagedRelationshipDescription) {
        if (property.relationshipType == ManagedRelationshipType.hasMany) {
          valueMap[property.name] = new ManagedSet()
            ..entity = property.destinationEntity;
        } else if (property.relationshipType == ManagedRelationshipType.hasOne ||
            property.relationshipType == ManagedRelationshipType.belongsTo) {
          valueMap[property.name] = property.destinationEntity.newInstance(backing: new ManagedMatcherBacking());
        }
      }
    }

    return valueMap[property.name];
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (value == null) {
      valueMap.remove(property.name);
      return;
    }

    if (value is MatcherExpression) {
      if (property is ManagedRelationshipDescription) {
        var innerObject = valueForProperty(property);
        if (innerObject is ManagedObject) {
          innerObject[innerObject.entity.primaryKey] = value;
        } else if (innerObject is ManagedSet) {
          innerObject.haveAtLeastOneWhere[innerObject.entity.primaryKey] =
              value;
        }
      } else {
        valueMap[property.name] = value;
      }
    } else {
      final typeName = MirrorSystem.getName(property.entity.instanceType.simpleName);

      throw new ArgumentError("Invalid query matcher assignment. Tried assigning value to 'Query<$typeName>.where.${property.name}'. Wrap value in 'whereEqualTo()'.");
    }
  }
}

class ManagedAccessTrackingBacking extends ManagedBacking {
  @override
  Map<String, dynamic> get valueMap => null;

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (property?.type?.kind == ManagedPropertyType.document) {
      return new KeyPath(property.name);
    }

    return property.name;
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    // no-op
  }
}
