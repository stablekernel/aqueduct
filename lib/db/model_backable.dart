part of monadart;

abstract class ModelBackable {
  ClassMirror _backingType;

  /// A class mirror on the backing type of the Model.
  ///
  /// Defined by the Model's [ModelBacking] metadata.
  ClassMirror get backingType {
    if (_backingType == null) {
      var modelBacking = reflect(this)
          .type
          .metadata
          .firstWhere((m) => m.type.isSubtypeOf(reflectType(ModelBacking)))
          .reflectee as ModelBacking;
      _backingType = reflectClass(modelBacking.backingType);
    }
    return _backingType;
  }
  void set backingType(ClassMirror b) { _backingType = b; }

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
      var relatedType = _backingTypeForModelType(propertyMirror.type.reflectedType);
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

    return ivarDeclaration.type;
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