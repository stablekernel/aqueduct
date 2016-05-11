part of aqueduct;

class ModelEntity {
  static Map<Type, ModelEntity> _entityCache = {};
  static ModelEntity entityForType(Type t) {
    var cachedEntity = _entityCache[t];
    if (cachedEntity != null) {
      return cachedEntity;
    }

    var entityTypeRefl = _modelDefinitionMirror(t);
    var entity = new ModelEntity(entityTypeRefl);

    _entityCache[t] = entity;

    return entity;
  }

  static ClassMirror _modelDefinitionMirror(Type modelType) {
    var rt = reflectClass(modelType);
    var modelRefl = reflectType(Model);
    var entityTypeRefl = rt;

    while (rt.superclass.isSubtypeOf(modelRefl)) {
      rt = rt.superclass;
      entityTypeRefl = rt;
    }

    if (rt.isSubtypeOf(modelRefl)) {
      entityTypeRefl = entityTypeRefl.typeArguments.first;
    }
    return entityTypeRefl;
  }


  ModelEntity(this.entityTypeMirror) {
    _buildCaches();
  }

  final ClassMirror entityTypeMirror;
  Type get type => entityTypeMirror.reflectedType;

  /// Name of primaryKey property.
  ///
  /// If this has a primary key (as determined by the having an [Attributes] with [Attributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null.
  String get primaryKey {
    return _primaryKey;
  }
  String _primaryKey;

  /// Name of table in database.
  ///
  /// By default, the table will be named by the backing type, e.g., a model class defined as class User extends Model<_User> implements _User has a backing
  /// type of _User. The table will be named _User. You may implement the static method tableName that returns a [String] to change this table name
  /// to that methods returned value.
  String get tableName {
    return _tableName;
  }
  String _tableName;

  Map<String, VariableMirror> _propertyCache;
  Map<String, String> _foreignKeyCache;

  String foreignKeyForProperty(String propertyName) {
    return _foreignKeyCache[propertyName];
  }

  RelationshipAttribute relationshipAttributeForProperty(String propertyName) {
    var varMirror = _propertyMirrorForProperty(propertyName);
    if (varMirror == null) {
      return null;
    }

    return _relationshipAttributeForPropertyMirror(varMirror);
  }

  RelationshipAttribute _relationshipAttributeForPropertyMirror(VariableMirror mirror) {
    return mirror.metadata.firstWhere((m) => m.reflectee is RelationshipAttribute, orElse: () => null)?.reflectee;
  }

  bool _hasProperty(String propertyName) {
    return _propertyCache[propertyName] != null;
  }

  String _firstPropertyNameWhere(bool test(VariableMirror element)) {
    var sym = _propertyCache.values.firstWhere(test, orElse: () => null)?.simpleName;

    return MirrorSystem.getName(sym);
  }

  TypeMirror _typeMirrorForProperty(String propertyName) {
    return _propertyCache[propertyName]?.type;
  }

  VariableMirror _propertyMirrorForProperty(String propertyName) {
    return _propertyCache[propertyName];
  }

  int get hashCode {
    return tableName.hashCode;
  }

  operator ==(ModelEntity other) {
    return tableName == other.tableName;
  }

  String toString() {
    return "ModelEntity on $tableName";
  }

  void _buildCaches() {
    var tableNameSymbol = new Symbol("tableName");
    if (entityTypeMirror.staticMembers[tableNameSymbol] != null) {
      _tableName = entityTypeMirror
          .invoke(tableNameSymbol, [])
          .reflectee;
    } else {
      _tableName = MirrorSystem.getName(entityTypeMirror.simpleName);
    }

    _propertyCache = {};
    entityTypeMirror.declarations.forEach((sym, declMir) {
      if (declMir is VariableMirror && !declMir.isStatic) {
        var key = MirrorSystem.getName(sym);
        _propertyCache[key] = declMir;
      }
    });

    _primaryKey = _firstPropertyNameWhere((ivar) {
      var attr = ivar.metadata.firstWhere((md) => md.reflectee is Attributes, orElse: () => null);
      if (attr == null) {
        return false;
      }

      return attr.reflectee.isPrimaryKey;
    });

    _buildForeignKeyCache();
  }

  void _buildForeignKeyCache() {
    _foreignKeyCache = {};

    _propertyCache.forEach((propertyName, variableMirror) {
      var attr = _relationshipAttributeForPropertyMirror(variableMirror);
      if (attr == null) {
        return;
      }

      var suffixName = attr.referenceKey;
      if (suffixName == null) {
        var propertyTypeMirror = variableMirror.type;
        if (propertyTypeMirror.isSubtypeOf(reflectType(List))) {
          propertyTypeMirror = propertyTypeMirror.typeArguments.first;
        }

        var relatedBackingMirror = _modelDefinitionMirror(propertyTypeMirror.reflectedType);
        var relatedTypePrimaryKeyAttr = relatedBackingMirror.declarations.values.firstWhere((dm) {
          Attributes propAttrs = dm.metadata.firstWhere((im) => im.reflectee is Attributes, orElse: () => null)?.reflectee;
          if (propAttrs == null) {
            return false;
          }
          return propAttrs.isPrimaryKey;
        }, orElse: () => null);

        if (relatedTypePrimaryKeyAttr == null) {
          var className = MirrorSystem.getName(variableMirror.owner.simpleName);
          throw new QueryException(500, "Related value for $propertyName on ${className} does not have a primary key or a reference key.", -1);
        }

        suffixName = MirrorSystem.getName(relatedTypePrimaryKeyAttr.simpleName);
      }

      _foreignKeyCache[propertyName] = "${propertyName}_${suffixName}";
    });

  }
}