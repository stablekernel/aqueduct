part of aqueduct;

class DataModel {
  DataModel(this.persistentStore, List<Type> modelTypes) {
    _buildEntities(modelTypes);
  }
  DataModel.fromModelBundle(this.persistentStore, String modelBundlePath) {
    // This would build the model from a series of schema files.
  }

  final PersistentStore persistentStore;
  Map<Type, ModelEntity> entities = {};

  ModelEntity entityForType(Type t) {
    var entity = entities[t];
    if (entity == null) {
      throw new DataModelException("Unknown ModelEntity for ${MirrorSystem.getName(reflectType(t).simpleName)}");
    }
    return entity;
  }

  void _buildEntities(List<Type> modelTypes) {
    modelTypes.forEach((type) {
      entities[type] = new ModelEntity(this, reflectClass(type), _backingMirrorForType(type));
    });

    entities.forEach((_, entity) {
      entity._tableName = _tableNameForEntity(entity);
      entity.attributes = _attributeMapForEntity(entity);
      entity._primaryKey = entity.attributes.values.firstWhere((attrDesc) => attrDesc.isPrimaryKey, orElse: () => null)?.name;
      if (entity.primaryKey == null) {
        throw new DataModelException("No primary key for entity ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)}");
      }
    });

    entities.forEach((_, entity) {
      entity.relationships = _relationshipMapForEntity(entity);
    });
  }

  String _tableNameForEntity(ModelEntity entity) {
    var tableNameSymbol = new Symbol("tableName");
    if (entity.persistentInstanceTypeMirror.staticMembers[tableNameSymbol] != null) {
      return entity.persistentInstanceTypeMirror
          .invoke(tableNameSymbol, [])
          .reflectee;
    }

    return MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName);
  }

  Map<String, AttributeDescription> _attributeMapForEntity(ModelEntity entity) {
    Map<String, AttributeDescription> map = {};
    entity.persistentInstanceTypeMirror.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror && !declMir.isStatic) {
        var key = MirrorSystem.getName(sym);
        bool hasRelationship = declMir.metadata.firstWhere((im) => im.type.isSubtypeOf(reflectType(RelationshipAttribute)), orElse: () => null) != null;
        if (!hasRelationship) {
          map[key] = _attributeFromVariableMirror(entity, declMir);
        }
      }
    });
    return map;
  }

  AttributeDescription _attributeFromVariableMirror(ModelEntity entity, VariableMirror mirror) {
    Attributes metadataAttrs = mirror.metadata
        .firstWhere((im) => im.type.isSubtypeOf(reflectType(Attributes)), orElse: () => null)
        ?.reflectee;

    var type = metadataAttrs?.databaseType ?? PropertyDescription.propertyTypeForDartType(mirror.type.reflectedType);
    if (type == null) {
      throw new DataModelException("Property ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} has invalid type");
    }

    return new AttributeDescription(entity, MirrorSystem.getName(mirror.simpleName), type,
        primaryKey: metadataAttrs?.isPrimaryKey ?? false,
        defaultValue: metadataAttrs?.defaultValue ?? null,
        unique: metadataAttrs?.isUnique ?? false,
        indexed: metadataAttrs?.isIndexed ?? false,
        nullable: metadataAttrs?.isNullable ?? false,
        includedInDefaultResultSet: !(metadataAttrs?.shouldOmitByDefault ?? false),
        autoincrement: metadataAttrs?.autoincrement ?? false);
  }

  Map<String, RelationshipDescription> _relationshipMapForEntity(ModelEntity entity) {
    Map<String, RelationshipDescription> map = {};

    entity.persistentInstanceTypeMirror.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror && !declMir.isStatic) {
        var key = MirrorSystem.getName(sym);
        RelationshipAttribute relationshipAttribute = declMir.metadata
            .firstWhere((im) => im.type.isSubtypeOf(reflectType(RelationshipAttribute)), orElse: () => null)
            ?.reflectee;

        if (relationshipAttribute != null) {
          map[key] = _relationshipFromVariableMirror(entity, declMir, relationshipAttribute);
        }
      }
    });

    return map;
  }

  RelationshipDescription _relationshipFromVariableMirror(ModelEntity entity, VariableMirror mirror, RelationshipAttribute relationshipAttribute) {
    if (mirror.metadata.firstWhere((im) => im.type.isSubtypeOf(reflectType(Attributes)), orElse: () => null) != null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} must not define additional Attributes");
    }

    String inverseKey = relationshipAttribute.inverseKey;
    var destinationEntity = _destinationEntityForVariableMirror(entity, mirror);
    var destinationVariableMirror = destinationEntity.persistentInstanceTypeMirror.declarations[new Symbol(inverseKey)];
    if (destinationVariableMirror == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} has no inverse (tried $inverseKey)");
    }

    RelationshipAttribute inverseRelationshipProperties = destinationVariableMirror.metadata
        .firstWhere((im) => im.type.isSubtypeOf(reflectType(RelationshipAttribute)), orElse: () => null)
        ?.reflectee;
    if (inverseRelationshipProperties == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} inverse ($inverseKey) has no RelationshipAttribute");
    }

    if ((relationshipAttribute.type == inverseRelationshipProperties.type)
    ||  (relationshipAttribute.type != RelationshipType.belongsTo && inverseRelationshipProperties.type != RelationshipType.belongsTo)) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} inverse ($inverseKey) has non-complimentary RelationshipType");
    }

    if (relationshipAttribute.type == RelationshipType.belongsTo
    && relationshipAttribute.deleteRule == RelationshipDeleteRule.nullify
    && !relationshipAttribute.isRequired) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${entity.tableName} set to nullify on delete, but is not nullable");
    }

    var referenceProperty = destinationEntity.attributes[destinationEntity.primaryKey];

    return new RelationshipDescription(entity, MirrorSystem.getName(mirror.simpleName), referenceProperty.type,
        destinationEntity, relationshipAttribute.deleteRule, relationshipAttribute.type, inverseKey,
        unique: inverseRelationshipProperties.type == RelationshipType.hasOne,
        indexed: relationshipAttribute.type == RelationshipType.belongsTo,
        nullable: !relationshipAttribute.isRequired,
        includedInDefaultResultSet: true);
  }

  ModelEntity _destinationEntityForVariableMirror(ModelEntity entity, VariableMirror mirror) {
    var typeMirror = mirror.type;
    if (mirror.type.isSubtypeOf(reflectType(List))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} destination ModelEntity does not exist");
    }

    return destinationEntity;
  }

  ClassMirror _backingMirrorForType(Type modelType) {
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

class DataModelException {
  DataModelException(this.message);

  final String message;

  String toString() {
    return "DataModelException: $message";
  }
}