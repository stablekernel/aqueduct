part of aqueduct;

/// A database row represented as an object.
///
/// Provides storage, serialization and deserialization capabilities.
/// Model types in an application extend Model<T>, where the Model type must also implement T. T holds properties
/// that are persisted in a database. T in the context is called the 'persistent instance type'. The subclass of Model<T>
/// is known as the 'instance type'. Any properties in the instance type are not persisted, except those they inherit from T.
/// Model instances are used in an application. Example:
///
/// class User extends Model<_User> implements _User {
///   String name; // Not persisted
/// }
/// class _User {
///   @primaryKey
///   int id; // persisted
/// }
///
class Model<T> implements Serializable {
  /// The [ModelContext] this instance belongs to.
  ModelContext context = ModelContext.defaultContext;

  /// The [ModelEntity] this instance is described by.
  ModelEntity get entity => context.dataModel.entityForType(T);

  /// Applied to each value when a Model is executing [readFromMap].
  ///
  /// Defaults to [_defaultValueDecoder], which simply converts ISO8601 strings to DateTimes.
  /// [propertyDescription] is the [PropertyDescription] definition of the property being assigned. [key] is the name of the property. [value] is the value being read and assigned to the property [key].
  Function get valueDecoder => _valueDecoder;
  void set valueDecoder(dynamic decode(PropertyDescription propertyDescription, dynamic value)) {
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

  /// Retrieves a value by property name.
  dynamic operator [](String propertyName) {
    if (entity.properties[propertyName] == null) {
      throw new DataModelException("Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $propertyName.");
    }

    if (!dynamicBacking.containsKey(propertyName)) {
      return null;
    }

    return dynamicBacking[propertyName];
  }

  /// Sets a value by property name.
  void operator []=(String propertyName, dynamic value) {
    var property = entity.properties[propertyName];
    if (property == null) {
      throw new DataModelException("Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $propertyName.");
    }

    if (value != null) {
      if (!property.isAssignableWith(value)) {
        var valueTypeName = MirrorSystem.getName(reflect(value).type.simpleName);
        throw new DataModelException("Type mismatch for property $propertyName on ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.");
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
      var property = entity.properties[k];
      DeclarationMirror decl = _declarationMirrorForProperty(k);

      if (property != null && !(property is AttributeDescription && property.isTransient)) {
        dynamicBacking[k] = _valueDecoder(property, v);
      } else if (decl != null && _declarationMirrorIsMappableOnInput(decl)) {
        reflect(this).setField(decl.simpleName, _valueDecoder(property, v));
      } else {
        throw new QueryException(400, "Key $k does not exist for ${MirrorSystem.getName(reflect(this).type.simpleName)}", -1);
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
  static dynamic _defaultValueDecoder(PropertyDescription propertyDescription, dynamic value) {
    if (propertyDescription is AttributeDescription) {
      if (propertyDescription.type == PropertyType.datetime) {
        value = DateTime.parse(value);
      }

      if (propertyDescription.isAssignableWith(value)) {
        return value;
      }
    } else if (propertyDescription is RelationshipDescription) {
      RelationshipDescription relationshipDescription = propertyDescription;
      var destinationEntity = relationshipDescription.destinationEntity;
      if (relationshipDescription.relationshipType == RelationshipType.belongsTo || relationshipDescription.relationshipType == RelationshipType.hasOne) {
        if (value is! Map) {
          throw new QueryException(400, "Expecting a Map for ${MirrorSystem.getName(destinationEntity.instanceTypeMirror.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        Model instance = destinationEntity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
        instance.readMap(value);

        return instance;
      } else if (relationshipDescription.relationshipType == RelationshipType.hasMany) {
        if (value is! List) {
          throw new QueryException(400, "Expecting a List for ${MirrorSystem.getName(destinationEntity.instanceTypeMirror.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        if (value.length > 0 && value.first is! Map) {
          throw new QueryException(400, "Expecting a List<Map> for ${MirrorSystem.getName(destinationEntity.instanceTypeMirror.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        return (value as List).map((v) {
          Model instance = destinationEntity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
          instance.readMap(v);
          return instance;
        }).toList();
      }
    }

    return value;
  }
}
