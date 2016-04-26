part of monadart;

/// A database row represented as an object.
///
/// Provides dynamic backing, serialization and deserialization capabilities.
/// Model types in an application extend Model<T>, where the Model type must also implement T. T holds properties
/// that are persisted in a database. Any properties in the Model type are not persisted, except those they inherit from T.
/// Model instances are used in an application. Example:
///
/// class User extends Model<_User> implements _User {
///   String name; // Not persisted
/// }
/// class _User {
///   int id; // persisted
/// }
///
class Model<T> implements Serializable {
  ModelEntity entity = ModelEntity.entityForType(T);

  /// Applied to each value when a Model is executing [readFromMap].
  ///
  /// Defaults to [_defaultValueDecoder], which simply converts ISO8601 strings to DateTimes.
  /// [typeMirror] is the type of the model object's property. [key] is the name of the property. [value] is the value being read and assigned to the property [key].
  Function get valueDecoder => _valueDecoder;
  void set valueDecoder(
      dynamic decode(TypeMirror typeMirror, String key, dynamic value)) {
    _valueDecoder = decode;
  }
  Function _valueDecoder = _defaultValueDecoder;

  /// Applied to each value when a Model is executing [asMap].
  ///
  /// Defaults to [_defaultValueEncoder], which converts DateTime objects to ISO8601 strings.
  /// [key] is the name of the property. [value] is the value of that property.
  Function get valueEncoder => _valueEncoder;
  void set valueEncoder(dynamic encode(String key, dynamic value)) {
    _valueEncoder = encode;
  }
  Function _valueEncoder = _defaultValueEncoder;

  /// A model object's data.
  ///
  /// Model objects may be sparsely populated; when values have not been assigned to a property, the key will not exist in [dynamicBacking].
  /// A value (including null) in [dynamicBacking] for a key means the property has been set on model instance.
  Map<String, dynamic> dynamicBacking = {};

  dynamic operator [](String propertyName) {
    if (!entity._hasProperty(propertyName)) {
      throw new QueryException(500, "Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $propertyName.", -1);
    }

    if (!dynamicBacking.containsKey(propertyName)) {
      return null;
    }

    return dynamicBacking[propertyName];
  }

  void operator []=(String propertyName, dynamic value) {
    if (!entity._hasProperty(propertyName)) {
      throw new QueryException(500, "Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $propertyName.", -1);
    }

    if (value != null) {
      var ivarType = entity._typeMirrorForProperty(propertyName);
      var valueType = reflect(value).type;
      if (!valueType.isSubtypeOf(ivarType)) {
        var ivarTypeName = MirrorSystem.getName(ivarType.simpleName);
        var valueTypeName = MirrorSystem.getName(valueType.simpleName);

        throw new QueryException(500, "Type mismatch for property $propertyName on ${MirrorSystem.getName(reflect(this).type.simpleName)}, expected $ivarTypeName but got $valueTypeName.", -1);
      }
    }

    dynamicBacking[propertyName] = value;
    return null;
  }

  noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      var propertyName = MirrorSystem.getName(invocation.memberName);
      return this[propertyName];
    } else if (invocation.isSetter) {
      var propertyName = MirrorSystem.getName(invocation.memberName);
      propertyName = propertyName.substring(0, propertyName.length - 1);

      var value = invocation.positionalArguments.first;
      this[propertyName] = value;
      return null;
    }

    return super.noSuchMethod(invocation);
  }

  /// Populates the properties of a Model object from a map.
  ///
  /// Usage:
  ///     var values = JSON.decode(requestBody);
  ///     var model = new UserModel()
  ///       ..readFromMap(values);
  void readMap(Map<String, dynamic> keyValues) {
    if (dynamicBacking == null) {
      dynamicBacking = {};
    }

    keyValues.forEach((k, v) {
      var variableMirror = entity._propertyMirrorForProperty(k);

      if (variableMirror == null) {
        DeclarationMirror decl = _declarationMirrorForProperty(k);

        if(decl != null && _declarationMirrorIsMappableOnInput(decl)) {
          reflect(this).setField(decl.simpleName, v);
        } else {
          throw new QueryException(400, "Key $k does not exist for ${MirrorSystem.getName(reflect(this).type.simpleName)}", -1);
        }
      } else {
        var fieldType = variableMirror.type as ClassMirror;
        dynamicBacking[k] = _valueDecoder(fieldType, k, v);
      }
    });
  }

  DeclarationMirror _declarationMirrorForProperty(String propertyName) {
    var reflectedThis = reflect(this);
    var sym = new Symbol(propertyName);

    return reflectedThis.type.declarations[sym];
  }

  Mappable _mappableAttributeForDeclarationMirror(DeclarationMirror mirror) {
    return mirror.metadata.firstWhere((im) => im.reflectee is Mappable, orElse: () => null)?.reflectee;
  }

  bool _declarationMirrorIsMappableOnInput(DeclarationMirror dm) {
    Mappable transientMetadata = _mappableAttributeForDeclarationMirror(dm);

    return transientMetadata != null && transientMetadata.isAvailableAsInput;
  }

  bool _declarationMirrorIsMappableOnOutput(DeclarationMirror dm) {
    Mappable transientMetadata =  _mappableAttributeForDeclarationMirror(dm);

    return transientMetadata != null && transientMetadata.isAvailableAsOutput;
  }


  /// Converts a model object into a serializable map.
  ///
  /// This method returns a map of the key-values pairs represented by the model object, typically then converted into a transmission format like JSON.
  ///
  /// Usage:
  ///     var json = JSON.encode(model.asMap());
  Map<String, dynamic> asMap() {
    var outputMap = {};

    dynamicBacking.forEach((k, v) {
      outputMap[k] = _valueEncoder(k, v);
    });

    var reflectedThis = reflect(this);
    reflectedThis.type.declarations.forEach((sym, decl) {
      if (_declarationMirrorIsMappableOnOutput(decl)) {
        var value = reflectedThis.getField(sym).reflectee;
        if (value != null) {
          outputMap[MirrorSystem.getName(sym)] = reflectedThis.getField(sym).reflectee;
        }
      }
    });

    return outputMap;
  }

  dynamic asSerializable() {
    return asMap();
  }

  /// The default encoder for values when converting them to a map.
  ///
  /// Embedded model objects and lists of embedded model objects will also be sent asMap().
  /// DateTime instances are converted to ISO8601 strings.
  static dynamic _defaultValueEncoder(String key, dynamic value) {
    if (value is List) {
      return (value as List)
          .map((Model innerValue) => innerValue.asMap())
          .toList();
    } else if (value is Model) {
      return (value as Model).asMap();
    }

    if (value is DateTime) {
      return (value as DateTime).toIso8601String();
    }

    return value;
  }

  /// The default decoder for values when reading from a map.
  ///
  /// ISO8601 strings are converted to DateTime instances of the type of the property as defined by [key] is DateTime.
  static dynamic _defaultValueDecoder(TypeMirror typeMirror, String key, dynamic value) {
    if (typeMirror.isSubtypeOf(reflectType(Model))) {
      if (value is! Map) {
        throw new QueryException(400, "Expecting a Map for ${MirrorSystem.getName(typeMirror.simpleName)} in the $key field, got $value instead.", -1);
      }
      Model instance = (typeMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
      instance.readMap(value);

      return instance;
    } else if (typeMirror.isSubtypeOf(reflectType(List))) {
      if (value is! List) {
        throw new QueryException(400, "Expecting a List for ${MirrorSystem.getName(typeMirror.simpleName)} in the $key field, got $value instead.", -1);
      }

      var listTypeMirror = typeMirror.typeArguments.first;
      return (value as List).map((v) {
        Model instance = (listTypeMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
        instance.readMap(v);
        return instance;
      }).toList();
    }

    if (typeMirror.isSubtypeOf(reflectType(DateTime))) {
      return DateTime.parse(value);
    }

    return value;
  }
}
