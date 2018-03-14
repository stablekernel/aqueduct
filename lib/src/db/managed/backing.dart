import 'dart:mirrors';
import 'package:aqueduct/src/db/managed/key_path.dart';

import 'managed.dart';
import '../query/matcher_internal.dart';
import 'relationship_type.dart';
import 'exception.dart';

final ArgumentError _invalidValueConstruction = new ArgumentError("Invalid property access when building 'Query.values'. "
    "May only assign values to properties backed by a column of the table being inserted into. "
    "This prohibits 'ManagedObject' and 'ManagedSet' properties, except for 'ManagedObject' "
    "properties with a 'Relate' annotation. For 'Relate' properties, you may only set their "
    "primary key property.");

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
  ManagedForeignKeyBuilderBacking();
  ManagedForeignKeyBuilderBacking.from(ManagedEntity entity, ManagedBacking backing) {
    if (backing.contents.containsKey(entity.primaryKey)) {
      contents[entity.primaryKey] = backing.contents[entity.primaryKey];
    }
  }

  @override
  Map<String, dynamic> contents = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (property is ManagedAttributeDescription && property.isPrimaryKey) {
      return contents[property.name];
    }

    throw _invalidValueConstruction;
  }

  @override
  void setValueForProperty(ManagedPropertyDescription property, dynamic value) {
    if (property is ManagedAttributeDescription && property.isPrimaryKey) {
      contents[property.name] = value;
      return;
    }

    throw _invalidValueConstruction;
  }
}

class ManagedBuilderBacking extends ManagedBacking {
  ManagedBuilderBacking();
  ManagedBuilderBacking.from(ManagedEntity entity, ManagedBacking original) {
    if (original is! ManagedValueBacking) {
      throw new ArgumentError("Invalid 'ManagedObject' assignment to 'Query.values'. Object must be created through default constructor.");
    }

    original.contents.forEach((key, value) {
      final prop = entity.properties[key];
      if (prop == null) {
        throw new ArgumentError("Invalid 'ManagedObject' assignment to 'Query.values'. Property '$key' does not exist for '${entity.name}'.");
      }

      if (prop is ManagedRelationshipDescription) {
        if (!prop.isBelongsTo) {
          return;
        }
      }

      setValueForProperty(prop, value);
    });
  }

  @override
  Map<String, dynamic> contents = {};

  @override
  dynamic valueForProperty(ManagedPropertyDescription property) {
    if (property is ManagedRelationshipDescription) {
      if (!property.isBelongsTo) {
        throw _invalidValueConstruction;
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
        throw _invalidValueConstruction;
      }

      final original = (value as ManagedObject);
      final replacementBacking = new ManagedForeignKeyBuilderBacking.from(original.entity, original.backing);
      final replacement = original.entity.newInstance(backing: replacementBacking);
      contents[property.name] = replacement;
    } else {
      contents[property.name] = value;
    }
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
