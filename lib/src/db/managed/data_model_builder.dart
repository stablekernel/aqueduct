import 'dart:mirrors';
import 'managed.dart';
import '../../utilities/mirror_helpers.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    instanceTypes.forEach((type) {
      var backingMirror = backingMirrorForType(type);
      var entity = new ManagedEntity(
          dataModel,
          tableNameForPersistentTypeMirror(backingMirror),
          reflectClass(type),
          backingMirror);
      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentType.reflectedType] = entity;

      entity.attributes = attributeMapForEntity(entity);
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipMapForEntity(entity);
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> persistentTypeToEntityMap = {};

  String tableNameForPersistentTypeMirror(ClassMirror typeMirror) {
    var tableNameSymbol = #tableName;
    if (typeMirror.staticMembers[tableNameSymbol] != null) {
      return typeMirror.invoke(tableNameSymbol, []).reflectee;
    }

    return MirrorSystem.getName(typeMirror.simpleName);
  }

  Map<String, ManagedAttributeDescription> attributeMapForEntity(
      ManagedEntity entity) {
    Map<String, ManagedAttributeDescription> map = {};

    // Grab actual properties from instance type
    entity.instanceType.declarations.values
        .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
        .where((declMir) => transientFromDeclaration(declMir) != null)
        .forEach((declMir) {
      var key = MirrorSystem.getName(declMir.simpleName);
      map[key] = attributeFromVariableMirror(entity, declMir);
    });

    // Grab getters/setters from instance type, as long as they the right type of Mappable
    entity.instanceType.declarations.values
        .where((declMir) =>
            declMir is MethodMirror &&
            !declMir.isStatic &&
            (declMir.isSetter || declMir.isGetter) &&
            !declMir.isSynthetic)
        .where((declMir) {
          var mapMetadata = transientFromDeclaration(declMir);
          if (mapMetadata == null) {
            return false;
          }

          MethodMirror methodMirror = declMir;

          // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
          return (methodMirror.isSetter && mapMetadata.isAvailableAsInput) ||
              (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
        })
        .map((declMir) => attributeFromMethodMirror(entity, declMir))
        .fold(<String, ManagedAttributeDescription>{},
            (Map<String, ManagedAttributeDescription> collectedMap, attr) {
          if (collectedMap.containsKey(attr.name)) {
            collectedMap[attr.name] = new ManagedAttributeDescription.transient(
                entity, attr.name, attr.type, managedTransientAttribute);
          } else {
            collectedMap[attr.name] = attr;
          }

          return collectedMap;
        })
        .forEach((_, attr) {
          map[attr.name] = attr;
        });

    // Grab persistent values, which must be properties (not relationships)
    entity.persistentType.declarations.values
        .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
        .where((declMir) => !doesVariableMirrorRepresentRelationship(declMir))
        .where((declMir) =>
            !map.containsKey(MirrorSystem.getName(declMir.simpleName)))
        .forEach((declMir) {
      var key = MirrorSystem.getName(declMir.simpleName);
      map[key] = attributeFromVariableMirror(entity, declMir);
    });

    return map;
  }

  ManagedAttributeDescription attributeFromMethodMirror(
      ManagedEntity entity, MethodMirror methodMirror) {
    var name = MirrorSystem.getName(methodMirror.simpleName);
    var dartTypeMirror = methodMirror.returnType;
    if (methodMirror.isSetter) {
      name = name.substring(0, name.length - 1);
      dartTypeMirror = methodMirror.parameters.first.type;
    }

    // We don't care about the mappable on the declaration when we specify it to the AttributeDescription,
    // only whether or not it is a getter/setter.
    return new ManagedAttributeDescription.transient(
        entity,
        name,
        ManagedPropertyDescription
            .propertyTypeForDartType(dartTypeMirror.reflectedType),
        new ManagedTransientAttribute(
            availableAsInput: methodMirror.isSetter,
            availableAsOutput: methodMirror.isGetter));
  }

  ManagedAttributeDescription attributeFromVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    if (entity.instanceType == mirror.owner) {
      // Transient; must be marked as Mappable.

      var name = MirrorSystem.getName(mirror.simpleName);
      var type = ManagedPropertyDescription
          .propertyTypeForDartType(mirror.type.reflectedType);
      if (type == null) {
        throw new ManagedDataModelException(
            "Property $name on ${MirrorSystem.getName(entity.instanceType.simpleName)} has invalid type");
      }
      return new ManagedAttributeDescription.transient(
          entity, name, type, transientFromDeclaration(mirror));
    } else {
      // Persistent
      var attrs = attributeMetadataFromDeclaration(mirror);

      var type = attrs?.databaseType ??
          ManagedPropertyDescription
              .propertyTypeForDartType(mirror.type.reflectedType);
      if (type == null) {
        throw new ManagedDataModelException(
            "Property ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentType.simpleName)} has invalid type");
      }

      return new ManagedAttributeDescription(
          entity, MirrorSystem.getName(mirror.simpleName), type,
          primaryKey: attrs?.isPrimaryKey ?? false,
          defaultValue: attrs?.defaultValue ?? null,
          unique: attrs?.isUnique ?? false,
          indexed: attrs?.isIndexed ?? false,
          nullable: attrs?.isNullable ?? false,
          includedInDefaultResultSet: !(attrs?.shouldOmitByDefault ?? false),
          autoincrement: attrs?.autoincrement ?? false);
    }
  }

  Map<String, ManagedRelationshipDescription> relationshipMapForEntity(
      ManagedEntity entity) {
    Map<String, ManagedRelationshipDescription> map = {};

    entity.persistentType.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror &&
          !declMir.isStatic &&
          doesVariableMirrorRepresentRelationship(declMir)) {
        var key = MirrorSystem.getName(sym);
        map[key] = relationshipFromVariableMirror(entity, declMir);
      }
    });

    return map;
  }

  ManagedRelationshipDescription relationshipFromVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    if (attributeMetadataFromDeclaration(mirror) != null) {
      throw new ManagedDataModelException(
          "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentType.simpleName)} must not define additional Attributes");
    }

    var destinationEntity = destinationEntityForVariableMirror(entity, mirror);
    var belongsToAttr = belongsToMetadataFromDeclaration(mirror);
    var referenceProperty =
        destinationEntity.attributes[destinationEntity.primaryKey];

    if (belongsToAttr != null) {
      var inverseKey = belongsToAttr.inverseKey;
      var destinationVariableMirror =
          destinationEntity.persistentType.declarations[inverseKey];

      if (destinationVariableMirror == null) {
        throw new ManagedDataModelException(
            "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentType.simpleName)} has no inverse (tried $inverseKey)");
      }

      if (belongsToAttr.onDelete == ManagedRelationshipDeleteRule.nullify &&
          belongsToAttr.isRequired) {
        throw new ManagedDataModelException(
            "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} set to nullify on delete, but is not nullable");
      }

      if (belongsToMetadataFromDeclaration(destinationVariableMirror) != null) {
        throw new ManagedDataModelException(
            "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} and ${MirrorSystem.getName(destinationVariableMirror.simpleName)} on ${destinationEntity.tableName} have BelongsTo metadata, only one may belong to the other.");
      }

      return new ManagedRelationshipDescription(
          entity,
          MirrorSystem.getName(mirror.simpleName),
          referenceProperty.type,
          destinationEntity,
          belongsToAttr.onDelete,
          ManagedRelationshipType.belongsTo,
          inverseKey,
          unique: !(destinationVariableMirror as VariableMirror)
              .type
              .isSubtypeOf(reflectType(ManagedSet)),
          indexed: true,
          nullable: !belongsToAttr.isRequired,
          includedInDefaultResultSet: true);
    }

    VariableMirror inversePropertyMirror = destinationEntity
        .persistentType.declarations.values
        .firstWhere((DeclarationMirror destinationDeclarationMirror) {
      if (destinationDeclarationMirror is VariableMirror) {
        var inverseBelongsToAttr =
            belongsToMetadataFromDeclaration(destinationDeclarationMirror);
        var matchesInverseKey =
            inverseBelongsToAttr?.inverseKey == mirror.simpleName;
        var isBelongsToVarMirrorSubtypeRightType =
            destinationDeclarationMirror.type.isSubtypeOf(entity.instanceType);

        if (matchesInverseKey && isBelongsToVarMirrorSubtypeRightType) {
          return true;
        }
      }

      return false;
    }, orElse: () => null);

    if (inversePropertyMirror == null) {
      throw new ManagedDataModelException(
          "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} has no inverse declared in ${MirrorSystem.getName(destinationEntity.persistentType.simpleName)} of appropriate type.");
    }

    var relType = ManagedRelationshipType.hasOne;
    if (mirror.type.isSubtypeOf(reflectType(ManagedSet))) {
      relType = ManagedRelationshipType.hasMany;
    }

    return new ManagedRelationshipDescription(
        entity,
        MirrorSystem.getName(mirror.simpleName),
        referenceProperty.type,
        destinationEntity,
        belongsToAttr?.onDelete,
        relType,
        inversePropertyMirror.simpleName,
        unique: false,
        indexed: true,
        nullable: false,
        includedInDefaultResultSet: false);
  }

  ManagedEntity destinationEntityForVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    var typeMirror = mirror.type;
    if (mirror.type.isSubtypeOf(reflectType(ManagedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      throw new ManagedDataModelException(
          "Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentType.simpleName)} destination ModelEntity does not exist");
    }

    return destinationEntity;
  }

  ClassMirror backingMirrorForType(Type instanceType) {
    var rt = reflectClass(instanceType);
    var modelRefl = reflectType(ManagedObject);
    var entityTypeRefl = rt;

    while (rt.superclass.isSubtypeOf(modelRefl)) {
      rt = rt.superclass;
      entityTypeRefl = rt;
    }

    if (rt.isSubtypeOf(modelRefl)) {
      entityTypeRefl = entityTypeRefl.typeArguments.first;
    } else {
      throw new ManagedDataModelException(
          "Invalid instance type $instanceType ${reflectClass(instanceType).simpleName}");
    }

    return entityTypeRefl;
  }
}
