import 'dart:mirrors';
import 'managed.dart';
import '../persistent_store/persistent_store.dart';
import '../query/query.dart';

/// Possible data types for [ManagedEntity] attributes.
enum ManagedPropertyType {
  /// Represented by instances of [int].
  integer,

  /// Represented by instances of [int].
  bigInteger,

  /// Represented by instances of [String].
  string,

  /// Represented by instances of [DateTime].
  datetime,

  /// Represented by instances of [bool].
  boolean,

  /// Represented by instances of [double].
  doublePrecision,

  /// Represented by instances of [Map]. Cannot be backed by underlying database.
  transientMap,

  /// Represented by instances of [List]. Cannot be backed by underlying database.
  transientList
}

/// Contains database column information and metadata for a property of a [ManagedObject] object.
///
/// Each property a [ManagedObject] object manages is described by an instance of [ManagedPropertyDescription], which contains useful information
/// about the property such as its name and type. Those properties are represented by concrete subclasses of this class, [ManagedRelationshipDescription]
/// and [ManagedAttributeDescription].
abstract class ManagedPropertyDescription {
  ManagedPropertyDescription(this.entity, this.name, this.type,
      {String explicitDatabaseType: null,
      bool unique: false,
      bool indexed: false,
      bool nullable: false,
      bool includedInDefaultResultSet: true,
      bool autoincrement: false})
      : isUnique = unique,
        isIndexed = indexed,
        isNullable = nullable,
        isIncludedInDefaultResultSet = includedInDefaultResultSet,
        this.autoincrement = autoincrement;

  /// A reference to the [ManagedEntity] that contains this property.
  final ManagedEntity entity;

  /// The value type of this property.
  ///
  /// Will indicate the Dart type and database column type of this property.
  final ManagedPropertyType type;

  /// The identifying name of this property.
  final String name;

  /// Whether or not this property must be unique to across all instances represented by [entity].
  ///
  /// Defaults to false.
  final bool isUnique;

  /// Whether or not this property should be indexed by a [PersistentStore].
  ///
  /// Defaults to false.
  final bool isIndexed;

  /// Whether or not this property can be null.
  ///
  /// Defaults to false.
  final bool isNullable;

  /// Whether or not this property is returned in the default set of [Query.returningProperties].
  ///
  /// This defaults to true. If true, when executing a [Query] that does not explicitly specify [Query.returningProperties],
  /// this property will be returned. If false, you must explicitly specify this property in [Query.returningProperties] to retrieve it from persistent storage.
  final bool isIncludedInDefaultResultSet;

  /// Whether or not this property should use an auto-incrementing scheme.
  ///
  /// By default, false. When true, it signals to the [PersistentStore] that this property should automatically be assigned a value
  /// by the database.
  final bool autoincrement;

  /// Returns the corresponding [ManagedPropertyType] given a Dart type.
  static ManagedPropertyType propertyTypeForDartType(Type t) {
    if (t == int) {
      return ManagedPropertyType.integer;
    } else if (t == String) {
      return ManagedPropertyType.string;
    } else if (t == DateTime) {
      return ManagedPropertyType.datetime;
    } else if (t == bool) {
      return ManagedPropertyType.boolean;
    } else if (t == double) {
      return ManagedPropertyType.doublePrecision;
    }

    var mirror = reflectClass(t);
    if (mirror.isSubtypeOf(reflectType(Map))) {
      return ManagedPropertyType.transientMap;
    } else if (mirror.isSubtypeOf(reflectType(List))) {
      return ManagedPropertyType.transientList;
    } else if (mirror.isEnum) {
      return ManagedPropertyType.string;
    }

    return null;
  }

  static List<Type> get supportedDartTypes {
    return [String, DateTime, bool, int, double];
  }

  /// Whether or not a the argument can be assigned to this property.
  bool isAssignableWith(dynamic dartValue) {
    if (dartValue == null) {
      return true;
    }

    switch (type) {
      case ManagedPropertyType.integer:
        return dartValue is int;
      case ManagedPropertyType.bigInteger:
        return dartValue is int;
      case ManagedPropertyType.boolean:
        return dartValue is bool;
      case ManagedPropertyType.datetime:
        return dartValue is DateTime;
      case ManagedPropertyType.doublePrecision:
        return dartValue is double;
      case ManagedPropertyType.string:
        return dartValue is String;
      case ManagedPropertyType.transientMap:
        return dartValue is Map;
      case ManagedPropertyType.transientList:
        return dartValue is List;
    }
    return false;
  }

