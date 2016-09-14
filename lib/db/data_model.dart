part of aqueduct;

/// Container for [ModelEntity]s, representing [Model] objects and their properties.
///
/// Required for [ModelContext].
class DataModel {
  /// Creates an instance of [DataModel] from a list of types that extends [Model].
  ///
  /// To register a class as a model object within this, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  DataModel(List<Type> modelTypes) {
    _buildEntities(modelTypes);
  }

  DataModel._fromModelBundle(String modelBundlePath) {
    // This will build the model from a series of schema files.
  }

  Map<Type, ModelEntity> _entities = {};
  Map<Type, ModelEntity> _persistentTypeToEntityMap = {};

  /// Returns a [ModelEntity] for a [Type].
  ///
  /// [type] may be either the model type or persistent type. For example, the following model
  /// definition, you could retrieve its entity via MyModel or _MyModel:
  ///
  ///         class MyModel extends Model<_MyModel> implements _MyModel {}
  ///         class _MyModel {
  ///           @primaryKey
  ///           int id;
  ///         }
  ModelEntity entityForType(Type type) {
    return _entities[type] ?? _persistentTypeToEntityMap[type];
  }

  void _buildEntities(List<Type> modelTypes) {
    modelTypes.forEach((type) {
      var entity = new ModelEntity(this, reflectClass(type), _backingMirrorForType(type));
      _entities[type] = entity;
      _persistentTypeToEntityMap[entity.persistentTypeMirror.reflectedType] = entity;
    });

    _entities.forEach((_, entity) {
      entity._tableName = _tableNameForEntity(entity);
      entity.attributes = _attributeMapForEntity(entity);
      entity._primaryKey = entity.attributes.values
          .firstWhere((attrDesc) => attrDesc.isPrimaryKey, orElse: () => null)
          ?.name;

      if (entity.primaryKey == null) {
        throw new DataModelException("No primary key for entity ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)}");
      }
    });

    _entities.forEach((_, entity) {
      entity.relationships = _relationshipMapForEntity(entity);
    });
  }

  String _tableNameForEntity(ModelEntity entity) {
    var tableNameSymbol = new Symbol("tableName");
    if (entity.persistentTypeMirror.staticMembers[tableNameSymbol] != null) {
      return entity.persistentTypeMirror
          .invoke(tableNameSymbol, [])
          .reflectee;
    }

    return MirrorSystem.getName(entity.persistentTypeMirror.simpleName);
  }

  Map<String, AttributeDescription> _attributeMapForEntity(ModelEntity entity) {
    Map<String, AttributeDescription> map = {};

    // Grab actual properties from model type
    entity.modelTypeMirror.declarations.values
      .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
      .where((declMir) => _mappableFromDeclaration(declMir) != null)
      .forEach((declMir) {
          var key = MirrorSystem.getName(declMir.simpleName);
          map[key] = _attributeFromVariableMirror(entity, declMir);
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
        .map((declMir) => _attributeFromMethodMirror(entity, declMir))
        .fold(<String, AttributeDescription>{}, (Map<String, AttributeDescription> collectedMap, attr) {
          if (collectedMap.containsKey(attr.name)) {
            collectedMap[attr.name] = new AttributeDescription.transient(entity, attr.name, attr.type, availableAsInputAndOutput);
          } else {
            collectedMap[attr.name] = attr;
          }

          return collectedMap;
        })
        .forEach((_, attr) {
          map[attr.name] = attr;
        });

    // Grab persistent values, which must be properties
    entity.persistentTypeMirror.declarations.values
      .where((declMir) => declMir is VariableMirror && !declMir.isStatic)
      .where((declMir) => !declMir.metadata.any((im) => im.type.isSubtypeOf(reflectType(Relationship))))
      .where((declMir) => !map.containsKey(MirrorSystem.getName(declMir.simpleName)))
      .forEach((declMir) {
        var key = MirrorSystem.getName(declMir.simpleName);
        map[key] = _attributeFromVariableMirror(entity, declMir);
      });

    return map;
  }

  AttributeDescription _attributeFromMethodMirror(ModelEntity entity, MethodMirror methodMirror) {
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
        new TransientMappability(availableAsInput: methodMirror.isSetter, availableAsOutput: methodMirror.isGetter));
  }

  AttributeDescription _attributeFromVariableMirror(ModelEntity entity, VariableMirror mirror) {
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

  Map<String, RelationshipDescription> _relationshipMapForEntity(ModelEntity entity) {
    Map<String, RelationshipDescription> map = {};

    entity.persistentTypeMirror.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror && !declMir.isStatic) {
        var key = MirrorSystem.getName(sym);
        var relationshipAttribute = _relationshipFromDeclaration(declMir);

        if (relationshipAttribute != null) {
          map[key] = _relationshipFromVariableMirror(entity, declMir, relationshipAttribute);
        }
      }
    });

    return map;
  }

  RelationshipDescription _relationshipFromVariableMirror(ModelEntity entity, VariableMirror mirror, Relationship relationshipAttribute) {
    if (relationshipAttribute.type == RelationshipType.hasMany) {
      if (!mirror.type.isSubtypeOf(reflectType(OrderedSet))) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} declares a hasMany relationship, but the property is not an OrderedSet.");
      }

      var innerType = mirror.type.typeArguments.first;
      if (!innerType.isSubtypeOf(reflectType(Model))) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} declares a hasMany relationship, but the generic type of OrderedSet is not a subclass of Model.");
      }
    } else {
      if (!mirror.type.isSubtypeOf(reflectType(Model))) {
        throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} does not declare a property that extends Model.");
      }
    }

    if (_attributeMetadataFromDeclaration(mirror) != null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} must not define additional Attributes");
    }

    String inverseKey = relationshipAttribute.inverseKey;
    var destinationEntity = _destinationEntityForVariableMirror(entity, mirror);
    var destinationVariableMirror = destinationEntity.persistentTypeMirror.declarations[new Symbol(inverseKey)];
    if (destinationVariableMirror == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} has no inverse (tried $inverseKey)");
    }

    var inverseRelationshipProperties = _relationshipFromDeclaration(destinationVariableMirror);
    if (inverseRelationshipProperties == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} inverse ($inverseKey) has no RelationshipAttribute");
    }

    if ((relationshipAttribute.type == inverseRelationshipProperties.type)
    ||  (relationshipAttribute.type != RelationshipType.belongsTo && inverseRelationshipProperties.type != RelationshipType.belongsTo)) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} inverse ($inverseKey) has non-complimentary RelationshipType");
    }

    if (relationshipAttribute.type == RelationshipType.belongsTo
    && relationshipAttribute.deleteRule == RelationshipDeleteRule.nullify
    && relationshipAttribute.isRequired) {
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
    if (mirror.type.isSubtypeOf(reflectType(OrderedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = _entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      throw new DataModelException("Relationship ${MirrorSystem.getName(mirror.simpleName)} on ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} destination ModelEntity does not exist");
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

/// Thrown when a [DataModel] encounters an error.
class DataModelException implements Exception {
  DataModelException(this.message);

  final String message;

  String toString() {
    return "DataModelException: $message";
  }
}