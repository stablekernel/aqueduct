import 'dart:mirrors';

import '../../http/serializable.dart';
import 'managed.dart';
import 'query_matchable.dart';
import 'backing.dart';

/// Instances of this class provide storage for [ManagedObject]s.
///
/// A [ManagedObject] stores properties declared by its type argument in instances of this type.
/// Values are validated against the [ManagedObject.entity].
///
/// Instances of this type only store properties for which a value has been explicitly set. This allows
/// serialization classes to omit unset values from the serialized values. Therefore, instances of this class
/// provide behavior that can differentiate between a property being the null value and a property simply not being
/// set. (Therefore, you must use [removeProperty] instead of setting a value to null to really remove it from instances
/// of this type.)
///
/// Aqueduct implements concrete subclasses of this class to provide behavior for property storage
/// and query-building.
abstract class ManagedBacking {

  /// Retrieve a property by its entity and name.
  dynamic valueForProperty(ManagedEntity entity, String propertyName);

  /// Sets a property by its entity and name.
  void setValueForProperty(
      ManagedEntity entity, String propertyName, dynamic value);

  /// Removes a property from this instance.
  ///
  /// Use this method to use any reference of a property from this instance.
  void removeProperty(String propertyName) {
    valueMap.remove(propertyName);
  }

  /// A map of all set values of this instance.
  Map<String, dynamic> get valueMap;
}

