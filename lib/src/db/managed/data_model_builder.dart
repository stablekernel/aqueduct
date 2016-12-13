import 'entity_mirrors.dart';
import 'dart:mirrors';
import 'managed.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    instanceTypes.forEach((type) {
      var backingMirror = backingMirrorForType(type);
      var entity = new ManagedEntity(
          dataModel,
          tableNameFromClass(backingMirror),
          reflectClass(type),
          backingMirror);
      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentType.reflectedType] = entity;

      entity.attributes = attributeMapForEntity(entity);
      if (entity.primaryKey == null) {
        throw new ManagedDataModelException.noPrimaryKey(entity);
      }
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipMapForEntity(entity);
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> persistentTypeToEntityMap = {};

  String tableNameFromClass(ClassMirror typeMirror) {
    var declaredTableNameClass = classHierarchyForClass(typeMirror)
        .firstWhere((cm) => cm.staticMembers[#tableName] != null,
        orElse: () => null);

    if (declaredTableNameClass == null) {
      return MirrorSystem.getName(typeMirror.simpleName);
    }
    return declaredTableNameClass
        .invoke(#tableName, [])
        .reflectee;
  }

  Map<String, ManagedAttributeDescription> attributeMapForEntity(
      ManagedEntity entity) {
    var transientProperties = entity.instanceType.declarations.values
        .where(isInstanceVariableMirror)
        .where(hasTransientMetadata)
        .map((dm) => attributeFromVariableMirror(entity, dm));

    var transientAccessors = entity.instanceType.declarations.values
        .where(isTransientAccessorMethod)
        .map((declMir) => attributeFromMethodMirror(entity, declMir));

    var persistentProperties = instanceVariableMirrorsFromClass(
        entity.persistentType)
        .where((declMir) => !doesVariableMirrorRepresentRelationship(declMir))
        .map((declMir) => attributeFromVariableMirror(entity, declMir));

    return [transientProperties, transientAccessors, persistentProperties]
        .expand((l) => l)
        .fold({}, (map, attribute) {
      if (map.containsKey(attribute.name)) {
        // If there is both a getter and setter declared to represent one transient property,
        // then we need to combine them here. No other reason a property would appear twice.
        map[attribute.name] = new ManagedAttributeDescription.transient(
            entity, attribute.name, attribute.type, managedTransientAttribute);
      } else {
        map[attribute.name] = attribute;
      }
      return map;
    });
  }

  ManagedAttributeDescription attributeFromMethodMirror(ManagedEntity entity,
      MethodMirror methodMirror) {
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

  ManagedAttributeDescription attributeFromVariableMirror(ManagedEntity entity,
      VariableMirror mirror) {
    var name = MirrorSystem.getName(mirror.simpleName);

    if (entity.instanceType == mirror.owner) {
      // This attribute is declared in the instance type.
      var type = ManagedPropertyDescription
          .propertyTypeForDartType(mirror.type.reflectedType);

      if (type == null) {
        throw new ManagedDataModelException.invalidType(
            entity, mirror.simpleName);
      }

      return new ManagedAttributeDescription.transient(
          entity, name, type, transientFromDeclaration(mirror));
    } else {
      // This attribute is declared in the persistent type.
      var attributes = attributeMetadataFromDeclaration(mirror);
      var type = attributes?.databaseType ??
          ManagedPropertyDescription
              .propertyTypeForDartType(mirror.type.reflectedType);

      if (type == null) {
        throw new ManagedDataModelException.invalidType(
            entity, mirror.simpleName);
      }

      return new ManagedAttributeDescription(
          entity, MirrorSystem.getName(mirror.simpleName), type,
          primaryKey: attributes?.isPrimaryKey ?? false,
          defaultValue: attributes?.defaultValue ?? null,
          unique: attributes?.isUnique ?? false,
          indexed: attributes?.isIndexed ?? false,
          nullable: attributes?.isNullable ?? false,
          includedInDefaultResultSet: !(attributes?.shouldOmitByDefault ??
              false),
          autoincrement: attributes?.autoincrement ?? false);
    }
  }

  Map<String, ManagedRelationshipDescription> relationshipMapForEntity(
      ManagedEntity entity) {
    return instanceVariableMirrorsFromClass(entity.persistentType)
        .where(doesVariableMirrorRepresentRelationship)
        .fold({}, (map, declMirror) {
      map[MirrorSystem.getName(declMirror.simpleName)] =
          relationshipFromVariableMirror(entity, declMirror);
      return map;
    });
  }

  ManagedRelationshipDescription relationshipFromVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    var destinationEntity = destinationEntityForVariableMirror(entity, mirror);

    if (attributeMetadataFromDeclaration(mirror) != null) {
      throw new ManagedDataModelException.invalidMetadata(
          entity, mirror.simpleName, destinationEntity);
    }

    if (managedRelationshipMetadataFromDeclaration(mirror) != null) {
      return relationshipDescriptionForForeignKeyProperty(
          entity, destinationEntity, mirror);
    }

    return relationshipDescriptionForHasManyOrOneProperty(
        entity, destinationEntity, mirror);
  }

  ManagedRelationshipDescription relationshipDescriptionForForeignKeyProperty(
      ManagedEntity entity, ManagedEntity destinationEntity,
      VariableMirror mirror) {
    var managedRelationship = managedRelationshipMetadataFromDeclaration(
        mirror);
    var referenceProperty =
    destinationEntity.attributes[destinationEntity.primaryKey];

    var inverseKey = managedRelationship.inverseKey;
    var destinationVariableMirror = variableMirrorFromClass(
        destinationEntity.persistentType, inverseKey);
    if (destinationVariableMirror == null) {
      throw new ManagedDataModelException.missingInverse(
          entity, mirror.simpleName, destinationEntity, inverseKey);
    }

    if (managedRelationship.onDelete == ManagedRelationshipDeleteRule.nullify &&
        managedRelationship.isRequired) {
      throw new ManagedDataModelException.incompatibleDeleteRule(
          entity, mirror.simpleName);
    }

    if (managedRelationshipMetadataFromDeclaration(destinationVariableMirror) !=
        null) {
      throw new ManagedDataModelException.dualMetadata(
          entity, mirror.simpleName, destinationEntity,
          destinationVariableMirror.simpleName);
    }

    return new ManagedRelationshipDescription(
        entity,
        MirrorSystem.getName(mirror.simpleName),
        referenceProperty.type,
        destinationEntity,
        managedRelationship.onDelete,
        ManagedRelationshipType.belongsTo,
        inverseKey,
        unique: !destinationVariableMirror.type.isSubtypeOf(
            reflectType(ManagedSet)),
        indexed: true,
        nullable: !managedRelationship.isRequired,
        includedInDefaultResultSet: true);
  }

  ManagedRelationshipDescription relationshipDescriptionForHasManyOrOneProperty(
      ManagedEntity entity, ManagedEntity destinationEntity,
      VariableMirror mirror) {
    var managedRelationship = managedRelationshipMetadataFromDeclaration(
        mirror);
    var referenceProperty = destinationEntity.attributes[destinationEntity
        .primaryKey];
    VariableMirror inversePropertyMirror =
    instanceVariableMirrorsFromClass(destinationEntity.persistentType)
        .firstWhere((DeclarationMirror destinationDeclarationMirror) {
      if (destinationDeclarationMirror is VariableMirror) {
        var inverseBelongsToAttr =
        managedRelationshipMetadataFromDeclaration(
            destinationDeclarationMirror);
        var matchesInverseKey =
            inverseBelongsToAttr?.inverseKey == mirror.simpleName;

        var hasRightType = entity
            .instanceType.isSubtypeOf(destinationDeclarationMirror.type);

        if (matchesInverseKey && hasRightType) {
          return true;
        }
      }

      return false;
    }, orElse: () => null);

    if (inversePropertyMirror == null) {
      throw new ManagedDataModelException.missingInverse(
          entity, mirror.simpleName, destinationEntity, null);
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
        managedRelationship?.onDelete,
        relType,
        inversePropertyMirror.simpleName,
        unique: false,
        indexed: true,
        nullable: false,
        includedInDefaultResultSet: false);
  }

  ManagedEntity destinationEntityForVariableMirror(ManagedEntity entity,
      VariableMirror mirror) {
    var typeMirror = mirror.type;
    if (mirror.type.isSubtypeOf(reflectType(ManagedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      var relationshipMetadata = managedRelationshipMetadataFromDeclaration(
          mirror);
      if (relationshipMetadata.isDeferred) {
        // Then we can scan for a list of possible entities that extend
        // the interface.
        var possibleEntities = entities.values.where((me) {
          return me.persistentType.isSubtypeOf(typeMirror);
        }).toList();

        if (possibleEntities.length == 0) {
          throw new ManagedDataModelException.noDestinationEntity(
              entity, mirror.simpleName);
        } else if (possibleEntities.length > 1) {
          throw new ManagedDataModelException.multipleDestinationEntities(
              entity, mirror.simpleName, possibleEntities);
        }

        destinationEntity = possibleEntities.first;
      } else {
        throw new ManagedDataModelException.noDestinationEntity(
            entity, mirror.simpleName);
      }
    }

    return destinationEntity;
  }

  ClassMirror backingMirrorForType(Type instanceType) {
    var ifNotFoundException = new ManagedDataModelException(
        "Invalid instance type '$instanceType' '${reflectClass(instanceType)
            .simpleName}'");

    return classHierarchyForClass(reflectClass(instanceType))
        .firstWhere((cm) =>
    !cm.superclass.isSubtypeOf(reflectType(ManagedObject)),
        orElse: () => throw ifNotFoundException)
        .typeArguments
        .first;
  }
}

