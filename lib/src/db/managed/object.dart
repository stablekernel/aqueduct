import 'dart:mirrors';

import '../../http/serializable.dart';
import 'managed.dart';
import 'backing.dart';
import '../query/query.dart';

/// Instances of this class provide storage for [ManagedObject]s.
///
/// This class is primarily used internally.
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

/// An object that represents a database row.
///
/// This class must be subclassed. A subclass is declared for each table in a database. These subclasses
/// create the data model of an application.
///
/// A managed object is declared in two parts, the subclass and its "persistent type".
///
///         class User extends ManagedObject<_User> implements _User {
///           String name;
///         }
///         class _User {
///           @primaryKey
///           int id;
///
///           @ManagedColumnAttributes(indexed: true)
///           String email;
///         }
///
/// Persistent types are plain Dart objects that represent a database table. Each property is a column in the database.
///
/// A subclass of this type must implement its persistent type and use it as the type argument of [ManagedObject]. Properties and methods
/// declared in the subclass (also called the 'instance type') are not stored in the database.
///
/// See more documentation on defining a data model at http://aqueduct.io/docs/db/modeling_data/
class ManagedObject<PersistentType> implements HTTPSerializable {
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

  /// Callback to modify an object prior to updating it with a [Query].
  ///
  /// Subclasses of this type may override this method to set or modify values prior to being updated
  /// via [Query.update] or [Query.updateOne]. It is automatically invoked by [Query.update] and [Query.updateOne].
  ///
  /// This method is invoked prior to validation and therefore any values modified in this method
  /// are subject to the validation behavior of this instance.
  ///
  /// An example implementation would set the 'updatedDate' of an object each time it was updated:
  ///
  ///         @override
  ///         void willUpdate() {
  ///           updatedDate = new DateTime.now().toUtc();
  ///         }
  ///
  /// This method is only invoked when a query is configured by its [Query.values]. This method is not invoked
  /// if [Query.valueMap] is used to configure a query.
  void willUpdate() {

  }

  /// Callback to modify an object prior to inserting it with a [Query].
  ///
  /// Subclasses of this type may override this method to set or modify values prior to being inserted
  /// via [Query.insert]. It is automatically invoked by [Query.insert].
  ///
  /// This method is invoked prior to validation and therefore any values modified in this method
  /// are subject to the validation behavior of this instance.
  ///
  /// An example implementation would set the 'createdDate' of an object when it is first created
  ///
  ///         @override
  ///         void willInsert() {
  ///           createdDate = new DateTime.now().toUtc();
  ///         }
  ///
  /// This method is only invoked when a query is configured by its [Query.values]. This method is not invoked
  /// if [Query.valueMap] is used to configure a query.
  void willInsert() {

  }

  /// Validates an object according to its property [Validate] metadata.
  ///
  /// This method is invoked by [Query] when inserting or updating an instance of this type. By default,
  /// this method runs all of the [Validate] metadata for each property of this instance's persistent type. See [Validate]
  /// for more information.
  ///
  /// This method return the result of [ManagedValidator.run]. You may override this method to provide additional validation
  /// prior to insertion or deletion. If you override this method, you *must* invoke the super implementation to
  /// validate property [Validate] metadata, e.g.:
  ///
  ///         bool validate({ValidateOperation forOperation: ValidateOperation.insert, List<String> collectErrorsIn}) {
  ///           var valid = super(forOperation: forOperation, collectErrorsIn: collectErrorsIn);
  ///
  ///           if (a + b > 10) {
  ///             valid = false;
  ///             collectErrorsIn.add("a + b > 10");
  ///           }
  ///
  ///           return valid;
  ///         }
  ///
  /// [collectErrorsIn] is guaranteed to be a non-null [List] when this method is invoked by [Query.updateOne], [Query.update]
  /// and [Query.insert]. It is not guaranteed to be non-null when invoked manually. This list is provided as a reference value
  /// by the object performing the validation. Do not create a new [List] and pass
  /// it to the superclass' implementation, as it will not be the same list the caller has access to.
  bool validate({ValidateOperation forOperation: ValidateOperation.insert, List<String> collectErrorsIn}) {
    return ManagedValidator.run(this, operation: forOperation, errors: collectErrorsIn);
  }

  @override
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
  @override
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

      if (propertyDescription.type == ManagedPropertyType.doublePrecision &&
          value is num) {
        value = value.toDouble();
      }

      // no need to check type here - gets checked by managed backing

      return value;
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