  dynamic encodeValue(dynamic value);

  dynamic decodeValue(dynamic value);
}

/// Stores the specifics of database columns in [ManagedObject]s as indicated by [ManagedColumnAttributes].
///
/// This class is used internally to manage data models. For specifying these attributes,
/// see [ManagedColumnAttributes].
///
/// Attributes are the scalar values of a [ManagedObject] (as opposed to relationship values,
/// which are [ManagedRelationshipDescription] instances).
///
/// Each scalar property [ManagedObject] object persists is described by an instance of [ManagedAttributeDescription]. This class
/// adds two properties to [ManagedPropertyDescription] that are only valid for non-relationship types, [isPrimaryKey] and [defaultValue].
class ManagedAttributeDescription extends ManagedPropertyDescription {
  ManagedAttributeDescription(
      ManagedEntity entity, String name, ManagedPropertyType type,
      {ManagedTransientAttribute transientStatus: null,
        bool primaryKey: false,
        String defaultValue: null,
        bool unique: false,
        bool indexed: false,
        bool nullable: false,
        bool includedInDefaultResultSet: true,
        bool autoincrement: false,
        List<Validate> validators: const [],
        Map<String, dynamic> enumerationValueMap})
      : this.isPrimaryKey = primaryKey,
        this.defaultValue = defaultValue,
        this.transientStatus = transientStatus,
        this.enumerationValueMap = enumerationValueMap,
        this._validators = validators,
        super(entity, name, type,
          unique: unique,
          indexed: indexed,
          nullable: nullable,
          includedInDefaultResultSet: includedInDefaultResultSet,
          autoincrement: autoincrement);

  ManagedAttributeDescription.transient(ManagedEntity entity, String name,
      ManagedPropertyType type, this.transientStatus)
      : this.isPrimaryKey = false,
        this.enumerationValueMap = null,
        this.defaultValue = null,
        this._validators = [],
        super(entity, name, type,
            unique: false,
            indexed: false,
            nullable: false,
            includedInDefaultResultSet: false,
            autoincrement: false);

  /// Whether or not this attribute is the primary key for its [ManagedEntity].
  ///
  /// Defaults to false.
  final bool isPrimaryKey;

  /// The default value for this attribute.
  ///
  /// By default, null. This value is a String, so the underlying persistent store is responsible for parsing it. This allows for default values
  /// that aren't constant values, such as database function calls.
  final String defaultValue;

  /// Whether or not this attribute is backed directly by the database.
  ///
  /// If [transientStatus] is non-null, this value will be true. Otherwise, the attribute is backed by a database field/column.
  bool get isTransient => transientStatus != null;

  /// Contains lookup table for string value of an enumeration to the enumerated value.
  ///
  /// Value is null when this attribute does not represent an enumerated type.
  ///
  /// If `enum Options { option1, option2 }` then this map contains:
  ///
  ///         {
  ///           "option1": Options.option1,
  ///           "option2": Options.option2
  ///          }
  ///
  final Map<String, dynamic> enumerationValueMap;

  /// The validity of a transient attribute as input, output or both.
  ///
  /// If this property is non-null, the attribute is transient (not backed by a database field/column).
  final ManagedTransientAttribute transientStatus;

  /// [ManagedValidator]s for this instance.
  List<Validate> get validators {
    if (isEnumeratedValue) {
      var total = new List.from(_validators);
      total.add(new Validate.oneOf(enumerationValueMap.values.toList()));
      return total;
    }

    return _validators;
  }

  final List<Validate> _validators;

  /// Whether or not this attribute is represented by a Dart enum.
  bool get isEnumeratedValue => enumerationValueMap != null;

  @override
  bool isAssignableWith(dynamic dartValue) {
    if (isEnumeratedValue) {
      return enumerationValueMap.containsValue(dartValue);
    }

    return super.isAssignableWith(dartValue);
  }

  @override
  String toString() {
    return "[Attribute]    ${entity.tableName}.$name ($type)";
  }

  @override
  dynamic encodeValue(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    } else if (isEnumeratedValue) {
      // todo: optimize?
      return value.toString().split(".").last;
    }

