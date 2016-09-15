part of aqueduct;

class _DataModelBuilder {
  _DataModelBuilder(DataModel dataModel, List<Type> modelTypes) {
    modelTypes.forEach((type) {
      var entity = new ModelEntity(dataModel, reflectClass(type), backingMirrorForType(type));
      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentTypeMirror.reflectedType] = entity;
    });

    entities.forEach((_, entity) {
      entity._tableName = tableNameForEntity(entity);
      entity.attributes = attributeMapForEntity(entity);
      entity._primaryKey = entity.attributes.values
          .firstWhere((attrDesc) => attrDesc.isPrimaryKey, orElse: () => null)
          ?.name;

      if (entity.primaryKey == null) {
        throw new DataModelException("No primary key for entity ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)}");
      }
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipMapForEntity(entity);
    });
  }

  Map<Type, ModelEntity> entities = {};
  Map<Type, ModelEntity> persistentTypeToEntityMap = {};

  String tableNameForEntity(ModelEntity entity) {
    var tableNameSymbol = new Symbol("tableName");
    if (entity.persistentTypeMirror.staticMembers[tableNameSymbol] != null) {
      return entity.persistentTypeMirror
          .invoke(tableNameSymbol, [])
          .reflectee;
    }

    return MirrorSystem.getName(entity.persistentTypeMirror.simpleName);
  }

  Map<String, AttributeDescription> attributeMapForEntity(ModelEntity entity) {
    Map<String, AttributeDescription> map = {};

    // Grab actual properties from model type
    entity.modelTypeMirror.declarations.values
      .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
      .where((declMir) => _mappableFromDeclaration(declMir) != null)
      .forEach((declMir) {
        var key = MirrorSystem.getName(declMir.simpleName);
        map[key] = attributeFromVariableMirror(entity, declMir);
      });

    // Grab getters/setters from model type, as long as they the right type of Mappable
    entity.modelTypeMirror.declarations.values
      .where((declMir) => declMir is MethodMirror && !declMir.isStatic && (declMir.isSetter || declMir.isGetter) && !declMir.isSynthetic)
      .where((declMir) {
        var mapMetadata = _mappableFromDeclaration(declMir);
        if (mapMetadata == null) {
          return false;
        }

        MethodMirror methodMirror = declMir;

        // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
        return (methodMirror.isSetter && mapMetadata.isAvailableAsInput)
            || (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
      })
      .map((declMir) => attributeFromMethodMirror(entity, declMir))
      .fold(<String, AttributeDescription>{}, (Map<String, AttributeDescription> collectedMap, attr) {
        if (collectedMap.containsKey(attr.name)) {
          collectedMap[attr.name] = new AttributeDescription.transient(entity, attr.name, attr.type, transientAttribute);
        } else {
          collectedMap[attr.name] = attr;
        }

        return collectedMap;
      })
      .forEach((_, attr) {
        map[attr.name] = attr;
      });

    // Grab persistent values, which must be properties (not relationships)
    entity.persistentTypeMirror.declarations.values
      .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
      .where((declMir) => !_doesVariableMirrorRepresentRelationship(declMir))
      .where((declMir) => !map.containsKey(MirrorSystem.getName(declMir.simpleName)))
      .forEach((declMir) {
        var key = MirrorSystem.getName(declMir.simpleName);
        map[key] = attributeFromVariableMirror(entity, declMir);
      });

    return map;
  }

  AttributeDescription attributeFromMethodMirror(ModelEntity entity, MethodMirror methodMirror) {
    var name = MirrorSystem.getName(methodMirror.simpleName);
    var dartTypeMirror = methodMirror.returnType;
    if (methodMirror.isSetter) {
      name = name.substring(0, name.length - 1);
      dartTypeMirror = methodMirror.parameters.first.type;
    }

    // We don't care about the mappable on the declaration when we specify it to the AttributeDescription,
    // only whether or not it is a getter/setter.
    return new AttributeDescription.transient(entity, name,
        PropertyDescription.propertyTypeForDartType(dartTypeMirror.reflectedType),
        new TransientAttribute(availableAsInput: methodMirror.isSetter, availableAsOutput: methodMirror.isGetter));
  }

  AttributeDescription attributeFromVariableMirror(ModelEntity entity, VariableMirror mirror) {
    if (entity.modelTypeMirror == mirror.owner) {
      // Transient; must be marked as Mappable.

      var name = MirrorSystem.getName(mirror.simpleName);
      var type = PropertyDescription.propertyTypeForDartType(mirror.type.reflectedType);
      if (type == null) {
        throw new DataModelException("Property $name on ${MirrorSystem.getName(entity.modelTypeMirror.simpleName)} has invalid type");
      }
      return new AttributeDescription.transient(entity, name, type, _mappableFromDeclaration(mirror));
    } else {
      // Persistent
      var attrs = _attributeMetadataFromDeclaration(mirror);

      var type = attrs?.databaseType ?? PropertyDescription.propertyTypeForDartType(mirror.type.reflectedType);
      if (type == null) {
        throw new DataModelException("Property ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} has invalid type");
      }

      return new AttributeDescription(entity, MirrorSystem.getName(mirror.simpleName), type,
          primaryKey: attrs?.isPrimaryKey ?? false,
          defaultValue: attrs?.defaultValue ?? null,
          unique: attrs?.isUnique ?? false,
          indexed: attrs?.isIndexed ?? false,
          nullable: attrs?.isNullable ?? false,
          includedInDefaultResultSet: !(attrs?.shouldOmitByDefault ?? false),
          autoincrement: attrs?.autoincrement ?? false);
    }
  }

  Map<String, RelationshipDescription> relationshipMapForEntity(ModelEntity entity) {
    Map<String, RelationshipDescription> map = {};

    entity.persistentTypeMirror.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror && !declMir.isStatic) {
        var key = MirrorSystem.getName(sym);

        if (_doesVariableMirrorRepresentRelationship(declMir)) {
          map[key] = relationshipFromVariableMirror(entity, declMir);
        }
      }
    });

    return map;
  }

  RelationshipDescription relationshipFromVariableMirror(ModelEntity entity, VariableMirror mirror) {
    if (_attributeMetadataFromDeclaration(mirror) != null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} must not define additional Attributes");
    }

    var destinationEntity = destinationEntityForVariableMirror(entity, mirror);
    var belongsToAttr = _belongsToMetadataFromDeclaration(mirror);
    var referenceProperty = destinationEntity.attributes[destinationEntity.primaryKey];

    if (belongsToAttr != null) {
      var inverseKey = belongsToAttr.inverseKey;
      var destinationVariableMirror = destinationEntity.persistentTypeMirror.declarations[inverseKey];

      if (destinationVariableMirror == null) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} has no inverse (tried $inverseKey)");
      }

      if (belongsToAttr.onDelete == RelationshipDeleteRule.nullify && belongsToAttr.isRequired) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} set to nullify on delete, but is not nullable");
      }

      if (_belongsToMetadataFromDeclaration(destinationVariableMirror) != null) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} and ${MirrorSystem.getName(destinationVariableMirror.simpleName)} on ${destinationEntity.tableName} have BelongsTo metadata, only one may belong to the other.");
      }

      return new RelationshipDescription(entity, MirrorSystem.getName(mirror.simpleName), referenceProperty.type,
          destinationEntity, belongsToAttr.onDelete, RelationshipType.belongsTo, inverseKey,
          unique: !(destinationVariableMirror as VariableMirror).type.isSubtypeOf(reflectType(OrderedSet)),
          indexed: true,
          nullable: !belongsToAttr.isRequired,
          includedInDefaultResultSet: true);
    }

    VariableMirror inversePropertyMirror = destinationEntity.persistentTypeMirror.declarations.values.firstWhere((DeclarationMirror destinationDeclarationMirror) {
      if (destinationDeclarationMirror is VariableMirror) {
        var inverseBelongsToAttr = _belongsToMetadataFromDeclaration(destinationDeclarationMirror);
        var matchesInverseKey = inverseBelongsToAttr?.inverseKey == mirror.simpleName;
        var isBelongsToVarMirrorSubtypeRightType = destinationDeclarationMirror.type.isSubtypeOf(entity.modelTypeMirror);

        if (matchesInverseKey && isBelongsToVarMirrorSubtypeRightType) {
          return true;
        }
      }

      return false;
    }, orElse: () => null);

    if (inversePropertyMirror == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} has no inverse declared in ${MirrorSystem.getName(destinationEntity.persistentTypeMirror.simpleName)} of appropriate type.");
    }

    var relType = RelationshipType.hasOne;
    if (mirror.type.isSubtypeOf(reflectType(OrderedSet))) {
      relType = RelationshipType.hasMany;
    }

    return new RelationshipDescription(entity, MirrorSystem.getName(mirror.simpleName), referenceProperty.type,
        destinationEntity, belongsToAttr?.onDelete, relType, inversePropertyMirror.simpleName,
        unique: false,
        indexed: true,
        nullable: false,
        includedInDefaultResultSet: false);
  }

  ModelEntity destinationEntityForVariableMirror(ModelEntity entity, VariableMirror mirror) {
    var typeMirror = mirror.type;
    if (mirror.type.isSubtypeOf(reflectType(OrderedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} destination ModelEntity does not exist");
    }

    return destinationEntity;
  }

  ClassMirror backingMirrorForType(Type modelType) {
    var rt = reflectClass(modelType);
    var modelRefl = reflectType(Model);
    var entityTypeRefl = rt;

    while (rt.superclass.isSubtypeOf(modelRefl)) {
      rt = rt.superclass;
      entityTypeRefl = rt;
    }

    if (rt.isSubtypeOf(modelRefl)) {
      entityTypeRefl = entityTypeRefl.typeArguments.first;
    } else {
      throw new DataModelException("Invalid modelType $modelType ${reflectClass(modelType).simpleName}");
    }

    return entityTypeRefl;
  }
}