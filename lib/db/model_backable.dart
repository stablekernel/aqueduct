part of monadart;

abstract class ModelBackable<T> {
  static ClassMirror backingTypeForModelType(Type modelType) {
    var refl = reflectClass(modelType);
    var modelClass = refl.superclass;
    var backingClass = modelClass.superclass;

    return backingClass.typeArguments.first;
  }

  static String tableNameForBackingType(Type backingType) {
    var backingTypeMirror = reflectClass(backingType);
    var tableNameSymbol = new Symbol("tableName");
    if (backingTypeMirror.staticMembers[tableNameSymbol] != null) {
      return backingTypeMirror
          .invoke(tableNameSymbol, [])
          .reflectee;
    }

    return MirrorSystem.getName(backingTypeMirror.simpleName);
  }

  ClassMirror get backingType => reflectClass(T);

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
      _cachedTableName = tableNameForBackingType(backingType.reflectedType);
    }
    return _cachedTableName;
  }

  String foreignKeyForProperty(String propertyName) {
    var propertyMirror = _variableMirrorForProperty(propertyName);
    if (propertyMirror == null) {
      return null;
    }

    var attr = _relationshipAttributeForPropertyMirror(propertyMirror);
    if (attr == null) {
      return null;
    }

    var suffixName = attr.referenceKey;
    if (suffixName == null) {
      var relatedType = backingTypeForModelType(propertyMirror.type.reflectedType);
      var relatedTypePrimaryKeyAttr = relatedType.declarations.values.firstWhere((dm) {
        Attributes propAttrs = dm.metadata.firstWhere((im) => im.reflectee is Attributes, orElse: () => null)?.reflectee;
        if (propAttrs == null) {
          return false;
        }
        return propAttrs.isPrimaryKey;
      }, orElse: () => null);

      if (relatedTypePrimaryKeyAttr == null) {
        var className = MirrorSystem.getName(propertyMirror.owner.simpleName);
        throw new ModelBackableException("Related value for $propertyName on ${className} does not have a primary key or a reference key.");
      }

      suffixName = MirrorSystem.getName(relatedTypePrimaryKeyAttr.simpleName);
    }

    return "${propertyName}_${suffixName}";
  }

  RelationshipAttribute relationshipAttributeForProperty(String propertyName) {
    var varMirror = _variableMirrorForProperty(propertyName);
    if (varMirror == null) {
      return null;
    }

    return _relationshipAttributeForPropertyMirror(varMirror);
  }

  RelationshipAttribute _relationshipAttributeForPropertyMirror(VariableMirror mirror) {
    return mirror.metadata.firstWhere((m) => m.reflectee is RelationshipAttribute, orElse: () => null)?.reflectee;
  }

  bool _hasProperty(String propertyName) {
    var backingTypeDecls = this.backingType.declarations;
    return backingTypeDecls.containsKey(new Symbol(propertyName));
  }

  String _firstPropertyNameWhere(bool test(VariableMirror element)) {
    var sym = backingType.declarations.values
        .where((decl) => decl is VariableMirror)
        .firstWhere(test, orElse: () => null)?.simpleName;

    if (sym == null) {
      return null;
    }

    return MirrorSystem.getName(sym);
  }

  TypeMirror _typeMirrorForProperty(String propertyName) {
    VariableMirror ivarDeclaration = backingType.declarations[new Symbol(propertyName)];

    return ivarDeclaration?.type;
  }

  VariableMirror _variableMirrorForProperty(String propertyName) {
    var decl = backingType.declarations[new Symbol(propertyName)];
    if (decl is VariableMirror) {
      return decl;
    }

    return null;
  }
}

class ModelBackableException {
  String message;
  ModelBackableException(this.message);
}