/// An object whose storage is managed by an underlying [Map].
///
/// This class is meant to be subclassed.
///
/// Instances of this class may store values in a [backingMap] instead of directly in its properties. The properties managed by the [backingMap]
/// are those declared in its [PersistentType] and those with [ManagedTransientAttribute] metadata in a subclass. The properties
/// declared by the [PersistentType] describes the columns of a database table. Properties declared in a subclass of this type are not persisted
/// in a database table, but are managed by the [backingMap] if and only if they are marked with [ManagedTransientAttribute]. Properties declared
/// by the subclass that do not have this metadata are stored in an instance variable like any other Dart class.
///
/// A [ManagedObject] can be serialized into or deserialized from a [Map]. This allows a managed object to be encoded into or decoded from a format like JSON.
/// Only properties in [backingMap] are serialized/deserialized.
///
/// Managed objects are compiled into a [ManagedDataModel], where each managed object's mapping to the database is represented by a [ManagedEntity].
///
/// Managed objects are also used in building queries. See [Query.matchOn] and [Query.values].
///
/// A managed object is declared in two parts:
///         class User extends ManagedObject<_User> implements _User {
///           String name; // Not persisted
///         }
///         class _User {
///           @primaryKey int id; // Persisted
///         }
class ManagedObject<PersistentType> extends Object
    with QueryMatchableExtension
    implements HTTPSerializable, QueryMatchable {
  /// Used when building a [Query] to include instances of this type.
  ///
  /// A [Query] will, by default, fetch rows from a single table and return them as instances
  /// of the appropriate [ManagedObject] subclass. A [Query] may join on multiple database tables
  /// when setting this property to true in its [Query.matchOn] subproperties. For example, the following
  /// query will fetch both 'Parent' and 'child' managed objects.
  ///
  ///         var query = new Query<Parent>()
  ///           ..matchOn.child.includeInResultSet = true;
  ///
  ///
  bool includeInResultSet = false;

  /// The [ManagedEntity] this instance is described by.
  ManagedEntity entity =
      ManagedContext.defaultContext.dataModel.entityForType(PersistentType);

  /// The managed values of this instance.
  ///
  /// Not all values are fetched or populated in a [ManagedObject] instance. This value contains
  /// key-value pairs for the managed object that have been set, either manually
  /// or when fetched from a database. When [ManagedObject] is instantiated, this map is empty.
  Map<String, dynamic> get backingMap => backing.valueMap;

  ManagedBacking backing = new ManagedValueBacking();

  /// Retrieves a value by property name from the [backingMap].
  dynamic operator [](String propertyName) =>
      backing.valueForProperty(entity, propertyName);

  /// Sets a value by property name in the [backingMap].
  void operator []=(String propertyName, dynamic value) {
    backing.setValueForProperty(entity, propertyName, value);
  }

  /// Removes a property from the [backingMap].
  ///
  /// This will remove a value from the backing map.
  void removePropertyFromBackingMap(String propertyName) {
    backing.removeProperty(propertyName);
  }

  /// Checks whether or not a property has been set in this instances' [backingMap].
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

  /// Populates the properties of a this instance from a map.
  ///
  /// This method will thrown an exception if a key in the map does not
  /// match a property of the receiver.
  ///
  /// Usage:
  ///     var values = JSON.decode(requestBody);
  ///     var user = new User()
  ///       ..readFromMap(values);
  void readMap(Map<String, dynamic> keyValues) {
    var mirror = reflect(this);

    keyValues.forEach((k, v) {
      var property = entity.properties[k];

      if (property == null) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message:
                "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}");
      }

      if (property is ManagedAttributeDescription) {
        if (!property.isTransient) {
          backing.setValueForProperty(entity, k, _valueDecoder(property, v));
        } else {
          if (!property.transientStatus.isAvailableAsInput) {
            throw new QueryException(QueryExceptionEvent.requestFailure,
                message:
                    "Key $k does not exist for ${MirrorSystem.getName(mirror.type.simpleName)}");
          }

          var decodedValue = _valueDecoder(property, v);
          if (!property.isAssignableWith(decodedValue)) {
            var valueTypeName =
                MirrorSystem.getName(reflect(decodedValue).type.simpleName);
            throw new QueryException(QueryExceptionEvent.requestFailure,
                message:
                    "Type mismatch for property ${property.name} on ${MirrorSystem.getName(entity.persistentType.simpleName)}, expected assignable type matching ${property.type} but got $valueTypeName.");
          }

          mirror.setField(new Symbol(k), decodedValue);
        }
      } else {
        backing.setValueForProperty(entity, k, _valueDecoder(property, v));
      }
    });
  }

  /// Converts this instance into a serializable map.
  ///
  /// This method returns a map of the key-values pairs in this instance. This value is typically converted into a transmission format like JSON.
  ///
  /// Only properties present in [backingMap] are serialized, otherwise, they are omitted from the map. If a property is present in [backingMap] and the value is null,
  /// the value null will be serialized for that property key.
  ///
  /// Usage:
  ///     var json = JSON.encode(model.asMap());
  Map<String, dynamic> asMap() {
    var outputMap = <String, dynamic>{};

    backing.valueMap.forEach((k, v) {
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

  static dynamic _valueDecoder(
      ManagedPropertyDescription propertyDescription, dynamic value) {
    if (propertyDescription is ManagedAttributeDescription) {
      if (propertyDescription.type == ManagedPropertyType.datetime) {
        value = DateTime.parse(value);
      }

      if (propertyDescription.isAssignableWith(value)) {
        return value;
      }
    } else if (propertyDescription is ManagedRelationshipDescription) {
      ManagedRelationshipDescription relationshipDescription =
          propertyDescription;
      var destinationEntity = relationshipDescription.destinationEntity;
      if (relationshipDescription.relationshipType ==
              ManagedRelationshipType.belongsTo ||
          relationshipDescription.relationshipType ==
              ManagedRelationshipType.hasOne) {
        if (value is! Map<String, dynamic>) {
          throw new QueryException(QueryExceptionEvent.requestFailure,
              message:
                  "Expecting a Map for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        ManagedObject instance = destinationEntity.instanceType
            .newInstance(new Symbol(""), []).reflectee;
        instance.readMap(value as Map<String, dynamic>);

        return instance;
      } else if (relationshipDescription.relationshipType ==
          ManagedRelationshipType.hasMany) {
        if (value is! List<Map<String, dynamic>>) {
          throw new QueryException(QueryExceptionEvent.requestFailure,
              message:
                  "Expecting a List for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        if (value.length > 0 && value.first is! Map) {
          throw new QueryException(QueryExceptionEvent.requestFailure,
              message:
                  "Expecting a List<Map> for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the ${relationshipDescription.name} field, got $value instead.");
        }

        return new ManagedSet.from(
            (value as List<Map<String, dynamic>>).map((v) {
          ManagedObject instance = destinationEntity.instanceType
              .newInstance(new Symbol(""), []).reflectee;
          instance.readMap(v);
          return instance;
        }));
      }
    }

    return value;
  }
}
