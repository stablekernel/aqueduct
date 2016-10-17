part of aqueduct;

/// Represents a row in a database.
///
/// Subclasses of [ManagedObject] represent a single row in a database. Model objects are also capable of serializing themselves into data
/// that can be encoded (into a format like JSON) and can be deserialized from similar data structures. Subclasses of
/// [ManagedObject] are called 'instance types'. These subclasses must also implement their [PersistentType]. The [PersistentType]
/// defines the columns in the corresponding database table.. Each property in the [PersistentType] is a column in the database table it represents.
///
/// Model objects are also used in building queries. See [Query.matchOn] and [Query.values].
///
///         class User extends Model<_User> implements _User {
///           String name; // Not persisted
///         }
///         class _User {
///           @primaryKey int id; // Persisted
///         }
class ManagedObject<PersistentType> extends Object with _QueryMatchableExtension implements HTTPSerializable, QueryMatchable {
  /// Used when building a [Query] to include instances of this type.
  ///
  /// A [Query] will, by default, fetch rows from a single table and return them as instances
  /// of the corresponding [ManagedObject] subclass. Setting this property to true on a property
  /// of the queried instance type will cause the [Query] to also fetch instances of this type
  /// using a SQL join.
  bool includeInResultSet = false;

  /// The [ManagedEntity] this instance is described by.
  ManagedEntity entity = ManagedContext.defaultContext.dataModel.entityForType(PersistentType);

  _ManagedBacking _backing = new _ManagedValueBacking();
  Map<String, dynamic> get _matcherMap => backingMap;

  /// The values available in this representation.
  ///
  /// Not all values are fetched or populated in a [ManagedObject] instance. This value contains
  /// key-value pairs for the model object that have been set, either manually
  /// or when fetched from a database. When [ManagedObject] is instantiated, this map is empty.
  Map<String, dynamic> get backingMap => _backing.valueMap;

  /// Retrieves a value by property name.
  dynamic operator [](String propertyName) => _backing.valueForProperty(entity, propertyName);

  /// Sets a value by property name.
  void operator []=(String propertyName, dynamic value) {
    _backing.setValueForProperty(entity, propertyName, value);
  }

  /// Removes a property from the backing map.
  ///
  /// This will remove a value from the backing map.
  void removePropertyFromBackingMap(String propertyName) {
    _backing.removeProperty(propertyName);
  }

  /// Checks whether or not a property has been set in this instance.
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
  /// This method will thrown an exception if a key in the map does not
  /// match a property of the receiver.
  ///
  /// Usage:
  ///     var values = JSON.decode(requestBody);
  ///     var model = new UserModel()
  ///       ..readFromMap(values);
  void readMap(Map<String, dynamic> keyValues) {
    var mirror = reflect(this);

    keyValues.forEach((k, v) {
      var property = entity.properties[k];

      if (property == null) {
        throw new QueryException(QueryExceptionEvent.requestFailure, message: "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}");
      }

      if (property is ManagedAttributeDescription) {
        if (!property.isTransient) {
          _backing.setValueForProperty(entity, k, _valueDecoder(property, v));
        } else {
          if (!property.transientStatus.isAvailableAsInput) {
            throw new QueryException(QueryExceptionEvent.requestFailure, message: "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}");
          }

          var decodedValue = _valueDecoder(property, v);
          if (!property.isAssignableWith(decodedValue)) {
            var valueTypeName = MirrorSystem.getName(reflect(decodedValue).type.simpleName);
            throw new QueryException(QueryExceptionEvent.requestFailure, message: "Type mismatch for property ${property.name} on ${MirrorSystem.getName(entity.persistentType.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.");
          }

          mirror.setField(new Symbol(k), decodedValue);
        }
      } else {
        _backing.setValueForProperty(entity, k, _valueDecoder(property, v));
      }
    });
  }

  /// Converts a model object into a serializable map.
  ///
  /// This method returns a map of the key-values pairs represented by the model object, typically then converted into a transmission format like JSON.
  ///
  /// Only properties present in [backingMap] are serialized, otherwise, they are omitted from the map. If a property is present in [backingMap] and the value is null,
  /// the value null will be serialized for that property key.
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
        .where((attr) => attr.transientStatus?.isAvailableAsOutput ?? false)
        .forEach((attr) {
          var value = reflectedThis.getField(new Symbol(attr.name)).reflectee;
          if (value != null) {
            outputMap[attr.name] = value;
          }
        });

    return outputMap;
  }

  /// Returns the output of [asMap].
  dynamic asSerializable() {
    return asMap();
  }

  static dynamic _valueEncoder(String key, dynamic value) {
    if (value is ManagedSet) {
      return value
          .map((ManagedObject innerValue) => innerValue.asMap())
          .toList();
    } else if (value is ManagedObject) {
      return value.asMap();
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    return value;
  }

  static dynamic _valueDecoder(ManagedPropertyDescription propertyDescription, dynamic value) {
    if (propertyDescription is ManagedAttributeDescription) {
      if (propertyDescription.type == ManagedPropertyType.datetime) {
        value = DateTime.parse(value);
      }

      if (propertyDescription.isAssignableWith(value)) {
        return value;
      }
    } else if (propertyDescription is ManagedRelationshipDescription) {
      ManagedRelationshipDescription relationshipDescription = propertyDescription;
      var destinationEntity = relationshipDescription.destinationEntity;
      if (relationshipDescription.relationshipType == ManagedRelationshipType.belongsTo || relationshipDescription.relationshipType == ManagedRelationshipType.hasOne) {
        if (value is! Map<String, dynamic>) {
          throw new QueryException(QueryExceptionEvent.requestFailure, message: "Expecting a Map for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        ManagedObject instance = destinationEntity.instanceType.newInstance(new Symbol(""), []).reflectee;
        instance.readMap(value as Map<String, dynamic>);

        return instance;
      } else if (relationshipDescription.relationshipType == ManagedRelationshipType.hasMany) {
        if (value is! List<Map<String, dynamic>>) {
          throw new QueryException(QueryExceptionEvent.requestFailure, message: "Expecting a List for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        if (value.length > 0 && value.first is! Map) {
          throw new QueryException(QueryExceptionEvent.requestFailure, message: "Expecting a List<Map> for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        return new ManagedSet.from((value as List<Map<String, dynamic>>).map((v) {
          ManagedObject instance = destinationEntity.instanceType.newInstance(new Symbol(""), []).reflectee;
          instance.readMap(v);
          return instance;
        }));
      }
    }

    return value;
  }
}
