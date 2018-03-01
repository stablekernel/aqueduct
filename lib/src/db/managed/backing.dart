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

    if (value is PredicateExpression) {
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
  List<KeyPath> keyPaths;
  KeyPath workingKeyPath;

  @override
  Map<String, dynamic> get valueMap => null;

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (workingKeyPath != null) {
      workingKeyPath.add(property);

      return forward(property, workingKeyPath);
    }


    keyPaths ??= [];
    final keyPath = new KeyPath(property);
    keyPaths.add(keyPath);

    return forward(property, keyPath);
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    // no-op
  }

  dynamic forward(ManagedPropertyDescription property, KeyPath keyPath) {
    if (property is ManagedRelationshipDescription) {
      final tracker = new ManagedAccessTrackingBacking()
        ..workingKeyPath = keyPath;
      return property.inverse.entity.newInstance(backing: tracker);
    } else if (property is ManagedAttributeDescription && property.type.kind == ManagedPropertyType.document) {
      return new DocumentAccessTracker(keyPath);
    }

    return null;
  }
}

class DocumentAccessTracker extends Document {
  DocumentAccessTracker(this.owner);

  final KeyPath owner;

  @override
  dynamic operator [](dynamic keyOrIndex) {
    owner.addDynamicElement(keyOrIndex);
    return this;
  }
}
