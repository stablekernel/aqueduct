import 'entity_mirrors.dart';
import 'dart:mirrors';
import 'managed.dart';
import 'relationship_type.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    instanceTypes.forEach((type) {
      var backingMirror = persistentTypeOfInstanceType(type);
      var name = tableNameFromClass(backingMirror);
      var entity = new ManagedEntity(dataModel, name, reflectClass(type), backingMirror);

      var existingEntityWithThisTableName = entities
          .values
          .firstWhere((e) => e.tableName == entity.tableName,
            orElse: () => null);
      if (existingEntityWithThisTableName != null) {
        throw new ManagedDataModelError.duplicateTables(existingEntityWithThisTableName, entity);
      }

      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentType.reflectedType] = entity;

      entity.attributes = attributesForEntity(entity);
      entity.validators = entity.attributes.values
          .map((desc) => desc.validators.map((v) => new ManagedValidator(desc, v)))
          .expand((e) => e)
          .toList();
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipsForEntity(entity);

      // Verify we don't have cyclic refs; we can do this here, before
      // every relationship has been established, because if there is a cyclic
      // reference, we'll catch one of them.
      entity.relationships.forEach((_, rel) {
        if (rel.relationshipType == ManagedRelationshipType.belongsTo) {
          var foreignKey = rel.destinationEntity.relationships?.values
              ?.firstWhere((r) => r.relationshipType == ManagedRelationshipType.belongsTo
                              && r.destinationEntity == entity, orElse: () => null);
          if (foreignKey != null) {
            throw new ManagedDataModelError.cyclicReference(
                entity, new Symbol(rel.name), foreignKey.entity, new Symbol(foreignKey.name));
          }
        }
      });

      entity.uniquePropertySet = instanceUniquePropertiesForEntity(entity);

      entity.symbolMap = {};
      entity.attributes.forEach((name, _) {
        entity.symbolMap[new Symbol(name)] = name;
        entity.symbolMap[new Symbol("$name=")] = name;
      });
      entity.relationships.forEach((name, _) {
        entity.symbolMap[new Symbol(name)] = name;
        entity.symbolMap[new Symbol("$name=")] = name;
      });
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
    var ifNotFoundException = new ManagedDataModelError(
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
            entity, attribute.name, attribute.type, new Serialize(input: true, output: true));
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
        throw new ManagedDataModelError.invalidType(
            entity, declaration.simpleName);
      }

      var validators = validatorsFromDeclaration(declaration);
      var attributes = attributeMetadataFromDeclaration(declaration);
      var name = propertyNameFromDeclaration(declaration);
      var enumToPropertyNameMap;
      var declType = declaration.type;
      if (declType is ClassMirror && declType.isEnum) {
        List<dynamic> enumeratedCases = declType.getField(#values).reflectee;
        enumToPropertyNameMap = enumeratedCases.fold({}, (m, v) {
          m[v.toString().split(".").last] = v;
          return m;
        });
      }

      return new ManagedAttributeDescription(entity, name, type,
          primaryKey: attributes?.isPrimaryKey ?? false,
          defaultValue: attributes?.defaultValue ?? null,
          unique: attributes?.isUnique ?? false,
          indexed: attributes?.isIndexed ?? false,
          nullable: attributes?.isNullable ?? false,
          includedInDefaultResultSet:
              !(attributes?.shouldOmitByDefault ?? false),
          autoincrement: attributes?.autoincrement ?? false,
          validators: validators,
          enumerationValueMap: enumToPropertyNameMap);
    });
  }

  Iterable<ManagedAttributeDescription> transientAttributesForEntity(
      ManagedEntity entity) {
    return entity.instanceType.declarations.values
        .where(isTransientPropertyOrAccessor)
        .map((declaration) {
      var type = propertyTypeFromDeclaration(declaration);
      if (type == null) {
        throw new ManagedDataModelError.invalidType(
            entity, declaration.simpleName);
      }

      var name = propertyNameFromDeclaration(declaration);
      var transience = transienceForProperty(declaration);
      if (transience == null) {
        throw new ManagedDataModelError.invalidTransient(
            entity, declaration.simpleName);
      }

      return new ManagedAttributeDescription.transient(
          entity, name, type, transience);
    });
  }

  Serialize transienceForProperty(DeclarationMirror property) {
    if (property is VariableMirror) {
      return transientMetadataFromDeclaration(property);
    }

    var metadata = transientMetadataFromDeclaration(property);
    MethodMirror m = property as MethodMirror;
    if (m.isGetter && metadata.isAvailableAsOutput) {
      return new Serialize(
          output: true, input: false);
    } else if (m.isSetter && metadata.isAvailableAsInput) {
      return new Serialize(
          input: true, output: false);
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
      throw new ManagedDataModelError.invalidMetadata(
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
    if (relationship.onDelete == DeleteRule.nullify &&
        relationship.isRequired) {
      throw new ManagedDataModelError.incompatibleDeleteRule(
          owningEntity, property.simpleName);
    }

    var inverseProperty =
        inverseRelationshipProperty(owningEntity, destinationEntity, property);

    // Make sure we didn't annotate both sides
    if (relationshipMetadataFromProperty(inverseProperty) != null) {
      throw new ManagedDataModelError.dualMetadata(owningEntity,
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
          throw new ManagedDataModelError.noDestinationEntity(
              owningEntity, property.simpleName);
        } else if (possibleEntities.length > 1) {
          throw new ManagedDataModelError.multipleDestinationEntities(
              owningEntity, property.simpleName, possibleEntities);
        }

        destinationEntity = possibleEntities.first;
      } else {
        throw new ManagedDataModelError.noDestinationEntity(
            owningEntity, property.simpleName);
      }
    }

    return destinationEntity;
  }

  List<VariableMirror> propertiesFromEntityWithType(
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
      // This is the belongs to side. Looking for the has-a side, which has an explicit inverse.
      if (!metadata.isDeferred) {
        var destinationProperty = instanceVariableFromClass(
            destinationEntity.persistentType, metadata.inversePropertyName);
        if (destinationProperty == null) {
          throw new ManagedDataModelError.missingInverse(
              owningEntity, property.simpleName, destinationEntity, null);
        }

        if (relationshipMetadataFromProperty(destinationProperty) != null) {
          throw new ManagedDataModelError.dualMetadata(
              owningEntity,
              property.simpleName,
              destinationEntity,
              destinationProperty.simpleName);
        }

        return destinationProperty;
      } else {
        // This is the belongs to side. Looking for the has-a side, but it is deferred.
        var candidates = propertiesFromEntityWithType(
            destinationEntity, owningEntity.instanceType);
        if (candidates.length == 0) {
          throw new ManagedDataModelError.missingInverse(
              owningEntity, property.simpleName, destinationEntity, null);
        } else if (candidates.length > 1) {
          throw new ManagedDataModelError.duplicateInverse(
              owningEntity,
              property.simpleName,
              destinationEntity,
              candidates.map((v) => v.simpleName).toList());
        }

        return candidates.first;
      }
    } else {
      // This is the has-a side. Looking for the belongs to side, which might be deferred on the other side
      // If we have an explicit inverse, look for that first.
      var candidates =
          instanceVariablesFromClass(destinationEntity.persistentType)
              .where((p) => relationshipMetadataFromProperty(p) != null)
              .toList();

      if (candidates.length == 0) {
        throw new ManagedDataModelError.missingInverse(
            owningEntity, property.simpleName, destinationEntity, null);
      }

      var specificInverses = candidates.where((p) {
        return relationshipMetadataFromProperty(p).inversePropertyName ==
            property.simpleName &&
        owningEntity.instanceType.isSubtypeOf(p.type);
      }).toList();
      if (specificInverses.length == 1) {
        return specificInverses.first;
      } else if (specificInverses.length > 1) {
        throw new ManagedDataModelError.duplicateInverse(
            owningEntity, property.simpleName, destinationEntity,
            candidates.map((vm) => vm.simpleName).toList());
      }

      // We may be deferring, so check for those and make sure the types match up.
      var deferredCandidates = candidates
          .where((p) => relationshipMetadataFromProperty(p).isDeferred)
          .where((p) => owningEntity.persistentType.isSubtypeOf(p.type))
          .toList();
      if (deferredCandidates.length == 0) {
        VariableMirror candidate;
        if (candidates.length > 0) {
          candidate = candidates.first;
        }
        throw new ManagedDataModelError.missingInverse(
            owningEntity, property.simpleName, destinationEntity, candidate?.simpleName);
      }

      if (deferredCandidates.length > 1) {
        throw new ManagedDataModelError.duplicateInverse(
            owningEntity,
            property.simpleName,
            destinationEntity,
            candidates.map((v) => v.simpleName).toList());
      }

      return deferredCandidates.first;
    }
  }

  List<ManagedPropertyDescription> instanceUniquePropertiesForEntity(ManagedEntity entity) {
    Table tableAttributes = entity.persistentType.metadata
        .firstWhere((im) => im.type.isSubtypeOf(reflectType(Table)),
          orElse: () => null)?.reflectee;

    if (tableAttributes?.uniquePropertySet != null) {
      if (tableAttributes.uniquePropertySet.length == 0) {
        throw new ManagedDataModelError.emptyEntityUniqueProperties(entity);
      } else if (tableAttributes.uniquePropertySet.length == 1) {
        throw new ManagedDataModelError.singleEntityUniqueProperty(
            entity, tableAttributes.uniquePropertySet.first);
      }

      return tableAttributes
          .uniquePropertySet
          .map((sym) {
            var prop = entity.properties[MirrorSystem.getName(sym)];
            if (prop == null) {
              throw new ManagedDataModelError.invalidEntityUniqueProperty(entity, sym);
            }

            if (prop is ManagedRelationshipDescription
            && prop.relationshipType != ManagedRelationshipType.belongsTo) {
              throw new ManagedDataModelError.relationshipEntityUniqueProperty(entity, sym);
            }

            return prop;
          })
          .toList();
    }

    return null;
  }
}
