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
  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (entity.properties[propertyName] == null) {
      throw new ArgumentError("Invalid property access for 'ManagedObject'. "
          "Property '$propertyName' does not exist on '${MirrorSystem.getName(entity.instanceType.simpleName)}'.");
    }

    return valueMap[propertyName];
  }

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    var property = entity.properties[propertyName];
    if (property == null) {
      throw new ArgumentError("Invalid property access for 'ManagedObject'. "
          "Property '$propertyName' does not exist on '${MirrorSystem.getName(entity.instanceType.simpleName)}'.");
    }

    if (value != null) {
      if (!property.isAssignableWith(value)) {
        throw new ValidationException(["invalid input value for '${propertyName}'"]);
      }
    }

    valueMap[propertyName] = value;
  }
}

class ManagedMatcherBacking extends ManagedBacking {
  @override
  Map<String, dynamic> valueMap = {};

  @override
  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    if (!valueMap.containsKey(propertyName)) {
      var relDesc = entity.relationships[propertyName];
      if (relDesc?.relationshipType == ManagedRelationshipType.hasMany) {
        valueMap[propertyName] = new ManagedSet()
          ..entity = relDesc.destinationEntity;
      } else if (relDesc?.relationshipType == ManagedRelationshipType.hasOne ||
          relDesc?.relationshipType == ManagedRelationshipType.belongsTo) {
        valueMap[propertyName] = relDesc.destinationEntity.newInstance()
          ..backing = new ManagedMatcherBacking();
      }
    }

    return valueMap[propertyName];
  }

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    if (value == null) {
      valueMap.remove(propertyName);
      return;
    }

    if (value is MatcherExpression) {
      var property = entity.properties[propertyName];

      if (property is ManagedRelationshipDescription) {
        var innerObject = valueForProperty(entity, propertyName);
        if (innerObject is ManagedObject) {
          innerObject[innerObject.entity.primaryKey] = value;
        } else if (innerObject is ManagedSet) {
          innerObject.haveAtLeastOneWhere[innerObject.entity.primaryKey] =
              value;
        }
      } else {
        valueMap[propertyName] = value;
      }
    } else {
      final typeName = MirrorSystem.getName(entity.instanceType.simpleName);

      throw new ArgumentError("Invalid query matcher assignment. Tried assigning value to 'Query<$typeName>.where.$propertyName'. Wrap value in 'whereEqualTo()'.");
    }
  }
}

class ManagedAccessTrackingBacking extends ManagedBacking {
  @override
  Map<String, dynamic> get valueMap => null;

  @override
  dynamic valueForProperty(ManagedEntity entity, String propertyName) {
    final prop = entity.properties[propertyName];

    if (prop?.type?.kind == ManagedPropertyType.document) {
      return new KeyPath(propertyName);
    }

    return propertyName;
  }

  @override
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value) {
    // no-op
  }
}
