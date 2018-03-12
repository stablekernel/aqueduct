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
