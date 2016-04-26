part of monadart;

class ModelEntity {
  static ModelEntity entityForType(Type t) {
    var rt = reflectClass(t);
    var modelRefl = reflectType(Model);
    var entityTypeRefl = rt;

    while (rt.superclass.isSubtypeOf(modelRefl)) {
      rt = rt.superclass;
      entityTypeRefl = rt;
    }

    if (rt.isSubtypeOf(modelRefl)) {
      entityTypeRefl = entityTypeRefl.typeArguments.first;
    }

    return new ModelEntity()
        ..entityTypeMirror = entityTypeRefl;
  }

  ClassMirror entityTypeMirror;
  Type get type => entityTypeMirror.reflectedType;

  /// Name of primaryKey property.
  ///
  /// If this has a primary key (as determined by the having an [Attributes] with [Attributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null.
  String get primaryKey {
    return _firstPropertyNameWhere((ivar) {
      var attr = ivar.metadata.firstWhere((md) => md.reflectee is Attributes, orElse: () => null);
      if (attr == null) {
        return false;
      }

      return attr.reflectee.isPrimaryKey;
    });
  }

  String _cachedTableName;
  String get tableName {
    if (_cachedTableName == null) {
      var tableNameSymbol = new Symbol("tableName");
      if (entityTypeMirror.staticMembers[tableNameSymbol] != null) {
        _cachedTableName = entityTypeMirror
            .invoke(tableNameSymbol, [])
            .reflectee;
      } else {
        _cachedTableName = MirrorSystem.getName(entityTypeMirror.simpleName);
      }
    }
    return _cachedTableName;
  }

  String foreignKeyForProperty(String propertyName) {
    var propertyMirror = _propertyMirrorForProperty(propertyName);
    if (propertyMirror == null) {
      return null;
    }

    var attr = _relationshipAttributeForPropertyMirror(propertyMirror);
    if (attr == null) {
      return null;
    }

    var suffixName = attr.referenceKey;
    if (suffixName == null) {
      var propertyTypeMirror = propertyMirror.type;
      if (propertyTypeMirror.isSubtypeOf(reflectType(List))) {
        propertyTypeMirror = propertyTypeMirror.typeArguments.first;
      }

      var relatedEntity = entityForType(propertyTypeMirror.reflectedType);
      var relatedTypePrimaryKeyAttr = relatedEntity.entityTypeMirror.declarations.values.firstWhere((dm) {
        Attributes propAttrs = dm.metadata.firstWhere((im) => im.reflectee is Attributes, orElse: () => null)?.reflectee;
        if (propAttrs == null) {
          return false;
        }
        return propAttrs.isPrimaryKey;
      }, orElse: () => null);

      if (relatedTypePrimaryKeyAttr == null) {
        var className = MirrorSystem.getName(propertyMirror.owner.simpleName);
        throw new QueryException(500, "Related value for $propertyName on ${className} does not have a primary key or a reference key.", -1);
      }

      suffixName = MirrorSystem.getName(relatedTypePrimaryKeyAttr.simpleName);
    }

    return "${propertyName}_${suffixName}";
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
    var decl = this.entityTypeMirror.declarations[new Symbol(propertyName)];
    if (decl == null) {
      return false;
    }
    if (decl is! VariableMirror) {
      return false;
    }
    if (decl.isStatic) {
      return false;
    }

    return true;
  }

  String _firstPropertyNameWhere(bool test(VariableMirror element)) {
    var sym = entityTypeMirror.declarations.values
        .where((decl) => decl is VariableMirror)
        .where((VariableMirror vm) => !vm.isStatic)
        .firstWhere(test, orElse: () => null)?.simpleName;

    if (sym == null) {
      return null;
    }

    return MirrorSystem.getName(sym);
  }

  TypeMirror _typeMirrorForProperty(String propertyName) {
    VariableMirror ivarDeclaration = entityTypeMirror.declarations[new Symbol(propertyName)];

    return ivarDeclaration?.type;
  }

  VariableMirror _propertyMirrorForProperty(String propertyName) {
    var decl = entityTypeMirror.declarations[new Symbol(propertyName)];
    if (decl is VariableMirror && !decl.isStatic) {
      return decl;
    }

    return null;
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
}