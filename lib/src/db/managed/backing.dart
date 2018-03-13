import 'dart:mirrors';
import 'package:aqueduct/src/db/managed/key_path.dart';

import 'managed.dart';
import '../query/matcher_internal.dart';
import 'relationship_type.dart';
import 'exception.dart';

class ManagedValueBacking extends ManagedBacking {
  @override
  Map<String, dynamic> contents = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    return contents[property.name];
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (value != null) {
      if (!property.isAssignableWith(value)) {
        throw new ValidationException(["invalid input value for '${property.name}'"]);
      }
    }

    contents[property.name] = value;
  }
}

class ManagedForeignKeyBuilderBacking extends ManagedBacking {
  @override
  Map<String, dynamic> contents = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (property is ManagedAttributeDescription && property.isPrimaryKey) {
      return contents[property.name];
    }


    throw new ArgumentError("Invalid property access. '${property.entity.name}' "
        "is being used in 'Query.values' to build a foreign key column. "
        "Only its primary key can be set.");
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (property is ManagedAttributeDescription && property.isPrimaryKey) {
      contents[property.name] = value;
    }

    throw new ArgumentError("Invalid property access. '${property.entity.name}' "
        "is being used in 'Query.values' to build a foreign key column. "
        "Only its primary key can be set.");
  }
}

class ManagedBuilderBacking extends ManagedBacking {
  @override
  Map<String, dynamic> contents = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (property is ManagedRelationshipDescription) {
      if (!property.isBelongsTo) {
        throw new StateError("Invalid property access. Cannot access has-one or has-many relationship when building 'Query.values'.");
      }

      if(!contents.containsKey(property.name)) {
        contents[property.name] = property.inverse.entity.newInstance(backing: new ManagedForeignKeyBuilderBacking());
      }
    }

    return contents[property.name];
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (property is ManagedRelationshipDescription) {
      if (!property.isBelongsTo) {
        throw new StateError("Invalid property access. Cannot access has-one or has-many relationship when building 'Query.values'.");
      }


    }

    contents[property.name] = value;
  }
}

class ManagedAccessTrackingBacking extends ManagedBacking {
  List<KeyPath> keyPaths;
  KeyPath workingKeyPath;

  @override
  Map<String, dynamic> get contents => null;

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
