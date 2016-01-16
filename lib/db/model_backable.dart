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