    return value;
  }

  @override
  dynamic decodeValue(dynamic value) {
    if (type == ManagedPropertyType.datetime) {
      value = DateTime.parse(value);
    } else if (type == ManagedPropertyType.doublePrecision &&
        value is num) {
      value = value.toDouble();
    } else if (isEnumeratedValue) {
      if (!enumerationValueMap.containsKey(value)) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message: "The value '$value' is not valid for '${MirrorSystem.getName(entity.instanceType.simpleName)}.$name'");
      }
      return enumerationValueMap[value];
    }

    // no need to check type here - gets checked by managed backing

    return value;
  }
}

/// Contains information for a relationship property of a [ManagedObject].
class ManagedRelationshipDescription extends ManagedPropertyDescription {
  ManagedRelationshipDescription(
      ManagedEntity entity,
      String name,
      ManagedPropertyType type,
      this.destinationEntity,
      this.deleteRule,
      this.relationshipType,
      this.inverseKey,
      {bool unique: false,
      bool indexed: false,
      bool nullable: false,
      bool includedInDefaultResultSet: true})
      : super(entity, name, type,
            unique: unique,
            indexed: indexed,
            nullable: nullable,
            includedInDefaultResultSet: includedInDefaultResultSet);

  /// The entity that this relationship's instances are represented by.
  final ManagedEntity destinationEntity;

  /// The delete rule for this relationship.
  final ManagedRelationshipDeleteRule deleteRule;

  /// The type of relationship.
  final ManagedRelationshipType relationshipType;

  /// The name of the [ManagedRelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  final Symbol inverseKey;

  /// The [ManagedRelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  ManagedRelationshipDescription get inverse =>
      destinationEntity.relationships[MirrorSystem.getName(inverseKey)];

  /// Whether or not a the argument can be assigned to this property.
  @override
  bool isAssignableWith(dynamic dartValue) {
    var type = reflect(dartValue).type;

    if (type.isSubtypeOf(reflectType(List))) {
      if (relationshipType != ManagedRelationshipType.hasMany) {
        throw new ManagedDataModelException(
            "Trying to assign List to relationship that isn't hasMany for ${MirrorSystem.getName(entity.persistentType.simpleName)} $name");
      }

      type = type.typeArguments.first;
      if (type == reflectType(dynamic)) {
        // We can't say for sure... so we have to assume it to be true at the current stage.
        return true;
      }
    }

    return type == destinationEntity.instanceType;
  }

  @override
  dynamic encodeValue(dynamic value) {
    if (value is ManagedSet) {
      return value
          .map((ManagedObject innerValue) => innerValue.asMap())
          .toList();
    } else if (value is ManagedObject) {
      return value.asMap();
    } else if (value == null) {
      return null;
    }

    throw new QueryException(QueryExceptionEvent.requestFailure,
        message: "Invalid value '$value' for property '$entity.$name', "
            "expected '${MirrorSystem.getName(destinationEntity.instanceType.simpleName)}'");
  }

  @override
  dynamic decodeValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (relationshipType == ManagedRelationshipType.belongsTo ||
        relationshipType == ManagedRelationshipType.hasOne) {
      if (value is! Map<String, dynamic>) {
        throw new QueryException(QueryExceptionEvent.requestFailure,
            message:
            "Expecting a Map for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the '$name' field, got '$value' instead.");
      }

      ManagedObject instance = destinationEntity.instanceType
          .newInstance(new Symbol(""), []).reflectee;
      instance.readFromMap(value as Map<String, dynamic>);

      return instance;
    }

    /* else if (relationshipType == ManagedRelationshipType.hasMany) { */

    if (value is! List<Map<String, dynamic>>) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Expecting a List for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the '$name' field, got '$value' instead.");
    }

    if (value.length > 0 && value.first is! Map) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
          "Expecting a List<Map> for ${MirrorSystem.getName(destinationEntity.instanceType.simpleName)} in the '$name' field, got '$value' instead.");
    }

    return new ManagedSet.from(
        (value as List<Map<String, dynamic>>).map((v) {
          ManagedObject instance = destinationEntity.instanceType
              .newInstance(new Symbol(""), []).reflectee;
          instance.readFromMap(v);
          return instance;
        }));
  }

  @override
  String toString() {
    return "[Relationship] ${entity.tableName}.$name $relationshipType ${destinationEntity.tableName}.${MirrorSystem.getName(inverseKey)}";
  }
}
