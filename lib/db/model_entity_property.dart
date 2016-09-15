part of aqueduct;

/// Possible data types for [ModelEntity] attributes.
enum PropertyType {
  integer,
  bigInteger,
  string,
  datetime,
  boolean,
  doublePrecision,
  transientMap,
  transientList
}


/// Contains information for a property of a [Model] object.
///
/// Each property a [Model] object persists is described by an instance of [PropertyDescription], which contains useful information
/// about the property such as its name and type. Those properties are represented by concrete subclasses of this class, [RelationshipDescription]
/// and [AttributeDescription].
abstract class PropertyDescription {
  PropertyDescription(this.entity, this.name, this.type, {String explicitDatabaseType: null, bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true, bool autoincrement: false})
      : isUnique = unique,
        isIndexed = indexed,
        isNullable = nullable,
        isIncludedInDefaultResultSet = includedInDefaultResultSet,
        this.autoincrement = autoincrement {
  }

  /// A reference to the [ModelEntity] that contains this property.
  final ModelEntity entity;

  /// The value type of this property.
  ///
  /// Will indicate the Dart type and database column type of this property.
  final PropertyType type;

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

  /// Whether or not this property is returned in the default set of [resultProperties].
  ///
  /// This defaults to true. If true, when executing a [Query] that does not explicitly specify [resultProperties],
  /// this property will be returned. If false, you must explicitly specify this property in a [Query]'s [resultProperties] to retrieve it from persistent storage.
  final bool isIncludedInDefaultResultSet;

  /// Whether or not this property should use an auto-incrementing scheme.
  ///
  /// By default, false. When true, it signals to the [PersistentStore] that this property should automatically be assigned a value
  /// from an incrementer.
  final bool autoincrement;

  /// Returns the corresponding [PropertyType] given a Dart type.
  static PropertyType propertyTypeForDartType(Type t) {
    switch (t) {
      case int:
        return PropertyType.integer;
      case String:
        return PropertyType.string;
      case DateTime:
        return PropertyType.datetime;
      case bool:
        return PropertyType.boolean;
      case double:
        return PropertyType.doublePrecision;
      case Map:
        return PropertyType.transientMap;
      case List:
        return PropertyType.transientList;
    }

    return null;
  }

  /// Whether or not a the argument can be assigned to this property.
  bool isAssignableWith(dynamic dartValue) {
    switch(type) {
      case PropertyType.integer: return dartValue is int;
      case PropertyType.bigInteger: return dartValue is int;
      case PropertyType.boolean: return dartValue is bool;
      case PropertyType.datetime: return dartValue is DateTime;
      case PropertyType.doublePrecision: return dartValue is double;
      case PropertyType.string: return dartValue is String;
      case PropertyType.transientMap: return dartValue is Map;
      case PropertyType.transientList: return dartValue is List;
    }
    return false;
  }
}

/// Contains information for an attribute of a [ModelEntity].
///
/// Each non-relationship property [Model] object persists is described by an instance of [AttributeDescription]. This class
/// adds two properties to [PropertyDescription] that are only valid for non-relationship types, [isPrimaryKey] and [defaultValue].
class AttributeDescription extends PropertyDescription {
  AttributeDescription.transient(ModelEntity entity, String name, PropertyType type, this.transientStatus) :
      isPrimaryKey = false,
      this.defaultValue = null,
      super(entity, name, type, unique: false,
          indexed: false,
          nullable: false,
          includedInDefaultResultSet: false,
          autoincrement: false);

  AttributeDescription(ModelEntity entity, String name, PropertyType type, {TransientAttribute transientStatus: null, bool primaryKey: false, String defaultValue: null, bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true, bool autoincrement: false}) :
        isPrimaryKey = primaryKey,
        this.defaultValue = defaultValue,
        this.transientStatus = transientStatus,
        super(entity, name, type,
          unique: unique,
          indexed: indexed,
          nullable: nullable,
          includedInDefaultResultSet: includedInDefaultResultSet,
          autoincrement: autoincrement);

  /// Whether or not this attribute is the primary key for its [ModelEntity].
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

  /// The validity of a transient attribute as input, output or both.
  ///
  /// If this property is non-null, the attribute is transient (not backed by a database field/column).
  final TransientAttribute transientStatus;

  String toString() {
    return "AttributeDescription on ${entity.tableName}.$name Type: $type";
  }
}

/// Contains information for a relationship of a [ModelEntity].
class RelationshipDescription extends PropertyDescription {
  RelationshipDescription(ModelEntity entity, String name, PropertyType type, this.destinationEntity, this.deleteRule, this.relationshipType, this.inverseKey, {bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true})
    : super(entity, name, type, unique: unique, indexed: indexed, nullable: nullable, includedInDefaultResultSet: includedInDefaultResultSet) {
  }

  /// The entity that this relationship's instances are represented by.
  final ModelEntity destinationEntity;

  /// The delete rule for this relationship.
  final RelationshipDeleteRule deleteRule;

  /// The type of relationship.
  final RelationshipType relationshipType;

  /// The name of the [RelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  final Symbol inverseKey;

  /// The [RelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  RelationshipDescription get inverseRelationship => destinationEntity.relationships[MirrorSystem.getName(inverseKey)];

  /// Whether or not a the argument can be assigned to this property.
  bool isAssignableWith(dynamic dartValue) {
    var type = reflect(dartValue).type;

    if (type.isSubtypeOf(reflectType(List))) {
      if (relationshipType != RelationshipType.hasMany) {
        throw new DataModelException("Trying to assign List to relationship that isn't hasMany for ${MirrorSystem.getName(entity.persistentTypeMirror.simpleName)} $name");
      }

      type = type.typeArguments.first;
      if (type == reflectType(dynamic)) {
        // We can't say for sure... so we have to assume it to be true at the current stage.
        return true;
      }
    }

    return type == destinationEntity.modelTypeMirror;
  }

  String toString() {
    if (relationshipType == RelationshipType.belongsTo) {
      return "RelationshipDescription on ${entity.tableName}.$name Type: ${relationshipType} ($type)";
    }

    return "RelationshipDescription on ${entity.tableName}.$name Type: ${relationshipType}";
  }
}