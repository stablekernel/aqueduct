part of aqueduct;

/// A database row represented as an object.
///
/// Provides storage, serialization and deserialization capabilities.
/// Instance types in an application extend [Model<PersistentType>], where the instance type must also implement [PersistentType]. [PersistentType] holds properties
/// that are persisted in a database. The subclass of [Model<PersistentType>]
/// is known as the 'instance type'. Any properties in the instance type are not persisted, except those they inherit from [PersistentType].
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
class Model<PersistentType> extends Object with _QueryMatchableExtension implements Serializable, QueryMatchable {
  /// The [ModelEntity] this instance is described by.
  ModelEntity entity = ModelContext.defaultContext.dataModel.entityForType(PersistentType);

  _ModelBacking _backing = new _ModelValueBacking();

  bool includeInResultSet = false;
  Map<String, dynamic> get _matcherMap => backingMap;

  /// The values available in this representation.
  ///
  /// Not all values are fetched or populated in a [Model] instance. This value contains
  /// any key-value pairs for properties that are stored in this instance.
  Map<String, dynamic> get backingMap => _backing.valueMap;

  /// Retrieves a value by property name.
  dynamic operator [](String propertyName) => _backing.valueForProperty(entity, propertyName);

  /// Sets a value by property name.
  void operator []=(String propertyName, dynamic value) {
    _backing.setValueForProperty(entity, propertyName, value);
  }

  void removePropertyFromBackingMap(String propertyName) {
    _backing.removeProperty(propertyName);
  }

  bool hasValueForProperty(String propertyName) {
    return backingMap.containsKey(propertyName);
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
    var mirror = reflect(this);

    keyValues.forEach((k, v) {
      var property = entity.properties[k];

      if (property != null) {
        if (property is AttributeDescription) {
          if (!property.isTransient) {
            _backing.setValueForProperty(entity, k, _valueDecoder(property, v));
          } else {
            if (property.transientStatus.isAvailableAsInput) {
              var decodedValue = _valueDecoder(property, v);
              if(property.isAssignableWith(decodedValue)) {
                mirror.setField(new Symbol(k), decodedValue);
              } else {
                var valueTypeName = MirrorSystem.getName(reflect(decodedValue).type.simpleName);
                throw new QueryException(400, "Type mismatch for property ${property.name} on ${MirrorSystem.getName(entity.persistentType.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.", -1);
              }
            } else {
              throw new QueryException(400, "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}", -1);
            }
          }
        } else {
          _backing.setValueForProperty(entity, k, _valueDecoder(property, v));
        }
      } else {
        throw new QueryException(400, "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}", -1);
      }
    });
  }

  /// Converts a model object into a serializable map.
  ///
  /// This method returns a map of the key-values pairs represented by the model object, typically then converted into a transmission format like JSON.
  ///
  /// Usage:
  ///     var json = JSON.encode(model.asMap());
  Map<String, dynamic> asMap() {
    var outputMap = <String, dynamic>{};

    _backing.valueMap.forEach((k, v) {
      outputMap[k] = _valueEncoder(k, v);
    });

    var reflectedThis = reflect(this);
    entity.attributes.values
        .where((attr) => attr.isTransient)
        .forEach((attr) {
          if (attr.transientStatus.isAvailableAsOutput) {
            var value = reflectedThis.getField(new Symbol(attr.name)).reflectee;
            if (value != null) {
              outputMap[attr.name] = value;
            }
          }
        });

    return outputMap;
  }

  dynamic asSerializable() {
    return asMap();
  }

  static dynamic _valueEncoder(String key, dynamic value) {
    if (value is OrderedSet) {
      return value
          .map((Model innerValue) => innerValue.asMap())
          .toList();
    } else if (value is Model) {
      return value.asMap();
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    return value;
  }

  static dynamic _valueDecoder(PropertyDescription propertyDescription, dynamic value) {
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
        if (value is! Map<String, dynamic>) {
          throw new QueryException(400, "Expecting a Map for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        Model instance = destinationEntity.instanceType.newInstance(new Symbol(""), []).reflectee;
        instance.readMap(value as Map<String, dynamic>);

        return instance;
      } else if (relationshipDescription.relationshipType == RelationshipType.hasMany) {
        if (value is! List<Map<String, dynamic>>) {
          throw new QueryException(400, "Expecting a List for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        if (value.length > 0 && value.first is! Map) {
          throw new QueryException(400, "Expecting a List<Map> for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.", -1);
        }

        return new OrderedSet.from((value as List<Map<String, dynamic>>).map((v) {
          Model instance = destinationEntity.instanceType.newInstance(new Symbol(""), []).reflectee;
          instance.readMap(v);
          return instance;
        }));
      }
    }

    return value;
  }
}
