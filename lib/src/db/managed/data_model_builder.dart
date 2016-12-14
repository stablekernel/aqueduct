import 'entity_mirrors.dart';
import 'dart:mirrors';
import 'managed.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    instanceTypes.forEach((type) {
      var backingMirror = persistentTypeOfInstanceType(type);
      var entity = new ManagedEntity(dataModel,
          tableNameFromClass(backingMirror), reflectClass(type), backingMirror);
      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentType.reflectedType] = entity;

      entity.attributes = attributesForEntity(entity);
      if (entity.primaryKey == null) {
        throw new ManagedDataModelException.noPrimaryKey(entity);
      }
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipsForEntity(entity);
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> persistentTypeToEntityMap = {};

  String tableNameFromClass(ClassMirror typeMirror) {
    var declaredTableNameClass = classHierarchyForClass(typeMirror).firstWhere(
        (cm) => cm.staticMembers[#tableName] != null,
        orElse: () => null);

    if (declaredTableNameClass == null) {
      return MirrorSystem.getName(typeMirror.simpleName);
    }
    return declaredTableNameClass.invoke(#tableName, []).reflectee;
  }

  ClassMirror persistentTypeOfInstanceType(Type instanceType) {
    var ifNotFoundException = new ManagedDataModelException(
        "Invalid instance type '$instanceType' '${reflectClass(instanceType)
            .simpleName}' is not subclass of 'ManagedObject'.");

    return classHierarchyForClass(reflectClass(instanceType))
        .firstWhere(
            (cm) => !cm.superclass.isSubtypeOf(reflectType(ManagedObject)),
            orElse: () => throw ifNotFoundException)
        .typeArguments
        .first;
  }

  Map<String, ManagedAttributeDescription> attributesForEntity(
      ManagedEntity entity) {
    var transientProperties = transientAttributesForEntity(entity);
    var persistentProperties = persistentAttributesForEntity(entity);

    return [transientProperties, persistentProperties].expand((l) => l).fold({},
        (map, attribute) {
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

  Iterable<ManagedAttributeDescription> persistentAttributesForEntity(
      ManagedEntity entity) {
    return instanceVariablesFromClass(entity.persistentType)
        .where((declaration) =>
            !doesVariableMirrorRepresentRelationship(declaration))
        .map((declaration) {
      var type = propertyTypeFromDeclaration(declaration);
      if (type == null) {
        throw new ManagedDataModelException.invalidType(
            entity, declaration.simpleName);
      }

      var attributes = attributeMetadataFromDeclaration(declaration);
      var name = propertyNameFromDeclaration(declaration);
      return new ManagedAttributeDescription(entity, name, type,
          primaryKey: attributes?.isPrimaryKey ?? false,
          defaultValue: attributes?.defaultValue ?? null,
          unique: attributes?.isUnique ?? false,
          indexed: attributes?.isIndexed ?? false,
          nullable: attributes?.isNullable ?? false,
          includedInDefaultResultSet:
              !(attributes?.shouldOmitByDefault ?? false),
          autoincrement: attributes?.autoincrement ?? false);
    });
  }

  Iterable<ManagedAttributeDescription> transientAttributesForEntity(
      ManagedEntity entity) {
    return entity.instanceType.declarations.values
        .where(isTransientPropertyOrAccessor)
        .map((declaration) {
      var type = propertyTypeFromDeclaration(declaration);
      if (type == null) {
        throw new ManagedDataModelException.invalidType(
            entity, declaration.simpleName);
      }

      var name = propertyNameFromDeclaration(declaration);
      var transience = transienceForProperty(declaration);
      if (transience == null) {
        throw new ManagedDataModelException.invalidTransient(
            entity, declaration.simpleName);
      }

      return new ManagedAttributeDescription.transient(
          entity, name, type, transience);
    });
  }

  ManagedTransientAttribute transienceForProperty(DeclarationMirror property) {
    if (property is VariableMirror) {
      return transientMetadataFromDeclaration(property);
    }

    var metadata = transientMetadataFromDeclaration(property);
    MethodMirror m = property as MethodMirror;
    if (m.isGetter && metadata.isAvailableAsOutput) {
      return new ManagedTransientAttribute(
          availableAsOutput: true, availableAsInput: false);
    } else if (m.isSetter && metadata.isAvailableAsInput) {
      return new ManagedTransientAttribute(
          availableAsInput: true, availableAsOutput: false);
    }

    return null;
  }

  Map<String, ManagedRelationshipDescription> relationshipsForEntity(
      ManagedEntity entity) {
    return instanceVariablesFromClass(entity.persistentType)
        .where(doesVariableMirrorRepresentRelationship)
        .fold({}, (map, declaration) {
      var key = MirrorSystem.getName(declaration.simpleName);
      map[key] = relationshipFromProperty(entity, declaration);

      return map;
    });
  }

  ManagedRelationshipDescription relationshipFromProperty(
      ManagedEntity owningEntity, VariableMirror property) {
    var destinationEntity = matchingEntityForProperty(owningEntity, property);

    if (attributeMetadataFromDeclaration(property) != null) {
      throw new ManagedDataModelException.invalidMetadata(
          owningEntity, property.simpleName, destinationEntity);
    }

    if (relationshipMetadataFromProperty(property) != null) {
      return relationshipForForeignKeyProperty(
          owningEntity, destinationEntity, property);
    }

    return relationshipDescriptionForHasManyOrOneProperty(
        owningEntity, destinationEntity, property);
  }

  ManagedRelationshipDescription relationshipForForeignKeyProperty(
      ManagedEntity owningEntity,
      ManagedEntity destinationEntity,
      VariableMirror property) {
    var relationship = relationshipMetadataFromProperty(property);

    // Make sure the relationship parameters are valid
    if (relationship.onDelete == ManagedRelationshipDeleteRule.nullify &&
        relationship.isRequired) {
      throw new ManagedDataModelException.incompatibleDeleteRule(
          owningEntity, property.simpleName);
    }

    var inverseProperty =
        inverseRelationshipProperty(owningEntity, destinationEntity, property);

    // Make sure we didn't annotate both sides
    if (relationshipMetadataFromProperty(inverseProperty) != null) {
      throw new ManagedDataModelException.dualMetadata(owningEntity,
          property.simpleName, destinationEntity, inverseProperty.simpleName);
    }

    var columnType =
        destinationEntity.attributes[destinationEntity.primaryKey].type;

    return new ManagedRelationshipDescription(
        owningEntity,
        MirrorSystem.getName(property.simpleName),
        columnType,
        destinationEntity,
        relationship.onDelete,
        ManagedRelationshipType.belongsTo,
        inverseProperty.simpleName,
        unique: !inverseProperty.type.isSubtypeOf(reflectType(ManagedSet)),
        indexed: true,
        nullable: !relationship.isRequired,
        includedInDefaultResultSet: true);
  }

  ManagedRelationshipDescription relationshipDescriptionForHasManyOrOneProperty(
      ManagedEntity owningEntity,
      ManagedEntity destinationEntity,
      VariableMirror property) {
    var managedRelationship = relationshipMetadataFromProperty(property);

    var inverseProperty =
        inverseRelationshipProperty(owningEntity, destinationEntity, property);

    var relType = ManagedRelationshipType.hasOne;
    if (property.type.isSubtypeOf(reflectType(ManagedSet))) {
      relType = ManagedRelationshipType.hasMany;
    }

    var columnType =
        destinationEntity.attributes[destinationEntity.primaryKey].type;

    return new ManagedRelationshipDescription(
        owningEntity,
        MirrorSystem.getName(property.simpleName),
        columnType,
        destinationEntity,
        managedRelationship?.onDelete,
        relType,
        inverseProperty.simpleName,
        unique: false,
        indexed: true,
        nullable: false,
        includedInDefaultResultSet: false);
  }

  ManagedEntity matchingEntityForProperty(
      ManagedEntity owningEntity, VariableMirror property) {
    var typeMirror = property.type;
    if (property.type.isSubtypeOf(reflectType(ManagedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      var relationshipMetadata = relationshipMetadataFromProperty(property);
      if (relationshipMetadata.isDeferred) {
        // Then we can scan for a list of possible entities that extend
        // the interface.
        var possibleEntities = entities.values.where((me) {
          return me.persistentType.isSubtypeOf(typeMirror);
        }).toList();

        if (possibleEntities.length == 0) {
          throw new ManagedDataModelException.noDestinationEntity(
              owningEntity, property.simpleName);
        } else if (possibleEntities.length > 1) {
          throw new ManagedDataModelException.multipleDestinationEntities(
              owningEntity, property.simpleName, possibleEntities);
        }

        destinationEntity = possibleEntities.first;
      } else {
        throw new ManagedDataModelException.noDestinationEntity(
            owningEntity, property.simpleName);
      }
    }

    return destinationEntity;
  }

  List<VariableMirror> entityRelationshipsWithType(
      ManagedEntity entity, TypeMirror type) {
    return instanceVariablesFromClass(entity.persistentType).where((p) {
      if (p.type.isSubtypeOf(type)) {
        return true;
      }

      if (p.type.isSubtypeOf(reflectType(ManagedSet)) &&
          p.type.typeArguments.first.isSubtypeOf(type)) {
        return true;
      }

      return false;
    }).toList();
  }

  VariableMirror inverseRelationshipProperty(ManagedEntity owningEntity,
      ManagedEntity destinationEntity, VariableMirror property) {
    var metadata = relationshipMetadataFromProperty(property);
    if (metadata != null) {
      // Looking for the has-a side, which has an explicit inverse.
      if (!metadata.isDeferred) {
        var destinationProperty = instanceVariableFromClass(
            destinationEntity.persistentType, metadata.inversePropertyName);
        if (destinationProperty == null) {
          throw new ManagedDataModelException.missingInverse(
              owningEntity, property.simpleName, destinationEntity, null);
        }

        if (relationshipMetadataFromProperty(destinationProperty) != null) {
          throw new ManagedDataModelException.dualMetadata(
              owningEntity,
              property.simpleName,
              destinationEntity,
              destinationProperty.simpleName);
        }

        return destinationProperty;
      } else {
        // Looking for the has-a side, but it is deferred.
        var candidates = entityRelationshipsWithType(
            destinationEntity, owningEntity.instanceType);
        if (candidates.length == 0) {
          throw new ManagedDataModelException.missingInverse(
              owningEntity, property.simpleName, destinationEntity, null);
        } else if (candidates.length > 1) {
          throw new ManagedDataModelException.duplicateInverse(
              owningEntity,
              property.simpleName,
              destinationEntity,
              candidates.map((v) => v.simpleName).toList());
        }

        return candidates.first;
      }
    } else {
      // Looking for the belongs to side, which might be deferred on the other side
      // If we have an explicit inverse, look for that first.

      var candidates =
          instanceVariablesFromClass(destinationEntity.persistentType)
              .where((p) => relationshipMetadataFromProperty(p) != null)
              .toList();

      if (candidates.length == 0) {
        throw new ManagedDataModelException.missingInverse(
            owningEntity, property.simpleName, destinationEntity, null);
      }

      var specificInverse = candidates.firstWhere(
          (p) =>
              relationshipMetadataFromProperty(p).inversePropertyName ==
              property.simpleName,
          orElse: () => null);
      if (specificInverse != null) {
        return specificInverse;
      }

      if (candidates.length > 1) {
        throw new ManagedDataModelException.duplicateInverse(
            owningEntity,
            property.simpleName,
            destinationEntity,
            candidates.map((v) => v.simpleName).toList());
      }

      return candidates.first;
    }
  }
}
